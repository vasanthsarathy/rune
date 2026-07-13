package canvas

import "core:math"

Color :: struct { r, g, b, a: u8 }

WHITE :: Color{255, 255, 255, 255}
BLACK :: Color{0, 0, 0, 255}

rgb  :: proc(r, g, b: u8) -> Color    { return Color{r, g, b, 255} }
rgba :: proc(r, g, b, a: u8) -> Color { return Color{r, g, b, a} }
gray :: proc(v: u8) -> Color          { return Color{v, v, v, 255} }

@(private) _to_u8 :: proc(v: f32) -> u8 { return u8(clamp(v*255 + 0.5, 0, 255)) }

@(private) _hue_rgb :: proc(hp, c, x, m: f32) -> (r, g, b: f32) {
	switch int(hp) % 6 {
	case 0: return c+m, x+m, 0+m
	case 1: return x+m, c+m, 0+m
	case 2: return 0+m, c+m, x+m
	case 3: return 0+m, x+m, c+m
	case 4: return x+m, 0+m, c+m
	case:   return c+m, 0+m, x+m
	}
}

// HSL color. h in [0,360), s & l in [0,1]. Great for print/plotter palettes.
hsl :: proc(h, s, l: f32) -> Color {
	hh := math.mod(h, 360); if hh < 0 { hh += 360 }
	c := (1 - abs(2*l - 1)) * s
	hp := hh / 60
	x := c * (1 - abs(math.mod(hp, 2) - 1))
	m := l - c/2
	r, g, b := _hue_rgb(hp, c, x, m)
	return Color{_to_u8(r), _to_u8(g), _to_u8(b), 255}
}

// HSV/HSB color. h in [0,360), s & v in [0,1].
hsv :: proc(h, s, v: f32) -> Color {
	hh := math.mod(h, 360); if hh < 0 { hh += 360 }
	c := v * s
	hp := hh / 60
	x := c * (1 - abs(math.mod(hp, 2) - 1))
	m := v - c
	r, g, b := _hue_rgb(hp, c, x, m)
	return Color{_to_u8(r), _to_u8(g), _to_u8(b), 255}
}
