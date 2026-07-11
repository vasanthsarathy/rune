# Odessa Plan 1 — Walking Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Odessa host/DLL hot-reload harness plus a minimal-but-real `canvas` library, so you can launch the app, see a hardcoded sketch drawing, edit it, and watch it hot-reload — with compile errors shown on-screen instead of crashing.

**Architecture:** A host `.exe` (`host/`, package `main`) creates the window and drives a reload loop; the reloadable module (`runtime/`, built as `odessa.dll`) exports lifecycle procs, owns per-frame state on a retained struct, and runs the active sketch. The `canvas/` package is the p5-style drawing API, imported both by the runtime and by sketches (aliased `c`). Sketches live in `sketches/<slug>/` as their own packages and self-register via an `@(init)` calling `c.sketch(...)`. The host also watches the source tree and spawns `odin build` on change, so reload is turnkey.

**Tech Stack:** Odin (`dev-2026-05` nightly or newer), `vendor:raylib`, `core:testing`, `core:dynlib`, `core:os`, `core:time`. Windows (PowerShell/batch build scripts).

## Global Constraints

- **Language:** Odin. Bitwise XOR is `~` / `~=` (NOT `^`). String literals may pass where `cstring` is expected only as untyped constants (mirror the template's window init).
- **Golden rule (from the game template):** the *runtime's* mutable state lives on the retained `Odessa_Memory` struct — never as mutable package globals in `runtime/`. The `canvas` package MAY use mutable package globals for per-frame drawing state and input/time mirrors, because the runtime resets/repopulates them every frame (they are allowed to be wiped on reload).
- **Sketch state = bare package globals; reload = restart** (re-runs `setup`). Do not attempt to preserve sketch state across reloads.
- **Library calls are qualified** under alias `c` (`c.circle(...)`). A sketch must not declare a local named `c`.
- **Coordinate system:** origin top-left, +y down (matches raylib; no flip).
- **Reproducibility:** the canvas RNG is a seedable xorshift; identical seeds must produce identical sequences.
- **Odin version floor:** `dev-2026-05-nightly` (the installed toolchain).
- **Build output dir:** `build/` (git-ignored). DLL name: `odessa.dll`. Host exe: `odessa.exe`.
- **DLL export prefix:** `odessa_` (the host mirrors exported symbols by this prefix).

---

## File Structure

```
2026-07_odessa/
  host/
    host.odin            # package main -> odessa.exe: reload loop + source watcher + build spawner
  runtime/
    runtime.odin         # package runtime: @(export) odessa_* lifecycle; Odessa_Memory; per-frame loop
    sketches_manifest.odin  # `import _ "../sketches/<slug>"` lines (one per sketch; hand-edited for now)
  canvas/
    canvas.odin          # package canvas: window/frame state, width/height/mouse/time mirrors, sketch registry
    math.odin            # map_range, lerp, clamp, dist, radians, degrees, constants
    math_test.odin       # @(test) for math.odin
    random.odin          # xorshift Rng, seed, random, random_range
    random_test.odin     # @(test) for random.odin
    color.odin           # Color type + constructors
    color_test.odin      # @(test) for color.odin
    shapes.odin          # background, fill/stroke/no_fill/no_stroke/stroke_weight, circle/rect/line/point
  sketches/
    hello/
      hello.odin         # package hello: the first hardcoded sketch
  build/                 # (git-ignored) odessa.dll, odessa.exe, temp copies
  build.bat              # build DLL + host once
  run.bat               # build (if needed) then launch odessa.exe
```

- `canvas/` is split by responsibility (math / random / color / shapes / core) so each file is small and independently testable.
- Pure-logic files (`math`, `random`, `color`) get real TDD. `shapes`, `canvas` core, `runtime`, and `host` touch raylib/OS and are verified by build-and-run smoke checks.

---

### Task 1: Repo skeleton + host/DLL harness shows a window

Adapt the template's verified host loop and produce a runtime DLL that opens a window and clears it to a dark background. No canvas or sketches yet — this proves the hot-reload harness builds and runs under Odessa's layout.

**Files:**
- Create: `runtime/runtime.odin`
- Create: `host/host.odin`
- Create: `build.bat`, `run.bat`

**Interfaces:**
- Produces (DLL exports the host binds to, all `@(export)`, prefix `odessa_`):
  - `odessa_init_window :: proc()`
  - `odessa_init :: proc()`
  - `odessa_update :: proc() -> bool`  (returns false to quit)
  - `odessa_shutdown :: proc()`
  - `odessa_shutdown_window :: proc()`
  - `odessa_memory :: proc() -> rawptr`
  - `odessa_memory_size :: proc() -> int`
  - `odessa_hot_reloaded :: proc(mem: rawptr)`
  - `odessa_force_reload :: proc() -> bool`
  - `odessa_force_restart :: proc() -> bool`

- [ ] **Step 1: Write the runtime module**

Create `runtime/runtime.odin`:

```odin
package runtime

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
```

- [ ] **Step 2: Write the host**

Create `host/host.odin`. This is the template's host loop with the export prefix changed to `odessa_`, the DLL path pointed at `build/odessa.dll`, and temp copies written into `build/`. (The source-watcher/build-spawner is added in Task 6 — keep this task's host minimal.)

