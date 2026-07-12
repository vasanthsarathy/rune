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

// --- editing ---

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
	enc, n := utf8_encode(r)
	if b.sel { delete_selection(b) }
	for i in 0..<n { insert_byte_raw(b, enc[i]) }
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

// --- selection ---

@(private) cursor_less :: proc(a, b: Cursor) -> bool {
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

// --- undo / redo (snapshot-based) ---

push_undo :: proc(b: ^Buffer) {
	append(&b.undo, Snapshot{ text = to_string(b), cursor = b.cursor })
	for s in b.redo { delete(s.text) }
	clear(&b.redo)
}

@(private) restore :: proc(b: ^Buffer, snap: Snapshot) {
	for &line in b.lines { delete(line) }
	clear(&b.lines)
	tmp := make_buffer(snap.text)
	for line in tmp.lines { append(&b.lines, line) }
	delete(tmp.lines) // move lines into b; free only tmp's header array
	b.cursor.line = clampi(snap.cursor.line, 0, len(b.lines)-1)
	b.cursor.col  = clampi(snap.cursor.col, 0, len(b.lines[b.cursor.line]))
	b.sel = false
}

undo :: proc(b: ^Buffer) {
	if len(b.undo) == 0 { return }
	append(&b.redo, Snapshot{ text = to_string(b), cursor = b.cursor })
	snap := pop(&b.undo)
	restore(b, snap)
	delete(snap.text)
}

redo :: proc(b: ^Buffer) {
	if len(b.redo) == 0 { return }
	append(&b.undo, Snapshot{ text = to_string(b), cursor = b.cursor })
	snap := pop(&b.redo)
	restore(b, snap)
	delete(snap.text)
}
