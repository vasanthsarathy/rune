package editor

// Minimal single-line Odin lexer for editor syntax highlighting.
// Emits only "interesting" spans (keyword/number/string/char/comment); plain
// identifiers and punctuation are left untagged and drawn in the base color.
// Block comments (/* */) are not handled in v1 (line comments cover most code).

Token_Kind :: enum { Keyword, Number, String, Char, Comment }

Token :: struct {
	start, end: int,
	kind:       Token_Kind,
}

@(rodata) KEYWORDS := [?]string{
	"package", "import", "proc", "struct", "enum", "union", "bit_set", "map",
	"distinct", "using", "defer", "if", "else", "for", "switch", "case", "when",
	"return", "break", "continue", "fallthrough", "in", "not_in", "do",
	"cast", "transmute", "auto_cast", "or_else", "or_return", "or_break", "or_continue",
	"nil", "true", "false", "context",
}

@(private) is_ident_start :: proc(c: u8) -> bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}
@(private) is_ident :: proc(c: u8) -> bool {
	return is_ident_start(c) || (c >= '0' && c <= '9')
}
@(private) is_digit :: proc(c: u8) -> bool {
	return c >= '0' && c <= '9'
}
@(private) is_keyword :: proc(word: string) -> bool {
	for k in KEYWORDS {
		if k == word { return true }
	}
	return false
}

tokenize :: proc(line: []u8, allocator := context.allocator) -> [dynamic]Token {
	toks := make([dynamic]Token, allocator)
	i := 0
	n := len(line)
	for i < n {
		c := line[i]
		// line comment: // to end of line
		if c == '/' && i+1 < n && line[i+1] == '/' {
			append(&toks, Token{i, n, .Comment})
			break
		}
		// string literals: "..." and `...`
		if c == '"' || c == '`' {
			quote := c
			j := i + 1
			for j < n {
				if line[j] == '\\' && quote == '"' { j += 2; continue }
				if line[j] == quote { j += 1; break }
				j += 1
			}
			append(&toks, Token{i, min(j, n), .String})
			i = j
			continue
		}
		// char literal: '...'
		if c == '\'' {
			j := i + 1
			for j < n {
				if line[j] == '\\' { j += 2; continue }
				if line[j] == '\'' { j += 1; break }
				j += 1
			}
			append(&toks, Token{i, min(j, n), .Char})
			i = j
			continue
		}
		// number
		if is_digit(c) {
			j := i
			for j < n && (is_ident(line[j]) || line[j] == '.') { j += 1 }
			append(&toks, Token{i, j, .Number})
			i = j
			continue
		}
		// identifier / keyword
		if is_ident_start(c) {
			j := i
			for j < n && is_ident(line[j]) { j += 1 }
			word := string(line[i:j])
			if is_keyword(word) {
				append(&toks, Token{i, j, .Keyword})
			}
			i = j
			continue
		}
		i += 1
	}
	return toks
}
