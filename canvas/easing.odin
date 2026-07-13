package canvas

import "core:math"

// Easing functions on t in [0,1]. All satisfy f(0)=0, f(1)=1.

ease_in_quad     :: proc(t: f32) -> f32 { return t*t }
ease_out_quad    :: proc(t: f32) -> f32 { return t*(2-t) }
ease_in_out_quad :: proc(t: f32) -> f32 {
	return 2*t*t if t < 0.5 else -1 + (4-2*t)*t
}

ease_in_cubic     :: proc(t: f32) -> f32 { return t*t*t }
ease_out_cubic    :: proc(t: f32) -> f32 { u := t-1; return u*u*u + 1 }
ease_in_out_cubic :: proc(t: f32) -> f32 {
	if t < 0.5 { return 4*t*t*t }
	u := 2*t - 2
	return 0.5*u*u*u + 1
}

ease_in_sine     :: proc(t: f32) -> f32 { return 1 - math.cos(t * math.PI / 2) }
ease_out_sine    :: proc(t: f32) -> f32 { return math.sin(t * math.PI / 2) }
ease_in_out_sine :: proc(t: f32) -> f32 { return -(math.cos(math.PI * t) - 1) / 2 }
