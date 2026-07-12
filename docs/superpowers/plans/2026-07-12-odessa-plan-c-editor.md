# Odessa Plan C — Built-in Code Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a built-in code editor to Odessa so you type your sketch *inside* the IDE (line numbers, cursor, selection, clipboard, undo/redo, scrolling), and **Run** builds what you typed — completing the Processing-IDE loop.

**Architecture:** A pure, testable `editor` package holds the text-buffer model (lines of bytes + cursor + selection + undo stacks) with no rendering. The `odessa` app gains an `editor_view.odin` that renders a `editor.Buffer` with raylib and translates keyboard/mouse into buffer operations. `main.odin` loads the sketch file into a buffer on startup, lays out toolbar / editor / console, saves the buffer to disk on Ctrl+S, and makes **Run** save-then-build.

**Tech Stack:** Odin (`dev-2026-05` nightly), `vendor:raylib` (rendering/input/clipboard), `core:strings`, `core:testing`, `core:os` (file load/save).

## Global Constraints

- **Language:** Odin. Dynamic-array builtins used: `inject_at(&arr, i, v)`, `ordered_remove(&arr, i)`, `remove_range(&arr, lo, hi)`, `resize(&arr, n)`, `append(&arr, ..slice)` — all verified against this toolchain.
- **v1 editor scope = "Minimal + line numbers"** (per spec §6): insert/delete, cursor (arrows/home/end + mouse click), selection (shift+arrows, click-drag), clipboard copy/cut/paste, undo/redo, vertical scroll keeping the cursor visible, line numbers, save/load. **Deferred fast-follows:** syntax highlighting, multi-file tabs, find/replace, autocomplete, auto-indent.
- **Text is byte-based (ASCII-oriented) in v1.** Cursor columns are byte offsets; typed runes are UTF-8-encoded into the buffer, but cursor arithmetic is per-byte. Proper multi-byte cursor navigation is a deferred fast-follow (documented, not a bug).
- **Font:** raylib's default font is fixed-width; the view treats it as monospace (advance = width of one glyph at `FONT_SIZE`).
- **The `editor` package must remain pure** (no `vendor:raylib` import) so `odin test editor` is fast and rendering-independent.
- **Odin version floor:** `dev-2026-05-nightly`. **Build output dir:** `build/` (git-ignored). All prior tests (canvas 12, runner 2) must stay green.
- **The edited sketch file** is `sketches/hello/hello.odin` (constant `SKETCH_FILE`). Saving writes the buffer there; Run saves then builds `sketches/hello`.

---

## File Structure (after this plan)

```
2026-07_odessa/
  editor/
    buffer.odin        # package editor: Buffer model + editing ops (pure)      [NEW]
    buffer_test.odin   # @(test) for the buffer                                 [NEW]
  odessa/
    editor_view.odin   # package main: render a Buffer + keyboard/mouse input   [NEW]
    main.odin          # integrate: load/save, layout, Run saves buffer         [MODIFIED]
  canvas/  runner/  sketches/  ...   # unchanged
```

---

### Task 1: Editor buffer core (TDD)

The text model and editing operations — construction, serialization, insert, delete, and cursor movement. Pure logic, no selection/undo yet (Task 2).

**Files:**
- Create: `editor/buffer.odin`, `editor/buffer_test.odin`

**Interfaces:**
- Produces:
  - `Cursor :: struct { line, col: int }`
  - `Buffer :: struct { lines: [dynamic][dynamic]u8, cursor: Cursor, anchor: Cursor, sel: bool, undo: [dynamic]Snapshot, redo: [dynamic]Snapshot }` (the `anchor`/`sel`/`undo`/`redo` fields are declared here but only used in Task 2)
  - `Snapshot :: struct { text: string, cursor: Cursor }` (used in Task 2)
  - `make_buffer :: proc(s: string) -> Buffer`
  - `destroy_buffer :: proc(b: ^Buffer)`
  - `to_string :: proc(b: ^Buffer, allocator := context.allocator) -> string`
  - `insert_text :: proc(b: ^Buffer, s: string)`
  - `insert_rune :: proc(b: ^Buffer, r: rune)`
  - `backspace :: proc(b: ^Buffer)`
  - `delete_forward :: proc(b: ^Buffer)`
  - `Move :: enum { Left, Right, Up, Down, Home, End }`
  - `move :: proc(b: ^Buffer, dir: Move, select := false)` (the `select` param is honored in Task 2; in Task 1 it may be ignored)
  - `set_cursor :: proc(b: ^Buffer, line, col: int, select := false)`

- [ ] **Step 1: Write the failing tests**

Create `editor/buffer_test.odin`:

