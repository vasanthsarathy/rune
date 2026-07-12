package canvas

import "core:math"

map_range :: proc(v, in_min, in_max, out_min, out_max: f32) -> f32 {
	return out_min + (v - in_min) * (out_max - out_min) / (in_max - in_min)
}

lerp :: proc(a, b, t: f32) -> f32 { return a + (b - a) * t }

clamp :: proc(v, lo, hi: f32) -> f32 {
	if v < lo { return lo }
	if v > hi { return hi }
	return v
}

dist :: proc(x1, y1, x2, y2: f32) -> f32 {
	dx := x2 - x1
	dy := y2 - y1
	return math.sqrt(dx*dx + dy*dy)
}

radians :: proc(deg: f32) -> f32 { return deg * PI / 180.0 }
degrees :: proc(rad: f32) -> f32 { return rad * 180.0 / PI }
