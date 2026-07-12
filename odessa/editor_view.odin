package main

import rl "vendor:raylib"
import "core:strings"
import "../editor"

ED_FONT   :: 18
ED_LINE_H :: 22
GUTTER_W  :: 52

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

@(private="file") char_w :: proc() -> f32 {
	return f32(rl.MeasureText("m", ED_FONT))
}

// Set the cursor from a mouse click inside the editor area.
editor_mouse :: proc(b: ^editor.Buffer, area: rl.Rectangle, scroll: int) {
	if !rl.IsMouseButtonPressed(.LEFT) { return }
	m := rl.GetMousePosition()
	if !rl.CheckCollisionPointRec(m, area) { return }
	line := scroll + int((m.y - area.y) / ED_LINE_H)
	col  := int((m.x - area.x - GUTTER_W) / char_w() + 0.5)
	editor.set_cursor(b, line, col) // set_cursor clamps
}

editor_draw :: proc(b: ^editor.Buffer, area: rl.Rectangle, scroll: ^int) {
	cw := char_w()
	visible := int(area.height) / ED_LINE_H

	// keep cursor visible
	if b.cursor.line < scroll^            { scroll^ = b.cursor.line }
	if b.cursor.line >= scroll^ + visible { scroll^ = b.cursor.line - visible + 1 }
	if scroll^ < 0 { scroll^ = 0 }

	rl.DrawRectangleRec(area, rl.Color{18, 18, 22, 255})

	// selection highlight
	if editor.has_selection(b) {
		start, end := editor.selection_range(b)
		for ln in start.line..=end.line {
			row := ln - scroll^
			if row < 0 || row >= visible { continue }
			lo := 0 if ln > start.line else start.col
			hi := len(b.lines[ln]) if ln < end.line else end.col
			x := area.x + GUTTER_W + f32(lo)*cw
			y := area.y + f32(row)*ED_LINE_H
			w := f32(hi-lo)*cw
			if ln < end.line { w += cw } // show the trailing newline as a sliver
			rl.DrawRectangleRec(rl.Rectangle{x, y, w, ED_LINE_H}, rl.Color{50, 70, 120, 255})
		}
	}

	// lines + gutter
	for row in 0..<visible {
		ln := scroll^ + row
		if ln >= len(b.lines) { break }
		y := i32(area.y) + i32(row*ED_LINE_H)
		num := rl.TextFormat("%d", ln+1)
		rl.DrawText(num, i32(area.x)+6, y, ED_FONT, rl.Color{90, 90, 110, 255})
		ctext := strings.clone_to_cstring(string(b.lines[ln][:]), context.temp_allocator)
		rl.DrawText(ctext, i32(area.x)+GUTTER_W, y, ED_FONT, rl.Color{220, 220, 225, 255})
	}

	// cursor
	crow := b.cursor.line - scroll^
	if crow >= 0 && crow < visible {
		cx := area.x + GUTTER_W + f32(b.cursor.col)*cw
		cy := area.y + f32(crow)*ED_LINE_H
		rl.DrawRectangleRec(rl.Rectangle{cx, cy, 2, ED_LINE_H}, rl.Color{240, 240, 120, 255})
	}
}
