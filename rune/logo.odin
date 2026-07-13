package main

import rl "vendor:raylib"

// The Rune mark: the Raidho rune (ᚱ, the "R" rune) as line segments in a
// normalized [-1,1] box. Shared by the toolbar mark and the window icon.
@(rodata) RUNE_SEGS := [?][4]f32{
	{-0.35, -0.85, -0.35,  0.85}, // stave
	{-0.35, -0.85,  0.40, -0.45}, // bowl top
	{ 0.40, -0.45, -0.35, -0.05}, // bowl bottom
	{-0.35, -0.05,  0.45,  0.85}, // leg
}

// Draw the rune centered at (cx, cy) scaled to radius r.
draw_logo :: proc(cx, cy, r, thick: f32, color: rl.Color) {
	for s in RUNE_SEGS {
		a := rl.Vector2{cx + s[0]*r, cy + s[1]*r}
		b := rl.Vector2{cx + s[2]*r, cy + s[3]*r}
		rl.DrawLineEx(a, b, thick, color)
	}
}

// Build the app/window icon procedurally from the same geometry.
set_window_icon :: proc() {
	N :: i32(64)
	img := rl.GenImageColor(N, N, BG_DEEP)
	defer rl.UnloadImage(img)
	cx, cy, r: f32 = 32, 32, 22
	for s in RUNE_SEGS {
		a := rl.Vector2{cx + s[0]*r, cy + s[1]*r}
		b := rl.Vector2{cx + s[2]*r, cy + s[3]*r}
		rl.ImageDrawLineEx(&img, a, b, 5, ACCENT)
	}
	rl.SetWindowIcon(img)
}
