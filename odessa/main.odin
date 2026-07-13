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
		"C:/Windows/Fonts/consola.ttf",     // Consolas: narrow, light, very readable
		"C:/Windows/Fonts/CascadiaMono.ttf",
		"C:/Windows/Fonts/CascadiaCode.ttf",
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

SKETCHES_ROOT :: "sketches"

// Paths for a sketch by name (temp-allocated; used transiently per build/load).
sketch_dir  :: proc(name: string) -> string { return strings.concatenate({SKETCHES_ROOT, "/", name}, context.temp_allocator) }
sketch_file :: proc(name: string) -> string { return strings.concatenate({SKETCHES_ROOT, "/", name, "/", name, ".odin"}, context.temp_allocator) }
sketch_exe  :: proc(name: string) -> string { return strings.concatenate({"build/", name, ".exe"}, context.temp_allocator) }

// Name of the currently-open sketch.
current_name :: proc(app: ^App) -> string {
	if app.current >= 0 && app.current < len(app.sketches) { return app.sketches[app.current] }
	return "hello"
}

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
	sketches:       [dynamic]string, // sketch names found under sketches/
	current:        int,             // index into sketches (the open one)
	naming:         bool,            // typing a name for a new sketch
	name_buf:       [dynamic]u8,     // the new sketch name being typed
}

NEW_SKETCH_TEMPLATE :: `package main

import c "../../canvas"

setup :: proc() {
	c.size(900, 900)
}

draw :: proc() {
	c.background(12, 12, 16)
}

main :: proc() {
	c.run(setup, draw)
}
`

TOOLBAR_H  :: 48
SIDEBAR_W  :: 150
SKETCH_ROW :: 28
CONSOLE_H  :: 160
LINE_H     :: 20
FONT_SIZE  :: 18

// Number of console lines that fit in the bottom strip.
console_visible_lines :: proc() -> int {
	return CONSOLE_H / LINE_H
}

// Editor area: right of the sidebar, below the toolbar, above the console strip.
editor_area :: proc() -> rl.Rectangle {
	h := int(rl.GetScreenHeight()) - TOOLBAR_H - CONSOLE_H
	if h < 0 { h = 0 }
	return rl.Rectangle{SIDEBAR_W, TOOLBAR_H, f32(int(rl.GetScreenWidth()) - SIDEBAR_W), f32(h)}
}

// Populate app.sketches from the subdirectories of sketches/.
list_sketches :: proc(app: ^App) {
	for s in app.sketches { delete(s) }
	clear(&app.sketches)
	fis, err := os.read_all_directory_by_path(SKETCHES_ROOT, context.allocator)
	if err != nil { return }
	for f in fis {
		if f.type == .Directory {
			append(&app.sketches, strings.clone(f.name))
		}
	}
}

load_sketch :: proc(app: ^App) {
	data, err := os.read_entire_file_from_path(sketch_file(current_name(app)), context.allocator)
	if err != nil {
		app.buf = editor.make_buffer("")
		return
	}
	defer delete(data)
	app.buf = editor.make_buffer(string(data))
}

save_sketch :: proc(app: ^App) {
	s := editor.to_string(&app.buf, context.temp_allocator)
	_ = os.write_entire_file(sketch_file(current_name(app)), transmute([]u8)s)
}

// Switch the open sketch: persist current edits, then load the chosen one.
open_sketch :: proc(app: ^App, idx: int) {
	if idx < 0 || idx >= len(app.sketches) || idx == app.current { return }
	save_sketch(app)
	editor.destroy_buffer(&app.buf)
	app.current = idx
	app.ed_scroll = 0
	load_sketch(app)
}

@(private="file") is_name_char :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_' || c == '-'
}

// Create a new sketch folder from the template and open it. No-op on empty /
// already-existing names.
create_sketch :: proc(app: ^App) {
	name := strings.clone(string(app.name_buf[:]), context.temp_allocator)
	clear(&app.name_buf)
	if name == "" { return }
	if os.exists(sketch_dir(name)) { return } // don't clobber an existing sketch

	if err := os.make_directory(sketch_dir(name)); err != nil { return }
	_ = os.write_entire_file(sketch_file(name), transmute([]u8)string(NEW_SKETCH_TEMPLATE))

	save_sketch(app)     // persist current edits before switching
	editor.destroy_buffer(&app.buf)
	list_sketches(app)   // rescan so the new sketch appears
	app.current = 0
	for n, i in app.sketches {
		if n == name { app.current = i; break }
	}
	app.ed_scroll = 0
	load_sketch(app)
}

