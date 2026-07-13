package main

import rl "vendor:raylib"
import "core:strings"
import "../editor"

ED_FONT   :: 20
ED_LINE_H :: 24
GUTTER_W  :: 56

// key "goes" this frame: initial press or auto-repeat.
key_go :: proc(k: rl.KeyboardKey) -> bool {
	return rl.IsKeyPressed(k) || rl.IsKeyPressedRepeat(k)
}

editor_input :: proc(b: ^editor.Buffer) {
	shift := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
	ctrl  := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)

	if ctrl {
		if rl.IsKeyPressed(.C) {
			s := editor.selected_text(b, context.temp_allocator)
			rl.SetClipboardText(strings.clone_to_cstring(s, context.temp_allocator))
			return
		}
		if rl.IsKeyPressed(.X) {
			s := editor.selected_text(b, context.temp_allocator)
			rl.SetClipboardText(strings.clone_to_cstring(s, context.temp_allocator))
			editor.push_undo(b); editor.delete_selection(b)
			return
		}
		if rl.IsKeyPressed(.V) {
			editor.push_undo(b)
			editor.insert_text(b, string(rl.GetClipboardText()))
			return
		}
		if rl.IsKeyPressed(.Z) { editor.undo(b); return }
		if rl.IsKeyPressed(.Y) { editor.redo(b); return }
		// Ctrl+S / Ctrl+R handled by main.
		return
	}

	// typed characters (GetCharPressed auto-repeats)
	for r := rl.GetCharPressed(); r != 0; r = rl.GetCharPressed() {
		if r >= 32 {
			editor.push_undo(b)
			editor.insert_rune(b, r)
		}
	}

	if key_go(.ENTER)     { editor.push_undo(b); editor.insert_rune(b, '\n') }
	if key_go(.BACKSPACE) { editor.push_undo(b); editor.backspace(b) }
	if key_go(.DELETE)    { editor.push_undo(b); editor.delete_forward(b) }
	if key_go(.LEFT)      { editor.move(b, .Left,  shift) }
	if key_go(.RIGHT)     { editor.move(b, .Right, shift) }
	if key_go(.UP)        { editor.move(b, .Up,    shift) }
	if key_go(.DOWN)      { editor.move(b, .Down,  shift) }
	if key_go(.HOME)      { editor.move(b, .Home,  shift) }
	if key_go(.END)       { editor.move(b, .End,   shift) }
}

// Pixel width of the first `col` bytes of a line, using raylib's own text
// layout so cursor/selection/tokens line up exactly with DrawText (works for
// any font, monospace or not).
@(private="file") prefix_w :: proc(line: []u8, col: int) -> f32 {
	c := clamp(col, 0, len(line))
	if c == 0 { return 0 }
	cs := strings.clone_to_cstring(string(line[:c]), context.temp_allocator)
	return measure(cs, ED_FONT)
}

// Inverse of prefix_w: the column whose left edge is nearest to x pixels.
@(private="file") col_at_x :: proc(line: []u8, x: f32) -> int {
	if x <= 0 { return 0 }
	for col in 1..=len(line) {
		wr := prefix_w(line, col)
		if wr >= x {
			wl := prefix_w(line, col-1)
			return col-1 if (x - wl) < (wr - x) else col
		}
	}
	return len(line)
}

token_color :: proc(k: editor.Token_Kind) -> rl.Color {
	switch k {
	case .Keyword: return rl.Color{198, 120, 221, 255} // purple
	case .Number:  return rl.Color{209, 154, 102, 255} // orange
	case .String:  return rl.Color{152, 195, 121, 255} // green
	case .Char:    return rl.Color{152, 195, 121, 255} // green
	case .Comment: return rl.Color{106, 115, 125, 255} // gray
	}
	return rl.Color{220, 220, 225, 255}
}

// Set the cursor from a mouse click inside the editor area.
editor_mouse :: proc(b: ^editor.Buffer, area: rl.Rectangle, scroll: int) {
	if !rl.IsMouseButtonPressed(.LEFT) { return }
	m := rl.GetMousePosition()
	if !rl.CheckCollisionPointRec(m, area) { return }
	line := scroll + int((m.y - area.y) / ED_LINE_H)
	line = clamp(line, 0, len(b.lines)-1)
	col  := col_at_x(b.lines[line][:], m.x - area.x - GUTTER_W)
	editor.set_cursor(b, line, col) // set_cursor clamps
}

BASE_COL :: rl.Color{220, 220, 225, 255}

// Draw one byte-span of a line at column `col` in `col_color`, returning the
// end column drawn to. Uses measured widths so it lines up with everything else.
@(private="file") draw_span :: proc(line: []u8, lo, hi: int, base_x, y: f32, color: rl.Color) {
	if hi <= lo { return }
	cs := strings.clone_to_cstring(string(line[lo:hi]), context.temp_allocator)
	draw_text(cs, base_x + prefix_w(line, lo), y, ED_FONT, color)
}

editor_draw :: proc(b: ^editor.Buffer, area: rl.Rectangle, scroll: ^int) {
	visible := int(area.height) / ED_LINE_H

	// keep cursor visible
	if b.cursor.line < scroll^            { scroll^ = b.cursor.line }
	if b.cursor.line >= scroll^ + visible { scroll^ = b.cursor.line - visible + 1 }
	if scroll^ < 0 { scroll^ = 0 }

	rl.DrawRectangleRec(area, rl.Color{18, 18, 22, 255})
	base_x := area.x + GUTTER_W
	nib := measure("m", ED_FONT) // nominal width for the newline sliver

	// selection highlight
	if editor.has_selection(b) {
		start, end := editor.selection_range(b)
		for ln in start.line..=end.line {
			row := ln - scroll^
			if row < 0 || row >= visible { continue }
			lo := 0 if ln > start.line else start.col
			hi := len(b.lines[ln]) if ln < end.line else end.col
			x0 := base_x + prefix_w(b.lines[ln][:], lo)
			x1 := base_x + prefix_w(b.lines[ln][:], hi)
			y := area.y + f32(row)*ED_LINE_H
			w := x1 - x0
			if ln < end.line { w += nib } // show the trailing newline as a sliver
			rl.DrawRectangleRec(rl.Rectangle{x0, y, w, ED_LINE_H}, rl.Color{50, 70, 120, 255})
		}
	}

	// lines: gutter number, then colored segments left-to-right
	for row in 0..<visible {
		ln := scroll^ + row
		if ln >= len(b.lines) { break }
		y := area.y + f32(row*ED_LINE_H)
		num := rl.TextFormat("%d", ln+1)
		draw_text(num, area.x+8, y, ED_FONT, rl.Color{90, 90, 110, 255})

		line := b.lines[ln][:]
		toks := editor.tokenize(line, context.temp_allocator)
		prev := 0
		for tok in toks {
			draw_span(line, prev, tok.start, base_x, y, BASE_COL)          // untagged gap
			draw_span(line, tok.start, tok.end, base_x, y, token_color(tok.kind))
			prev = tok.end
		}
		draw_span(line, prev, len(line), base_x, y, BASE_COL)              // trailing gap
	}

	// cursor
	crow := b.cursor.line - scroll^
	if crow >= 0 && crow < visible {
		cx := base_x + prefix_w(b.lines[b.cursor.line][:], b.cursor.col)
		cy := area.y + f32(crow)*ED_LINE_H
		rl.DrawRectangleRec(rl.Rectangle{cx, cy, 2, ED_LINE_H}, rl.Color{240, 240, 120, 255})
	}
}