```odin
package editor

import "core:testing"

@(test) test_roundtrip :: proc(t: ^testing.T) {
	b := make_buffer("hello\nworld")
	defer destroy_buffer(&b)
	s := to_string(&b)
	defer delete(s)
	testing.expect_value(t, s, "hello\nworld")
	testing.expect_value(t, len(b.lines), 2)
}

@(test) test_empty_buffer_has_one_line :: proc(t: ^testing.T) {
	b := make_buffer("")
	defer destroy_buffer(&b)
	testing.expect_value(t, len(b.lines), 1)
	s := to_string(&b); defer delete(s)
	testing.expect_value(t, s, "")
}

@(test) test_insert_text :: proc(t: ^testing.T) {
	b := make_buffer("ac")
	defer destroy_buffer(&b)
	set_cursor(&b, 0, 1)
	insert_text(&b, "b")
	s := to_string(&b); defer delete(s)
	testing.expect_value(t, s, "abc")
	testing.expect_value(t, b.cursor.col, 2)
}

@(test) test_insert_newline_splits_line :: proc(t: ^testing.T) {
	b := make_buffer("abcd")
	defer destroy_buffer(&b)
	set_cursor(&b, 0, 2)
	insert_text(&b, "\n")
	s := to_string(&b); defer delete(s)
	testing.expect_value(t, s, "ab\ncd")
	testing.expect_value(t, b.cursor.line, 1)
	testing.expect_value(t, b.cursor.col, 0)
}

@(test) test_backspace_within_line :: proc(t: ^testing.T) {
	b := make_buffer("abc")
	defer destroy_buffer(&b)
	set_cursor(&b, 0, 2)
	backspace(&b)
	s := to_string(&b); defer delete(s)
	testing.expect_value(t, s, "ac")
	testing.expect_value(t, b.cursor.col, 1)
}

@(test) test_backspace_merges_lines :: proc(t: ^testing.T) {
	b := make_buffer("ab\ncd")
	defer destroy_buffer(&b)
	set_cursor(&b, 1, 0)
	backspace(&b)
	s := to_string(&b); defer delete(s)
	testing.expect_value(t, s, "abcd")
	testing.expect_value(t, b.cursor.line, 0)
	testing.expect_value(t, b.cursor.col, 2)
}

@(test) test_delete_forward_merges_lines :: proc(t: ^testing.T) {
	b := make_buffer("ab\ncd")
	defer destroy_buffer(&b)
	set_cursor(&b, 0, 2)
	delete_forward(&b)
	s := to_string(&b); defer delete(s)
	testing.expect_value(t, s, "abcd")
}

@(test) test_cursor_movement_clamps :: proc(t: ^testing.T) {
	b := make_buffer("ab\ncde")
	defer destroy_buffer(&b)
	set_cursor(&b, 0, 2)  // end of "ab"
	move(&b, .Right)       // -> start of next line
	testing.expect_value(t, b.cursor.line, 1)
	testing.expect_value(t, b.cursor.col, 0)
	move(&b, .End)         // -> end of "cde"
	testing.expect_value(t, b.cursor.col, 3)
	move(&b, .Down)        // already last line: clamp, col stays <= line len
	testing.expect_value(t, b.cursor.line, 1)
	move(&b, .Up)          // -> line 0, col clamped to len("ab")=2
	testing.expect_value(t, b.cursor.line, 0)
	testing.expect_value(t, b.cursor.col, 2)
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `odin test editor`
Expected: FAIL — `make_buffer` etc. undefined.

- [ ] **Step 3: Implement `buffer.odin`**

Create `editor/buffer.odin`:

```odin
package editor

import "core:strings"

Cursor :: struct { line, col: int }

Snapshot :: struct {
	text:   string,
	cursor: Cursor,
}

Buffer :: struct {
	lines:  [dynamic][dynamic]u8,
	cursor: Cursor,
	anchor: Cursor,            // selection anchor (Task 2)
	sel:    bool,              // selection active (Task 2)
	undo:   [dynamic]Snapshot, // (Task 2)
	redo:   [dynamic]Snapshot, // (Task 2)
}

@(private) make_line :: proc(bytes: []u8) -> [dynamic]u8 {
	l := make([dynamic]u8)
	append(&l, ..bytes)
	return l
}

make_buffer :: proc(s: string) -> Buffer {
	b: Buffer
	b.lines = make([dynamic][dynamic]u8)
	start := 0
	for i in 0..=len(s) {
		if i == len(s) || s[i] == '\n' {
			append(&b.lines, make_line(transmute([]u8)s[start:i]))
			start = i + 1
		}
	}
	if len(b.lines) == 0 {
		append(&b.lines, make([dynamic]u8))
	}
	return b
}

