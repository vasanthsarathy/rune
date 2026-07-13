package main

import rl "vendor:raylib"
import "core:strings"
import "../editor"

g_docs_open:     bool
g_docs_sel:      int          // index into g_docs_filtered
g_docs_scroll:   int
g_docs_search:   [dynamic]u8
g_docs_filtered: [dynamic]int // indices into DOCS matching the search

DOCS_LIST_W :: 240
DOCS_ROW    :: 30
DOCS_LIST_TOP :: TOOLBAR_H + 66 // below the REFERENCE label + search field

@(private="file") ci_contains :: proc(hay, needle: string) -> bool {
	if needle == "" { return true }
	// case-insensitive substring
	for i := 0; i+len(needle) <= len(hay); i += 1 {
		match := true
		for j in 0..<len(needle) {
			a := hay[i+j]; b := needle[j]
			if a >= 'A' && a <= 'Z' { a += 32 }
			if b >= 'A' && b <= 'Z' { b += 32 }
			if a != b { match = false; break }
		}
		if match { return true }
	}
	return false
}

docs_refilter :: proc() {
	clear(&g_docs_filtered)
	needle := string(g_docs_search[:])
	for e, i in DOCS {
		if ci_contains(e.name, needle) || ci_contains(e.sig, needle) {
			append(&g_docs_filtered, i)
		}
	}
	if g_docs_sel >= len(g_docs_filtered) { g_docs_sel = 0 }
}

// Open docs, optionally jumping to the symbol under the cursor (c.<name>).
docs_open_at_cursor :: proc(b: ^editor.Buffer) {
	g_docs_open = true
	clear(&g_docs_search)
	g_docs_sel = 0
	g_docs_scroll = 0
	line := b.lines[b.cursor.line][:]
	if obj, _, _, ok := editor.dot_context(line, b.cursor.col); ok && obj == "c" {
		// find the full identifier the cursor sits in
		i := b.cursor.col
		for i < len(line) && is_ident_b(line[i]) { i += 1 }
		start := b.cursor.col
		for start > 0 && is_ident_b(line[start-1]) { start -= 1 }
		if idx := doc_index(string(line[start:i])); idx >= 0 {
			docs_refilter()
			for fi, k in g_docs_filtered { if fi == idx { g_docs_sel = k; break } }
			return
		}
	}
	docs_refilter()
}

@(private="file") is_ident_b :: proc(c: u8) -> bool {
	return (c>='a'&&c<='z')||(c>='A'&&c<='Z')||(c>='0'&&c<='9')||c=='_'
}

docs_row_rect :: proc(i: int) -> rl.Rectangle {
	return rl.Rectangle{0, f32(DOCS_LIST_TOP + i*DOCS_ROW - g_docs_scroll), DOCS_LIST_W, DOCS_ROW}
}

docs_input :: proc() {
	// search typing
	for r := rl.GetCharPressed(); r != 0; r = rl.GetCharPressed() {
		if r >= 32 && r < 128 { append(&g_docs_search, u8(r)) }
	}
	if key_go(.BACKSPACE) && len(g_docs_search) > 0 { pop(&g_docs_search) }
	docs_refilter()

	if key_go(.DOWN) && len(g_docs_filtered) > 0 { g_docs_sel = (g_docs_sel+1) %% len(g_docs_filtered) }
	if key_go(.UP)   && len(g_docs_filtered) > 0 { g_docs_sel = (g_docs_sel-1) %% len(g_docs_filtered) }
	if rl.IsKeyPressed(.ESCAPE) { g_docs_open = false }

	if wheel := rl.GetMouseWheelMove(); wheel != 0 {
		g_docs_scroll -= int(wheel*3)*DOCS_ROW
		if g_docs_scroll < 0 { g_docs_scroll = 0 }
	}

	// click a list row
	if rl.IsMouseButtonPressed(.LEFT) {
		m := rl.GetMousePosition()
		for _, k in g_docs_filtered {
			if rl.CheckCollisionPointRec(m, docs_row_rect(k)) { g_docs_sel = k; break }
		}
	}
}

