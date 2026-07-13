package main

import rl "vendor:raylib"
import "core:os"
import "core:strings"
import "../runner"
import "../editor"
import "../sketch"

// Logical (DPI-independent) drawable size. raylib's GetScreenWidth/Height are
// unreliable under WINDOW_HIGHDPI after a resize (they flip to physical), but
// GetRenderWidth/Height stay consistently physical — so derive logical size
// from render size / DPI. All layout uses these.
ui_scale :: proc() -> f32 {
	s := rl.GetWindowScaleDPI().x
	return s < 1 ? 1 : s
}
screen_w :: proc() -> i32 { return i32(f32(rl.GetRenderWidth()) / ui_scale()) }
screen_h :: proc() -> i32 { return i32(f32(rl.GetRenderHeight()) / ui_scale()) }

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
	// Bake the glyph atlas at the display's physical pixel density so text stays
	// crisp on high-DPI screens (glyphs are drawn from a higher-res atlas).
	dpi := rl.GetWindowScaleDPI().x
	if dpi < 1 { dpi = 1 }
	base := i32(f32(FONT_BASE) * dpi)

	candidates := []string{
		// Windows
		"C:/Windows/Fonts/consola.ttf",     // Consolas: narrow, light, very readable
		"C:/Windows/Fonts/CascadiaMono.ttf",
		"C:/Windows/Fonts/CascadiaCode.ttf",
		// macOS
		"/System/Library/Fonts/Menlo.ttc",
		"/System/Library/Fonts/SFNSMono.ttf",
		"/Library/Fonts/Menlo.ttc",
		// Linux
		"/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
		"/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf",
		"/usr/share/fonts/TTF/DejaVuSansMono.ttf",
		"/usr/share/fonts/jetbrains-mono/JetBrainsMono-Regular.ttf",
	}
	for path in candidates {
		if os.exists(path) {
			f := rl.LoadFontEx(strings.clone_to_cstring(path, context.temp_allocator), base, nil, 0)
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
sketch_dir     :: proc(name: string) -> string { return strings.concatenate({SKETCHES_ROOT, "/", name}, context.temp_allocator) }
sketch_exe     :: proc(name: string) -> string { return strings.concatenate({"build/", name, ".exe"}, context.temp_allocator) }
main_file_name :: proc(name: string) -> string { return strings.concatenate({name, ".odin"}, context.temp_allocator) }
file_path      :: proc(sketch_name, file: string) -> string { return strings.concatenate({SKETCHES_ROOT, "/", sketch_name, "/", file}, context.temp_allocator) }

// Name of the currently-open sketch.
current_name :: proc(app: ^App) -> string {
	if app.current >= 0 && app.current < len(app.sketches) { return app.sketches[app.current] }
	return "hello"
}

// Name / path of the file currently open in the editor.
current_file_name :: proc(app: ^App) -> string {
	if app.current_file >= 0 && app.current_file < len(app.files) { return app.files[app.current_file] }
	return main_file_name(current_name(app))
}
current_file_path :: proc(app: ^App) -> string { return file_path(current_name(app), current_file_name(app)) }

// Re-select the open file / sketch by name after a relist rebuilt the slice
// (indices shift). Falls back to index 0 when the name is gone.
select_file_by_name :: proc(app: ^App, name: string) {
	app.current_file = 0
	for f, i in app.files { if f == name { app.current_file = i; break } }
}
select_sketch_by_name :: proc(app: ^App, name: string) {
	app.current = 0
	for n, i in app.sketches { if n == name { app.current = i; break } }
}

RUN_RECT  :: rl.Rectangle{46, 8, 90, 32}
STOP_RECT :: rl.Rectangle{144, 8, 90, 32}
DOCS_RECT :: rl.Rectangle{242, 8, 76, 32}

// Toggle the docs panel (jumps to the symbol under the cursor when opening).
docs_toggle :: proc(app: ^App) {
	if g_docs_open { g_docs_open = false } else { docs_open_at_cursor(&app.buf) }
}

Status :: enum { Idle, Compiling, Running, Compile_Error }

// Which inline text field (if any) is currently capturing keystrokes.
Input_Mode :: enum { None, New_Sketch, New_File, Rename_File }
// Which sidebar popup (if any) is open on a file row.
Menu_Kind :: enum { None, Context, Confirm_Delete }

App :: struct {
	run:            runner.Runner,
	status:         Status,
	console:        string,   // last build output (owned)
	console_lines:  []string, // console split into lines once per build (owned; slices into console)
	console_scroll: int,      // first visible line index
	buf:            editor.Buffer, // the file source being edited
	ed_scroll:      int,           // editor's first visible line
	sketches:       [dynamic]string, // sketch names found under sketches/
	current:        int,             // index into sketches (the open one)
	files:          [dynamic]string, // active sketch's .odin files (main first, then A–Z)
	current_file:   int,             // index into files (the open one)
	input_mode:     Input_Mode,      // active inline text field, if any
	name_buf:       [dynamic]u8,     // the name being typed (new sketch / new file / rename)
	menu_file:      int,             // file index a context menu / delete-confirm targets
	menu_kind:      Menu_Kind,       // which file-row popup is open, if any
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

// Number of console lines that fit in the bottom strip (below its label).
console_visible_lines :: proc() -> int {
	return (CONSOLE_H - CONSOLE_PAD) / LINE_H
}

// Editor area: right of the sidebar, below the toolbar, above the console strip.
editor_area :: proc() -> rl.Rectangle {
	h := int(screen_h()) - TOOLBAR_H - CONSOLE_H
	if h < 0 { h = 0 }
	return rl.Rectangle{SIDEBAR_W, TOOLBAR_H, f32(int(screen_w()) - SIDEBAR_W), f32(h)}
}

// Populate app.sketches from the subdirectories of sketches/.
list_sketches :: proc(app: ^App) {
	for s in app.sketches { delete(s) }
	clear(&app.sketches)
	fis, err := os.read_all_directory_by_path(SKETCHES_ROOT, context.allocator)
	if err != nil { return }
	defer os.file_info_slice_delete(fis, context.allocator) // free the listing
	for f in fis {
		if f.type == .Directory {
			append(&app.sketches, strings.clone(f.name))
		}
	}
}

// Populate app.files from the active sketch's .odin files (main first, then A–Z).
list_files :: proc(app: ^App) {
	for f in app.files { delete(f) }
	clear(&app.files)
	dir := current_name(app)
	fis, err := os.read_all_directory_by_path(sketch_dir(dir), context.allocator)
	if err != nil { return }
	defer os.file_info_slice_delete(fis, context.allocator)
	raw := make([dynamic]string, 0, len(fis), context.temp_allocator)
	for f in fis {
		if f.type != .Directory && sketch.is_odin_file(f.name) {
			append(&raw, f.name) // borrowed from fis; cloned below, before fis is freed
		}
	}
	ordered := sketch.order_files(raw[:], main_file_name(dir), context.temp_allocator)
	for name in ordered { append(&app.files, strings.clone(name)) }
}

// Read the current file into the editor buffer (blank buffer if it can't be read).
load_file :: proc(app: ^App) {
	data, err := os.read_entire_file_from_path(current_file_path(app), context.allocator)
	if err != nil {
		app.buf = editor.make_buffer("")
		return
	}
	defer delete(data)
	app.buf = editor.make_buffer(string(data))
}

// Write the editor buffer to the current file. Returns whether it succeeded.
// For an empty sketch (no .odin files) current_file_path falls back to the main
// file, so a first save materializes <name>.odin rather than being discarded.
save_current_file :: proc(app: ^App) -> bool {
	s := editor.to_string(&app.buf, context.temp_allocator)
	return os.write_entire_file(current_file_path(app), transmute([]u8)s) == nil
}

// Surface a one-line error message in the console.
console_error :: proc(app: ^App, msg: string) {
	if app.console_lines != nil { delete(app.console_lines); app.console_lines = nil }
	if app.console != "" { delete(app.console) }
	app.console = strings.clone(msg)
	app.console_lines = strings.split_lines(app.console, context.allocator)
	app.status = .Compile_Error
}

// Switch the open sketch: persist current edits, then load its main file.
open_sketch :: proc(app: ^App, idx: int) {
	if idx < 0 || idx >= len(app.sketches) || idx == app.current { return }
	if !save_current_file(app) { // don't discard unsaved edits on a failed write
		console_error(app, strings.concatenate({"Could not save ", current_file_name(app), " — staying here."}, context.temp_allocator))
		return
	}
	editor.destroy_buffer(&app.buf)
	app.current = idx
	app.current_file = 0
	app.ed_scroll = 0
	app.menu_kind = .None
	list_files(app)
	load_file(app)
}

// Switch the open file within the active sketch: persist current edits, then load.
open_file :: proc(app: ^App, idx: int) {
	if idx < 0 || idx >= len(app.files) || idx == app.current_file { return }
	if !save_current_file(app) {
		console_error(app, strings.concatenate({"Could not save ", current_file_name(app), " — staying here."}, context.temp_allocator))
		return
	}
	editor.destroy_buffer(&app.buf)
	app.current_file = idx
	app.ed_scroll = 0
	app.menu_kind = .None
	load_file(app)
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

	if !save_current_file(app) { // persist current edits before switching away
		console_error(app, strings.concatenate({"Could not save ", current_file_name(app), " — new sketch not created."}, context.temp_allocator))
		return
	}
	if err := os.make_directory(sketch_dir(name)); err != nil { return }
	main := file_path(name, main_file_name(name))
	if os.write_entire_file(main, transmute([]u8)string(NEW_SKETCH_TEMPLATE)) != nil {
		console_error(app, strings.concatenate({"Could not write ", main}, context.temp_allocator))
		return
	}
	editor.destroy_buffer(&app.buf)
	list_sketches(app)   // rescan so the new sketch appears
	select_sketch_by_name(app, name)
	app.current_file = 0
	app.ed_scroll = 0
	list_files(app)
	load_file(app)
}

// Create a new .odin file in the active sketch from name_buf, then open it.
create_file :: proc(app: ^App) {
	stem := strings.clone(string(app.name_buf[:]), context.temp_allocator)
	clear(&app.name_buf)
	if !sketch.valid_file_name(stem) { return }
	fname := sketch.ensure_odin_ext(stem, context.temp_allocator)
	if os.exists(file_path(current_name(app), fname)) { return } // don't clobber
	if !save_current_file(app) {
		console_error(app, strings.concatenate({"Could not save ", current_file_name(app), " — file not created."}, context.temp_allocator))
		return
	}
	// Seed with just the package clause — no imports, so it always compiles.
	if os.write_entire_file(file_path(current_name(app), fname), transmute([]u8)string("package main\n\n")) != nil {
		console_error(app, strings.concatenate({"Could not write ", fname}, context.temp_allocator))
		return
	}
	editor.destroy_buffer(&app.buf)
	list_files(app)
	select_file_by_name(app, fname)
	app.ed_scroll = 0
	load_file(app)
}

// Rename the file at idx (never the main file) to name_buf's value.
rename_file :: proc(app: ^App, idx: int) {
	if idx < 0 || idx >= len(app.files) { return }
	if app.files[idx] == main_file_name(current_name(app)) { return } // main is protected
	stem := strings.clone(string(app.name_buf[:]), context.temp_allocator)
	clear(&app.name_buf)
	if !sketch.valid_file_name(stem) { return }
	newname := sketch.ensure_odin_ext(stem, context.temp_allocator)
	if newname == app.files[idx] { return } // no-op
	if os.exists(file_path(current_name(app), newname)) { return } // don't clobber

	was_open := idx == app.current_file
	// The file that should stay open afterwards, captured by name (indices shift
	// on relist, and old app.files strings are freed by list_files).
	open_name := was_open ? newname : strings.clone(current_file_name(app), context.temp_allocator)
	if was_open && !save_current_file(app) {
		console_error(app, strings.concatenate({"Could not save ", current_file_name(app), " — not renamed."}, context.temp_allocator))
		return
	}
	if os.rename(file_path(current_name(app), app.files[idx]), file_path(current_name(app), newname)) != nil {
		console_error(app, strings.concatenate({"Could not rename to ", newname}, context.temp_allocator))
		return
	}
	if was_open { editor.destroy_buffer(&app.buf) }
	list_files(app)
	select_file_by_name(app, open_name)
	if was_open { load_file(app) }
}

// Delete the file at idx (never the main file).
delete_file :: proc(app: ^App, idx: int) {
	if idx < 0 || idx >= len(app.files) { return }
	if app.files[idx] == main_file_name(current_name(app)) { return } // main is protected
	deleting_open := idx == app.current_file
	// Keep editing the same file if we're deleting a different one.
	open_name := deleting_open ? "" : strings.clone(current_file_name(app), context.temp_allocator)
	if os.remove(file_path(current_name(app), app.files[idx])) != nil {
		console_error(app, strings.concatenate({"Could not delete ", app.files[idx]}, context.temp_allocator))
		return
	}
	if deleting_open {
		editor.destroy_buffer(&app.buf)
		list_files(app)
		app.current_file = 0 // main file leads after ordering
		app.ed_scroll = 0
		load_file(app)
	} else {
		list_files(app) // buffer untouched; just fix the open file's index
		select_file_by_name(app, open_name)
	}
}

// Seed name_buf with a file's stem (its name without the ".odin" suffix).
seed_stem :: proc(app: ^App, filename: string) {
	clear(&app.name_buf)
	stem := filename
	if sketch.is_odin_file(stem) { stem = stem[:len(stem)-5] } // strip ".odin"
	for i in 0..<len(stem) { append(&app.name_buf, stem[i]) }
}

// One frame of inline text-field input (active while app.input_mode != .None).
name_input :: proc(app: ^App) {
	for r := rl.GetCharPressed(); r != 0; r = rl.GetCharPressed() {
		if r < 128 && is_name_char(u8(r)) && len(app.name_buf) < 40 {
			append(&app.name_buf, u8(r))
		}
	}
	if key_go(.BACKSPACE) && len(app.name_buf) > 0 { pop(&app.name_buf) }
	if rl.IsKeyPressed(.ENTER) {
		switch app.input_mode {
		case .New_Sketch:  create_sketch(app)
		case .New_File:    create_file(app)
		case .Rename_File: rename_file(app, app.menu_file)
		case .None:
		}
		app.input_mode = .None
	}
	if rl.IsKeyPressed(.ESCAPE) { clear(&app.name_buf); app.input_mode = .None }
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

// Draw a labeled button (no side effects). Primary = filled accent; secondary
// = quiet filled surface.
draw_button :: proc(rect: rl.Rectangle, label: cstring, enabled: bool, primary := false) {
	hover := enabled && rl.CheckCollisionPointRec(rl.GetMousePosition(), rect)
	fg: rl.Color
	if primary {
		bg := ACCENT_DK
		if enabled { bg = hover ? rl.Color{132, 214, 255, 255} : ACCENT }
		rl.DrawRectangleRounded(rect, 0.35, 6, bg)
		fg = enabled ? BG_DEEP : FG_DIM
	} else {
		bg := enabled ? (hover ? BG_HOVER : BG_RAISE) : BG_RAISE
		rl.DrawRectangleRounded(rect, 0.35, 6, bg)
		fg = enabled ? FG : FG_DIM
	}
	tw := measure(label, 18)
	draw_text(label, rect.x + (rect.width-tw)/2, rect.y + (rect.height-18)/2, 18, fg)
}

do_run :: proc(app: ^App) {
	if !save_current_file(app) { // persist the editor buffer, then build what's on disk
		console_error(app, strings.concatenate({"Could not save ", current_file_name(app), " — not running."}, context.temp_allocator))
		return
	}
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
	if runner.launch(&app.run, sketch_exe(current_name(app))) {
		app.status = .Running
	} else {
		console_error(app, strings.concatenate({"Compiled, but could not launch ", sketch_exe(name), " (locked by antivirus?)."}, context.temp_allocator))
	}
}

do_stop :: proc(app: ^App) {
	runner.stop(&app.run)
	app.status = .Idle
}

// Pure render of the (already-clamped) console as a fixed bottom strip starting
// at top_y. Scroll clamping lives in the update phase; no side effects.
CONSOLE_PAD :: 22 // room for the CONSOLE eyebrow label

draw_console_strip :: proc(app: ^App, top_y: int) {
	top := i32(top_y)
	bottom := screen_h()
	if bottom <= top { return }
	rl.DrawRectangle(0, top, screen_w(), bottom-top, BG_PANEL)
	rl.DrawRectangle(0, top, screen_w(), 1, LINE) // hairline divider
	draw_eyebrow("CONSOLE", 12, f32(top)+6)

	if len(app.console_lines) == 0 {
		draw_text("build output appears here", 12, f32(top)+CONSOLE_PAD, FONT_SIZE, FG_DIM)
		return
	}

	col := app.status == .Compile_Error ? DANGER : FG

	max_visible := (int(bottom-top) - CONSOLE_PAD) / LINE_H
	y := f32(top) + CONSOLE_PAD
	for i := app.console_scroll; i < len(app.console_lines) && (i - app.console_scroll) < max_visible; i += 1 {
		ctext := strings.clone_to_cstring(app.console_lines[i], context.temp_allocator)
		draw_text(ctext, 12, y, FONT_SIZE, col)
		y += LINE_H
	}
}

SIDEBAR_TOP  :: TOOLBAR_H + 26 // room for the SKETCHES eyebrow
FILE_INDENT  :: 22             // x offset for file rows under the active sketch

// A single sidebar row. build_rows lays these out top-to-bottom so drawing and
// hit-testing share one source of truth (the active sketch expands into files).
Row_Kind :: enum { New_Sketch, Sketch, File, New_File }
Row :: struct {
	kind:   Row_Kind,
	sketch: int, // index into app.sketches (Sketch / File / New_File)
	file:   int, // index into app.files    (File)
	rect:   rl.Rectangle,
}

build_rows :: proc(app: ^App) -> []Row {
	rows := make([dynamic]Row, 0, 2 + len(app.sketches) + len(app.files), context.temp_allocator)
	y := f32(SIDEBAR_TOP)
	append(&rows, Row{ kind = .New_Sketch, rect = rl.Rectangle{8, y, SIDEBAR_W-16, SKETCH_ROW-4} })
	y += SKETCH_ROW
	for _, si in app.sketches {
		append(&rows, Row{ kind = .Sketch, sketch = si, rect = rl.Rectangle{0, y, SIDEBAR_W, SKETCH_ROW} })
		y += SKETCH_ROW
		if si == app.current { // only the active sketch expands into its files
			for _, fi in app.files {
				append(&rows, Row{ kind = .File, sketch = si, file = fi, rect = rl.Rectangle{0, y, SIDEBAR_W, SKETCH_ROW} })
				y += SKETCH_ROW
			}
			append(&rows, Row{ kind = .New_File, sketch = si, rect = rl.Rectangle{8, y, SIDEBAR_W-16, SKETCH_ROW-4} })
			y += SKETCH_ROW
		}
	}
	return rows[:]
}

// Locate an open file row's rect (for anchoring its context menu / confirm).
file_row_rect :: proc(rows: []Row, fileidx: int) -> (rl.Rectangle, bool) {
	for row in rows {
		if row.kind == .File && row.file == fileidx { return row.rect, true }
	}
	return {}, false
}

// Geometry for the file context menu and the inline delete-confirm buttons,
// derived from a file row's rect so draw and click never disagree.
menu_rect :: proc(anchor: rl.Rectangle) -> rl.Rectangle {
	return rl.Rectangle{anchor.x + 40, anchor.y + anchor.height - 4, 112, 56}
}
menu_item_rects :: proc(mr: rl.Rectangle) -> (ren, del: rl.Rectangle) {
	ren = rl.Rectangle{mr.x, mr.y,      mr.width, 28}
	del = rl.Rectangle{mr.x, mr.y + 28, mr.width, 28}
	return
}
confirm_rects :: proc(r: rl.Rectangle) -> (cancel, del: rl.Rectangle) {
	cancel = rl.Rectangle{r.x + r.width - 104, r.y, 52, r.height}
	del    = rl.Rectangle{r.x + r.width - 52,  r.y, 52, r.height}
	return
}

// Fit a filename into maxw pixels, middle-truncating with '~' while keeping the
// ".odin" suffix visible.
fit_name :: proc(name: string, maxw, size: f32) -> cstring {
	full := strings.clone_to_cstring(name, context.temp_allocator)
	if measure(full, size) <= maxw { return full }
	stem := name; suffix := ""
	if sketch.is_odin_file(name) { stem = name[:len(name)-5]; suffix = ".odin" }
	trunc :: proc(stem: string, k: int, suffix: string) -> cstring {
		return strings.clone_to_cstring(strings.concatenate({stem[:k], "~", suffix}, context.temp_allocator), context.temp_allocator)
	}
	// Rendered width grows monotonically with k, so binary-search the widest
	// stem[:k] + "~" + suffix that still fits (O(log n) measures, not O(n)).
	lo, hi := 0, len(stem)
	for lo < hi {
		mid := (lo + hi + 1) / 2
		if measure(trunc(stem, mid, suffix), size) <= maxw { lo = mid } else { hi = mid - 1 }
	}
	return trunc(stem, lo, suffix)
}

@(private="file") inline_field :: proc(app: ^App, r: rl.Rectangle, x_off, size: f32) {
	rl.DrawRectangleRounded(r, 0.3, 6, ACCENT_DK)
	label := strings.clone_to_cstring(strings.concatenate({string(app.name_buf[:]), "_"}, context.temp_allocator), context.temp_allocator)
	draw_text(label, r.x+x_off, r.y+3, size, FG_BRIGHT)
}

draw_sidebar :: proc(app: ^App) {
	sh := screen_h()
	rl.DrawRectangle(0, TOOLBAR_H, SIDEBAR_W, sh-TOOLBAR_H, BG_PANEL)
	mouse := rl.GetMousePosition()
	draw_eyebrow("SKETCHES", 12, f32(TOOLBAR_H)+8)

	rows := build_rows(app)
	menu_anchor: rl.Rectangle
	for row in rows {
		r := row.rect
		switch row.kind {
		case .New_Sketch:
			if app.input_mode == .New_Sketch {
				inline_field(app, r, 8, 16)
			} else {
				hov := rl.CheckCollisionPointRec(mouse, r)
				rl.DrawRectangleRounded(r, 0.3, 6, hov ? BG_HOVER : BG_RAISE)
				draw_text("+  New sketch", r.x+8, r.y+3, 16, hov ? ACCENT : FG_DIM)
			}
		case .Sketch:
			active := row.sketch == app.current
			if active {
				rl.DrawRectangleRec(r, BG_SEL)
				rl.DrawRectangle(0, i32(r.y), 3, i32(r.height), ACCENT) // signature accent bar
			} else if rl.CheckCollisionPointRec(mouse, r) {
				rl.DrawRectangleRec(r, BG_HOVER)
			}
			fg := active ? FG_BRIGHT : FG_DIM
			draw_text(strings.clone_to_cstring(app.sketches[row.sketch], context.temp_allocator), 14, r.y+5, 17, fg)
		case .File:
			if row.file == app.menu_file { menu_anchor = r }
			// delete-confirm replaces the row
			if app.menu_kind == .Confirm_Delete && row.file == app.menu_file {
				rl.DrawRectangleRec(r, BG_SEL)
				draw_text("delete?", FILE_INDENT, r.y+6, 15, DANGER)
				cancel, del := confirm_rects(r)
				draw_text("keep", cancel.x+8, cancel.y+6, 14, FG_DIM)
				draw_text("del", del.x+10, del.y+6, 14, DANGER)
				continue
			}
			// inline rename field replaces the row
			if app.input_mode == .Rename_File && row.file == app.menu_file {
				rl.DrawRectangleRec(r, ACCENT_DK)
				label := strings.clone_to_cstring(strings.concatenate({string(app.name_buf[:]), "_"}, context.temp_allocator), context.temp_allocator)
				draw_text(label, FILE_INDENT, r.y+6, 16, FG_BRIGHT)
				continue
			}
			is_open := row.file == app.current_file
			if is_open {
				rl.DrawRectangleRec(r, BG_SEL)
				rl.DrawRectangle(0, i32(r.y), 3, i32(r.height), ACCENT)
			} else if rl.CheckCollisionPointRec(mouse, r) {
				rl.DrawRectangleRec(r, BG_HOVER)
			}
			fg := is_open ? FG_BRIGHT : FG
			draw_text(fit_name(app.files[row.file], SIDEBAR_W-FILE_INDENT-6, 16), FILE_INDENT, r.y+6, 16, fg)
		case .New_File:
			if app.input_mode == .New_File {
				inline_field(app, r, FILE_INDENT-8, 15)
			} else {
				hov := rl.CheckCollisionPointRec(mouse, r)
				if hov { rl.DrawRectangleRounded(r, 0.25, 6, BG_HOVER) }
				draw_text("+ file", r.x+FILE_INDENT-8, r.y+3, 15, hov ? ACCENT : FG_DIM)
			}
		}
	}

	// file context menu overlays the rows
	if app.menu_kind == .Context {
		mr := menu_rect(menu_anchor)
		is_main := app.menu_file >= 0 && app.menu_file < len(app.files) && app.files[app.menu_file] == main_file_name(current_name(app))
		ren, del := menu_item_rects(mr)
		rl.DrawRectangleRounded(mr, 0.15, 6, BG_RAISE)
		if !is_main && rl.CheckCollisionPointRec(mouse, ren) { rl.DrawRectangleRounded(ren, 0.15, 6, BG_HOVER) }
		if !is_main && rl.CheckCollisionPointRec(mouse, del) { rl.DrawRectangleRounded(del, 0.15, 6, BG_HOVER) }
		draw_text("Rename", ren.x+12, ren.y+6, 15, is_main ? FG_DIM : FG)
		draw_text("Delete", del.x+12, del.y+6, 15, is_main ? FG_DIM : DANGER)
	}

	rl.DrawRectangle(SIDEBAR_W-1, TOOLBAR_H, 1, sh-TOOLBAR_H, LINE)
}

// Handle a click in the sidebar: file popups first, then rows.
sidebar_click :: proc(app: ^App) {
	left  := rl.IsMouseButtonPressed(.LEFT)
	right := rl.IsMouseButtonPressed(.RIGHT)
	if !left && !right { return }
	if app.input_mode != .None { return } // finish the inline field (Enter/Esc) first
	m := rl.GetMousePosition()
	rows := build_rows(app)

	// an open context menu captures the next click
	if app.menu_kind == .Context {
		if !left { return }
		anchor, ok := file_row_rect(rows, app.menu_file)
		if ok {
			mr := menu_rect(anchor)
			ren, del := menu_item_rects(mr)
			is_main := app.files[app.menu_file] == main_file_name(current_name(app))
			if !is_main && rl.CheckCollisionPointRec(m, ren) {
				seed_stem(app, app.files[app.menu_file])
				app.input_mode = .Rename_File
				app.menu_kind = .None
				return
			}
			if !is_main && rl.CheckCollisionPointRec(m, del) { app.menu_kind = .Confirm_Delete; return }
		}
		app.menu_kind = .None // click anywhere else closes it
		return
	}
	// an open delete-confirm captures the next click
	if app.menu_kind == .Confirm_Delete {
		if !left { return }
		anchor, ok := file_row_rect(rows, app.menu_file)
		if ok {
			cancel, del := confirm_rects(anchor)
			if rl.CheckCollisionPointRec(m, del)    { delete_file(app, app.menu_file); app.menu_kind = .None; return }
			if rl.CheckCollisionPointRec(m, cancel) { app.menu_kind = .None; return }
		}
		app.menu_kind = .None
		return
	}

	for row in rows {
		if !rl.CheckCollisionPointRec(m, row.rect) { continue }
		switch row.kind {
		case .New_Sketch:
			if left { app.input_mode = .New_Sketch; clear(&app.name_buf) }
		case .Sketch:
			if left { open_sketch(app, row.sketch) }
		case .File:
			if right      { app.menu_file = row.file; app.menu_kind = .Context }
			else if left  { open_file(app, row.file) }
		case .New_File:
			if left { app.input_mode = .New_File; clear(&app.name_buf) }
		}
		return
	}
}

// small status dot color per state
status_dot :: proc(s: Status) -> rl.Color {
	switch s {
	case .Running:       return ACCENT
	case .Compiling:     return rl.Color{221, 161, 106, 255} // amber
	case .Compile_Error: return DANGER
	case .Idle:          return FG_DIM
	}
	return FG_DIM
}

draw_ui :: proc(app: ^App) {
	rl.ClearBackground(BG_DEEP)

	// editor (right of sidebar, between toolbar and console strip)
	editor_draw(&app.buf, editor_area(), &app.ed_scroll)
	if app.input_mode == .None { ac_draw(&app.buf, editor_area(), app.ed_scroll) }

	// sidebar (sketch list) and console strip
	draw_sidebar(app)
	draw_console_strip(app, int(screen_h()) - CONSOLE_H)

	// docs panel overlays the workspace when open
	if g_docs_open { docs_draw() }

	// toolbar
	rl.DrawRectangle(0, 0, screen_w(), TOOLBAR_H, BG_RAISE)
	rl.DrawRectangle(0, TOOLBAR_H-1, screen_w(), 1, LINE) // hairline
	draw_logo(24, 24, 13, 2.5, ACCENT) // the Rune mark
	draw_button(RUN_RECT, "Run", app.status != .Running && app.status != .Compiling, primary = true)
	draw_button(STOP_RECT, "Stop", app.status == .Running)
	draw_button(DOCS_RECT, g_docs_open ? "Editor" : "Docs", true)

	// current sketch name (accent) — the throughline tying chrome to the art
	draw_text(strings.clone_to_cstring(current_name(app), context.temp_allocator), 334, 15, 20, ACCENT)


	// status: a dot + label, right-aligned
	label := status_text(app.status)
	lw := measure(label, 16)
	sx := f32(screen_w()) - lw - 20
	rl.DrawCircle(i32(sx)-12, 24, 4, status_dot(app.status))
	draw_text(label, sx, 16, 16, FG_DIM)
}

main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .WINDOW_HIGHDPI, .MSAA_4X_HINT})
	rl.InitWindow(1100, 760, "Rune")
	rl.SetTargetFPS(60)
	defer rl.CloseWindow()

	load_ui_font()
	defer if g_font_custom { rl.UnloadFont(g_font) }
	set_window_icon()

	app: App
	app.status = .Idle
	list_sketches(&app)
	// initial sketch: first positional arg (e.g. `rune attractor`), else "hello"
	want := "hello"
	for a in os.args[1:] {
		if len(a) >= 2 && a[:2] == "--" { continue }
		want = a
		break
	}
	select_sketch_by_name(&app, want)
	app.current_file = 0
	list_files(&app)
	load_file(&app)
	defer editor.destroy_buffer(&app.buf)
	defer { for s in app.sketches { delete(s) }; delete(app.sketches); for f in app.files { delete(f) }; delete(app.files); delete(app.name_buf); delete(g_ac_matches); delete(g_ac_prefix); delete(g_docs_search); delete(g_docs_filtered) }

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

		// F1 or the Docs button toggles the reference panel (always available)
		if rl.IsKeyPressed(.F1) || button_clicked(DOCS_RECT, true) { docs_toggle(&app) }

		// Run / Stop always available
		run_now  := button_clicked(RUN_RECT, app.status != .Running && app.status != .Compiling) || (ctrl && rl.IsKeyPressed(.R))
		stop_now := button_clicked(STOP_RECT, app.status == .Running)
		if run_now  { do_run(&app) }
		if stop_now { do_stop(&app) }

		if g_docs_open {
			docs_input()
		} else {
			// sketch list clicks (+ New, or switch the open sketch)
			sidebar_click(&app)

			if app.input_mode != .None {
				name_input(&app) // editor input suspended while an inline field is active
			} else if app.menu_kind != .None {
				// a file popup is open: swallow editor keystrokes; Esc closes it
				if rl.IsKeyPressed(.ESCAPE) { app.menu_kind = .None }
			} else {
				prev_cursor := app.buf.cursor
				editor_input(&app.buf)
				editor_mouse(&app.buf, editor_area(), app.ed_scroll)
				if app.buf.cursor != prev_cursor {
					ensure_cursor_visible(&app.buf, &app.ed_scroll, editor_visible_lines(editor_area()))
				}
				if ctrl && rl.IsKeyPressed(.S) { save_current_file(&app) }
				if ctrl && (rl.IsKeyPressed(.EQUAL) || rl.IsKeyPressed(.KP_ADD))      { g_ed_font = clamp(g_ed_font+2, 10, 40) }
				if ctrl && (rl.IsKeyPressed(.MINUS) || rl.IsKeyPressed(.KP_SUBTRACT)) { g_ed_font = clamp(g_ed_font-2, 10, 40) }
			}

			// Mouse wheel: Ctrl+wheel zooms; otherwise scroll the hovered pane.
			if wheel := rl.GetMouseWheelMove(); wheel != 0 {
				if ctrl {
					g_ed_font = clamp(g_ed_font + wheel, 10, 40)
				} else if rl.CheckCollisionPointRec(rl.GetMousePosition(), editor_area()) {
					app.ed_scroll -= int(wheel * 3)
				} else {
					app.console_scroll -= int(wheel * 3)
				}
			}
			app.console_scroll = clamp(app.console_scroll, 0, max(0, len(app.console_lines) - console_visible_lines()))
			app.ed_scroll      = clamp(app.ed_scroll, 0, max(0, len(app.buf.lines) - editor_visible_lines(editor_area())))
		}

		// --- draw ---
		rl.BeginDrawing()
		draw_ui(&app)
		rl.EndDrawing()

		free_all(context.temp_allocator) // reclaim per-frame temp allocations (console cstrings, etc.)
	}

	runner.stop(&app.run) // hygiene: never orphan the sketch
}