destroy_buffer :: proc(b: ^Buffer) {
	for &line in b.lines { delete(line) }
	delete(b.lines)
	for snap in b.undo { delete(snap.text) }
	for snap in b.redo { delete(snap.text) }
	delete(b.undo)
	delete(b.redo)
}

to_string :: proc(b: ^Buffer, allocator := context.allocator) -> string {
	sb: strings.Builder
	strings.builder_init(&sb, allocator)
	for line, i in b.lines {
		if i > 0 { strings.write_byte(&sb, '\n') }
		strings.write_bytes(&sb, line[:])
	}
	return strings.to_string(sb)
}

@(private) clampi :: proc(v, lo, hi: int) -> int {
	if v < lo { return lo }
	if v > hi { return hi }
	return v
}

set_cursor :: proc(b: ^Buffer, line, col: int, select := false) {
	if !select { b.sel = false }
	else if !b.sel { b.sel = true; b.anchor = b.cursor }
	b.cursor.line = clampi(line, 0, len(b.lines)-1)
	b.cursor.col  = clampi(col, 0, len(b.lines[b.cursor.line]))
}

// --- editing (Task 2 will prepend selection-deletion) ---

@(private) insert_byte_raw :: proc(b: ^Buffer, c: u8) {
	if c == '\n' {
		line := &b.lines[b.cursor.line]
		tail := make_line(line[b.cursor.col:])
		resize(line, b.cursor.col)
		inject_at(&b.lines, b.cursor.line+1, tail)
		b.cursor.line += 1
		b.cursor.col = 0
	} else {
		inject_at(&b.lines[b.cursor.line], b.cursor.col, c)
		b.cursor.col += 1
	}
}

insert_text :: proc(b: ^Buffer, s: string) {
	if b.sel { delete_selection(b) }
	for i in 0..<len(s) {
		insert_byte_raw(b, s[i])
	}
}

insert_rune :: proc(b: ^Buffer, r: rune) {
	buf: [4]u8
	n := 0
	if r < 0x80 {
		buf[0] = u8(r); n = 1
	} else {
		// UTF-8 encode (stored as bytes; cursor is byte-based in v1)
		enc, sz := utf8_encode(r)
		buf = enc; n = sz
	}
	if b.sel { delete_selection(b) }
	for i in 0..<n { insert_byte_raw(b, buf[i]) }
}

@(private) utf8_encode :: proc(r: rune) -> ([4]u8, int) {
	buf: [4]u8
	c := u32(r)
	switch {
	case c < 0x80:
		buf[0] = u8(c); return buf, 1
	case c < 0x800:
		buf[0] = u8(0xC0 | (c >> 6)); buf[1] = u8(0x80 | (c & 0x3F)); return buf, 2
	case c < 0x10000:
		buf[0] = u8(0xE0 | (c >> 12)); buf[1] = u8(0x80 | ((c >> 6) & 0x3F)); buf[2] = u8(0x80 | (c & 0x3F)); return buf, 3
	case:
		buf[0] = u8(0xF0 | (c >> 18)); buf[1] = u8(0x80 | ((c >> 12) & 0x3F)); buf[2] = u8(0x80 | ((c >> 6) & 0x3F)); buf[3] = u8(0x80 | (c & 0x3F)); return buf, 4
	}
}

backspace :: proc(b: ^Buffer) {
	if b.sel { delete_selection(b); return }
	if b.cursor.col > 0 {
		ordered_remove(&b.lines[b.cursor.line], b.cursor.col-1)
		b.cursor.col -= 1
	} else if b.cursor.line > 0 {
		prev := &b.lines[b.cursor.line-1]
		plen := len(prev)
		append(prev, ..b.lines[b.cursor.line][:])
		delete(b.lines[b.cursor.line])
		ordered_remove(&b.lines, b.cursor.line)
		b.cursor.line -= 1
		b.cursor.col = plen
	}
}

delete_forward :: proc(b: ^Buffer) {
	if b.sel { delete_selection(b); return }
	line := &b.lines[b.cursor.line]
	if b.cursor.col < len(line) {
		ordered_remove(line, b.cursor.col)
	} else if b.cursor.line < len(b.lines)-1 {
		next := b.lines[b.cursor.line+1]
		append(line, ..next[:])
		delete(next)
		ordered_remove(&b.lines, b.cursor.line+1)
	}
}

Move :: enum { Left, Right, Up, Down, Home, End }

