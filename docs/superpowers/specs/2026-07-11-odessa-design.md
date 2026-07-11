# Odessa — Design Spec

**Date:** 2026-07-11
**Status:** Approved (brainstorming complete)
**Author:** Vasanth + Claude

## What this is

Odessa is a Processing/p5-style **creative-coding studio** written in Odin. It is
a desktop app that presents a **gallery of sketches**, runs the one you pick, and
**hot-reloads** it as you edit. Sketches are written against a built-in **`canvas`
library** — a p5-style, immediate-mode API (`circle`, `fill`, `translate`, `noise`,
`random`, `map_range`, …).

It is a **real tool for making art**, not a faithful 1:1 Processing port. The
workflow (fast hot-reload loop, low-ceremony authoring, reproducible export) is the
priority over API completeness.

### Goals (v1)

- Launch a studio window with a gallery of registered sketches.
- Create a new sketch from an in-app **"New Sketch"** button (foldering hidden).
- Edit a sketch file and see it **hot-reload live**.
- Draw with the **v1 core `canvas` API**.
- **Export** the current frame as PNG and export a numbered PNG **sequence**.

### Non-goals (v1)

- Direct GIF/MP4 encoding (assemble sequences externally with ffmpeg).
- Persistent sketch state across reloads (reload = restart; see §5).
- Simplex noise, pixel-buffer read/write, rich typography, a scaffolding CLI — all
  named **fast-follows**, deliberately deferred.
- 3D.

## 1. Architecture

Layered, host/DLL split (reuses the hot-reload architecture from the Odin+Raylib
game template):

```
┌─────────────────────────────────────────────┐
│  Studio shell (window, gallery, hot-reload    │  ← the host .exe you launch
│  watcher, playback controls, export)          │
├─────────────────────────────────────────────┤
│  Sketch registry  (list of runnable sketches) │  ← how the gallery finds sketches
├─────────────────────────────────────────────┤
│  Your sketches    (setup/draw + your state)   │  ← what you write; compiled into the DLL
├─────────────────────────────────────────────┤
│  `canvas` library — the p5-style API          │  ← circle(), fill(), noise(), ...
├─────────────────────────────────────────────┤
│  raylib (window, GPU drawing, input, PNG I/O) │  ← vendored via Odin `vendor:raylib`
└─────────────────────────────────────────────┘
```

- The studio shell is the **host `.exe`**. Sketches + the `canvas` library compile
  into the **reloadable `.dll`**.
- The **`canvas` library** is the heart: free functions over a single global canvas
  state (p5 "global mode"). Only one sketch draws at a time, so a single shared
  drawing state is safe.
- **Sketches never touch raylib directly** — only the `canvas` API. Keeps sketches
  portable if the backend is ever swapped.

## 2. Authoring a sketch

The p5 feel: open a file, write `setup`/`draw`, keep state in plain variables, call
bare functions. Odin requires unique top-level names per package, so **each sketch is
its own package (its own folder)** — giving every sketch a clean namespace and natural
global names. The in-app scaffolder makes the folder ceremony invisible.

```odin
package flowfield              // each sketch is its own tiny package (a folder)
using import cv "../../canvas" // pull the library in; `using` gives bare names

// --- your state: ordinary package globals, named however you like ---
t:         f32
particles: [8000]Vec2

setup :: proc() {
    size(900, 900)
    for &p in particles do p = random_vec2()
}

draw :: proc() {
    background(10, 10, 12, 20)   // low alpha = trails
    stroke(255)
    t += 0.01
    for &p in particles {
        angle := noise(p.x*0.002, p.y*0.002, t) * TAU
        p += vec2(cos(angle), sin(angle))
        point(p.x, p.y)
    }
}

@(init) register :: proc() { sketch("Flow Field", setup, draw) }
```

- A sketch registers itself into the gallery via an `@(init)` proc calling
  `sketch(name, setup, draw)`.
- A committed `registry.odin` does `import _ "sketches/<slug>"` per sketch folder,
  which triggers each `@(init)`. (Explicit + committed → deterministic builds; Odin
  has no auto-discovery.)
- Adding a sketch = scaffold folder + append one import line. The in-app New Sketch
  button writes both.

## 3. The built-in `canvas` library

Grouped into small, focused modules. **Bold = v1 core**; the rest are fast-follows on
the same foundation. Covers all four target sketch types (generative, animation,
interactive, data/vector).

- **Setup & window** — `size`, `background`, `frame_rate`, `pixel_density`;
  `width`/`height`.
- **Shapes** — `point`, `line`, `rect`, `circle`/`ellipse`, `triangle`, `quad`,
  `arc`, `polygon`, plus a `begin_shape`/`vertex`/`end_shape` path builder for
  freeform/bezier curves.
- **Color & style** — `fill`, `stroke`, `no_fill`, `no_stroke`, `stroke_weight`;
  RGBA default with an **HSB mode** toggle (`color_mode`); a `Color` type and a small
  palette helper.
- **Transforms** — `push`/`pop` (matrix stack), `translate`, `rotate`, `scale`.
- **Math & random** — `map_range`, `lerp`, `clamp`, `dist`, `radians`/`degrees`,
  constants (`PI`, `TAU`); `random`, `random_range`, `random_gaussian`, and a
  **seedable RNG** (reproducible art).
