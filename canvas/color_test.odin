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
