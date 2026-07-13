package main

import c "../../canvas"
import "core:math"

t: f32

setup :: proc() {
	c.size(1000,1000)
}

draw :: proc() {
	c.background(18, 18, 22)
	t += c.delta_time

	// a ring of circles that pulse
	cx := f32(c.width) * 0.5
	cy := f32(c.height) * 0.5
	c.no_stroke()
	for i in 0..<12 {
		a := f32(i) / 12 * c.TAU + t
		x := cx + math.cos(a) * 220
		y := cy + math.sin(a) * 220
		r := 30 + 18 * math.sin(t*2 + f32(i))
		c.fill(u8(120 + 100*math.sin(t+f32(i))), 90, 200)
		c.circle(x, y, r)
	}

	// a dot that follows the mouse
	c.fill(255, 240, 120)
	c.circle(c.mouse_x, c.mouse_y, 12)
}

main :: proc() {
	c.run(setup, draw)
}
