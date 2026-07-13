package main

import rl "vendor:raylib"
import "core:strings"
import "../editor"

// The canvas public API, offered when the user types `c.` in a sketch.
@(rodata) CANVAS_API := [?]string{
	// setup / window / loop
	"size", "size_paper", "run", "width", "height",
	// time / input
	"frame_count", "time", "delta_time", "mouse", "mouse_x", "mouse_y", "mouse_pressed",
	// color & style
	"background", "fill", "no_fill", "stroke", "no_stroke", "stroke_weight",
	"Color", "rgb", "rgba", "gray", "hsl", "hsv", "WHITE", "BLACK",
	// shapes
	"circle", "rect", "line", "point",
	// math
	"map_range", "lerp", "clamp", "dist", "radians", "degrees", "PI", "TAU",
	// random
	"random", "random_range", "seed",
	// vectors
	"Vec2", "vec2", "vlength", "vnormalize", "vdist", "vheading", "vfrom_angle", "vrotate", "vlerp",
	// noise
	"noise", "noise_seed",
	// easing
	"ease_in_quad", "ease_out_quad", "ease_in_out_quad",
	"ease_in_cubic", "ease_out_cubic", "ease_in_out_cubic",
	"ease_in_sine", "ease_out_sine", "ease_in_out_sine",
}

AC_MAX_ROWS :: 10

g_ac_open:          bool
g_ac_matches:       [dynamic]string
g_ac_sel:           int
g_ac_start:         int
g_ac_dismissed:     bool
g_ac_dismiss_line:  int
g_ac_dismiss_start: int

// Recompute the completion popup from the buffer's current `c.<prefix>` context.
ac_update :: proc(b: ^editor.Buffer) {
	g_ac_open = false
	line := b.lines[b.cursor.line][:]
	obj, prefix, start, ok := editor.dot_context(line, b.cursor.col)
	if !ok || obj != "c" {
		g_ac_dismissed = false
		return
	}
	if g_ac_dismissed && b.cursor.line == g_ac_dismiss_line && start == g_ac_dismiss_start {
		return // user pressed Esc for this exact spot
	}
	g_ac_dismissed = false

	clear(&g_ac_matches)
	for name in CANVAS_API {
		if strings.has_prefix(name, prefix) { append(&g_ac_matches, name) }
	}
	if len(g_ac_matches) == 0 { return }
	g_ac_start = start
	if g_ac_sel >= len(g_ac_matches) { g_ac_sel = 0 }
	g_ac_open = true
}

// Handle popup navigation keys. Returns true if it consumed this frame's input
// (so the editor should not also act on it). Typing keys pass through (false).
ac_intercept :: proc(b: ^editor.Buffer) -> bool {
	if !g_ac_open { return false }
	if key_go(.DOWN) { g_ac_sel = (g_ac_sel + 1) %% len(g_ac_matches); return true }
	if key_go(.UP)   { g_ac_sel = (g_ac_sel - 1) %% len(g_ac_matches); return true }
	if rl.IsKeyPressed(.TAB) || rl.IsKeyPressed(.ENTER) { ac_accept(b); return true }
	if rl.IsKeyPressed(.ESCAPE) {
		g_ac_dismissed     = true
		g_ac_dismiss_line  = b.cursor.line
		g_ac_dismiss_start = g_ac_start
		g_ac_open          = false
		return true
	}
	return false
}

ac_accept :: proc(b: ^editor.Buffer) {
	defer g_ac_open = false
	if g_ac_sel < 0 || g_ac_sel >= len(g_ac_matches) { return }
	m := g_ac_matches[g_ac_sel]
	plen := b.cursor.col - g_ac_start
	if plen >= 0 && plen <= len(m) {
		editor.push_undo(b)
		editor.insert_text(b, m[plen:]) // insert the rest of the name
	}
}

ac_draw :: proc(b: ^editor.Buffer, area: rl.Rectangle, scroll: int) {
	if !g_ac_open { return }
	crow := b.cursor.line - scroll
	if crow < 0 { return }
	line := b.lines[b.cursor.line][:]
	x := area.x + GUTTER_W + prefix_w(line, g_ac_start)
	y := area.y + f32(crow+1)*ed_line_h()

	n := min(len(g_ac_matches), AC_MAX_ROWS)
	row := ed_line_h()
	w: f32 = 260
	box := rl.Rectangle{x, y, w, f32(n)*row + 6}
	rl.DrawRectangleRounded(box, 0.06, 6, BG_RAISE)
	rl.DrawRectangleRoundedLinesEx(box, 0.06, 6, 1, LINE)
	for i in 0..<n {
		ry := y + 3 + f32(i)*row
		if i == g_ac_sel {
			rl.DrawRectangleRec(rl.Rectangle{x+2, ry, w-4, row}, BG_SEL)
			rl.DrawRectangle(i32(x)+2, i32(ry), 2, i32(row), ACCENT) // accent marker
		}
		fg := i == g_ac_sel ? FG_BRIGHT : FG
		draw_text(strings.clone_to_cstring(g_ac_matches[i], context.temp_allocator), x+12, ry+2, g_ed_font*0.95, fg)
	}
}
