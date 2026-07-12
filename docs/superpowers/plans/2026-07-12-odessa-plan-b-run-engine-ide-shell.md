# Odessa Plan B — Run/Stop Engine + IDE Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Odessa IDE window: a raylib app with a **Run ▶ / Stop ■** toolbar, a **status line**, and a **console** that compiles the current sketch, launches it in its own window on success, kills it on Stop, and shows the compiler error on failure.

**Architecture:** A `runner` package (pure-ish, testable) wraps the compile/launch/stop lifecycle over `core:os`'s process API. The `odessa` app (`package main` → `odessa.exe`) owns a raylib window and draws an immediate-mode UI (buttons + status + console), calling into `runner`. The sketch it builds/launches is the standalone `sketches/hello` program from Plan A (which has its own `main`).

**Tech Stack:** Odin (`dev-2026-05` nightly), `vendor:raylib` (IDE window/UI), `core:os` (process API), `core:strings`, `core:testing`.

## Global Constraints

- **Language:** Odin. **The process API is in `core:os`** in this toolchain (verified): `os.Process_Desc{ command = []string{...} }`; `os.process_exec(desc, allocator) -> (state: os.Process_State, stdout: []byte, stderr: []byte, err: os.Error)` where `state.exit_code: int` (**use this** — 0 = success), `state.exited: bool`, and `state.success: bool` (means "ran to completion", NOT "exit 0" — do not use it to detect build failure); `os.process_start(desc) -> (os.Process, os.Error)`; `os.process_kill(p) -> os.Error`; `os.process_wait(p, timeout) -> (os.Process_State, os.Error)`. **`core:os/os2` does NOT exist here — do not import it.**
- **No hot reload / no DLL:** the IDE compiles and launches a standalone sketch program, and kills it. Nothing reloads.
- **Scoped simplification from the spec:** the spec (§5) says Odessa injects `main` at build time so sketch files stay clean. **This plan does NOT implement main-injection** — sketches keep the visible `main :: proc() { c.run(setup, draw) }` from Plan A, and Odessa builds the sketch directory directly. (Main-injection is deferred to a later fast-follow; noted so sketch files carry a one-line `main` for now.)
- **Which sketch:** v1 has no file picker/editor, so the IDE targets a fixed sketch by name — the constant `SKETCH_NAME :: "hello"`. Plan C's editor makes this dynamic.
- **Working directory:** the IDE is launched from the repo root; all sketch paths (`sketches/hello`, `build/hello.exe`) are relative to that root.
- **Process hygiene:** the IDE tracks the launched sketch's process and kills it on Stop, on the next Run, and on IDE exit — never leave an orphan sketch window.
- **Odin version floor:** `dev-2026-05-nightly`. **Build output dir:** `build/` (git-ignored). Canvas's 12 tests must remain green.

---

## File Structure (after this plan)

```
2026-07_odessa/
  canvas/               # unchanged (Plan A)
  sketches/hello/       # unchanged (Plan A; has its own main)
  runner/
    runner.odin         # package runner: build / launch / stop / poll over core:os  [NEW]
    runner_test.odin    # @(test) smoke tests (good build + bad build)               [NEW]
    testdata/
      good/good.odin    # a trivial valid program (no raylib) — build should succeed [NEW]
      bad/bad.odin      # a syntactically broken program — build should fail          [NEW]
  odessa/
    main.odin           # package main -> odessa.exe: raylib window + UI + wiring     [NEW]
  build_odessa.bat      # build + launch the IDE                                      [NEW]
  build/                # (git-ignored)
```

---

### Task 1: The `runner` package — build / launch / stop / poll (with smoke tests)

The compile-and-run engine, isolated from any UI so it can be unit-tested.

**Files:**
- Create: `runner/runner.odin`, `runner/runner_test.odin`
- Create: `runner/testdata/good/good.odin`, `runner/testdata/bad/bad.odin`

