# Contributing to Rune

Thanks for your interest in Rune! It's early (v0.1), so there's plenty of room to help.

## Ways to help

- **Report bugs** — open an issue with steps to reproduce, your OS, and the exact error text.
- **Suggest features** — open an issue describing the use case (what art/workflow it enables).
- **Send a pull request** — bug fixes, `canvas` API additions, editor improvements, docs.

## Development setup

You need the [Odin compiler](https://odin-lang.org/docs/install/) (`dev-2026-05-nightly` or newer; it bundles raylib) on your `PATH`.

```bash
build.bat            # Windows: build + launch the IDE
./build.sh           # Linux / macOS
odin test canvas && odin test editor && odin test runner   # run the tests
```

Read **[AGENTS.md](AGENTS.md)** — it's the working guide (architecture, conventions, and the gotchas we've already hit). It applies to human and AI contributors alike.

## Pull requests

1. Branch off `main` (e.g. `feat/svg-export`, `fix/console-scroll`).
2. Keep the change focused. Follow the existing style (tabs, Odin idioms, `theme.odin` colors).
3. **Add tests** for new pure logic (buffer/tokenizer/canvas math live in testable packages).
4. Make sure `odin test canvas`, `odin test editor`, `odin test runner` pass, and the IDE builds.
5. If you add a `canvas` function, update its docs (`rune/docs.odin`) and autocomplete (`rune/autocomplete.odin`) too.
6. Use clear commit messages (`feat:`, `fix:`, `docs:`, …) and explain the *why*.
7. Open the PR; CI must be green before merge.

## Scope for v0.1

Rune is intentionally small and legible. Prefer changes that keep it that way. Big new subsystems (e.g. the pen-plotter SVG backend) are worth an issue to discuss the design first.

## License

By contributing, you agree that your contributions are licensed under the project's [zlib license](LICENSE).
