package canvas

import rl "vendor:raylib"

background :: proc(args: ..u8) {
	col := args_to_color(args)
	// Draw a full-canvas rect so alpha creates trails (ClearBackground ignores alpha).
	rl.DrawRectangle(0, 0, i32(width), i32(height), _rlcol(col))
}

fill :: proc(args: ..u8) {
	_fill_col = args_to_color(args)
	_fill_on  = true
}
no_fill :: proc() { _fill_on = false }

stroke :: proc(args: ..u8) {
	_stroke_col = args_to_color(args)
	_stroke_on  = true
}
no_stroke :: proc() { _stroke_on = false }

stroke_weight :: proc(w: f32) { _stroke_w = w }

circle :: proc(x, y, r: f32) {
	if _fill_on   { rl.DrawCircleV(rl.Vector2{x, y}, r, _rlcol(_fill_col)) }
	if _stroke_on { rl.DrawRing(rl.Vector2{x, y}, r - _stroke_w, r, 0, 360, 64, _rlcol(_stroke_col)) }
}

rect :: proc(x, y, w, h: f32) {
	if _fill_on   { rl.DrawRectangleV(rl.Vector2{x, y}, rl.Vector2{w, h}, _rlcol(_fill_col)) }
	if _stroke_on { rl.DrawRectangleLinesEx(rl.Rectangle{x, y, w, h}, _stroke_w, _rlcol(_stroke_col)) }
}

line :: proc(x1, y1, x2, y2: f32) {
	if _stroke_on {
		rl.DrawLineEx(rl.Vector2{x1, y1}, rl.Vector2{x2, y2}, _stroke_w, _rlcol(_stroke_col))
	}
}

point :: proc(x, y: f32) {
	col := _stroke_on ? _stroke_col : _fill_col
	if _stroke_w <= 1 {
		rl.DrawPixelV(rl.Vector2{x, y}, _rlcol(col))
	} else {
		rl.DrawCircleV(rl.Vector2{x, y}, _stroke_w * 0.5, _rlcol(col))
	}
}