**Interfaces:**
- Produces:
  - `Build_Result :: struct { ok: bool, output: string }` — `output` is combined stdout+stderr, allocated in the passed allocator.
  - `build :: proc(src_dir, out_exe: string, allocator := context.allocator) -> Build_Result`
  - `Runner :: struct { running: bool, process: os.Process }`
  - `launch :: proc(r: ^Runner, exe_path: string) -> bool`
  - `stop :: proc(r: ^Runner)`
  - `poll :: proc(r: ^Runner)` — non-blocking; if the launched process has exited, set `running = false`.

- [ ] **Step 1: Create the test fixtures**

Create `runner/testdata/good/good.odin`:

```odin
package main
main :: proc() {}
```

Create `runner/testdata/bad/bad.odin` (intentionally broken — missing closing brace):

```odin
package main
main :: proc() {
```

- [ ] **Step 2: Write the failing smoke tests**

Create `runner/runner_test.odin`:

```odin
package runner

import "core:testing"
import "core:strings"

@(test) test_build_good :: proc(t: ^testing.T) {
	res := build("runner/testdata/good", "build/_test_good.exe")
	defer delete(res.output)
	testing.expect(t, res.ok, "expected the good fixture to compile")
}

@(test) test_build_bad :: proc(t: ^testing.T) {
	res := build("runner/testdata/bad", "build/_test_bad.exe")
	defer delete(res.output)
	testing.expect(t, !res.ok, "expected the bad fixture to fail compilation")
	testing.expect(t, len(strings.trim_space(res.output)) > 0, "expected non-empty compiler output on failure")
}
```

Note: these tests shell out to `odin build`, so they are slower than pure unit tests (a second or two each). They are the spec's §7 Run-lifecycle smoke test. Run them from the repo root so the relative `runner/testdata/...` paths resolve.

- [ ] **Step 3: Run tests to verify they fail**

Run: `odin test runner`
Expected: FAIL — `build`, `Build_Result`, etc. undefined.

- [ ] **Step 4: Implement `runner.odin`**

Create `runner/runner.odin`. (The process API is in `core:os` per Global Constraints; verify each proc against `odin doc`-equivalent by compiling — the signatures below were verified against this toolchain.)

```odin
package runner

import "core:os"
import "core:strings"

Build_Result :: struct {
	ok:     bool,
	output: string, // combined stdout+stderr, allocated in the caller's allocator
}

// Compile the Odin package at src_dir into out_exe (debug). Blocking.
build :: proc(src_dir, out_exe: string, allocator := context.allocator) -> Build_Result {
	out_arg := strings.concatenate({"-out:", out_exe}, context.temp_allocator)
	desc := os.Process_Desc{
		command = []string{"odin", "build", src_dir, out_arg, "-debug"},
	}
	state, stdout, stderr, err := os.process_exec(desc, context.temp_allocator)
	if err != nil {
		return Build_Result{ ok = false, output = strings.clone("failed to run the Odin compiler", allocator) }
	}
	// Compiler diagnostics go to stderr; keep stdout too for completeness.
	// NOTE: state.success means "ran to completion", NOT "exit 0" — a failed
	// compile has success=true, exit_code=1. Key off exit_code.
	combined := strings.concatenate({string(stdout), string(stderr)}, allocator)
	return Build_Result{ ok = state.exit_code == 0, output = combined }
}

Runner :: struct {
	running: bool,
	process: os.Process,
}

// Launch an already-built exe as a detached child. Returns whether it started.
launch :: proc(r: ^Runner, exe_path: string) -> bool {
	desc := os.Process_Desc{ command = []string{exe_path} }
	p, err := os.process_start(desc)
	if err != nil {
		return false
	}
	r.process = p
	r.running = true
	return true
}

// Kill the running child if any.
stop :: proc(r: ^Runner) {
	if r.running {
		_ = os.process_kill(r.process)
		_ = os.process_wait(r.process) // reap
		r.running = false
	}
}

// Non-blocking check: has the child exited on its own?
poll :: proc(r: ^Runner) {
	if !r.running {
		return
	}
	// A zero timeout returns immediately; if the process is still alive it reports
	// a timeout error (not exited), otherwise it returns the final state.
	state, err := os.process_wait(r.process, 0)
	if err == nil && state.exited {
		r.running = false
	}
}
```