// Draw wrapped text; returns the y just below the last line.
draw_wrapped :: proc(text: string, x, y, maxw, size: f32, color: rl.Color) -> f32 {
	yy := y
	t := text
	for para in strings.split_lines_iterator(&t) {
		p := para
		cur := ""
		for word in strings.split_iterator(&p, " ") {
			trial := cur == "" ? word : strings.concatenate({cur, " ", word}, context.temp_allocator)
			if measure(strings.clone_to_cstring(trial, context.temp_allocator), size) > maxw && cur != "" {
				draw_text(strings.clone_to_cstring(cur, context.temp_allocator), x, yy, size, color)
				yy += size*1.5
				cur = word
			} else {
				cur = trial
			}
		}
		draw_text(strings.clone_to_cstring(cur, context.temp_allocator), x, yy, size, color)
		yy += size*1.5
	}
	return yy
}

docs_draw :: proc() {
	sw := f32(rl.GetScreenWidth())
	sh := f32(rl.GetScreenHeight())
	top: f32 = TOOLBAR_H

	// backdrop
	rl.DrawRectangleRec(rl.Rectangle{0, top, sw, sh-top}, BG_DEEP)

	// --- left: search + list ---
	rl.DrawRectangleRec(rl.Rectangle{0, top, DOCS_LIST_W, sh-top}, BG_PANEL)
	rl.DrawRectangle(DOCS_LIST_W-1, i32(top), 1, i32(sh-top), LINE)
	draw_eyebrow("REFERENCE", 12, top+10)

	// search field
	sb := rl.Rectangle{10, top+30, DOCS_LIST_W-20, 26}
	rl.DrawRectangleRounded(sb, 0.3, 6, BG_RAISE)
	q := string(g_docs_search[:])
	if q == "" {
		draw_text("search…", sb.x+8, sb.y+4, 16, FG_DIM)
	} else {
		draw_text(strings.clone_to_cstring(strings.concatenate({q, "_"}, context.temp_allocator), context.temp_allocator), sb.x+8, sb.y+4, 16, FG)
	}

	// list (clipped below the search field)
	list_top := f32(DOCS_LIST_TOP)
	rl.BeginScissorMode(0, i32(list_top), DOCS_LIST_W, i32(sh-list_top))
	for fi, k in g_docs_filtered {
		r := docs_row_rect(k)
		if r.y+r.height < list_top || r.y > sh { continue }
		if k == g_docs_sel {
			rl.DrawRectangleRec(r, BG_SEL)
			rl.DrawRectangle(0, i32(r.y), 3, i32(r.height), ACCENT)
		} else if rl.CheckCollisionPointRec(rl.GetMousePosition(), r) {
			rl.DrawRectangleRec(r, BG_HOVER)
		}
		draw_text(strings.clone_to_cstring(DOCS[fi].name, context.temp_allocator), 14, r.y+6, 17, k == g_docs_sel ? FG_BRIGHT : FG)
	}
	rl.EndScissorMode()

	// --- right: detail ---
	dx: f32 = DOCS_LIST_W + 28
	dw := sw - dx - 28
	if len(g_docs_filtered) == 0 {
		draw_text("no matches", dx, top+40, 18, FG_DIM)
		return
	}
	e := DOCS[g_docs_filtered[g_docs_sel]]
	y := top + 26
	draw_text(strings.clone_to_cstring(e.name, context.temp_allocator), dx, y, 30, FG_BRIGHT)
	y += 44

	// signature chip
	sig_c := strings.clone_to_cstring(e.sig, context.temp_allocator)
	sw2 := measure(sig_c, 18)
	rl.DrawRectangleRounded(rl.Rectangle{dx-6, y-4, sw2+20, 30}, 0.25, 6, BG_RAISE)
	draw_text(sig_c, dx+4, y+2, 18, ACCENT)
	y += 44

	y = draw_wrapped(e.summary, dx, y, dw, 18, FG) + 14

	// example box
	draw_eyebrow("EXAMPLE", dx, y)
	y += 20
	lines := strings.split_lines(e.example, context.temp_allocator)
	box_h := f32(len(lines))*24 + 16
	rl.DrawRectangleRounded(rl.Rectangle{dx, y, dw, box_h}, 0.04, 6, rl.Color{16, 17, 24, 255})
	ey := y + 8
	for ln in lines {
		// light syntax coloring of the example
		lb := transmute([]u8)ln
		toks := editor.tokenize(lb, context.temp_allocator)
		draw_text(strings.clone_to_cstring(ln, context.temp_allocator), dx+12, ey, 17, FG)
		for tok in toks {
			sub := strings.clone_to_cstring(string(lb[tok.start:tok.end]), context.temp_allocator)
			px := dx + 12 + measure(strings.clone_to_cstring(string(lb[:tok.start]), context.temp_allocator), 17)
			draw_text(sub, px, ey, 17, token_color(tok.kind))
		}
		ey += 24
	}
}
