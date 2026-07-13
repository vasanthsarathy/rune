package canvas

import rl "vendor:raylib"
import "core:os"
import "core:fmt"
import "core:strings"

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

@(private) _rt_ready:  bool
@(private) _rt_active: bool

// (Re)create the canvas render texture at w×h and begin drawing into it, so
// anything drawn afterwards — including in setup(), e.g. background() — is kept.
@(private) _make_canvas :: proc(w, h: int) {
	if _rt_ready {
		if _rt_active { rl.EndTextureMode(); _rt_active = false }
		rl.UnloadRenderTexture(_canvas_rt)
	}
	width, height = w, h
	_canvas_rt = rl.LoadRenderTexture(i32(w), i32(h))
	_rt_ready = true
	rl.BeginTextureMode(_canvas_rt)
	_rt_active = true
	rl.ClearBackground(rl.Color{18, 18, 22, 255})
}

// Set the canvas size in pixels. Call once at the start of setup().
size :: proc(w, h: int) {
	_make_canvas(w, h)
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

	// Setup draws into the canvas buffer: size() creates it (and starts a texture
	// session); if setup never calls size(), fall back to a default-size canvas.
	if user_setup != nil { user_setup() }
	if !_rt_ready { _make_canvas(DEFAULT_W, DEFAULT_H) }
	if _rt_active { rl.EndTextureMode(); _rt_active = false }
	defer rl.UnloadRenderTexture(_canvas_rt)

	cw, ch := width, height

	// The window is a fit-to-screen preview; large print canvases scale down on
	// screen but export at full resolution.
	mon := rl.GetCurrentMonitor()
	dw, dh := _fit(cw, ch, int(f32(rl.GetMonitorWidth(mon))*0.9), int(f32(rl.GetMonitorHeight(mon))*0.85))
	rl.SetWindowSize(i32(dw), i32(dh))
	rl.SetWindowPosition((rl.GetMonitorWidth(mon)-i32(dw))/2, (rl.GetMonitorHeight(mon)-i32(dh))/2)

	frame := 0
	for !rl.WindowShouldClose() {
		// map mouse from window (preview) coords into canvas coords
		mp := rl.GetMousePosition()
		sx := f32(cw) / f32(rl.GetScreenWidth())
		sy := f32(ch) / f32(rl.GetScreenHeight())
		set_frame_inputs(cw, ch, frame, f32(rl.GetTime()), rl.GetFrameTime(), mp.x*sx, mp.y*sy, rl.IsMouseButtonDown(.LEFT))
		frame_begin()

		// Ctrl+S exports the canvas to output/export-NNN.png at full resolution
		if (rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)) && rl.IsKeyPressed(.S) {
			save_frame()
		}

		// draw into the persistent buffer (no auto-clear -> accumulation)
		rl.BeginTextureMode(_canvas_rt); _rt_active = true
		if user_draw != nil { user_draw() }
		rl.EndTextureMode(); _rt_active = false

		// blit the buffer to the window (render textures are y-flipped)
		rl.BeginDrawing()
		rl.ClearBackground(rl.BLACK)
		src := rl.Rectangle{0, 0, f32(cw), -f32(ch)}
		dst := rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
		rl.DrawTexturePro(_canvas_rt.texture, src, dst, rl.Vector2{0, 0}, 0, rl.WHITE)
		rl.EndDrawing()

		free_all(context.temp_allocator)
		frame += 1
	}
}

@(private) _fit :: proc(w, h, maxw, maxh: int) -> (int, int) {
	if w <= maxw && h <= maxh { return w, h }
	s := min(f32(maxw)/f32(w), f32(maxh)/f32(h))
	return int(f32(w)*s), int(f32(h)*s)
}

@(private) _save_count: int

// Export the current canvas to a PNG (output/export-NNN.png) at full resolution.
// Bound to Ctrl+S in the sketch window; also callable from a sketch.
save_frame :: proc() {
	_ = os.make_directory("output") // ignore "already exists"; a real failure surfaces below
	img := rl.LoadImageFromTexture(_canvas_rt.texture)
	defer rl.UnloadImage(img)
	rl.ImageFlipVertical(&img) // render textures are stored y-flipped
	name := fmt.tprintf("output/export-%03d.png", _save_count)
	if rl.ExportImage(img, strings.clone_to_cstring(name, context.temp_allocator)) {
		fmt.printfln("saved %s", name)
		_save_count += 1
	} else {
		fmt.eprintfln("save_frame: failed to export %s", name)
	}
}