move :: proc(b: ^Buffer, dir: Move, select := false) {
	if !select { b.sel = false }
	else if !b.sel { b.sel = true; b.anchor = b.cursor }

	switch dir {
	case .Left:
		if b.cursor.col > 0 { b.cursor.col -= 1 }
		else if b.cursor.line > 0 { b.cursor.line -= 1; b.cursor.col = len(b.lines[b.cursor.line]) }
	case .Right:
		if b.cursor.col < len(b.lines[b.cursor.line]) { b.cursor.col += 1 }
		else if b.cursor.line < len(b.lines)-1 { b.cursor.line += 1; b.cursor.col = 0 }
	case .Up:
		if b.cursor.line > 0 { b.cursor.line -= 1; b.cursor.col = clampi(b.cursor.col, 0, len(b.lines[b.cursor.line])) }
	case .Down:
		if b.cursor.line < len(b.lines)-1 { b.cursor.line += 1; b.cursor.col = clampi(b.cursor.col, 0, len(b.lines[b.cursor.line])) }
	case .Home:
		b.cursor.col = 0
	case .End:
		b.cursor.col = len(b.lines[b.cursor.line])
	}
}

// Stub replaced in Task 2 (needed now so editing procs compile).
delete_selection :: proc(b: ^Buffer) {
	b.sel = false
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `odin test editor`
Expected: all 8 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add editor/buffer.odin editor/buffer_test.odin
git commit -m "feat: editor buffer core (insert/delete/cursor) with tests"
```

---

### Task 2: Selection, clipboard text, and undo/redo (TDD)

Complete the model: selection range/extraction/deletion and snapshot-based undo/redo.

**Files:**
- Modify: `editor/buffer.odin` (replace the `delete_selection` stub; add selection + undo procs)
- Modify: `editor/buffer_test.odin` (add tests)

**Interfaces:**
- Produces:
  - `has_selection :: proc(b: ^Buffer) -> bool`
  - `selection_range :: proc(b: ^Buffer) -> (start, end: Cursor)` (normalized so start ≤ end)
  - `selected_text :: proc(b: ^Buffer, allocator := context.allocator) -> string`
  - `delete_selection :: proc(b: ^Buffer)` (real implementation)
  - `push_undo :: proc(b: ^Buffer)` (snapshot current text+cursor; clears redo)
  - `undo :: proc(b: ^Buffer)`, `redo :: proc(b: ^Buffer)`

- [ ] **Step 1: Add the failing tests**

Append to `editor/buffer_test.odin`:

```odin
@(test) test_selection_range_normalized :: proc(t: ^testing.T) {
	b := make_buffer("abcdef")
	defer destroy_buffer(&b)
	set_cursor(&b, 0, 4)
	move(&b, .Left, true) // select leftward: cursor=3, anchor=4
	move(&b, .Left, true) // cursor=2, anchor=4
	start, end := selection_range(&b)
	testing.expect_value(t, start.col, 2)
	testing.expect_value(t, end.col, 4)
}

@(test) test_selected_text :: proc(t: ^testing.T) {
	b := make_buffer("hello\nworld")
	defer destroy_buffer(&b)
	set_cursor(&b, 0, 2)
	set_cursor(&b, 1, 3, true) // anchor (0,2) .. cursor (1,3)
	s := selected_text(&b); defer delete(s)
	testing.expect_value(t, s, "llo\nwor")
}

@(test) test_delete_selection :: proc(t: ^testing.T) {
	b := make_buffer("hello\nworld")
	defer destroy_buffer(&b)
	set_cursor(&b, 0, 2)
	set_cursor(&b, 1, 3, true)
	delete_selection(&b)
	s := to_string(&b); defer delete(s)
	testing.expect_value(t, s, "held")
	testing.expect_value(t, b.cursor.line, 0)
	testing.expect_value(t, b.cursor.col, 2)
	testing.expect(t, !b.sel)
}

@(test) test_insert_replaces_selection :: proc(t: ^testing.T) {
	b := make_buffer("abcd")
	defer destroy_buffer(&b)
	set_cursor(&b, 0, 1)
	set_cursor(&b, 0, 3, true) // select "bc"
	insert_text(&b, "X")
	s := to_string(&b); defer delete(s)
	testing.expect_value(t, s, "aXd")
}

@(test) test_undo_redo :: proc(t: ^testing.T) {
	b := make_buffer("a")
	defer destroy_buffer(&b)
	set_cursor(&b, 0, 1)
	push_undo(&b)
	insert_text(&b, "bc")
	s1 := to_string(&b); defer delete(s1)
	testing.expect_value(t, s1, "abc")
	undo(&b)
	s2 := to_string(&b); defer delete(s2)
	testing.expect_value(t, s2, "a")
	redo(&b)
	s3 := to_string(&b); defer delete(s3)
	testing.expect_value(t, s3, "abc")
}
```

- [ ] **Step 2: Run to verify the new tests fail**

Run: `odin test editor`
Expected: FAIL — `has_selection`/`selection_range`/`selected_text`/`push_undo`/`undo`/`redo` undefined (and the `delete_selection` stub produces wrong results for the selection tests).

- [ ] **Step 3: Replace the stub and add the selection/undo implementation**

In `editor/buffer.odin`, delete the stub:

```odin
// Stub replaced in Task 2 (needed now so editing procs compile).
delete_selection :: proc(b: ^Buffer) {
	b.sel = false
}
```

and append the real implementations:

```odin
cursor_less :: proc(a, b: Cursor) -> bool {
	if a.line != b.line { return a.line < b.line }
	return a.col < b.col
}

has_selection :: proc(b: ^Buffer) -> bool {
	return b.sel && b.anchor != b.cursor
}

selection_range :: proc(b: ^Buffer) -> (start, end: Cursor) {
	if cursor_less(b.cursor, b.anchor) { return b.cursor, b.anchor }
	return b.anchor, b.cursor
}

selected_text :: proc(b: ^Buffer, allocator := context.allocator) -> string {
	if !has_selection(b) { return strings.clone("", allocator) }
	start, end := selection_range(b)
	sb: strings.Builder
	strings.builder_init(&sb, allocator)
	for ln in start.line..=end.line {
		lo := 0 if ln > start.line else start.col
		hi := len(b.lines[ln]) if ln < end.line else end.col
		if ln > start.line { strings.write_byte(&sb, '\n') }
		strings.write_bytes(&sb, b.lines[ln][lo:hi])
	}
	return strings.to_string(sb)
}

delete_selection :: proc(b: ^Buffer) {
	if !has_selection(b) { b.sel = false; return }
	start, end := selection_range(b)
	if start.line == end.line {
		remove_range(&b.lines[start.line], start.col, end.col)
	} else {
		// keep head of start line + tail of end line; drop the lines between
		resize(&b.lines[start.line], start.col)
		append(&b.lines[start.line], ..b.lines[end.line][end.col:])
		for ln := end.line; ln > start.line; ln -= 1 {
			delete(b.lines[ln])
			ordered_remove(&b.lines, ln)
		}
	}
	b.cursor = start
	b.sel = false
}

push_undo :: proc(b: ^Buffer) {
	snap := Snapshot{ text = to_string(b), cursor = b.cursor }
	append(&b.undo, snap)
	for s in b.redo { delete(s.text) }
	clear(&b.redo)
}

@(private) restore :: proc(b: ^Buffer, snap: Snapshot) {
	for &line in b.lines { delete(line) }
	clear(&b.lines)
	tmp := make_buffer(snap.text)
	// move tmp's lines into b
	for line in tmp.lines { append(&b.lines, line) }
	delete(tmp.lines)
	b.cursor = snap.cursor
	b.sel = false
	b.cursor.line = clampi(b.cursor.line, 0, len(b.lines)-1)
	b.cursor.col  = clampi(b.cursor.col, 0, len(b.lines[b.cursor.line]))
}

undo :: proc(b: ^Buffer) {
	if len(b.undo) == 0 { return }
	cur := Snapshot{ text = to_string(b), cursor = b.cursor }
	append(&b.redo, cur)
	snap := pop(&b.undo)
	restore(b, snap)
	delete(snap.text)
}

redo :: proc(b: ^Buffer) {
	if len(b.redo) == 0 { return }
	cur := Snapshot{ text = to_string(b), cursor = b.cursor }
	append(&b.undo, cur)
	snap := pop(&b.redo)
	restore(b, snap)
	delete(snap.text)
}
```

- [ ] **Step 4: Run to verify all pass**

Run: `odin test editor`
Expected: all tests (Task 1 + Task 2) PASS, output pristine (no leak warnings — every test `defer destroy_buffer` and frees its `to_string`/`selected_text` results).

- [ ] **Step 5: Commit**

```bash
git add editor/buffer.odin editor/buffer_test.odin
git commit -m "feat: editor selection, clipboard text, and undo/redo with tests"
```

---

### Task 3: Editor view + IDE integration

Render the buffer and wire keyboard/mouse into it, then integrate: load the sketch on startup, lay out toolbar / editor / console, save on Ctrl+S, and make **Run** save the buffer before building. Verified visually.

**Files:**
- Create: `odessa/editor_view.odin`
- Modify: `odessa/main.odin`

**Interfaces:**
- Produces (in `package main`):
  - `editor_input :: proc(b: ^editor.Buffer)` — apply one frame of keyboard/mouse edits (called in the update phase).
  - `editor_draw :: proc(b: ^editor.Buffer, area: rl.Rectangle, scroll: ^int)` — draw gutter + text + cursor + selection, adjusting `scroll` to keep the cursor visible.
- Consumes: the whole `editor` API from Tasks 1–2; `runner` from Plan B.

- [ ] **Step 1: Write the editor view**

Create `odessa/editor_view.odin`. Note the raylib input procs used (`GetCharPressed`, `IsKeyPressed`, `IsKeyPressedRepeat`, `GetClipboardText`, `SetClipboardText`, `IsKeyDown`, `CheckCollisionPointRec`, `IsMouseButtonPressed/Down`) — if `IsKeyPressedRepeat` is absent in the installed bindings, define `key_go` to fall back to `IsKeyPressed` only.

```odin
package main

import rl "vendor:raylib"
import "core:strings"
import "../editor"

ED_FONT   :: 18
ED_LINE_H :: 22
GUTTER_W  :: 52

// key "goes" this frame: initial press or auto-repeat.
key_go :: proc(k: rl.KeyboardKey) -> bool {
	return rl.IsKeyPressed(k) || rl.IsKeyPressedRepeat(k)
}

editor_input :: proc(b: ^editor.Buffer) {
	shift := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
	ctrl  := rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL)

	if ctrl {
		if rl.IsKeyPressed(.C) {
			s := editor.selected_text(b, context.temp_allocator)
			rl.SetClipboardText(strings.clone_to_cstring(s, context.temp_allocator))
			return
		}
		if rl.IsKeyPressed(.X) {
			s := editor.selected_text(b, context.temp_allocator)
			rl.SetClipboardText(strings.clone_to_cstring(s, context.temp_allocator))
			editor.push_undo(b); editor.delete_selection(b)
			return
		}
		if rl.IsKeyPressed(.V) {
			editor.push_undo(b)
			editor.insert_text(b, string(rl.GetClipboardText()))
			return
		}
		if rl.IsKeyPressed(.Z) { editor.undo(b); return }
		if rl.IsKeyPressed(.Y) { editor.redo(b); return }
		// Ctrl+S / Ctrl+R handled by main.
		return
	}

	// typed characters (GetCharPressed auto-repeats)
	for r := rl.GetCharPressed(); r != 0; r = rl.GetCharPressed() {
		if r >= 32 {
			editor.push_undo(b)
			editor.insert_rune(b, r)
		}
	}

	if key_go(.ENTER)     { editor.push_undo(b); editor.insert_rune(b, '\n') }
	if key_go(.BACKSPACE) { editor.push_undo(b); editor.backspace(b) }
	if key_go(.DELETE)    { editor.push_undo(b); editor.delete_forward(b) }
	if key_go(.LEFT)      { editor.move(b, .Left,  shift) }
	if key_go(.RIGHT)     { editor.move(b, .Right, shift) }
	if key_go(.UP)        { editor.move(b, .Up,    shift) }
	if key_go(.DOWN)      { editor.move(b, .Down,  shift) }
	if key_go(.HOME)      { editor.move(b, .Home,  shift) }
	if key_go(.END)       { editor.move(b, .End,   shift) }
}

