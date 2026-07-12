# Odessa Plan A — Sketch-as-Program Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pivot the codebase from the abandoned hot-reload harness to the Processing "compile-and-run" model: remove `host/` + `runtime/`, give the `canvas` library a `run()` entry point that owns the sketch window + frame loop, and prove a sketch compiles into a standalone program that opens its own animated window.

**Architecture:** A sketch becomes a standalone Odin program (`package main`) that imports `canvas` (aliased `c`), defines `setup`/`draw`, and calls `c.run(setup, draw)` from `main`. `canvas.run` opens the raylib window, calls `setup` once (honoring `size()`), then loops `draw()` each frame. No DLL, no host, no hot reload. (The later IDE will inject `main` and manage compile/launch; this plan keeps `main` visible in the sketch to prove the model.)

**Tech Stack:** Odin (`dev-2026-05` nightly or newer), `vendor:raylib`, `core:testing`. Windows (batch scripts).

## Global Constraints

- **Language:** Odin. Package `canvas` MAY use mutable package globals for per-frame draw state + input/time mirrors (the `run` loop repopulates them each frame). The `canvas` package must remain buildable/testable in isolation via `odin test canvas`.
- **Library calls are qualified** under alias `c` in sketches (`c.circle(...)`). A sketch's own state stays bare globals.
- **Coordinate system:** origin top-left, +y down (matches raylib; no flip).
- **No hot reload:** do not reintroduce any DLL/host/reload/watcher/registry machinery.
- **Odin version floor:** `dev-2026-05-nightly` (installed toolchain).
- **Build output dir:** `build/` (git-ignored).
- **Canvas tests must stay green:** the 12 existing `odin test canvas` tests must pass after every task.

---

## File Structure (after this plan)

```
2026-07_odessa/
  canvas/
    canvas.odin        # package canvas: PI/TAU, Vec2, mirrors, draw state, size(), run() loop  [MODIFIED]
    math.odin          # unchanged
    math_test.odin     # unchanged
    random.odin        # unchanged
    random_test.odin   # unchanged
    color.odin         # unchanged
    color_test.odin    # unchanged
    shapes.odin        # unchanged
  sketches/
    hello/
      hello.odin       # package main: setup/draw + main{ c.run(...) }  [REWRITTEN]
  build/               # (git-ignored)
  build_sketch.bat     # build + run one sketch: build_sketch.bat hello   [NEW]
  # REMOVED: host/, runtime/, build.bat, run.bat
```

---

### Task 1: Remove the hot-reload harness and old build scripts

Delete the DLL/host machinery. After this task the repo no longer contains the abandoned architecture; the `canvas` package still builds and its 12 tests still pass.

**Files:**
- Delete: `host/` (whole directory), `runtime/` (whole directory)
- Delete: `build.bat`, `run.bat`
- (Leave `sketches/hello/hello.odin` for now — it is rewritten in Task 3. It will not compile as part of anything until then, which is fine.)

- [ ] **Step 1: Delete the harness directories and scripts**

Run (from repo root `C:/Users/vasan/Workspace/1_Projects/2026-07_odessa`):

```bash
git rm -r host runtime build.bat run.bat
```

Expected: git stages the deletions of `host/host.odin`, `runtime/runtime.odin`, `runtime/sketches_manifest.odin`, `build.bat`, `run.bat`.

- [ ] **Step 2: Verify the canvas package still builds and tests pass**

