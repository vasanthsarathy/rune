package canvas

import "core:testing"

@(test) test_rgb_sets_full_alpha :: proc(t: ^testing.T) {
	col := rgb(10, 20, 30)
	testing.expect(t, col == Color{10, 20, 30, 255})
}

@(test) test_rgba_passthrough :: proc(t: ^testing.T) {
	col := rgba(1, 2, 3, 4)
	testing.expect(t, col == Color{1, 2, 3, 4})
}

@(test) test_gray :: proc(t: ^testing.T) {
	testing.expect(t, gray(128) == Color{128, 128, 128, 255})
}

@(test) test_named_colors :: proc(t: ^testing.T) {
	testing.expect(t, WHITE == Color{255, 255, 255, 255})
	testing.expect(t, BLACK == Color{0, 0, 0, 255})
}

@(test) test_hsl :: proc(t: ^testing.T) {
	testing.expect(t, hsl(0, 1, 0.5)   == Color{255, 0, 0, 255})
	testing.expect(t, hsl(120, 1, 0.5) == Color{0, 255, 0, 255})
	testing.expect(t, hsl(240, 1, 0.5) == Color{0, 0, 255, 255})
	testing.expect(t, hsl(0, 0, 1)     == WHITE)
	testing.expect(t, hsl(0, 0, 0)     == BLACK)
	testing.expect(t, hsl(360, 1, 0.5) == hsl(0, 1, 0.5)) // wraps
}

@(test) test_hsv :: proc(t: ^testing.T) {
	testing.expect(t, hsv(0, 1, 1) == Color{255, 0, 0, 255})
	testing.expect(t, hsv(0, 0, 1) == WHITE)
	testing.expect(t, hsv(0, 0, 0) == BLACK)
}

@(test) test_paper_px :: proc(t: ^testing.T) {
	w, h := paper_px(.A4, 300)
	testing.expect_value(t, w, 2480)
	testing.expect_value(t, h, 3508)
	w2, h2 := paper_px(.A4, 72)
	testing.expect_value(t, w2, 595)
	testing.expect_value(t, h2, 842)
}
