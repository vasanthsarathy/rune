package main

import rl "vendor:raylib"
import "core:os"
import "core:strings"
import "../runner"

// True if the given flag was passed on the command line.
has_arg :: proc(name: string) -> bool {
	for a in os.args[1:] {
		if a == name { return true }
	}
	return false
}

SKETCH_NAME :: "hello"
SKETCH_DIR  :: "sketches/hello"
SKETCH_EXE  :: "build/hello.exe"

RUN_RECT  :: rl.Rectangle{8, 8, 90, 32}
STOP_RECT :: rl.Rectangle{106, 8, 90, 32}

Status :: enum { Idle, Compiling, Running, Compile_Error }

App :: struct {
	run:            runner.Runner,
	status:         Status,
	console:        string, // last build output (owned)
	console_scroll: int,    // first visible line index
}

CONSOLE_TOP :: 56
LINE_H      :: 18
FONT_SIZE   :: 16

status_text :: proc(s: Status) -> cstring {
	switch s {
	case .Idle:          return "Idle"
	case .Compiling:     return "Compiling..."
	case .Running:       return "Running"
	case .Compile_Error: return "Compile error"
	}
	return "?"
}

// True if the button at rect was clicked this frame (and is enabled).
button_clicked :: proc(rect: rl.Rectangle, enabled: bool) -> bool {
	if !enabled { return false }
	return rl.CheckCollisionPointRec(rl.GetMousePosition(), rect) && rl.IsMouseButtonPressed(.LEFT)
}

// Draw a labeled button (no side effects).
draw_button :: proc(rect: rl.Rectangle, label: cstring, enabled: bool) {
	hover := enabled && rl.CheckCollisionPointRec(rl.GetMousePosition(), rect)
	col := rl.Color{60, 60, 68, 255}
	if !enabled {
		col = rl.Color{40, 40, 46, 255}
	} else if hover {
		col = rl.Color{90, 90, 100, 255}
	}
	rl.DrawRectangleRec(rect, col)
	tw := rl.MeasureText(label, 20)
	rl.DrawText(label, i32(rect.x) + (i32(rect.width)-tw)/2, i32(rect.y) + 8, 20, rl.WHITE)
}

do_run :: proc(app: ^App) {
	runner.stop(&app.run) // stop any prior sketch first
	app.status = .Compiling
	// Paint one "Compiling..." frame before the blocking build (outside the main
	// loop's draw phase — no nested BeginDrawing).
	rl.BeginDrawing(); draw_ui(app); rl.EndDrawing()

	if app.console != "" {
		delete(app.console)
		app.console = ""
	}
	res := runner.build(SKETCH_DIR, SKETCH_EXE)
	app.console = res.output
	if !res.ok {
		app.status = .Compile_Error
		return
	}
	app.status = runner.launch(&app.run, SKETCH_EXE) ? .Running : .Idle
}

do_stop :: proc(app: ^App) {
	runner.stop(&app.run)
	app.status = .Idle
}

draw_console :: proc(app: ^App) {
	top: i32 = CONSOLE_TOP
	bottom := rl.GetScreenHeight() - 8
	rl.DrawRectangle(0, CONSOLE_TOP-4, rl.GetScreenWidth(), bottom-(CONSOLE_TOP-4), rl.Color{16, 16, 20, 255})

	if app.console == "" {
		rl.DrawText("(console)", 8, top, FONT_SIZE, rl.Color{90, 90, 100, 255})
		return
	}

	lines := strings.split_lines(app.console, context.temp_allocator)
	max_visible := int((bottom - top) / LINE_H)

	// clamp scroll
	if app.console_scroll < 0 { app.console_scroll = 0 }
	if app.console_scroll > max(0, len(lines)-max_visible) {
		app.console_scroll = max(0, len(lines)-max_visible)
	}

	col := rl.Color{200, 200, 205, 255}
	if app.status == .Compile_Error { col = rl.Color{255, 180, 180, 255} }

	y := top
	for i := app.console_scroll; i < len(lines) && int((y-top)/LINE_H) < max_visible; i += 1 {
		ctext := strings.clone_to_cstring(lines[i], context.temp_allocator)
		rl.DrawText(ctext, 8, y, FONT_SIZE, col)
		y += LINE_H
	}
}

draw_ui :: proc(app: ^App) {
	rl.ClearBackground(rl.Color{24, 24, 28, 255})
	draw_console(app)
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), 48, rl.Color{32, 32, 38, 255})
	draw_button(RUN_RECT, "Run", app.status != .Running && app.status != .Compiling)
	draw_button(STOP_RECT, "Stop", app.status == .Running)
	rl.DrawText(status_text(app.status), 210, 16, 20, rl.Color{200, 200, 210, 255})
}

main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(900, 640, "Odessa")
	rl.SetTargetFPS(60)
	defer rl.CloseWindow()

	app: App
	app.status = .Idle

	// --run: build & launch the sketch immediately on startup (scriptable entry).
	if has_arg("--run") {
		do_run(&app)
	}

	for !rl.WindowShouldClose() {
		// --- update / input (outside the draw phase) ---
		runner.poll(&app.run)
		if !app.run.running && app.status == .Running {
			app.status = .Idle // the sketch window was closed
		}

		ctrl := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)
		run_now  := button_clicked(RUN_RECT, app.status != .Running && app.status != .Compiling) || (ctrl && rl.IsKeyPressed(.R))
		stop_now := button_clicked(STOP_RECT, app.status == .Running)

		if run_now  { do_run(&app) }
		if stop_now { do_stop(&app) }

		if wheel := rl.GetMouseWheelMove(); wheel != 0 {
			app.console_scroll -= int(wheel * 3)
		}

		// --- draw ---
		rl.BeginDrawing()
		draw_ui(&app)
		rl.EndDrawing()
	}

	runner.stop(&app.run) // hygiene: never orphan the sketch
}
