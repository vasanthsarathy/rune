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

@(private) args_to_color :: proc(args: []u8) -> Color {
	switch len(args) {
	case 1: return Color{args[0], args[0], args[0], 255}
	case 2: return Color{args[0], args[0], args[0], args[1]}
	case 3: return Color{args[0], args[1], args[2], 255}
	case 4: return Color{args[0], args[1], args[2], args[3]}
	}
	return BLACK
}

@(private) _rlcol :: proc(col: Color) -> rl.Color { return rl.Color{col.r, col.g, col.b, col.a} }

size :: proc(w, h: int) {
	_pending_w = w
	_pending_h = h
	_size_dirty = true
}

// Called by run() once per frame, before the sketch's draw.
@(private) frame_begin :: proc() {
	_fill_col   = WHITE
	_fill_on    = true
	_stroke_col = BLACK
	_stroke_on  = true
	_stroke_w   = 1
}

@(private) set_frame_inputs :: proc(w, h, frame: int, t, dt, mx, my: f32, pressed: bool) {
	width, height = w, h
	frame_count = frame
	time, delta_time = t, dt
	mouse_x, mouse_y = mx, my
	mouse = Vec2{mx, my}
	mouse_pressed = pressed
}

@(private) apply_pending_size :: proc() {
	if _size_dirty {
		rl.SetWindowSize(i32(_pending_w), i32(_pending_h))
		_size_dirty = false
	}
}

SKETCH_TITLE :: "Rune Sketch"
DEFAULT_W    :: 800
DEFAULT_H    :: 800

@(private) _canvas_rt: rl.RenderTexture2D

// Opens the window, runs setup once, then draws every frame until the window closes.
// This is the sketch program's entry point (called from the sketch's main).
//
// Drawing goes into a PERSISTENT accumulation buffer (a render texture) that is
// only cleared when the sketch calls background(). This matches Processing: if
// you don't call background() each frame, points/shapes accumulate — the basis
// for density plots (strange attractors) and motion trails.
run :: proc(user_setup: proc(), user_draw: proc()) {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(DEFAULT_W, DEFAULT_H, SKETCH_TITLE)
	rl.SetTargetFPS(60)
	defer rl.CloseWindow()

	if user_setup != nil { user_setup() }
	apply_pending_size()   // honor a size() call made in setup

	// canvas mirrors reflect the actual window; the accumulation buffer matches it
	width  = int(rl.GetScreenWidth())
	height = int(rl.GetScreenHeight())
	_canvas_rt = rl.LoadRenderTexture(i32(width), i32(height))
	defer rl.UnloadRenderTexture(_canvas_rt)
	rl.BeginTextureMode(_canvas_rt)
	rl.ClearBackground(rl.Color{18, 18, 22, 255})
	rl.EndTextureMode()

	frame := 0
	for !rl.WindowShouldClose() {
		mp := rl.GetMousePosition()
		set_frame_inputs(
			int(_canvas_rt.texture.width), int(_canvas_rt.texture.height),
			frame,
			f32(rl.GetTime()), rl.GetFrameTime(),
			mp.x, mp.y, rl.IsMouseButtonDown(.LEFT),
		)
		frame_begin()

		// draw into the persistent buffer (no auto-clear -> accumulation)
		rl.BeginTextureMode(_canvas_rt)
		if user_draw != nil { user_draw() }
		rl.EndTextureMode()

		// blit the buffer to the window (render textures are y-flipped)
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		src := rl.Rectangle{0, 0, f32(_canvas_rt.texture.width), -f32(_canvas_rt.texture.height)}
		dst := rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
		rl.DrawTexturePro(_canvas_rt.texture, src, dst, rl.Vector2{0, 0}, 0, rl.WHITE)
		rl.EndDrawing()

		free_all(context.temp_allocator)
		frame += 1
	}
}
