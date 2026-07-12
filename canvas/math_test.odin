package canvas

import "core:testing"
import "core:math"

@(test) test_map_range :: proc(t: ^testing.T) {
	testing.expect(t, map_range(5, 0, 10, 0, 100) == 50)
	testing.expect(t, map_range(0, 0, 10, 20, 40) == 20)
	testing.expect(t, map_range(10, 0, 10, 20, 40) == 40)
}

@(test) test_lerp :: proc(t: ^testing.T) {
	testing.expect(t, lerp(0, 10, 0.5) == 5)
	testing.expect(t, lerp(2, 4, 0) == 2)
	testing.expect(t, lerp(2, 4, 1) == 4)
}

@(test) test_clamp :: proc(t: ^testing.T) {
	testing.expect(t, clamp(5, 0, 10) == 5)
	testing.expect(t, clamp(-3, 0, 10) == 0)
	testing.expect(t, clamp(99, 0, 10) == 10)
}

@(test) test_dist :: proc(t: ^testing.T) {
	testing.expect(t, dist(0, 0, 3, 4) == 5)
}

@(test) test_angle_conversions :: proc(t: ^testing.T) {
	testing.expect(t, math.abs(radians(180) - PI) < 1e-5)
	testing.expect(t, math.abs(degrees(PI) - 180) < 1e-3)
}