```odin
package main

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:time"

DLL_PATH :: "build/odessa.dll"

Api :: struct {
	init_window:     proc(),
	init:            proc(),
	update:          proc() -> bool,
	shutdown:        proc(),
	shutdown_window: proc(),
	memory:          proc() -> rawptr,
	memory_size:     proc() -> int,
	hot_reloaded:    proc(mem: rawptr),
	force_reload:    proc() -> bool,
	force_restart:   proc() -> bool,

	__handle:    dynlib.Library,
	dll_time:    time.Time,
	api_version: int,
}

copy_dll :: proc(to: string) -> bool {
	data, read_err := os.read_entire_file(DLL_PATH, context.allocator)
	if read_err != nil {
		fmt.eprintfln("Failed to read %s: %v", DLL_PATH, read_err)
		return false
	}
	defer delete(data)
	if write_err := os.write_entire_file(to, data); write_err != nil {
		fmt.eprintfln("Failed to write %s: %v", to, write_err)
		return false
	}
	return true
}

load_api :: proc(version: int) -> (api: Api, ok: bool) {
	dll_time, time_err := os.last_write_time_by_name(DLL_PATH)
	if time_err != nil {
		fmt.eprintfln("Failed to stat %s: %v", DLL_PATH, time_err)
		return
	}
	dll_copy := fmt.tprintf("build/odessa_hot_%d.dll", version)
	if !copy_dll(dll_copy) { return }
	_, init_ok := dynlib.initialize_symbols(&api, dll_copy, "odessa_", "__handle")
	if !init_ok {
		fmt.eprintfln("Failed to init symbols: %s", dynlib.last_error())
		return
	}
	api.dll_time = dll_time
	api.api_version = version
	ok = true
	return
}

unload_api :: proc(api: ^Api) {
	if api.__handle != nil {
		if !dynlib.unload_library(api.__handle) {
			fmt.eprintfln("Failed to unload: %s", dynlib.last_error())
		}
	}
	if os.remove(fmt.tprintf("build/odessa_hot_%d.dll", api.api_version)) != nil {}
}

main :: proc() {
	api, ok := load_api(0)
	if !ok { fmt.eprintln("Failed to load Odessa API on startup."); return }
	version := 1

	api.init_window()
	api.init()

	old_apis := make([dynamic]Api, 0, 8)

	for api.update() {
		reload := api.force_reload() || api.force_restart()
		force_restart := api.force_restart()

		dll_time, err := os.last_write_time_by_name(DLL_PATH)
		if err == nil && dll_time != api.dll_time { reload = true }

		if reload {
			new_api, new_ok := load_api(version)
			if new_ok {
				restart := force_restart || api.memory_size() != new_api.memory_size()
				if restart {
					api.shutdown()
					for &old in old_apis { unload_api(&old) }
					clear(&old_apis)
					unload_api(&api)
					api = new_api
					api.init()
				} else {
					append(&old_apis, api)
					mem := api.memory()
					api = new_api
					api.hot_reloaded(mem)
				}
				version += 1
			}
		}
	}

	api.shutdown()
	api.shutdown_window()
	for &old in old_apis { unload_api(&old) }
	delete(old_apis)
	unload_api(&api)
}
```

- [ ] **Step 3: Write build scripts**

Create `build.bat`:

```bat
@echo off
if not exist build mkdir build
odin build runtime -build-mode:dll -out:build\odessa.dll -debug
if %errorlevel% neq 0 exit /b 1
odin build host -out:build\odessa.exe -debug
if %errorlevel% neq 0 exit /b 1
echo Built build\odessa.dll and build\odessa.exe
```

Create `run.bat`:

```bat
@echo off
call build.bat
if %errorlevel% neq 0 exit /b 1
build\odessa.exe
```

- [ ] **Step 4: Build and smoke-test (verification)**

Run: `cmd /c build.bat`
Expected: prints `Built build\odessa.dll and build\odessa.exe`, exit 0.

