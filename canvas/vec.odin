package canvas

import "core:math"

// Vec2 is [2]f32 (defined in canvas.odin); Odin gives it +,-,*,/ and .x/.y.
// These helpers cover the PVector-style operations Processing sketches expect.

vlength :: proc(v: Vec2) -> f32 {
	return math.sqrt(v.x*v.x + v.y*v.y)
}

vnormalize :: proc(v: Vec2) -> Vec2 {
	l := vlength(v)
	return v if l == 0 else v / l
}

vdist :: proc(a, b: Vec2) -> f32 {
	return vlength(b - a)
}

vheading :: proc(v: Vec2) -> f32 {
	return math.atan2(v.y, v.x)
}

vfrom_angle :: proc(a: f32) -> Vec2 {
	return Vec2{math.cos(a), math.sin(a)}
}

vrotate :: proc(v: Vec2, a: f32) -> Vec2 {
	c := math.cos(a)
	s := math.sin(a)
	return Vec2{v.x*c - v.y*s, v.x*s + v.y*c}
}

vlerp :: proc(a, b: Vec2, t: f32) -> Vec2 {
	return a + (b - a) * t
}
