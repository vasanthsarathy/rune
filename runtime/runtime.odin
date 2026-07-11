package odessa_runtime

import rl "vendor:raylib"

WINDOW_W :: 1280
WINDOW_H :: 720
TITLE    :: "Odessa"

// All runtime state lives here so it survives hot reloads (golden rule).
Odessa_Memory :: struct {
	run: bool,
}

g: ^Odessa_Memory

@(export) odessa_init_window :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(WINDOW_W, WINDOW_H, TITLE)
	rl.SetTargetFPS(60)
}

@(export) odessa_init :: proc() {
	g = new(Odessa_Memory)
	g^ = Odessa_Memory{ run = true }
	odessa_hot_reloaded(g)
}

@(export) odessa_update :: proc() -> bool {
	rl.BeginDrawing()
	rl.ClearBackground(rl.Color{18, 18, 22, 255})
	rl.EndDrawing()

	free_all(context.temp_allocator)
	if rl.WindowShouldClose() {
		g.run = false
	}
	return g.run
}

@(export) odessa_shutdown        :: proc()             { free(g) }
@(export) odessa_shutdown_window :: proc()             { rl.CloseWindow() }
@(export) odessa_memory          :: proc() -> rawptr   { return g }
@(export) odessa_memory_size     :: proc() -> int      { return size_of(Odessa_Memory) }
@(export) odessa_hot_reloaded    :: proc(mem: rawptr)  { g = (^Odessa_Memory)(mem) }
@(export) odessa_force_reload    :: proc() -> bool     { return rl.IsKeyPressed(.F5) }
@(export) odessa_force_restart   :: proc() -> bool     { return rl.IsKeyPressed(.F6) }