@(private="file") char_w :: proc() -> f32 {
	return f32(rl.MeasureText("m", ED_FONT))
}

// Set the cursor from a mouse click inside the editor area.
editor_mouse :: proc(b: ^editor.Buffer, area: rl.Rectangle, scroll: int) {
	if !rl.IsMouseButtonPressed(.LEFT) { return }
	m := rl.GetMousePosition()
	if !rl.CheckCollisionPointRec(m, area) { return }
	line := scroll + int((m.y - area.y) / ED_LINE_H)
	col  := int((m.x - area.x - GUTTER_W) / char_w() + 0.5)
	editor.set_cursor(b, line, col) // set_cursor clamps
}

editor_draw :: proc(b: ^editor.Buffer, area: rl.Rectangle, scroll: ^int) {
	cw := char_w()
	visible := int(area.height) / ED_LINE_H

	// keep cursor visible
	if b.cursor.line < scroll^            { scroll^ = b.cursor.line }
	if b.cursor.line >= scroll^ + visible { scroll^ = b.cursor.line - visible + 1 }
	if scroll^ < 0 { scroll^ = 0 }

	rl.DrawRectangleRec(area, rl.Color{18, 18, 22, 255})

	// selection highlight
	if editor.has_selection(b) {
		start, end := editor.selection_range(b)
		for ln in start.line..=end.line {
			row := ln - scroll^
			if row < 0 || row >= visible { continue }
			lo := 0 if ln > start.line else start.col
			hi := len(b.lines[ln]) if ln < end.line else end.col
			x := area.x + GUTTER_W + f32(lo)*cw
			y := area.y + f32(row)*ED_LINE_H
			w := f32(hi-lo)*cw
			if ln < end.line { w += cw } // show the trailing newline as a sliver
			rl.DrawRectangleRec(rl.Rectangle{x, y, w, ED_LINE_H}, rl.Color{50, 70, 120, 255})
		}
	}

	// lines + gutter
	for row in 0..<visible {
		ln := scroll^ + row
		if ln >= len(b.lines) { break }
		y := i32(area.y) + i32(row*ED_LINE_H)
		num := rl.TextFormat("%d", ln+1)
		rl.DrawText(num, i32(area.x)+6, y, ED_FONT, rl.Color{90, 90, 110, 255})
		ctext := strings.clone_to_cstring(string(b.lines[ln][:]), context.temp_allocator)
		rl.DrawText(ctext, i32(area.x)+GUTTER_W, y, ED_FONT, rl.Color{220, 220, 225, 255})
	}

	// cursor
	crow := b.cursor.line - scroll^
	if crow >= 0 && crow < visible {
		cx := area.x + GUTTER_W + f32(b.cursor.col)*cw
		cy := area.y + f32(crow)*ED_LINE_H
		rl.DrawRectangleRec(rl.Rectangle{cx, cy, 2, ED_LINE_H}, rl.Color{240, 240, 120, 255})
	}
}
```

- [ ] **Step 2: Integrate into `main.odin`**

Modify `odessa/main.odin`:

1. Add imports and constants:

```odin
import "../editor"
```

and a sketch-file constant near the others:

```odin
SKETCH_FILE :: "sketches/hello/hello.odin"
```

2. Add editor state to `App`:

```odin
App :: struct {
	run:            runner.Runner,
	status:         Status,
	console:        string,
	console_lines:  []string,
	console_scroll: int,
	buf:            editor.Buffer,
	ed_scroll:      int,
}
```

3. Add load/save helpers:

```odin
load_sketch :: proc(app: ^App) {
	data, err := os.read_entire_file_from_path(SKETCH_FILE, context.allocator)
	if err != nil {
		app.buf = editor.make_buffer("")
		return
	}
	defer delete(data)
	app.buf = editor.make_buffer(string(data))
}