// One frame of name-entry input (active while app.naming).
name_input :: proc(app: ^App) {
	for r := rl.GetCharPressed(); r != 0; r = rl.GetCharPressed() {
		if r < 128 && is_name_char(u8(r)) && len(app.name_buf) < 40 {
			append(&app.name_buf, u8(r))
		}
	}
	if key_go(.BACKSPACE) && len(app.name_buf) > 0 { pop(&app.name_buf) }
	if rl.IsKeyPressed(.ENTER)  { create_sketch(app); app.naming = false }
	if rl.IsKeyPressed(.ESCAPE) { clear(&app.name_buf); app.naming = false }
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
	name := current_name(app)
	res := runner.build(sketch_dir(name), sketch_exe(name))
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
	app.status = runner.launch(&app.run, sketch_exe(current_name(app))) ? .Running : .Idle
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

// "+ New" button occupies the first sidebar row; sketch rows follow below it.
new_button_rect :: proc() -> rl.Rectangle {
	return rl.Rectangle{0, TOOLBAR_H, SIDEBAR_W, SKETCH_ROW}
}
sketch_row_rect :: proc(i: int) -> rl.Rectangle {
	return rl.Rectangle{0, f32(TOOLBAR_H + (i+1)*SKETCH_ROW), SIDEBAR_W, SKETCH_ROW}
}

draw_sidebar :: proc(app: ^App) {
	sh := rl.GetScreenHeight()
	rl.DrawRectangle(0, TOOLBAR_H, SIDEBAR_W, sh-TOOLBAR_H, rl.Color{28, 28, 34, 255})
	mouse := rl.GetMousePosition()

	// "+ New" row: shows a text field while naming, otherwise a button.
	nb := new_button_rect()
	if app.naming {
		rl.DrawRectangleRec(nb, rl.Color{40, 46, 60, 255})
		label := strings.clone_to_cstring(strings.concatenate({"", string(app.name_buf[:]), "_"}, context.temp_allocator), context.temp_allocator)
		draw_text(label, 8, nb.y+5, 17, rl.Color{235, 235, 240, 255})
	} else {
		hov := rl.CheckCollisionPointRec(mouse, nb)
		rl.DrawRectangleRec(nb, hov ? rl.Color{50, 60, 50, 255} : rl.Color{34, 40, 34, 255})
		draw_text("+ New", 8, nb.y+5, 17, rl.Color{150, 200, 150, 255})
	}

	for name, i in app.sketches {
		r := sketch_row_rect(i)
		bg := rl.Color{28, 28, 34, 255}
		if i == app.current             { bg = rl.Color{54, 60, 82, 255} }
		else if rl.CheckCollisionPointRec(mouse, r) { bg = rl.Color{40, 40, 48, 255} }
		rl.DrawRectangleRec(r, bg)
		fg := i == app.current ? rl.Color{235, 235, 240, 255} : rl.Color{170, 170, 180, 255}
		draw_text(strings.clone_to_cstring(name, context.temp_allocator), 10, r.y+5, 17, fg)
	}
	rl.DrawRectangle(SIDEBAR_W-1, TOOLBAR_H, 1, sh-TOOLBAR_H, rl.Color{50, 50, 58, 255})
}

// Handle a click in the sidebar (the + New button, or a sketch row).
sidebar_click :: proc(app: ^App) {
	if !rl.IsMouseButtonPressed(.LEFT) { return }
	m := rl.GetMousePosition()
	if rl.CheckCollisionPointRec(m, new_button_rect()) {
		app.naming = true
		clear(&app.name_buf)
		return
	}
	if app.naming { return } // finish naming (Enter/Esc) before switching
	for _, i in app.sketches {
		if rl.CheckCollisionPointRec(m, sketch_row_rect(i)) {
			open_sketch(app, i)
			return
		}
	}
}

draw_ui :: proc(app: ^App) {
	rl.ClearBackground(rl.Color{24, 24, 28, 255})

	// editor (right of sidebar, between toolbar and console strip)
	editor_draw(&app.buf, editor_area(), &app.ed_scroll)

	// sidebar (sketch list) and console strip
	draw_sidebar(app)
	draw_console_strip(app, int(rl.GetScreenHeight()) - CONSOLE_H)

	// toolbar on top
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), TOOLBAR_H, rl.Color{32, 32, 38, 255})
	draw_button(RUN_RECT, "Run", app.status != .Running && app.status != .Compiling)
	draw_button(STOP_RECT, "Stop", app.status == .Running)
	draw_text(status_text(app.status), 210, 14, 20, rl.Color{200, 200, 210, 255})
	draw_text(strings.clone_to_cstring(current_name(app), context.temp_allocator), 340, 14, 20, rl.Color{130, 160, 210, 255})
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
	list_sketches(&app)
	// initial sketch: first positional arg (e.g. `odessa attractor`), else "hello"
	app.current = 0
	want := "hello"
	for a in os.args[1:] {
		if len(a) >= 2 && a[:2] == "--" { continue }
		want = a
		break
	}
	for name, i in app.sketches {
		if name == want { app.current = i; break }
	}
	load_sketch(&app)
	defer editor.destroy_buffer(&app.buf)
	defer { for s in app.sketches { delete(s) }; delete(app.sketches); delete(app.name_buf) }

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

		// sketch list clicks (+ New, or switch the open sketch)
		sidebar_click(&app)

		if app.naming {
			// typing the name of a new sketch — editor input is suspended
			name_input(&app)
		} else {
			// editor edits (typing goes here; Ctrl combos for run/save handled below)
			prev_cursor := app.buf.cursor
			editor_input(&app.buf)
			editor_mouse(&app.buf, editor_area(), app.ed_scroll)
			// only chase the cursor when it actually moved (so wheel scrolling sticks)
			if app.buf.cursor != prev_cursor {
				ensure_cursor_visible(&app.buf, &app.ed_scroll, editor_visible_lines(editor_area()))
			}
		}

		if ctrl && rl.IsKeyPressed(.S) { save_sketch(&app) }
		// Ctrl +/- : adjust editor font size
		if ctrl && (rl.IsKeyPressed(.EQUAL) || rl.IsKeyPressed(.KP_ADD))      { g_ed_font = clamp(g_ed_font+2, 10, 40) }
		if ctrl && (rl.IsKeyPressed(.MINUS) || rl.IsKeyPressed(.KP_SUBTRACT)) { g_ed_font = clamp(g_ed_font-2, 10, 40) }

		run_now  := button_clicked(RUN_RECT, app.status != .Running && app.status != .Compiling) || (ctrl && rl.IsKeyPressed(.R))
		stop_now := button_clicked(STOP_RECT, app.status == .Running)

		if run_now  { do_run(&app) }
		if stop_now { do_stop(&app) }

		// Mouse wheel: Ctrl+wheel zooms; otherwise scroll whichever pane is hovered.
		if wheel := rl.GetMouseWheelMove(); wheel != 0 {
			if ctrl {
				g_ed_font = clamp(g_ed_font + wheel, 10, 40)
			} else if rl.CheckCollisionPointRec(rl.GetMousePosition(), editor_area()) {
				app.ed_scroll -= int(wheel * 3)
			} else {
				app.console_scroll -= int(wheel * 3)
			}
		}
		// Clamp both scrolls (guards shrunk window / font changes).
		app.console_scroll = clamp(app.console_scroll, 0, max(0, len(app.console_lines) - console_visible_lines()))
		app.ed_scroll      = clamp(app.ed_scroll, 0, max(0, len(app.buf.lines) - editor_visible_lines(editor_area())))

		// --- draw ---
		rl.BeginDrawing()
		draw_ui(&app)
		rl.EndDrawing()

		free_all(context.temp_allocator) // reclaim per-frame temp allocations (console cstrings, etc.)
	}

	runner.stop(&app.run) // hygiene: never orphan the sketch
}