Run: `cmd /c run.bat` (or `build\odessa.exe`)
Expected: a resizable 1280×720 window titled "Odessa" clears to dark gray (RGB 18,18,22). Closing the window exits cleanly. (Close it manually to end the smoke test.)

- [ ] **Step 5: Commit**

```bash
git add runtime/runtime.odin host/host.odin build.bat run.bat
git commit -m "feat: Odessa host/DLL hot-reload harness shows a window"
```

---

### Task 2: canvas math + random core (TDD)

Pure, deterministic helpers. No raylib. This is the reproducible engine behind generative work.

**Files:**
- Create: `canvas/canvas.odin` (package declaration + shared constants only, for now)
- Create: `canvas/math.odin`, `canvas/math_test.odin`
- Create: `canvas/random.odin`, `canvas/random_test.odin`

**Interfaces:**
- Produces:
  - Constants: `PI :: 3.14159265358979323846`, `TAU :: 2 * PI`
  - `map_range :: proc(v, in_min, in_max, out_min, out_max: f32) -> f32`
  - `lerp :: proc(a, b, t: f32) -> f32`
  - `clamp :: proc(v, lo, hi: f32) -> f32`
  - `dist :: proc(x1, y1, x2, y2: f32) -> f32`
  - `radians :: proc(deg: f32) -> f32`
  - `degrees :: proc(rad: f32) -> f32`
  - `Rng :: struct { state: u64 }`
  - `seed :: proc(s: u64)` (seeds the package-global `rng`)
  - `random :: proc() -> f32` (uniform [0,1))
  - `random_range :: proc(lo, hi: f32) -> f32`
  - `rng_next_u64 :: proc(r: ^Rng) -> u64`, `rng_f32 :: proc(r: ^Rng) -> f32` (explicit-Rng variants for testing)

- [ ] **Step 1: Create the package anchor file**

Create `canvas/canvas.odin`:

```odin
package canvas

PI  :: 3.14159265358979323846
TAU :: 2.0 * PI
```

- [ ] **Step 2: Write the failing math tests**

Create `canvas/math_test.odin`:

```odin
package canvas

import "core:testing"
import "core:math"

@(test) test_map_range :: proc(t: ^testing.T) {
	testing.expect(t, map_range(5, 0, 10, 0, 100) == 50)
	testing.expect(t, map_range(0, 0, 10, 20, 40) == 20)
	testing.expect(t, map_range(10, 0, 10, 20, 40) == 40)
}

@(test) test_lerp :: proc(t: ^testing.T) {
	testing.expect(t, lerp(0, 10, 0.5) == 5)
	testing.expect(t, lerp(2, 4, 0) == 2)
	testing.expect(t, lerp(2, 4, 1) == 4)
}

@(test) test_clamp :: proc(t: ^testing.T) {
	testing.expect(t, clamp(5, 0, 10) == 5)
	testing.expect(t, clamp(-3, 0, 10) == 0)
	testing.expect(t, clamp(99, 0, 10) == 10)
}

@(test) test_dist :: proc(t: ^testing.T) {
	testing.expect(t, dist(0, 0, 3, 4) == 5)
}

@(test) test_angle_conversions :: proc(t: ^testing.T) {
	testing.expect(t, math.abs(radians(180) - PI) < 1e-5)
	testing.expect(t, math.abs(degrees(PI) - 180) < 1e-3)
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `odin test canvas`
Expected: FAIL — undefined `map_range`, `lerp`, `clamp`, `dist`, `radians`, `degrees`.

- [ ] **Step 4: Implement math.odin**

Create `canvas/math.odin`:

```odin
package canvas

import "core:math"

map_range :: proc(v, in_min, in_max, out_min, out_max: f32) -> f32 {
	return out_min + (v - in_min) * (out_max - out_min) / (in_max - in_min)
}

lerp :: proc(a, b, t: f32) -> f32 { return a + (b - a) * t }

clamp :: proc(v, lo, hi: f32) -> f32 {
	if v < lo { return lo }
	if v > hi { return hi }
	return v
}

dist :: proc(x1, y1, x2, y2: f32) -> f32 {
	dx := x2 - x1
	dy := y2 - y1
	return math.sqrt(dx*dx + dy*dy)
}

radians :: proc(deg: f32) -> f32 { return deg * PI / 180.0 }
degrees :: proc(rad: f32) -> f32 { return rad * 180.0 / PI }
```

- [ ] **Step 5: Run math tests to verify they pass**

Run: `odin test canvas`
Expected: the five math tests PASS. (Random tests don't exist yet.)

- [ ] **Step 6: Write the failing random tests**

Create `canvas/random_test.odin`:

```odin
package canvas

