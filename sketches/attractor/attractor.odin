package main

import c "../../canvas"
import "core:math"

// Peter de Jong strange attractor (à la Paul Bourke). Each frame plots ~120k
// points into the persistent canvas; over a few seconds MILLIONS accumulate
// into a density plot — the kind of thing p5/Processing can't keep up with.
//
//   x' = sin(a*y) - cos(b*x)
//   y' = sin(c*x) - cos(d*y)

A :: 1.4
B :: -2.3
C :: 2.4
D :: -2.1

x, y: f32 = 0.1, 0.1

setup :: proc() {
	c.size(900, 900)
	c.background(6, 6, 10) // once; the canvas accumulates after this
}

draw :: proc() {
	c.stroke(150, 190, 255, 8) // low alpha so density builds up gradually
	cx := f32(c.width) * 0.5
	cy := f32(c.height) * 0.5
	s  := f32(c.width) * 0.22
	for i in 0..<120_000 {
		nx := math.sin(A*y) - math.cos(B*x)
		ny := math.sin(C*x) - math.cos(D*y)
		x, y = nx, ny
		c.point(cx + x*s, cy + y*s)
	}
}

main :: proc() {
	c.run(setup, draw)
}
