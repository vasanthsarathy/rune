package canvas

import "core:testing"

@(test) test_rng_seeded_reproducible :: proc(t: ^testing.T) {
	a := Rng{ state = 0xDEADBEEF }
	b := Rng{ state = 0xDEADBEEF }
	for _ in 0..<8 {
		testing.expect(t, rng_f32(&a) == rng_f32(&b))
	}
}

@(test) test_rng_in_unit_interval :: proc(t: ^testing.T) {
	r := Rng{ state = 1 }
	for _ in 0..<1000 {
		v := rng_f32(&r)
		testing.expect(t, v >= 0 && v < 1)
	}
}

@(test) test_global_rng :: proc(t: ^testing.T) {
	// Test that seed resets sequence correctly
	seed(7)
	first := random()
	seed(7)
	testing.expect(t, random() == first)

	// Test that random_range produces values in correct interval
	seed(42)
	for _ in 0..<1000 {
		v := random_range(10, 20)
		testing.expect(t, v >= 10 && v < 20)
	}
}