Run: `odin test canvas`
Expected: `All tests were successful.` — 12 tests. (The canvas package does not depend on host/runtime, so removing them changes nothing here.)

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "refactor: remove hot-reload harness (host/, runtime/, build scripts)"
```

---

### Task 2: Refactor `canvas` — remove the sketch registry, add `run()`

Remove the DLL-only registry, and add the `run(setup, draw)` procedure that owns the window and frame loop (folding in what the removed runtime used to do). Mark the loop's internal helpers `@(private)` so sketches only see the public API.

**Files:**
- Modify: `canvas/canvas.odin`

**Interfaces:**
- Removed (were only used by the DLL runtime): `Sketch_Proc`, `Sketch_Entry`, `_registry`, `sketch`, `registry`.
- Made `@(private)` (internal to the loop; sketches must not call them): `frame_begin`, `set_frame_inputs`, `apply_pending_size`, `args_to_color`, `_rlcol`.
- Kept public (read/called by sketches): the mirrors (`width`, `height`, `frame_count`, `time`, `delta_time`, `mouse`, `mouse_x`, `mouse_y`, `mouse_pressed`), `Vec2`/`vec2`, `size`, `PI`/`TAU`, and everything in `shapes.odin`/`color.odin`/`math.odin`/`random.odin`.
- Added public: `run :: proc(user_setup: proc(), user_draw: proc())`.

- [ ] **Step 1: Read the current file**

Read `canvas/canvas.odin` in full so the edits below target the exact current content. It currently contains (in order): `package canvas`; `PI`/`TAU`; the raylib import; `Vec2`/`vec2`; the mirror variables; the draw-state variables; `args_to_color`; `_rlcol`; `size`; `frame_begin`; `set_frame_inputs`; `apply_pending_size`; and (at the end) the registry block (`Sketch_Proc`, `Sketch_Entry`, `_registry`, `sketch`, `registry`).

- [ ] **Step 2: Remove the registry block**

Delete these five declarations from `canvas/canvas.odin` (the block added for the old gallery):

```odin
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
```

- [ ] **Step 3: Mark the loop internals `@(private)`**

Add `@(private)` to the four helper procs and the color helper so they are not callable from sketches. Change each declaration line as follows (leave the bodies unchanged):

```odin
@(private) args_to_color :: proc(args: []u8) -> Color {
```
```odin
@(private) _rlcol :: proc(col: Color) -> rl.Color {
```
```odin
@(private) frame_begin :: proc() {
```
```odin
@(private) set_frame_inputs :: proc(w, h, frame: int, t, dt, mx, my: f32, pressed: bool) {
```
```odin
@(private) apply_pending_size :: proc() {
```

(Note: `shapes.odin` calls `args_to_color` and `_rlcol` — they are in the same package, so `@(private)` (package-private) still permits those calls. `@(private)` restricts to the package, not the file.)

- [ ] **Step 4: Add the `run` loop**

Append to `canvas/canvas.odin`:

```odin
SKETCH_TITLE :: "Odessa Sketch"
DEFAULT_W    :: 800
DEFAULT_H    :: 800

// Opens the window, runs setup once, then draws every frame until the window closes.
// This is the sketch program's entry point (called from the sketch's main).
run :: proc(user_setup: proc(), user_draw: proc()) {
	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(DEFAULT_W, DEFAULT_H, SKETCH_TITLE)
	rl.SetTargetFPS(60)
	defer rl.CloseWindow()

	if user_setup != nil { user_setup() }
	apply_pending_size()   // honor a size() call made in setup

	frame := 0
	for !rl.WindowShouldClose() {
		mp := rl.GetMousePosition()
		set_frame_inputs(
			int(rl.GetScreenWidth()), int(rl.GetScreenHeight()),
			frame,
			f32(rl.GetTime()), rl.GetFrameTime(),
			mp.x, mp.y, rl.IsMouseButtonDown(.LEFT),
		)
		frame_begin()

		rl.BeginDrawing()
		rl.ClearBackground(rl.Color{18, 18, 22, 255})
		if user_draw != nil { user_draw() }
		rl.EndDrawing()

		free_all(context.temp_allocator)
		frame += 1
	}
}
```

- [ ] **Step 5: Verify canvas still type-checks and tests pass**

Run: `odin test canvas`
Expected: `All tests were successful.` — 12 tests. (Removing the registry and adding `run` does not touch the tested math/random/color logic; this also confirms `run` and the `@(private)` markers compile.)

- [ ] **Step 6: Commit**

```bash
git add canvas/canvas.odin
git commit -m "refactor: canvas drops sketch registry, adds run() window loop"
```

---

### Task 3: Standalone `hello` sketch + build script, and run it

Rewrite `hello` as a standalone program using `c.run`, add a one-line build+run script, and confirm the sketch opens its own animated window.

**Files:**
- Rewrite: `sketches/hello/hello.odin`
- Create: `build_sketch.bat`

**Interfaces:**
- Consumes: `c.run`, `c.size`, `c.background`, `c.no_stroke`, `c.fill`, `c.circle`, `c.delta_time`, `c.width`, `c.height`, `c.mouse_x`, `c.mouse_y`, `c.TAU`.

- [ ] **Step 1: Rewrite the hello sketch as a standalone program**

Replace the entire contents of `sketches/hello/hello.odin` with:

```odin
package main

import c "../../canvas"
import "core:math"

t: f32

setup :: proc() {
	c.size(800, 800)
}

draw :: proc() {
	c.background(18, 18, 22)
	t += c.delta_time

	cx := f32(c.width) * 0.5
	cy := f32(c.height) * 0.5
	c.no_stroke()
	for i in 0..<12 {
		a := f32(i) / 12 * c.TAU + t
		x := cx + math.cos(a) * 220
		y := cy + math.sin(a) * 220
		r := 30 + 18 * math.sin(t*2 + f32(i))
		c.fill(u8(120 + 100*math.sin(t+f32(i))), 90, 200)
		c.circle(x, y, r)
	}

	c.fill(255, 240, 120)
	c.circle(c.mouse_x, c.mouse_y, 12)
}

main :: proc() {
	c.run(setup, draw)
}
```

Note: no `@(init)`, no `#+feature global-context`, no registry call — those were DLL-era. `main` is visible here to prove the standalone model; the later IDE (Plan B) injects `main` at build time and the sketch file loses it.

- [ ] **Step 2: Add the build+run script**

Create `build_sketch.bat`:

```bat
@echo off
if "%~1"=="" (
	echo Usage: build_sketch.bat ^<sketch-name^>
	exit /b 1
)
if not exist build mkdir build
odin build sketches\%~1 -out:build\%~1.exe -debug
if %errorlevel% neq 0 exit /b 1
echo Running %~1 ...
build\%~1.exe
```

- [ ] **Step 3: Build and run (verification)**

Run: `cmd //c ".\\build_sketch.bat hello"` (from Git Bash) or `build_sketch.bat hello` (from cmd).

IMPORTANT for the implementer: `build\hello.exe` opens a blocking GUI window. Do not let it hang the session — build it first (`odin build sketches\hello -out:build\hello.exe -debug`, expect exit 0), then launch it NON-BLOCKING (start it, wait ~3s, confirm it is running with no immediate crash, ideally capture the window via Win32 PrintWindow, then terminate it by PID). Always kill the process you launched — do not leave an orphaned `hello.exe`.

Expected: compilation exits 0; an 800×800 window titled "Odessa Sketch" opens showing a rotating ring of 12 pulsing purple circles on a dark background, plus a yellow dot at the mouse. Report exactly how you verified (and, if you couldn't observe the window, that the exe built and launched without immediate error).

- [ ] **Step 4: Commit**

```bash
git add sketches/hello/hello.odin build_sketch.bat
git commit -m "feat: hello sketch runs as a standalone canvas.run program"
```

---

## Self-Review

**Spec coverage (Plan A scope):**
- Remove hot-reload harness (spec §1 "Removed") → Task 1. ✔
- `canvas.run` window/frame loop (spec §3 "the window/loop entry point") → Task 2. ✔
- Sketch as standalone program using `canvas.run` (spec §1, §2) → Task 3. ✔
- Deferred to later plans (correctly out of scope): the IDE window, editor, Run/Stop lifecycle, `main` injection, console (Plans B & C). ✔

**Placeholder scan:** No TBD/TODO; every code step shows complete code; verification steps give exact commands + expected results. ✔

**Type consistency:** `run(user_setup: proc(), user_draw: proc())` defined in Task 2 and called as `c.run(setup, draw)` in Task 3. Mirrors (`c.width`, `c.mouse_x`, etc.), `c.size`, `c.TAU`, and the draw procs used in Task 3 all exist in the kept `canvas` public API. `@(private)` helpers are only called within the `canvas` package (`run` calls them; `shapes.odin` calls `args_to_color`/`_rlcol`). ✔

**Known risk flagged for the implementer:** raylib binding names (`GetScreenWidth`, `GetMousePosition`, `IsMouseButtonDown(.LEFT)`, `SetConfigFlags`, etc.) are the same ones the (now-removed) runtime used successfully earlier in this repo's history, so they are known-good against this toolchain; if any drifts, check `odin doc vendor:raylib` and adjust only the offending call. Work strictly inside `C:/Users/vasan/Workspace/1_Projects/2026-07_odessa` — no external reference projects.
