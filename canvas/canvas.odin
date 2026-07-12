package canvas

import rl "vendor:raylib"

PI  :: 3.14159265358979323846
TAU :: 2.0 * PI

Vec2 :: [2]f32
vec2 :: proc(x, y: f32) -> Vec2 { return Vec2{x, y} }

// --- input/time mirrors, repopulated by the runtime every frame ---
width:         int
height:        int
frame_count:   int
time:          f32
delta_time:    f32
mouse:         Vec2
mouse_x:       f32
mouse_y:       f32
mouse_pressed: bool

// --- per-frame draw state ---
_fill_col:    Color
_fill_on:     bool
_stroke_col:  Color
_stroke_on:   bool
_stroke_w:    f32

// --- pending window size requested via size() ---
_pending_w: int
_pending_h: int
_size_dirty: bool

args_to_color :: proc(args: []u8) -> Color {
	switch len(args) {
	case 1: return Color{args[0], args[0], args[0], 255}
	case 2: return Color{args[0], args[0], args[0], args[1]}
	case 3: return Color{args[0], args[1], args[2], 255}
	case 4: return Color{args[0], args[1], args[2], args[3]}
	}
	return BLACK
}

_rlcol :: proc(col: Color) -> rl.Color { return rl.Color{col.r, col.g, col.b, col.a} }

size :: proc(w, h: int) {
	_pending_w = w
	_pending_h = h
	_size_dirty = true
}

// Called by the runtime once per frame, before the sketch's draw.
frame_begin :: proc() {
	_fill_col   = WHITE
	_fill_on    = true
	_stroke_col = BLACK
	_stroke_on  = true
	_stroke_w   = 1
}

set_frame_inputs :: proc(w, h, frame: int, t, dt, mx, my: f32, pressed: bool) {
	width, height = w, h
	frame_count = frame
	time, delta_time = t, dt
	mouse_x, mouse_y = mx, my
	mouse = Vec2{mx, my}
	mouse_pressed = pressed
}

apply_pending_size :: proc() {
	if _size_dirty {
		rl.SetWindowSize(i32(_pending_w), i32(_pending_h))
		_size_dirty = false
	}
}

Sketch_Proc :: proc()
Sketch_Entry :: struct {
	name:  string,
	setup: Sketch_Proc,
	draw:  Sketch_Proc,
}

_registry: [dynamic]Sketch_Entry

sketch :: proc(name: string, setup, draw: Sketch_Proc) {
	append(&_registry, Sketch_Entry{name, setup, draw})
}

registry :: proc() -> []Sketch_Entry { return _registry[:] }
