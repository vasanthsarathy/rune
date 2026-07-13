package editor

import "core:testing"

@(test) test_tokenize_keyword :: proc(t: ^testing.T) {
	toks := tokenize(transmute([]u8)string("package main"))
	defer delete(toks)
	testing.expect_value(t, len(toks), 1)
	testing.expect_value(t, toks[0].kind, Token_Kind.Keyword)
	testing.expect_value(t, toks[0].start, 0)
	testing.expect_value(t, toks[0].end, 7)
}

@(test) test_tokenize_number :: proc(t: ^testing.T) {
	toks := tokenize(transmute([]u8)string("x := 42"))
	defer delete(toks)
	testing.expect_value(t, len(toks), 1)
	testing.expect_value(t, toks[0].kind, Token_Kind.Number)
	testing.expect_value(t, toks[0].start, 5)
	testing.expect_value(t, toks[0].end, 7)
}

@(test) test_tokenize_string :: proc(t: ^testing.T) {
	toks := tokenize(transmute([]u8)string(`s := "hi"`))
	defer delete(toks)
	testing.expect_value(t, len(toks), 1)
	testing.expect_value(t, toks[0].kind, Token_Kind.String)
	testing.expect_value(t, toks[0].start, 5)
	testing.expect_value(t, toks[0].end, 9) // includes both quotes
}

@(test) test_tokenize_comment :: proc(t: ^testing.T) {
	toks := tokenize(transmute([]u8)string("a := 1 // note"))
	defer delete(toks)
	// number 1, then comment to EOL
	testing.expect_value(t, len(toks), 2)
	testing.expect_value(t, toks[1].kind, Token_Kind.Comment)
	testing.expect_value(t, toks[1].start, 7)
	testing.expect_value(t, toks[1].end, 14)
}

@(test) test_tokenize_identifiers_untagged :: proc(t: ^testing.T) {
	toks := tokenize(transmute([]u8)string("c.circle(x, y, r)"))
	defer delete(toks)
	testing.expect_value(t, len(toks), 0) // no keywords/numbers/strings
}