- **Noise** — `noise(x)`, `noise(x,y)`, `noise(x,y,z)` (Perlin) + `noise_seed`.
  Simplex is a fast-follow.
- **Vectors** — `Vec2 :: [2]f32` with `vec2`, built-in `+ - *` array math, plus
  `length`, `normalize`, `rotate`, `from_angle`, `lerp`.
- **Time & animation** — `frame_count`, `time` (seconds), `delta_time`, `millis`; an
  **easing** set (quad/cubic/sine/elastic…) and a `playhead` (0→1 loop position) for
  seamless loops + export.
- **Input** — `mouse` (`Vec2`), `mouse_x/y`, `pmouse`, `mouse_pressed`, button state;
  `key_down(key)`; optional event hooks a sketch may implement (`on_mouse_pressed`,
  `on_key_pressed`).
- **Typography** *(modest v1)* — `text`, `text_size`, `text_align`, `text_font`
  (load `.ttf`).
- **Images/pixels** — `load_image`, `image`, `save_frame` (PNG). Direct pixel
  read/write is a fast-follow.

## 4. The studio shell

Deliberately minimal — the sketch is the star.

- **Gallery / launcher** — on start, a list/grid of registered sketches (name +
  small thumbnail). Click to run. A **"＋ New Sketch"** entry prompts for a name,
  scaffolds the folder behind the scenes, and the sketch appears once hot-reload
  rebuilds.
- **Running view** — the sketch fills the window. A thin, **toggleable overlay bar**
  (hotkey to hide for clean viewing/recording):
  - **Play / pause / step** (advance one frame at a time)
  - **Restart** (re-run `setup`)
  - **FPS + frame counter**
  - **Back to gallery**
- **Export:**
  - `S` → **save current frame** as timestamped PNG to the sketch's `output/` folder.
  - **Export sequence** → prompt for frame count / loop cycles → render
    `frame_0000.png …` deterministically. Export drives `time`/`playhead` by a
    **fixed timestep** (not wall-clock), so output is smooth and reproducible
    regardless of render speed. Progress readout; ESC cancels.
- **Hot-reload feedback** — a brief toast on reload; on **compile failure the studio
  stays up and shows the compiler error on-screen** instead of crashing.

## 5. Hot-reload & state mechanics

Reuses the template's host/DLL reload pattern, in which the host retains a heap state
struct across reloads (only code swaps). Consequence: **mutable package-level globals
in the DLL are wiped/re-initialized on every reload.**

- **Studio state** (active sketch, play/pause, export progress, window size) lives on
  a retained `Studio_Memory` struct → obeys the template's golden rule, survives
  reloads.
- **Sketch state = bare package globals; reload = restart.** On reload the host
  re-runs the active sketch's `setup`. Seeded RNG makes the restart reproducible.
  Per-frame canvas state (fill/stroke/transform stack) is transient, rebuilt each
  frame. This is the p5-like "save = restart" behavior — chosen for simplicity over
  state-preservation.
- **Stable slug lookup:** the host tracks the active sketch by its registered *name*
  (a string), not a pointer — so after a reload rebuilds the registry it re-resolves
  the same sketch. Robust across added/removed sketches.
- **Studio owns the rebuild (turnkey):** the studio watches `sketches/` + `canvas/`,
  runs `odin build … -build-mode:dll` on change, reloads on success, shows the error
  on-screen on failure. Replaces the template's "re-run the .bat in another terminal"
  with one integrated loop. New Sketch writes files → same build path → appears in
  the gallery.
- **Persistent sketch state across reloads** (edit code, animation keeps morphing) is
  an explicit **non-goal for v1**; a future opt-in retained-arena mechanism can add it
  without changing the default authoring style.

## 6. Testing

- **Deterministic core → real unit tests** (`odin test`, `@(test)`): math
  (`map_range`/`lerp`/`clamp`/easing), noise (seed reproducibility + output bounds),
  RNG (seeded reproducibility), vectors (length/normalize/rotate), color (RGB↔HSB
  round-trip), transform matrix stack (push/pop correctness).
- **Rendering layer → light smoke tests:** build the DLL, run a known sketch
  headlessly for a few frames, assert no crash and that `save_frame` produces a
  non-empty PNG. Optional golden-image compare later.
- **Scaffolder test:** New Sketch produces a folder + registry line that compiles
  (build smoke test).
- Visual/aesthetic judgment stays manual — appropriate for an art tool — but the
  reproducible engine underneath is covered.

## Open decisions locked during brainstorming

| Decision | Choice |
|---|---|
| Primary goal | A real tool for making art |
| Authoring model | Processing-style `setup`/`draw` with bare globals |
| Sketch types to support | Generative, animation, interactive, data/vector (all four) |
| Run model | Sketch gallery + hot reload (a personal studio) |
| Export scope (v1) | PNG frame + numbered PNG sequence |
| Scaffolding trigger | In-app "New Sketch" only (no CLI in v1) |
| Reload behavior | Restart (re-run `setup`); bare globals |
| Name | Odessa; drawing library package `canvas` |
| Location | `1_Projects/2026-07_odessa/` (separate repo) |