save_sketch :: proc(app: ^App) {
	s := editor.to_string(&app.buf, context.temp_allocator)
	os.write_entire_file(SKETCH_FILE, transmute([]u8)s)
}
```

(If `os.write_entire_file` / `os.read_entire_file_from_path` differ in this toolchain, compile-check and use the installed spelling — the intent is "read the file into a string" and "write a string to the file".)

4. In `do_run`, save the buffer before building — add at the very top of `do_run`:

```odin
	save_sketch(app)
```

5. Rework layout: the editor sits between the toolbar and the console. Replace `draw_ui` with a split, and give the console a fixed bottom strip. Change `CONSOLE_TOP` usage: define an editor area and a console area from the window height.

Replace `draw_ui` with:

```odin
CONSOLE_H :: 150

draw_ui :: proc(app: ^App) {
	rl.ClearBackground(rl.Color{24, 24, 28, 255})
	sh := rl.GetScreenHeight()

	// editor area (below toolbar, above console)
	ed_area := rl.Rectangle{0, 48, f32(rl.GetScreenWidth()), f32(int(sh) - 48 - CONSOLE_H)}
	editor_draw(&app.buf, ed_area, &app.ed_scroll)

	// console area (bottom strip)
	draw_console_strip(app, int(sh) - CONSOLE_H)

	// toolbar on top
	rl.DrawRectangle(0, 0, rl.GetScreenWidth(), 48, rl.Color{32, 32, 38, 255})
	draw_button(RUN_RECT, "Run", app.status != .Running && app.status != .Compiling)
	draw_button(STOP_RECT, "Stop", app.status == .Running)
	rl.DrawText(status_text(app.status), 210, 16, 20, rl.Color{200, 200, 210, 255})
}
```

Rename the existing `draw_console` to `draw_console_strip` and make it draw from a given top `y` (a fixed-height bottom strip) instead of `CONSOLE_TOP`:

```odin
draw_console_strip :: proc(app: ^App, top_y: int) {
	top := i32(top_y)
	bottom := rl.GetScreenHeight()
	rl.DrawRectangle(0, top, rl.GetScreenWidth(), bottom-top, rl.Color{16, 16, 20, 255})
	if len(app.console_lines) == 0 { return }
	col := rl.Color{200, 200, 205, 255}
	if app.status == .Compile_Error { col = rl.Color{255, 180, 180, 255} }
	max_visible := int((bottom - top) / LINE_H)
	y := top
	for i := app.console_scroll; i < len(app.console_lines) && (i - app.console_scroll) < max_visible; i += 1 {
		ctext := strings.clone_to_cstring(app.console_lines[i], context.temp_allocator)
		rl.DrawText(ctext, 8, y, FONT_SIZE, col)
		y += LINE_H
	}
}
```

Update the console-scroll clamp in the main loop to use the strip height: replace `console_visible_lines` body to `CONSOLE_H`-based:

```odin
console_visible_lines :: proc() -> int {
	return CONSOLE_H / LINE_H
}
```

6. In `main`, initialize/destroy the buffer and route input. After `app.status = .Idle` add:

```odin
	load_sketch(&app)
	defer editor.destroy_buffer(&app.buf)
