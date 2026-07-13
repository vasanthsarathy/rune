package main

import rl "vendor:raylib"

// "Ink & Signal" — a deep indigo ground with one luminous azure accent pulled
// from the generative art Odessa makes. Azure sits outside the syntax palette
// (purple/green/orange) so UI chrome never competes with code.

BG_DEEP   :: rl.Color{13, 14, 20, 255}    // editor canvas
BG_PANEL  :: rl.Color{18, 20, 28, 255}    // sidebar / console
BG_RAISE  :: rl.Color{26, 29, 40, 255}    // toolbar / popups
BG_HOVER  :: rl.Color{35, 39, 54, 255}    // hover states
BG_SEL    :: rl.Color{34, 46, 68, 255}    // active row / text selection
LINE      :: rl.Color{38, 43, 58, 255}    // hairline dividers
FG_DIM    :: rl.Color{92, 100, 122, 255}  // gutter, secondary labels
FG        :: rl.Color{211, 216, 230, 255} // primary text
FG_BRIGHT :: rl.Color{238, 241, 248, 255} // emphasized text
ACCENT    :: rl.Color{92, 200, 255, 255}  // azure — the one signal color
ACCENT_DK :: rl.Color{22, 52, 72, 255}    // accent-tinted fill
DANGER    :: rl.Color{240, 110, 110, 255} // stop / errors

// syntax colors (kept cohesive with the theme)
SYN_KEYWORD :: rl.Color{198, 128, 226, 255}
SYN_NUMBER  :: rl.Color{221, 161, 106, 255}
SYN_STRING  :: rl.Color{140, 200, 150, 255}
SYN_COMMENT :: rl.Color{88, 96, 116, 255}

// A small uppercase, letter-spaced section label ("eyebrow").
draw_eyebrow :: proc(text: cstring, x, y: f32) {
	// manual letter spacing for a spaced-caps feel
	s := string(text)
	cx := x
	for i in 0..<len(s) {
		ch := rl.TextFormat("%c", rune(s[i]))
		draw_text(ch, cx, y, 12, FG_DIM)
		cx += measure(ch, 12) + 2
	}
}
