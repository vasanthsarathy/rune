package main

import rl "vendor:raylib"
import "core:os"
import "core:strings"
import "../runner"
import "../editor"

// True if the given flag was passed on the command line.
has_arg :: proc(name: string) -> bool {
	for a in os.args[1:] {
		if a == name { return true }
	}
	return false
}

// --- UI font (a real monospace TTF, loaded once) ---
FONT_BASE    :: 48 // baked glyph size; DrawTextEx scales down crisply
TEXT_SPACING :: f32(0)

g_font:        rl.Font
g_font_custom: bool

load_ui_font :: proc() {
	candidates := []string{
		"C:/Windows/Fonts/CascadiaCode.ttf",
		"C:/Windows/Fonts/CascadiaMono.ttf",
		"C:/Windows/Fonts/consola.ttf",
	}
	for path in candidates {
		if os.exists(path) {
			f := rl.LoadFontEx(strings.clone_to_cstring(path, context.temp_allocator), FONT_BASE, nil, 0)
			if f.glyphCount > 0 {
				rl.SetTextureFilter(f.texture, .BILINEAR)
				g_font = f
				g_font_custom = true
				return
			}
		}
	}
	g_font = rl.GetFontDefault()
	g_font_custom = false
}

draw_text :: proc(s: cstring, x, y: f32, size: f32, color: rl.Color) {
	rl.DrawTextEx(g_font, s, rl.Vector2{x, y}, size, TEXT_SPACING, color)
}

measure :: proc(s: cstring, size: f32) -> f32 {
	return rl.MeasureTextEx(g_font, s, size, TEXT_SPACING).x
}

SKETCH_NAME :: "hello"
SKETCH_DIR  :: "sketches/hello"
SKETCH_EXE  :: "build/hello.exe"
SKETCH_FILE :: "sketches/hello/hello.odin"

RUN_RECT  :: rl.Rectangle{8, 8, 90, 32}
STOP_RECT :: rl.Rectangle{106, 8, 90, 32}

Status :: enum { Idle, Compiling, Running, Compile_Error }

App :: struct {
	run:            runner.Runner,
	status:         Status,
	console:        string,   // last build output (owned)
	console_lines:  []string, // console split into lines once per build (owned; slices into console)
	console_scroll: int,      // first visible line index
	buf:            editor.Buffer, // the sketch source being edited
	ed_scroll:      int,           // editor's first visible line
}

TOOLBAR_H :: 48
CONSOLE_H :: 160
LINE_H    :: 20
FONT_SIZE :: 18

// Number of console lines that fit in the bottom strip.
console_visible_lines :: proc() -> int {
	return CONSOLE_H / LINE_H
}

// Editor area: below the toolbar, above the console strip.
editor_area :: proc() -> rl.Rectangle {
	h := int(rl.GetScreenHeight()) - TOOLBAR_H - CONSOLE_H
	if h < 0 { h = 0 }
	return rl.Rectangle{0, TOOLBAR_H, f32(rl.GetScreenWidth()), f32(h)}
}

load_sketch :: proc(app: ^App) {
	data, err := os.read_entire_file_from_path(SKETCH_FILE, context.allocator)
	if err != nil {
		app.buf = editor.make_buffer("")
		return
	}
	defer delete(data)
	app.buf = editor.make_buffer(string(data))
}

save_sketch :: proc(app: ^App) {
	s := editor.to_string(&app.buf, context.temp_allocator)
	_ = os.write_entire_file(SKETCH_FILE, transmute([]u8)s)
}

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
	tw := measure(label, 20)
	draw_text(label, rect.x + (rect.width-tw)/2, rect.y + 6, 20, rl.WHITE)
}

