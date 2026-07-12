# Odessa — Design Spec (Processing IDE for Odin)

**Date:** 2026-07-12
**Status:** Draft for review
**Author:** Vasanth + Claude
**Supersedes:** `2026-07-11-odessa-design.md` (hot-reload studio — abandoned)

## What this is

Odessa is a **Processing-style IDE for the Odin language**. It is a desktop app with
a **built-in code editor**; you write a sketch (`setup`/`draw` using a built-in
`canvas` library that mirrors the Processing/p5 API), press **Run ▶**, and Odessa
compiles the sketch and launches it in **its own separate window**, animating. Press
**Stop ■** to kill it. Edit, Run again.

It is a **real tool for making art**. The model is deliberately Processing's: a simple
**edit → Run → watch → Stop → edit** loop. **There is no hot reload** — that was an
earlier direction, now abandoned.

### Goals (v1)

- A single IDE window: **code editor** + **toolbar (Run/Stop)** + **console**.
- Write a sketch with the `canvas` (Processing-style) API.
- **Run** compiles the current sketch and launches it in its own window.
- **Stop** terminates the running sketch.
- **Console** shows compile errors (so you can fix them) and the sketch's stdout/stderr.

### Non-goals (v1)

- Hot reload / live coding (abandoned by design).
- Syntax highlighting, multiple-file tabs, find/replace, autocomplete — **fast-follows**.
- An embedded preview pane (the sketch runs in its **own** window in v1).
- Direct GIF/MP4 export, HSB color, simplex noise, images, rich typography — deferred
  (as in the prior spec; the `canvas` library grows over time).

## 1. Architecture

Two programs plus a shared library:

```
┌───────────────────────────────────────────────┐
│  odessa.exe — the IDE                          │
│  ┌──────────────────────┬──────────────────┐  │
│  │  Code editor pane     │                  │  │
│  │  (text buffer, cursor,│   Toolbar:       │  │
│  │   selection, scroll,  │   ▶ Run  ■ Stop  │  │
│  │   line numbers)       │                  │  │
│  ├──────────────────────┴──────────────────┤  │
│  │  Console (compile errors + sketch output) │  │
│  └───────────────────────────────────────────┘ │
│  Owns its own raylib window + input.            │
└───────────────────────────────────────────────┘
        │ writes sketch file, spawns compiler, launches/kills process
        ▼
┌───────────────────────────────────────────────┐
│  the sketch — a standalone compiled program    │
│  (its own raylib window; runs setup once +      │
│   draw() each frame via canvas.run)             │
└───────────────────────────────────────────────┘
        │ imports
        ▼
┌───────────────────────────────────────────────┐
│  canvas/ — the Processing-style API library     │
│  (shapes, color, math, random, noise, vectors,  │
│   time, input, + the run() window loop)         │
└───────────────────────────────────────────────┘
```

- **`odessa.exe`** is the IDE. It renders the editor UI with raylib, manages the sketch
  file on disk, and drives the compile/run/stop lifecycle. It is a normal foreground
  program — **no DLL hot-reload machinery** (that is all removed).
- **A sketch is a standalone program.** It imports `canvas`, defines `setup`/`draw`, and
  is compiled to an `.exe` that opens its own window. The `main` entry point is provided
  by Odessa at build time (see §5), so the user's sketch file contains only `setup`/`draw`
  (+ their imports/state) — Processing-like.
- **`canvas`** is the Processing API surface **plus** a `run(setup, draw)` procedure that
  owns the sketch's window + frame loop. (In the abandoned design, a hot-reload runtime
  owned the loop; now `canvas.run` does.)

### Carried forward vs. removed

- **Carried forward (already built + tested):** `canvas/math.odin`, `canvas/random.odin`,
  `canvas/color.odin`, `canvas/shapes.odin`, and the frame-state/mirrors/`size`/draw-state
  parts of `canvas/canvas.odin` (12 passing unit tests).
- **Removed:** `host/` (DLL loader), `runtime/` (hot-reload module + sketch manifest), the
  `@(init)` sketch registry, and the `#+feature global-context` requirement. The
  `set_frame_inputs`/`frame_begin`/`apply_pending_size` hooks are **folded into**
  `canvas.run` rather than called by an external runtime.

## 2. Authoring a sketch

