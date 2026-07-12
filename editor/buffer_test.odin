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
