package main

import rl "vendor:raylib"
import "core:strings"
import "../editor"

// The reference panel has three tabs.
Ref_Tab :: enum { Canvas, Odin, Shortcuts }
g_ref_tab: Ref_Tab

REF_TAB_H :: 40
PANEL_TOP :: TOOLBAR_H + REF_TAB_H

// --- Odin language cheatsheet (Learn-X-in-Y-Minutes style) ---
Cheat :: struct { title, code: string }

@(rodata) CHEATSHEET := []Cheat{
	{"Comments", "// line comment\n/* block comment */"},
	{"Packages & imports", "package main\nimport \"core:fmt\"\nimport c \"../../canvas\"   // aliased"},
	{"Variables", "x := 10          // type inferred\ny: f32 = 1.5     // explicit type\nz: int           // zero value (0)"},
	{"Constants", "PI   :: 3.14159\nNAME :: \"Rune\"    // :: means compile-time"},
	{"Basic types", "int  i8 i16 i32 i64   u8 u16 u32 u64\nf32 f64   bool   string   rune   byte"},
	{"Procedures", "add :: proc(a, b: int) -> int {\n\treturn a + b\n}"},
	{"Multiple returns", "divmod :: proc(a, b: int) -> (int, int) {\n\treturn a/b, a%b\n}\nq, r := divmod(7, 2)"},
	{"If / else", "if x > 0 {\n\t// ...\n} else if x < 0 {\n} else {\n}"},
	{"Ternary", "y := a if cond else b"},
	{"For loops", "for i in 0..<10 { }      // 0..9\nfor i in 0..=10 { }      // 0..10\nfor x > 0 { x -= 1 }     // while-style\nfor v, i in arr { }      // iterate + index"},
	{"Switch", "switch dir {\ncase .North: // ...\ncase .East:  // ...\ncase:        // default\n}"},
	{"Arrays & slices", "a: [4]int              // fixed size (a value)\ns := a[:]              // slice (a view)\nd: [dynamic]int\nappend(&d, 1, 2, 3)"},
	{"Maps", "m: map[string]int\nm[\"a\"] = 1\nv, ok := m[\"a\"]        // ok = found?"},
	{"Structs", "Point :: struct { x, y: f32 }\np := Point{1, 2}\np.x = 3"},
	{"Enums", "Dir :: enum { North, East, South, West }\nd := Dir.North         // or just .North"},
	{"Pointers", "p := &x                // address of x\np^ = 5                 // ^ dereferences"},
	{"Defer", "defer delete(data)     // runs at scope exit"},
	{"Value vs reference", "// [N]T arrays & structs COPY on assign.\n// slices, [dynamic], maps are references."},
}

// --- keyboard shortcuts ---
Shortcut :: struct { keys, desc: string }

@(rodata) SHORTCUTS := []Shortcut{
	{"Ctrl + R", "Run the current sketch"},
	{"Ctrl + S", "Save the sketch (in the editor)"},
	{"Ctrl + S", "Export canvas to PNG (in a running sketch window)"},
	{"F1", "Open docs (jumps to the symbol under the cursor)"},
	{"Esc", "Close docs / cancel"},
	{"Ctrl + = / -", "Zoom the editor font in / out"},
	{"Ctrl + Wheel", "Zoom the editor font"},
	{"Wheel", "Scroll the editor or console"},
	{"Ctrl + C / X / V", "Copy / Cut / Paste"},
	{"Ctrl + Z / Y", "Undo / Redo"},
	{"Click + drag", "Select text"},
	{"Shift + Arrows", "Select while moving"},
	{"Arrows / Home / End", "Move the cursor"},
	{"Tab / Enter", "Accept an autocomplete suggestion"},
	{"+ New (sidebar)", "Create a new sketch"},
}