do_run :: proc(app: ^App) {
	save_sketch(app) // persist the editor buffer, then build what's on disk
	runner.stop(&app.run) // stop any prior sketch first
	app.status = .Compiling
	// Paint one "Compiling..." frame before the blocking build (outside the main
	// loop's draw phase — no nested BeginDrawing).
	rl.BeginDrawing(); draw_ui(app); rl.EndDrawing()

	if app.console_lines != nil {
		delete(app.console_lines)
		app.console_lines = nil
	}
	if app.console != "" {
		delete(app.console)
		app.console = ""
	}
	app.console_scroll = 0
	res := runner.build(SKETCH_DIR, SKETCH_EXE)
	app.console = res.output
	// Split once per build (not per frame). split_lines yields a phantom trailing
	// "" when the output ends in '\n' — drop it.
	app.console_lines = strings.split_lines(app.console, context.allocator)
	if n := len(app.console_lines); n > 0 && app.console_lines[n-1] == "" {
		app.console_lines = app.console_lines[:n-1]
	}
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

// Pure render of the (already-clamped) console as a fixed bottom strip starting
// at top_y. Scroll clamping lives in the update phase; no side effects.
draw_console_strip :: proc(app: ^App, top_y: int) {
	top := i32(top_y)
	bottom := rl.GetScreenHeight()
	if bottom <= top { return }
	rl.DrawRectangle(0, top, rl.GetScreenWidth(), bottom-top, rl.Color{16, 16, 20, 255})

	if len(app.console_lines) == 0 {
		draw_text("(console)", 8, f32(top)+4, FONT_SIZE, rl.Color{90, 90, 100, 255})
		return
	}

	col := rl.Color{200, 200, 205, 255}
	if app.status == .Compile_Error { col = rl.Color{255, 180, 180, 255} }

	max_visible := console_visible_lines()
	y := f32(top) + 4
	for i := app.console_scroll; i < len(app.console_lines) && (i - app.console_scroll) < max_visible; i += 1 {
		ctext := strings.clone_to_cstring(app.console_lines[i], context.temp_allocator)
		draw_text(ctext, 8, y, FONT_SIZE, col)
		y += LINE_H
	}
}

draw_ui :: proc(app: ^App) {
	rl.ClearBackground(rl.Color{24, 24, 28, 255})

	// editor (between toolbar and console strip)
	editor_draw(&app.buf, editor_area(), &app.ed_scroll)

	// console strip at the bottom
	draw_console_strip(app, int(rl.GetScreenHeight()) - CONSOLE_H)

	// toolbar on top
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), TOOLBAR_H, rl.Color{32, 32, 38, 255})
	draw_button(RUN_RECT, "Run", app.status != .Running && app.status != .Compiling)
	draw_button(STOP_RECT, "Stop", app.status == .Running)
	draw_text(status_text(app.status), 210, 14, 20, rl.Color{200, 200, 210, 255})
}

main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(900, 640, "Odessa")
	rl.SetTargetFPS(60)
	defer rl.CloseWindow()

	load_ui_font()
	defer if g_font_custom { rl.UnloadFont(g_font) }

	app: App
	app.status = .Idle
	load_sketch(&app)
	defer editor.destroy_buffer(&app.buf)

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

		// editor edits (typing goes here; Ctrl combos for run/save handled below)
		editor_input(&app.buf)
		editor_mouse(&app.buf, editor_area(), app.ed_scroll)

		if ctrl && rl.IsKeyPressed(.S) { save_sketch(&app) }

		run_now  := button_clicked(RUN_RECT, app.status != .Running && app.status != .Compiling) || (ctrl && rl.IsKeyPressed(.R))
		stop_now := button_clicked(STOP_RECT, app.status == .Running)

		if run_now  { do_run(&app) }
		if stop_now { do_stop(&app) }

		if wheel := rl.GetMouseWheelMove(); wheel != 0 {
			app.console_scroll -= int(wheel * 3)
		}
		// Clamp scroll here (update phase), guarding a shrunk window.
		max_scroll := max(0, len(app.console_lines) - console_visible_lines())
		app.console_scroll = clamp(app.console_scroll, 0, max_scroll)

		// --- draw ---
		rl.BeginDrawing()
		draw_ui(&app)
		rl.EndDrawing()

		free_all(context.temp_allocator) // reclaim per-frame temp allocations (console cstrings, etc.)
	}

	runner.stop(&app.run) // hygiene: never orphan the sketch
}
