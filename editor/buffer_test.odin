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

@(test) test_selection_range_normalized :: proc(t: ^testing.T) {
	b := make_buffer("abcdef")
	defer destroy_buffer(&b)
	set_cursor(&b, 0, 4)
	move(&b, .Left, true) // cursor=3, anchor=4
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