// Draw a block of code with syntax highlighting; returns the y below it.
draw_code_block :: proc(code: string, x, y, size: f32) -> f32 {
	yy := y
	lines := strings.split_lines(code, context.temp_allocator)
	for ln in lines {
		lb := transmute([]u8)ln
		draw_text(strings.clone_to_cstring(ln, context.temp_allocator), x, yy, size, FG)
		toks := editor.tokenize(lb, context.temp_allocator)
		for tok in toks {
			sub := strings.clone_to_cstring(string(lb[tok.start:tok.end]), context.temp_allocator)
			px := x + measure(strings.clone_to_cstring(string(lb[:tok.start]), context.temp_allocator), size)
			draw_text(sub, px, yy, size, token_color(tok.kind))
		}
		yy += size * 1.45
	}
	return yy
}

// Upper bound for the reference panel's vertical scroll, per tab.
docs_max_scroll :: proc() -> int {
	avail := int(screen_h()) - PANEL_TOP
	switch g_ref_tab {
	case .Canvas:
		visible := max(1, (int(screen_h()) - DOCS_LIST_TOP) / DOCS_ROW)
		return max(0, len(g_docs_filtered) - visible) * DOCS_ROW
	case .Odin:
		h := 22
		for sec in CHEATSHEET {
			nlines := strings.count(sec.code, "\n") + 1
			h += 28 + int(f32(nlines)*17*1.45) + 20
		}
		return max(0, h - avail)
	case .Shortcuts:
		return max(0, len(SHORTCUTS)*42 + 48 - avail)
	}
	return 0
}

ref_tab_rect :: proc(i: int) -> rl.Rectangle {
	return rl.Rectangle{DOCS_LIST_W*0 + f32(12 + i*118), f32(TOOLBAR_H) + 4, 110, REF_TAB_H - 8}
}

draw_ref_tabs :: proc() {
	labels := [3]cstring{"Canvas API", "Odin", "Shortcuts"}
	for i in 0..<3 {
		r := ref_tab_rect(i)
		active := int(g_ref_tab) == i
		hover := rl.CheckCollisionPointRec(rl.GetMousePosition(), r)
		if active {
			rl.DrawRectangleRounded(r, 0.3, 6, BG_SEL)
		} else if hover {
			rl.DrawRectangleRounded(r, 0.3, 6, BG_HOVER)
		}
		tw := measure(labels[i], 17)
		draw_text(labels[i], r.x + (r.width-tw)/2, r.y + 5, 17, active ? ACCENT : FG_DIM)
	}
	rl.DrawRectangle(0, i32(PANEL_TOP)-1, screen_w(), 1, LINE) // divider under tabs
}

draw_cheatsheet :: proc() {
	sw := f32(screen_w()); sh := f32(screen_h())
	top := f32(PANEL_TOP)
	rl.BeginScissorMode(0, i32(top), i32(sw), i32(sh-top))
	x: f32 = 40
	y := top + 22 - f32(g_docs_scroll)
	for sec in CHEATSHEET {
		draw_text(strings.clone_to_cstring(sec.title, context.temp_allocator), x, y, 19, FG_BRIGHT)
		y += 28
		y = draw_code_block(sec.code, x+10, y, 17) + 20
	}
	rl.EndScissorMode()
}

draw_shortcuts :: proc() {
	sw := f32(screen_w()); sh := f32(screen_h())
	top := f32(PANEL_TOP)
	rl.BeginScissorMode(0, i32(top), i32(sw), i32(sh-top))
	x: f32 = 40
	y := top + 24 - f32(g_docs_scroll)
	for s in SHORTCUTS {
		kw := measure(strings.clone_to_cstring(s.keys, context.temp_allocator), 17)
		rl.DrawRectangleRounded(rl.Rectangle{x, y-2, kw+18, 28}, 0.3, 6, BG_RAISE)
		draw_text(strings.clone_to_cstring(s.keys, context.temp_allocator), x+9, y+2, 17, FG_BRIGHT)
		draw_text(strings.clone_to_cstring(s.desc, context.temp_allocator), x+240, y+2, 17, FG)
		y += 42
	}
	rl.EndScissorMode()
}
