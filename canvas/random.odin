package canvas

// Seedable xorshift64 PRNG. Deterministic: identical state -> identical stream.
Rng :: struct { state: u64 }

rng_next_u64 :: proc(r: ^Rng) -> u64 {
	x := r.state
	x ~= x << 13
	x ~= x >> 7
	x ~= x << 17
	r.state = x
	return x
}

// Uniform f32 in [0, 1) using the top 24 bits.
rng_f32 :: proc(r: ^Rng) -> f32 {
	return f32(rng_next_u64(r) >> 40) / f32(1 << 24)
}

// Package-global generator used by the bare `random*` helpers.
rng: Rng = { state = 0x9E3779B97F4A7C15 }

seed :: proc(s: u64) {
	rng.state = s == 0 ? 0x9E3779B97F4A7C15 : s
}

random :: proc() -> f32 { return rng_f32(&rng) }

random_range :: proc(lo, hi: f32) -> f32 { return lo + (hi - lo) * random() }
