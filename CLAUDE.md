# CLAUDE.md

This file guides Claude Code (and other agents) working in this repository.

@AGENTS.md

## Quick reference

- Build the IDE: `build.bat` (Windows) / `./build.sh` (Unix) — outputs `build/rune.exe`.
- Run a sketch: `build_sketch.bat <name>` / `./build_sketch.sh <name>`.
- Test before claiming done: `odin test canvas && odin test editor && odin test runner`.
- Never reintroduce DLL hot-reload — Rune is compile-and-run (see AGENTS.md).
- Use `screen_w()/screen_h()` and the `theme.odin` colors; keep `canvas` API, docs, and autocomplete in sync when adding functions.
