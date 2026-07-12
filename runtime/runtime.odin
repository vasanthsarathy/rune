package odessa_runtime

import rl "vendor:raylib"
import c "../canvas"

WINDOW_W :: 1280
WINDOW_H :: 720
TITLE    :: "Odessa"

Odessa_Memory :: struct {
	run:           bool,
	active:        int,  // index into c.registry()
	setup_done:    bool,
}

g: ^Odessa_Memory

@(export) odessa_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(WINDOW_W, WINDOW_H, TITLE)
	rl.SetTargetFPS(60)
}

@(export) odessa_init :: proc() {
	g = new(Odessa_Memory)
	g^ = Odessa_Memory{ run = true, active = 0, setup_done = false }
	odessa_hot_reloaded(g)
}

@(export) odessa_update :: proc() -> bool {
	reg := c.registry()

	// Push inputs/time into the canvas mirrors.
	mp := rl.GetMousePosition()
	c.set_frame_inputs(
		int(rl.GetScreenWidth()), int(rl.GetScreenHeight()),
		g.setup_done ? c.frame_count + 1 : 0,
		f32(rl.GetTime()), rl.GetFrameTime(),
		mp.x, mp.y, rl.IsMouseButtonDown(.LEFT),
	)

	rl.BeginDrawing()
	rl.ClearBackground(rl.Color{18, 18, 22, 255})

	if len(reg) > 0 && g.active >= 0 && g.active < len(reg) {
		s := reg[g.active]
		if !g.setup_done {
			if s.setup != nil { s.setup() }
			c.apply_pending_size()
			g.setup_done = true
		}
		c.frame_begin()
		if s.draw != nil { s.draw() }
	}

	rl.EndDrawing()
	free_all(context.temp_allocator)

	if rl.WindowShouldClose() { g.run = false }
	return g.run
}

@(export) odessa_shutdown        :: proc()             { free(g) }
@(export) odessa_shutdown_window :: proc()             { rl.CloseWindow() }
@(export) odessa_memory          :: proc() -> rawptr   { return g }
@(export) odessa_memory_size     :: proc() -> int      { return size_of(Odessa_Memory) }
@(export) odessa_hot_reloaded    :: proc(mem: rawptr)  { g = (^Odessa_Memory)(mem) }
@(export) odessa_force_reload    :: proc() -> bool     { return rl.IsKeyPressed(.F5) }
@(export) odessa_force_restart   :: proc() -> bool     { return rl.IsKeyPressed(.F6) }