import "core:testing"

@(test) test_rng_seeded_reproducible :: proc(t: ^testing.T) {
	a := Rng{ state = 0xDEADBEEF }
	b := Rng{ state = 0xDEADBEEF }
	for _ in 0..<8 {
		testing.expect(t, rng_f32(&a) == rng_f32(&b))
	}
}

@(test) test_rng_in_unit_interval :: proc(t: ^testing.T) {
	r := Rng{ state = 1 }
	for _ in 0..<1000 {
		v := rng_f32(&r)
		testing.expect(t, v >= 0 && v < 1)
	}
}

@(test) test_random_range :: proc(t: ^testing.T) {
	seed(42)
	for _ in 0..<1000 {
		v := random_range(10, 20)
		testing.expect(t, v >= 10 && v < 20)
	}
}

@(test) test_seed_resets_sequence :: proc(t: ^testing.T) {
	seed(7)
	first := random()
	seed(7)
	testing.expect(t, random() == first)
}
```

- [ ] **Step 7: Run to verify they fail**

Run: `odin test canvas`
Expected: FAIL — undefined `Rng`, `rng_f32`, `seed`, `random`, `random_range`.

- [ ] **Step 8: Implement random.odin**

Create `canvas/random.odin`. Note: a zero state makes xorshift degenerate, so `seed` forces a nonzero state.

```odin
package canvas

// Seedable xorshift64 PRNG. Deterministic: identical state -> identical stream.
Rng :: struct { state: u64 }

rng_next_u64 :: proc(r: ^Rng) -> u64 {
	x := r.state
	x ~= x << 13
	x ~= x >> 7
	x ~= x << 17
	r.state = x
	return x
}

// Uniform f32 in [0, 1) using the top 24 bits.
rng_f32 :: proc(r: ^Rng) -> f32 {
	return f32(rng_next_u64(r) >> 40) / f32(1 << 24)
}

// Package-global generator used by the bare `random*` helpers.
rng: Rng = { state = 0x9E3779B97F4A7C15 }

seed :: proc(s: u64) {
	rng.state = s == 0 ? 0x9E3779B97F4A7C15 : s
}

random :: proc() -> f32 { return rng_f32(&rng) }

random_range :: proc(lo, hi: f32) -> f32 { return lo + (hi - lo) * random() }
```

- [ ] **Step 9: Run all canvas tests to verify they pass**

Run: `odin test canvas`
Expected: all math + random tests PASS.

- [ ] **Step 10: Commit**

```bash
git add canvas/canvas.odin canvas/math.odin canvas/math_test.odin canvas/random.odin canvas/random_test.odin
git commit -m "feat: canvas math + seedable random core with tests"
```

---

### Task 3: canvas color core (TDD)

A small `Color` type and constructors. RGBA only in this plan (HSB mode is Plan 2).

**Files:**
- Create: `canvas/color.odin`, `canvas/color_test.odin`

**Interfaces:**
- Produces:
  - `Color :: struct { r, g, b, a: u8 }`
  - `rgb :: proc(r, g, b: u8) -> Color` (a = 255)
  - `rgba :: proc(r, g, b, a: u8) -> Color`
  - `gray :: proc(v: u8) -> Color` (r=g=b=v, a=255)
  - `WHITE`, `BLACK` constants of type `Color`

- [ ] **Step 1: Write the failing color tests**

Create `canvas/color_test.odin`:

```odin
package canvas

import "core:testing"

@(test) test_rgb_sets_full_alpha :: proc(t: ^testing.T) {
	col := rgb(10, 20, 30)
	testing.expect(t, col == Color{10, 20, 30, 255})
}

@(test) test_rgba_passthrough :: proc(t: ^testing.T) {
	col := rgba(1, 2, 3, 4)
	testing.expect(t, col == Color{1, 2, 3, 4})
}

@(test) test_gray :: proc(t: ^testing.T) {
	testing.expect(t, gray(128) == Color{128, 128, 128, 255})
}