The user writes only `setup`/`draw` (+ their own bare-global state), using the `canvas`
API under the single-letter alias `c` (library calls are qualified — Odin can't do bare
cross-package calls; see the prior spec's finding). Example:

```odin
package main            // a sketch is a standalone program
import c "canvas"       // the Processing-style library, aliased to `c`
import "core:math"

t: f32                  // your own state: ordinary bare globals

setup :: proc() {
    c.size(800, 800)
}

draw :: proc() {
    c.background(18, 18, 22)
    t += c.delta_time
    c.fill(255, 120, 40)
    c.circle(c.mouse_x, c.mouse_y, 40 + 20*math.sin(t))
}
```

- **No `main`, no `@(init)`, no feature flags** in the sketch file — Odessa injects the
  `main` that calls `c.run(setup, draw)` at build time (§5).
- The user's own state stays bare globals (`t`); library calls are `c.…`.
- Caveat retained: don't name a local `c` (it shadows the library alias).

## 3. The `canvas` library

Unchanged in spirit from the prior spec's §3 (that design is carried forward). The v1
core: **setup/window** (`size`, `background`, `width`/`height`), **shapes** (`point`,
`line`, `rect`, `circle`/`ellipse`, plus more as fast-follows), **color & style**
(`fill`, `stroke`, `no_fill`, `no_stroke`, `stroke_weight`, `Color`), **math & random**
(`map_range`, `lerp`, `clamp`, `dist`, `radians`/`degrees`, `PI`/`TAU`, seedable
`random`/`random_range`), **time & input** (`frame_count`, `time`, `delta_time`,
`mouse`/`mouse_x`/`mouse_y`, `mouse_pressed`). Noise, vectors, easing, transforms,
typography, images remain fast-follows.

**New in this design — the window/loop entry point:**

- `run :: proc(setup: proc(), draw: proc(), title := "Odessa Sketch")` — opens the raylib
  window, calls `setup` once (honoring a `size()` request), then loops each frame:
  refresh the input/time mirrors → reset per-frame draw state → `BeginDrawing` → `draw()`
  → `EndDrawing`, until the window is closed. This consolidates the loop logic that the
  removed hot-reload runtime used to perform.

## 4. The IDE (`odessa.exe`)

A single window, three regions:

- **Code editor pane** — the v1 editor (see §6). Edits one sketch file at a time.
- **Toolbar** — **Run ▶**, **Stop ■**, and a small status line (Idle / Compiling / Running
  / Compile-error). Run is also bound to a hotkey (e.g. `Ctrl+R`); Save to `Ctrl+S`.
- **Console** — a scrollable text area showing: compiler output on a failed Run (so you
  can read the Odin error), and the running sketch's stdout/stderr. Cleared at the start
  of each Run.

The IDE owns one raylib window and its own input handling. It does **not** render the
sketch — the sketch has its own window.

## 5. Run / Stop mechanics

- **On Run:**
  1. Save the editor buffer to the sketch's source file on disk.
  2. Ensure the build harness `main` exists: Odessa writes a generated `_odessa_main.odin`
     into the sketch folder containing `package main` + `import c "…/canvas"` +
     `main :: proc() { c.run(setup, draw) }`. (The user's file stays clean.)
  3. Compile: spawn `odin build <sketch_dir> -out:<build>/sketch.exe` (debug). Capture
     stdout+stderr and the exit code.
  4. On **failure**: show the captured compiler output in the console; status →
     Compile-error. Do not launch.
  5. On **success**: launch `sketch.exe` as a child process; status → Running. Capture its
     stdout/stderr into the console.
- **On Stop:** terminate the sketch child process (and clean up); status → Idle. Stop is
  also implicit if the user closes the sketch window (Odessa detects the child exited).
- **Only one sketch runs at a time** in v1. Pressing Run while one is Running does Stop →
  rebuild → Run.
- **Process hygiene:** Odessa always tracks the child PID and kills it on Stop, on the next
  Run, and on IDE exit — no orphaned sketch windows.

**Open technical item to pin during planning:** the exact Odin requirement for building an
executable from a sketch directory (package-name rules for `main`, and whether the
generated `_odessa_main.odin` must co-reside in the sketch's package). Verified against the
installed toolchain in the plan, not assumed.

## 6. The editor (v1 scope: "Minimal + line numbers")

The largest single piece; raylib provides font rendering + raw input but no editor widget,
so this is built from scratch. **v1 includes:**

- A text buffer supporting insert/delete of characters and newlines.
- Cursor with arrow-key movement (left/right/up/down, home/end), and mouse click to place
  the cursor.
- Text selection (shift+arrows, click-drag), with copy/cut/paste via the system clipboard.
- Undo/redo.
- Vertical scrolling (the buffer can exceed the visible area); keep the cursor in view.
- **Line numbers** in a gutter.
- Save to disk (`Ctrl+S`) and load a sketch file on open.
- Monospace font rendering.

**Explicitly deferred (fast-follows):** syntax highlighting, multiple files/tabs,
find/replace, autocomplete, bracket matching, auto-indent.

## 7. Testing

- **Deterministic `canvas` core** keeps its real unit tests (`odin test`): math, seedable
  random, color — already passing (12 tests), carried forward.
- **Editor text buffer** is pure logic and gets **real unit tests**: insert/delete,
  cursor movement across line boundaries, selection ranges, undo/redo, and clipboard
  edits operate on a testable buffer model independent of rendering.
- **Run/Stop lifecycle** is verified by a smoke test: compile a known-good sketch → assert
  an exe is produced and launches; compile a known-bad sketch → assert the compiler error
  is captured (non-empty) and no process launches; Stop → assert the child is gone.
- **Rendering** (editor UI + sketch drawing) stays manual/visual, as appropriate for a
  creative tool — but the buffer model, the run lifecycle, and the canvas math are covered.

## Decisions locked during brainstorming

| Decision | Choice |
|---|---|
| Product shape | Processing-style IDE for Odin (editor + Run/Stop) |
| Live reload | **None** — compile-and-run, like Processing |
| Where the sketch runs | Its **own separate window** (not embedded) |
| Authoring | `setup`/`draw` only; user state = bare globals; library via alias `c`; `main` injected at build time |
| Editor v1 scope | Minimal + line numbers (no syntax highlighting yet) |
| Sketch = | a standalone compiled program using `canvas.run` |
| Kept from prior work | the `canvas` library (math/random/color/shapes, 12 tests) |
| Dropped from prior work | host/DLL hot-reload harness, sketch registry, `@(init)`/feature-flag |
| Name / location | Odessa; `1_Projects/2026-07_odessa/` |