- [ ] **Step 5: Verify tests pass**

Run: `odin test runner`
Expected: both tests PASS (good compiles → ok; bad fails → not ok with non-empty output).

If `os.process_wait(r.process, 0)` or `state.exited` does not match this toolchain (the timeout/field spelling is the most likely drift point), compile-check and adjust `poll` to the installed signature — its only job is "set running=false once the child has exited." Do not change `build`/`launch`/`stop` behavior. Document any adjustment.

- [ ] **Step 6: Commit**

```bash
git add runner
git commit -m "feat: runner package - build/launch/stop/poll a sketch, with smoke tests"
```

---

### Task 2: The IDE window — toolbar (Run/Stop), status, wiring

The `odessa.exe` window with two working buttons and a status line, wired to the runner. No console yet (Task 3) — the status line reflects state.

**Files:**
- Create: `odessa/main.odin`
- Create: `build_odessa.bat`

**Interfaces:**
- Consumes: `runner.build`, `runner.launch`, `runner.stop`, `runner.poll`, `runner.Runner`, `runner.Build_Result`.
- Internal state (in `main`): the `runner.Runner`, an app `Status` enum, and the last `Build_Result` output (kept for Task 3's console).

- [ ] **Step 1: Write the IDE window**

Create `odessa/main.odin`. (raylib UI procs used — `rl.CheckCollisionPointRec`, `rl.DrawRectangleRec`, `rl.DrawText`, `rl.IsMouseButtonPressed`, `rl.IsKeyDown`, `rl.IsKeyPressed` — are standard; if a name drifts, compile-check and adjust only that call.)

```odin
package main

import rl "vendor:raylib"
import "core:strings"
import "runner"

SKETCH_NAME :: "hello"
SKETCH_DIR  :: "sketches/hello"
SKETCH_EXE  :: "build/hello.exe"

Status :: enum { Idle, Compiling, Running, Compile_Error }

App :: struct {
	run:      runner.Runner,
	status:   Status,
	console:  string, // last build output (owned)
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

// Draw a labeled button; return true if clicked this frame.
button :: proc(rect: rl.Rectangle, label: cstring, enabled: bool) -> bool {
	mouse := rl.GetMousePosition()
	hover := enabled && rl.CheckCollisionPointRec(mouse, rect)
	col := rl.Color{60, 60, 68, 255}
	if !enabled { col = rl.Color{40, 40, 46, 255} }
	else if hover { col = rl.Color{90, 90, 100, 255} }
	rl.DrawRectangleRec(rect, col)
	tw := rl.MeasureText(label, 20)
	rl.DrawText(label, i32(rect.x) + (i32(rect.width)-tw)/2, i32(rect.y) + 8, 20, rl.WHITE)
	return hover && rl.IsMouseButtonPressed(.LEFT)
}

do_run :: proc(app: ^App) {
	runner.stop(&app.run)          // stop any prior sketch first
	app.status = .Compiling
	// Draw one "Compiling..." frame so the UI isn't frozen silently.
	rl.BeginDrawing(); draw_ui(app); rl.EndDrawing()

	if app.console != "" { delete(app.console); app.console = "" }
	res := runner.build(SKETCH_DIR, SKETCH_EXE)
	app.console = res.output
	if !res.ok {
		app.status = .Compile_Error
		return
	}
	if runner.launch(&app.run, SKETCH_EXE) {
		app.status = .Running
	} else {
		app.status = .Idle
	}
}

do_stop :: proc(app: ^App) {
	runner.stop(&app.run)
	app.status = .Idle
}

draw_ui :: proc(app: ^App) {
	rl.ClearBackground(rl.Color{24, 24, 28, 255})
	// toolbar
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), 48, rl.Color{32, 32, 38, 255})
	run_clicked  := button(rl.Rectangle{8, 8, 90, 32}, "Run", app.status != .Running && app.status != .Compiling)
	stop_clicked := button(rl.Rectangle{106, 8, 90, 32}, "Stop", app.status == .Running)
	// status
	rl.DrawText(status_text(app.status), 210, 16, 20, rl.Color{200, 200, 210, 255})

	if run_clicked  { do_run(app) }
	if stop_clicked { do_stop(app) }
}

main :: proc() {
	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(900, 640, "Odessa")
	rl.SetTargetFPS(60)
	defer rl.CloseWindow()

	app: App
	app.status = .Idle

	for !rl.WindowShouldClose() {
		runner.poll(&app.run)
		if !app.run.running && app.status == .Running {
			app.status = .Idle // the sketch window was closed
		}
		// Ctrl+R = Run
		if (rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)) && rl.IsKeyPressed(.R) {
			do_run(&app)
		}

		rl.BeginDrawing()
		draw_ui(&app)
		rl.EndDrawing()
	}

	runner.stop(&app.run) // hygiene: never orphan the sketch
}
```

Note on `do_run` drawing a frame mid-proc: the blocking `build` freezes the loop for ~1-2s; painting one "Compiling..." frame first keeps the window from looking hung. This is a deliberate v1 simplicity choice (no build thread).

- [ ] **Step 2: Write the IDE build+launch script**

Create `build_odessa.bat`:

```bat
@echo off
if not exist build mkdir build
odin build odessa -out:build\odessa.exe -debug
if %errorlevel% neq 0 exit /b 1
echo Launching Odessa ...
build\odessa.exe
```

- [ ] **Step 3: Build and smoke-test (verification)**

Build: `odin build odessa -out:build/odessa.exe -debug` — expect exit 0.

Then launch the IDE NON-BLOCKING (it opens a GUI window; start it, drive it, then terminate by PID — never leave it or a spawned sketch running):
- Confirm the Odessa window opens (900×640, title "Odessa") with a **Run** and **Stop** button and an "Idle" status.
- Click **Run** (or send it enough time): the status shows Running and the **`hello` sketch window opens** (the animated ring). Capture the Odessa window and/or the sketch window if feasible (Win32 PrintWindow).
- Click **Stop** (or, if you can't click, verify the reverse path in Task 3): the sketch window closes and status returns to Idle.
- Close Odessa; confirm no leftover `hello.exe` or `odessa.exe` processes remain (kill by PID if needed).

Report exactly what you observed. If you cannot drive clicks in this environment, at minimum confirm the build produced `odessa.exe`, it launches without immediate crash, and the window renders the toolbar; note what you could not verify.

- [ ] **Step 4: Commit**

```bash
git add odessa/main.odin build_odessa.bat
git commit -m "feat: Odessa IDE window with Run/Stop toolbar wired to runner"
```

---

### Task 3: Console pane — show compiler output / errors

Render the runner's last build output in a scrollable console area, so a failed Run shows the Odin compiler error instead of just a status word.

**Files:**
- Modify: `odessa/main.odin`

**Interfaces:**
- Consumes: `App.console` (populated in `do_run` from `Build_Result.output`).
- Adds: a console draw routine + a scroll offset field on `App`.

- [ ] **Step 1: Add a scroll offset to App and render the console**

In `odessa/main.odin`:

1. Add a field to `App`:

```odin
App :: struct {
	run:           runner.Runner,
	status:        Status,
	console:       string,
	console_scroll: int, // first visible line index
}
```

2. Add a console renderer (draws the lower part of the window; splits `console` into lines and draws those that fit, offset by `console_scroll`):

```odin
CONSOLE_TOP  :: 56
LINE_H       :: 18
FONT_SIZE    :: 16

draw_console :: proc(app: ^App) {
	x: i32 = 8
	top: i32 = CONSOLE_TOP
	bottom := rl.GetScreenHeight() - 8
	rl.DrawRectangle(0, CONSOLE_TOP-4, rl.GetScreenWidth(), bottom-(CONSOLE_TOP-4), rl.Color{16, 16, 20, 255})

	if app.console == "" {
		rl.DrawText("(console)", x, top, FONT_SIZE, rl.Color{90, 90, 100, 255})
		return
	}

	lines := strings.split_lines(app.console, context.temp_allocator)
	max_visible := int((bottom - top) / LINE_H)

	// clamp scroll
	if app.console_scroll < 0 { app.console_scroll = 0 }
	if app.console_scroll > max(0, len(lines)-max_visible) {
		app.console_scroll = max(0, len(lines)-max_visible)
	}

	y := top
	for i := app.console_scroll; i < len(lines) && int((y-top)/LINE_H) < max_visible; i += 1 {
		ctext := strings.clone_to_cstring(lines[i], context.temp_allocator)
		colr := rl.Color{200, 200, 205, 255}
		if app.status == .Compile_Error { colr = rl.Color{255, 180, 180, 255} }
		rl.DrawText(ctext, x, y, FONT_SIZE, colr)
		y += LINE_H
	}
}
```

3. Call `draw_console(app)` at the end of `draw_ui`, and handle mouse-wheel scrolling in the main loop (before drawing):

```odin
	wheel := rl.GetMouseWheelMove()
	if wheel != 0 {
		app.console_scroll -= int(wheel * 3)
	}
```

- [ ] **Step 2: Build and smoke-test the error path (verification)**

Build: `odin build odessa -out:build/odessa.exe -debug` — expect exit 0.

Verify (launch non-blocking, terminate by PID after):
- Temporarily introduce a syntax error into `sketches/hello/hello.odin` (e.g. delete a `}`), launch Odessa, Run → status "Compile error" and the **console shows the Odin compiler error text** (red). Capture the window if feasible.
- Restore `sketches/hello/hello.odin` to its correct state, Run again → the sketch launches and the console shows the (empty or benign) build output.
- **Before committing, ensure `sketches/hello/hello.odin` is back to its correct, building form** (no leftover syntax error).

Report exactly what you observed.

- [ ] **Step 3: Commit**

```bash
git add odessa/main.odin
git commit -m "feat: Odessa console pane shows compiler output/errors"
```

---

## Self-Review

**Spec coverage (Plan B scope):**
- IDE window with Run/Stop toolbar + status (spec §4) → Tasks 2. ✔
- Console showing compile errors (spec §4, §5) → Task 3. ✔
- Run = compile → launch separate window; Stop = kill; process hygiene (spec §5) → Tasks 1, 2. ✔
- Run-lifecycle smoke test (spec §7) → Task 1. ✔
- Deliberate deviation (documented): no `main`-injection — sketches keep a visible `main` (spec §5's injection deferred). ✔
- Deferred to Plan C (correctly out of scope): the text editor, dynamic sketch selection, live sketch stdout streaming. ✔

**Placeholder scan:** No TBD/TODO; every code step is complete; verification steps give exact commands + expected observations. ✔

**Type consistency:** `runner.build`/`launch`/`stop`/`poll`, `runner.Runner`, `runner.Build_Result` defined in Task 1 and used identically in Tasks 2–3. `App`/`Status`/`do_run`/`do_stop`/`draw_ui` consistent across Tasks 2–3; `App` gains `console_scroll` in Task 3. The `core:os` process signatures are copied verbatim from the verified Global Constraints. ✔

**Known risks flagged for the implementer:** (1) `os.process_wait` timeout/`state.exited` spelling is the most likely drift point — `poll` isolates it. (2) raylib UI proc names (`CheckCollisionPointRec`, `DrawRectangleRec`, `GetMouseWheelMove`) — compile-check and adjust only the offending call. (3) Work strictly inside `C:/Users/vasan/Workspace/1_Projects/2026-07_odessa`; when driving GUI apps, always terminate spawned `odessa.exe`/`hello.exe` by PID — never leave orphans.
