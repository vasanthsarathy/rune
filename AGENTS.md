# Working on Rune

Guidance for anyone — human or AI agent — contributing to Rune. Read this before making changes. (Claude Code reads `CLAUDE.md`, which imports this file.)

## What Rune is (and isn't)

Rune is a **Processing-style creative-coding IDE for Odin**. The model is Processing's **compile-and-run**, *not* hot-reload:

- A **sketch** is a standalone Odin program that imports the `canvas` package and calls `c.run(setup, draw)`.
- The **IDE** (`rune/`, `package main`) edits a sketch file and, on Run, shells out to `odin build` and launches the resulting executable.

There is deliberately **no DLL hot-reloading**. Don't reintroduce it.

## Repository layout

```
canvas/    the Processing-style drawing API + the run() window loop
editor/    pure, unit-tested text-buffer model (cursor, selection, undo, Odin tokenizer)
runner/    compile / launch / stop a sketch process (over core:os)
rune/      the IDE app (package main): editor view, docs, autocomplete, theme, logo
sketches/  sketches, each a standalone Odin program
assets/    logo + screenshots
docs/      design specs & plans (historical; the app predates a couple of renames)
```

## Build & test

Requires the [Odin compiler](https://odin-lang.org/docs/install/) (`dev-2026-05-nightly` or newer; it bundles raylib).

```bash
# build + launch the IDE
build.bat            # Windows
./build.sh           # Linux / macOS

# build + run a sketch directly
build_sketch.bat hello   # or ./build_sketch.sh hello

# run the unit tests (ALWAYS before claiming a change works)
odin test canvas
odin test editor
odin test runner
```

The `canvas`, `editor`, and `runner` packages have real unit tests. Pure logic (buffer, tokenizer, math, color, RNG, noise) is TDD'd — add tests for new pure logic.

## Conventions

- **Odin idioms**, tabs for indentation, match the surrounding style.
- **Theme:** UI colors live in `rune/theme.odin` ("Ink & Signal" — deep indigo + one azure accent). Don't hardcode colors; use the constants.
- **Text & layout:** draw text via `draw_text` / `measure` (a loaded TTF). For window dimensions use `screen_w()` / `screen_h()` — **never** `rl.GetScreenWidth/Height` (they're unreliable under high-DPI after a resize).
- **Canvas state:** the `canvas` package may use mutable package globals for per-frame draw/input state (the run loop resets them each frame). This is intentional and the one exception to "no mutable globals."
- **Editor:** the buffer *model* is pure and lives in `editor/` (testable, no raylib); *rendering/input* lives in `rune/editor_view.odin`.

## Adding to the `canvas` API

When you add a public `canvas` function, do all three:

1. Implement it in `canvas/`.
2. Add a doc entry to `DOCS` in `rune/docs.odin` (name, signature, summary, example).
3. Add the name to `CANVAS_API` in `rune/autocomplete.odin`.

## Gotchas (learned the hard way — don't rediscover these)

- **High-DPI resize:** `rl.GetScreenWidth/Height` flip from logical to physical after a resize under `WINDOW_HIGHDPI`. Use `screen_w()/screen_h()` (derived from render size ÷ DPI).
- **`os.process_start` needs an absolute path** on Windows (a forward-slash relative path → `Not_Exist`); see `runner.launch` (`filepath.abs`).
- **`Process_State.success` ≠ exit 0** — it means "ran to completion". Key build success off `state.exit_code == 0`.
- **Bitwise XOR is `~` / `~=`**, not `^`.
- **`reserved package name`:** `runtime` is reserved; don't name a package that.
- **Font crispness:** the glyph atlas is baked at physical DPI (`FONT_BASE * dpi`); text is positioned by measured width so it stays aligned in any font.

## Verifying changes

- Compiles is not enough. **Run the unit tests**, and for UI changes, **look at the window** — capture it (Windows: `PrintWindow`) since interactive testing can't always be automated. Note honestly what you could and couldn't verify.
- Keep `build/` and `output/` out of commits (they're git-ignored).

## Commits & branches

- Conventional-style messages: `feat:`, `fix:`, `docs:`, `refactor:`, `test:` — imperative mood, and explain the *why*.
- Work on a feature branch; open a PR to `main`. CI (build + test on Windows/Linux/macOS) must pass.