```

In the update phase (before the button handling, so typing doesn't require focus juggling), add editor input and mouse — but only feed typing to the editor when Ctrl is not driving a toolbar action. Insert after the `runner.poll` block:

```odin
		editor_input(&app.buf)
		ed_area := rl.Rectangle{0, 48, f32(rl.GetScreenWidth()), f32(int(rl.GetScreenHeight()) - 48 - CONSOLE_H)}
		editor_mouse(&app.buf, ed_area, app.ed_scroll)
```

7. Add Ctrl+S save handling next to the Ctrl+R run handling:

```odin
		if ctrl && rl.IsKeyPressed(.S) { save_sketch(&app) }
```

(`ctrl` is already computed in the loop for Ctrl+R.)

- [ ] **Step 3: Build and verify (visual)**

Build: `odin build odessa -out:build/odessa.exe -debug` — expect exit 0. Also run `odin test editor && odin test canvas && odin test runner` — all green.

Launch the IDE NON-BLOCKING (terminate by PID after; never leave orphans). Verify:
- The window shows the **toolbar**, the **`hello.odin` source in the editor** (with line numbers and a cursor), and the **console strip** at the bottom.
- Because synthetic keyboard input to a raylib window is unreliable from scripts, verify TEXT EDITING by whatever means available; at minimum confirm the sketch source is loaded and rendered with line numbers and a cursor (capture the window). If you can inject input, type a character and confirm it appears; otherwise note editing was not script-verified (a real keypress exercises `editor_input`, which is covered by the Task 1–2 unit tests at the model level).
- Confirm **Run still works**: launching with `--run` should save the buffer and build+launch the sketch (the sketch window opens). Capture it.
- Close the IDE; confirm no orphan `hello.exe`/`odessa.exe`.

Report exactly what was observed and what (if anything) could not be script-verified.

- [ ] **Step 4: Commit**

```bash
git add odessa/editor_view.odin odessa/main.odin
git commit -m "feat: built-in code editor - view, input, and IDE integration"
```

---

## Self-Review

**Spec coverage (Plan C scope, spec §6):**
- Text buffer, insert/delete → Task 1. ✔
- Cursor arrows/home/end + mouse click → Tasks 1 (model) + 3 (mouse). ✔
- Selection (shift+arrows, click-drag path via set_cursor+select), clipboard copy/cut/paste → Tasks 2 + 3. ✔
- Undo/redo → Task 2. ✔
- Vertical scroll keeping cursor visible → Task 3 (`editor_draw` scroll adjust). ✔
- Line numbers → Task 3 gutter. ✔
- Save (Ctrl+S) + load on open + Run-saves-buffer → Task 3. ✔
- Deferred (documented): syntax highlighting, tabs, find/replace, multi-byte cursor nav. ✔

**Placeholder scan:** No TBD/TODO; complete code in every step; verification steps give exact commands + expected results and honestly bound what can/can't be script-verified. ✔

**Type consistency:** `editor.Buffer`/`Cursor`/`Move`/`make_buffer`/`to_string`/`insert_text`/`insert_rune`/`backspace`/`delete_forward`/`move`/`set_cursor` (Task 1) and `has_selection`/`selection_range`/`selected_text`/`delete_selection`/`push_undo`/`undo`/`redo` (Task 2) are used with matching names/signatures in Task 3. `App` gains `buf`/`ed_scroll` in Task 3; `draw_console`→`draw_console_strip` rename is applied consistently. ✔

**Known risks flagged for the implementer:** (1) `IsKeyPressedRepeat` may be absent — fall back to `IsKeyPressed`. (2) `os.read_entire_file_from_path` / `os.write_entire_file` spellings — compile-check against the installed `core:os`. (3) synthetic keyboard input can't be driven from scripts here — editing behavior is covered by the buffer unit tests; the view wiring is thin. (4) The default raylib font is treated as monospace; a proper monospace TTF is a fast-follow. Work strictly inside the Odessa project directory.
