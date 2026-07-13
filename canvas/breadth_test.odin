package canvas

import "core:testing"
import "core:math"

@(test) test_vec_helpers :: proc(t: ^testing.T) {
	testing.expect(t, vlength(Vec2{3, 4}) == 5)
	testing.expect(t, vdist(Vec2{0, 0}, Vec2{3, 4}) == 5)
	testing.expect(t, math.abs(vlength(vnormalize(Vec2{3, 4})) - 1) < 1e-5)
	testing.expect(t, vnormalize(Vec2{0, 0}) == Vec2{0, 0}) // no divide-by-zero
	testing.expect(t, vlerp(Vec2{0, 0}, Vec2{10, 10}, 0.5) == Vec2{5, 5})

	a := vfrom_angle(0)
	testing.expect(t, math.abs(a.x - 1) < 1e-5 && math.abs(a.y) < 1e-5)
	r := vrotate(Vec2{1, 0}, PI/2)
	testing.expect(t, math.abs(r.x) < 1e-5 && math.abs(r.y - 1) < 1e-5)
}

// All noise assertions in one proc: noise() shares the package-global _perm,
// which noise_seed mutates — keeping them in a single test avoids a parallel
// test-runner race on that shared state.
@(test) test_noise :: proc(t: ^testing.T) {
	// determinism (default permutation)
	testing.expect(t, noise(1.5, 2.5, 0.5) == noise(1.5, 2.5, 0.5))

	// at integer lattice points improved Perlin is 0 -> remaps to exactly 0.5
	testing.expect(t, math.abs(noise(3, 0, 0) - 0.5) < 1e-5)

	// output stays within [0,1]
	for i in 0..<500 {
		v := noise(f32(i)*0.13, f32(i)*0.07, f32(i)*0.29)
		testing.expect(t, v >= 0 && v <= 1)
	}

	// reseeding is reproducible
	noise_seed(42)
	x := noise(1.3, 2.7)
	noise_seed(42)
	testing.expect(t, noise(1.3, 2.7) == x)
}

@(test) test_easing_endpoints :: proc(t: ^testing.T) {
	fns := []proc(f32) -> f32{
		ease_in_quad, ease_out_quad, ease_in_out_quad,
		ease_in_cubic, ease_out_cubic, ease_in_out_cubic,
		ease_in_sine, ease_out_sine, ease_in_out_sine,
	}
	for f in fns {
		testing.expect(t, math.abs(f(0) - 0) < 1e-5)
		testing.expect(t, math.abs(f(1) - 1) < 1e-5)
	}
}