@(test) test_named_colors :: proc(t: ^testing.T) {
	testing.expect(t, WHITE == Color{255, 255, 255, 255})
	testing.expect(t, BLACK == Color{0, 0, 0, 255})
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `odin test canvas`
Expected: FAIL — undefined `Color`, `rgb`, `rgba`, `gray`, `WHITE`, `BLACK`.

- [ ] **Step 3: Implement color.odin**

Create `canvas/color.odin`:

```odin
package canvas

Color :: struct { r, g, b, a: u8 }

WHITE :: Color{255, 255, 255, 255}
BLACK :: Color{0, 0, 0, 255}

rgb  :: proc(r, g, b: u8) -> Color    { return Color{r, g, b, 255} }
rgba :: proc(r, g, b, a: u8) -> Color { return Color{r, g, b, a} }
gray :: proc(v: u8) -> Color          { return Color{v, v, v, 255} }
```

- [ ] **Step 4: Run to verify they pass**

Run: `odin test canvas`
Expected: all color tests PASS (plus the earlier math/random tests).

- [ ] **Step 5: Commit**

```bash
git add canvas/color.odin canvas/color_test.odin
git commit -m "feat: canvas Color type and constructors with tests"
```

---

### Task 4: canvas frame state + drawing primitives

The per-frame drawing surface: window sizing, the mutable draw state (current fill/stroke), input/time mirrors, and a first set of shapes. This layer talks to raylib, so it is verified by build + a smoke sketch in Task 5 rather than unit tests.

**Files:**
- Modify: `canvas/canvas.odin` (add frame state, mirrors, `size`, `begin_frame`/`end_frame` used by the runtime)
- Create: `canvas/shapes.odin`

**Interfaces:**
- Produces (read by sketches):
  - Mirror variables, updated each frame by the runtime: `width: int`, `height: int`, `frame_count: int`, `time: f32`, `delta_time: f32`, `mouse: Vec2`, `mouse_x: f32`, `mouse_y: f32`, `mouse_pressed: bool`
  - `Vec2 :: [2]f32`, `vec2 :: proc(x, y: f32) -> Vec2`
  - `size :: proc(w, h: int)` — sets desired canvas size and resizes the window
  - `background :: proc(args: ..u8)` — accepts `(v)`, `(v,a)`, `(r,g,b)`, `(r,g,b,a)`; draws a full-canvas (possibly translucent) rect
  - `fill :: proc(args: ..u8)`, `no_fill :: proc()`
  - `stroke :: proc(args: ..u8)`, `no_stroke :: proc()`
  - `stroke_weight :: proc(w: f32)`
  - `circle :: proc(x, y, r: f32)`
  - `rect :: proc(x, y, w, h: f32)`
  - `line :: proc(x1, y1, x2, y2: f32)`
  - `point :: proc(x, y: f32)`
- Produces (called by the runtime, not sketches):
  - `frame_begin :: proc()` — resets per-frame draw state to defaults
  - `set_frame_inputs :: proc(w, h, frame: int, t, dt, mx, my: f32, pressed: bool)`
  - `apply_pending_size :: proc()` — if `size()` was called, resize the raylib window; returns nothing
- Consumes: `Color`, `rgb`, `rgba` (Task 3); `PI`/`TAU` (Task 2).

Helper (internal): `args_to_color :: proc(args: []u8) -> Color` maps 1/2/3/4 `u8` args to a `Color` the way Processing overloads do (`v` → gray; `v,a` → gray+alpha; `r,g,b`; `r,g,b,a`).

- [ ] **Step 1: Add frame state + helpers to canvas.odin**

Append to `canvas/canvas.odin`:

```odin
import rl "vendor:raylib"

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

args_to_color :: proc(args: []u8) -> Color {
	switch len(args) {
	case 1: return Color{args[0], args[0], args[0], 255}
	case 2: return Color{args[0], args[0], args[0], args[1]}
	case 3: return Color{args[0], args[1], args[2], 255}
	case 4: return Color{args[0], args[1], args[2], args[3]}
	}
	return BLACK
}

_rlcol :: proc(col: Color) -> rl.Color { return rl.Color{col.r, col.g, col.b, col.a} }

size :: proc(w, h: int) {
	_pending_w = w
	_pending_h = h
	_size_dirty = true
}

// Called by the runtime once per frame, before the sketch's draw.
frame_begin :: proc() {
	_fill_col   = WHITE
	_fill_on    = true
	_stroke_col = BLACK
	_stroke_on  = true
	_stroke_w   = 1
}

set_frame_inputs :: proc(w, h, frame: int, t, dt, mx, my: f32, pressed: bool) {
	width, height = w, h
	frame_count = frame
	time, delta_time = t, dt
	mouse_x, mouse_y = mx, my
	mouse = Vec2{mx, my}
	mouse_pressed = pressed
}

apply_pending_size :: proc() {
	if _size_dirty {
		rl.SetWindowSize(i32(_pending_w), i32(_pending_h))
		_size_dirty = false
	}
}
```

- [ ] **Step 2: Implement shapes.odin**

Create `canvas/shapes.odin`:

```odin
package canvas

import rl "vendor:raylib"

background :: proc(args: ..u8) {
	col := args_to_color(args)
	// Draw a full-canvas rect so alpha creates trails (ClearBackground ignores alpha).
	rl.DrawRectangle(0, 0, i32(width), i32(height), _rlcol(col))
}

fill :: proc(args: ..u8) {
	_fill_col = args_to_color(args)
	_fill_on  = true
}
no_fill :: proc() { _fill_on = false }

stroke :: proc(args: ..u8) {
	_stroke_col = args_to_color(args)
	_stroke_on  = true
}
no_stroke :: proc() { _stroke_on = false }

stroke_weight :: proc(w: f32) { _stroke_w = w }

circle :: proc(x, y, r: f32) {
	if _fill_on   { rl.DrawCircleV(rl.Vector2{x, y}, r, _rlcol(_fill_col)) }
	if _stroke_on { rl.DrawRing(rl.Vector2{x, y}, r - _stroke_w, r, 0, 360, 64, _rlcol(_stroke_col)) }
}

rect :: proc(x, y, w, h: f32) {
	if _fill_on   { rl.DrawRectangleV(rl.Vector2{x, y}, rl.Vector2{w, h}, _rlcol(_fill_col)) }
	if _stroke_on { rl.DrawRectangleLinesEx(rl.Rectangle{x, y, w, h}, _stroke_w, _rlcol(_stroke_col)) }
}

line :: proc(x1, y1, x2, y2: f32) {
	if _stroke_on {
		rl.DrawLineEx(rl.Vector2{x1, y1}, rl.Vector2{x2, y2}, _stroke_w, _rlcol(_stroke_col))
	}
}

point :: proc(x, y: f32) {
	col := _stroke_on ? _stroke_col : _fill_col
	if _stroke_w <= 1 {
		rl.DrawPixelV(rl.Vector2{x, y}, _rlcol(col))
	} else {
		rl.DrawCircleV(rl.Vector2{x, y}, _stroke_w * 0.5, _rlcol(col))
	}
}
```

- [ ] **Step 3: Build to verify the canvas package compiles**

Run: `odin build canvas -build-mode:obj -out:build/_canvas_check.obj -debug` (compile-only check; the package has no `main`).
Expected: exit 0, no errors. (If the toolchain rejects `-build-mode:obj` for a library package, instead run `odin test canvas` which also fully type-checks the package; the existing tests must still pass.)

- [ ] **Step 4: Commit**

```bash
git add canvas/canvas.odin canvas/shapes.odin
git commit -m "feat: canvas frame state, input mirrors, and first drawing primitives"
```

---

### Task 5: Sketch registry + runtime runs one hardcoded sketch

Wire it together: the `canvas` package holds a registry of sketches; a sketch registers via `@(init)`; the runtime picks the first registered sketch, calls its `setup` once, and its `draw` every frame with inputs pushed in.

**Files:**
- Modify: `canvas/canvas.odin` (add the registry + `sketch()`)
- Create: `sketches/hello/hello.odin`
- Create: `runtime/sketches_manifest.odin`
- Modify: `runtime/runtime.odin` (drive the active sketch)

**Interfaces:**
- Produces (from canvas):
  - `Sketch_Proc :: proc()`
  - `Sketch_Entry :: struct { name: string, setup: Sketch_Proc, draw: Sketch_Proc }`
  - `sketch :: proc(name: string, setup, draw: Sketch_Proc)` — appends to the registry
  - `registry :: proc() -> []Sketch_Entry` — the runtime reads this
- Consumes (runtime → canvas): `frame_begin`, `set_frame_inputs`, `apply_pending_size`, mirrors.

- [ ] **Step 1: Add the registry to canvas.odin**

Append to `canvas/canvas.odin`:

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

- [ ] **Step 2: Write the hello sketch**

Create `sketches/hello/hello.odin`:

```odin
package hello

import c "../../canvas"
import "core:math"

t: f32

setup :: proc() {
	c.size(800, 800)
}

draw :: proc() {
	c.background(18, 18, 22)
	t += c.delta_time

	// a ring of circles that pulse
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

	// a dot that follows the mouse
	c.fill(255, 240, 120)
	c.circle(c.mouse_x, c.mouse_y, 12)
}

@(init) _register :: proc() {
	c.sketch("Hello", setup, draw)
}
```

- [ ] **Step 3: Create the sketches manifest**

Create `runtime/sketches_manifest.odin`. The blank import pulls the sketch package into the build so its `@(init)` runs. (Plan 3's scaffolder will append lines here automatically; for now it is hand-edited.)

```odin
package runtime

import _ "../sketches/hello"
```

- [ ] **Step 4: Drive the active sketch from the runtime**

Replace `runtime/runtime.odin` with:

```odin
package runtime

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
```

Note: `frame_count` is a canvas mirror; the runtime advances it by passing `c.frame_count + 1`. On reload, `setup_done` stays true (retained), so the sketch keeps drawing without re-running setup — but pressing **F6** (force_restart) rebuilds memory and re-runs `setup`. On a *code* hot-reload (F5 or DLL change without layout change) the sketch's own globals reset per the design; `setup` is re-run only when memory is rebuilt. To match the spec's "reload = restart" for sketch edits, Task 6 makes the watcher trigger a restart-style reload; for this task, manual F6 restarts.

- [ ] **Step 5: Build and smoke-test (verification)**

Run: `cmd /c build.bat`
Expected: exit 0.

Run: `build\odessa.exe`
Expected: an 800×800 window (resized by `size()`), a rotating ring of 12 pulsing purple circles, and a yellow dot tracking the mouse. Press **F6** → sketch restarts (ring resets to its start angle). Close window to exit.

- [ ] **Step 6: Commit**

```bash
git add canvas/canvas.odin sketches/hello/hello.odin runtime/sketches_manifest.odin runtime/runtime.odin
git commit -m "feat: sketch registry + runtime drives the hello sketch"
```

---

### Task 6: Integrated rebuild watcher + on-screen compile errors

Make the loop turnkey: the host watches the source tree and spawns `odin build` on change; on success the existing DLL-time poll reloads (as a restart, so sketch state resets per spec); on failure the host writes the compiler output to `build/build_error.txt`, and the runtime overlays that text so the studio never dies on a typo.

**Files:**
- Modify: `host/host.odin` (add a source-tree mtime watcher + build spawner)
- Modify: `runtime/runtime.odin` (read `build/build_error.txt`; overlay it if present)

**Interfaces:**
- Consumes: existing `Api` reload loop.
- Produces: `build/build_error.txt` written by the host on build failure, deleted on success. The runtime treats its presence as "show this error."

- [ ] **Step 1: Add a source watcher + build spawner to the host**

Add these procs to `host/host.odin` and call `maybe_rebuild()` once per loop iteration (before the DLL-time check). Watch `.odin` files under `runtime/`, `canvas/`, and `sketches/` and rebuild when the newest mtime increases.

```odin
import "core:os/os2"
import "core:path/filepath"
import "core:strings"

WATCH_DIRS := []string{"runtime", "canvas", "sketches"}

newest_source_mtime :: proc() -> time.Time {
	newest: time.Time
	for dir in WATCH_DIRS {
		filepath.walk(dir, proc(info: os.File_Info, in_err: os.Error, user: rawptr) -> (os.Error, bool) {
			newest := (^time.Time)(user)
			if !info.is_dir && strings.has_suffix(info.name, ".odin") {
				if info.modification_time._nsec > newest._nsec {
					newest^ = info.modification_time
				}
			}
			return nil, false
		}, &newest)
	}
	return newest
}

last_src_time: time.Time

// Returns true if a rebuild was attempted (regardless of success).
maybe_rebuild :: proc() -> bool {
	src := newest_source_mtime()
	if src._nsec <= last_src_time._nsec { return false }
	last_src_time = src

	// Spawn: odin build runtime -build-mode:dll -out:build/odessa.dll -debug
	desc := os2.Process_Desc{
		command = []string{"odin", "build", "runtime", "-build-mode:dll", "-out:build/odessa.dll", "-debug"},
	}
	state, stdout, stderr, err := os2.process_exec(desc, context.allocator)
	defer delete(stdout)
	defer delete(stderr)

	if err != nil || !state.success {
		msg := len(stderr) > 0 ? string(stderr) : string(stdout)
		os.write_entire_file("build/build_error.txt", transmute([]u8)msg)
		fmt.eprintln("Build failed; error shown in-app.")
		return true
	}
	os.remove("build/build_error.txt")
	return true
}
```

In `main`, inside the `for api.update()` loop, add `maybe_rebuild()` as the first statement, and initialize `last_src_time = newest_source_mtime()` just before the loop so the first launch doesn't rebuild immediately.

Also change the reload branch so a source-driven reload performs a **restart** (re-run `setup`, matching the spec's "edit = restart"): when `dll_time` changed, set `force_restart := true` for that iteration. Concretely, replace the reload/restart computation with:

```odin
	last_src_time = newest_source_mtime()
	for api.update() {
		maybe_rebuild()

		force_reload  := api.force_reload()
		force_restart := api.force_restart()
		reload := force_reload || force_restart

		dll_time, err := os.last_write_time_by_name(DLL_PATH)
		if err == nil && dll_time != api.dll_time {
			reload = true
			force_restart = true   // edit-driven reload = restart (spec §5)
		}

		if reload {
			new_api, new_ok := load_api(version)
			if new_ok {
				restart := force_restart || api.memory_size() != new_api.memory_size()
				if restart {
					api.shutdown()
					for &old in old_apis { unload_api(&old) }
					clear(&old_apis)
					unload_api(&api)
					api = new_api
					api.init()
				} else {
					append(&old_apis, api)
					mem := api.memory()
					api = new_api
					api.hot_reloaded(mem)
				}
				version += 1
			}
		}
	}
```

- [ ] **Step 2: Overlay the build error in the runtime**

In `runtime/runtime.odin`, at the end of `odessa_update` (after drawing the sketch, before `rl.EndDrawing()`), read the error file and, if present, draw it:

```odin
	if data, ok := os.read_entire_file("build/build_error.txt", context.temp_allocator); ok && len(data) > 0 {
		rl.DrawRectangle(0, 0, i32(rl.GetScreenWidth()), 120, rl.Color{120, 20, 20, 220})
		rl.DrawText("BUILD ERROR (fix the sketch to reload):", 12, 10, 20, rl.WHITE)
		ctext := strings.clone_to_cstring(string(data), context.temp_allocator)
		rl.DrawText(ctext, 12, 40, 16, rl.Color{255, 220, 220, 255})
	}
```

Add `import "core:os"` and `import "core:strings"` to `runtime/runtime.odin` if not already present.

- [ ] **Step 3: Build and smoke-test the happy path (verification)**

Run: `cmd /c build.bat` then `build\odessa.exe`.
While it runs, edit `sketches/hello/hello.odin` — change the ring radius `220` to `300` and save.
Expected: within ~1s the host rebuilds, the window reloads, and the ring is visibly larger. The sketch restarts (ring angle resets).

- [ ] **Step 4: Smoke-test the error path (verification)**

While it still runs, introduce a deliberate syntax error in `hello.odin` (e.g. delete a closing `}`) and save.
Expected: a red banner appears at the top of the window with the Odin compiler error; the app keeps running the last-good sketch underneath. Fix the error and save.
Expected: the banner disappears and the sketch reloads.

- [ ] **Step 5: Commit**

```bash
git add host/host.odin runtime/runtime.odin
git commit -m "feat: integrated rebuild watcher with on-screen compile errors"
```

---

## Self-Review

**Spec coverage (Plan 1 scope only):**
- Host/DLL split + hot reload (spec §1, §5) → Tasks 1, 5, 6. ✔
- Studio owns the rebuild; compile error stays alive on-screen (spec §5) → Task 6. ✔
- `canvas` math/random/color/shapes core subset (spec §3) → Tasks 2–4. ✔
- Sketch authoring: own package, bare state globals, `c.`-qualified calls, `@(init)` registration (spec §2) → Task 5. ✔
- Reload = restart for edits (spec §5) → Task 6 Step 1. ✔
- Seedable reproducible RNG (spec §3) → Task 2. ✔
- Deferred to later plans (correctly out of scope here): gallery UI, New Sketch scaffolder, transforms/noise/vectors/easing/typography/images, HSB, export. Tracked in Plans 2–4.

**Placeholder scan:** No TBD/TODO; every code step shows complete code; every verification step states exact commands and expected results. ✔

**Type consistency:** `Sketch_Proc`/`Sketch_Entry`/`sketch`/`registry` used identically in Tasks 5. `Color`/`rgb`/`rgba`/`gray` consistent across Tasks 3–4. `args_to_color`, `_rlcol`, mirror variable names consistent between `canvas.odin` and `shapes.odin`. `Api` field names match the DLL's `odessa_*` exports via the `odessa_` prefix binding. ✔

**Known risk flagged for the implementer:** exact `vendor:raylib` proc names (`DrawRing`, `DrawRectangleLinesEx`, `DrawPixelV`, `GetScreenWidth`) and the `core:os/os2` process API can drift between Odin nightlies. If any fails to compile, check the installed bindings (`odin doc vendor:raylib` / `odin doc core:os/os2`) and adjust the call — the surrounding logic is unaffected. The game template's verified raylib usage is a reference for the primitives it already uses.
