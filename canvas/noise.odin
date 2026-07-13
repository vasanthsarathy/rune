package canvas

import "core:math"

// Classic "improved" Perlin noise (Ken Perlin, 2002), remapped to [0, 1).
// noise(x), noise(x,y), noise(x,y,z) via default args. noise_seed reshuffles.

@(private) _perm: [512]int
@(private) _perm_ready: bool

@(rodata, private) _default_p := [256]int{
	151,160,137,91,90,15,131,13,201,95,96,53,194,233,7,225,140,36,103,30,69,142,8,99,37,240,21,10,23,
	190,6,148,247,120,234,75,0,26,197,62,94,252,219,203,117,35,11,32,57,177,33,88,237,149,56,87,174,20,
	125,136,171,168,68,175,74,165,71,134,139,48,27,166,77,146,158,231,83,111,229,122,60,211,133,230,220,
	105,92,41,55,46,245,40,244,102,143,54,65,25,63,161,1,216,80,73,209,76,132,187,208,89,18,169,200,196,
	135,130,116,188,159,86,164,100,109,198,173,186,3,64,52,217,226,250,124,123,5,202,38,147,118,126,255,
	82,85,212,207,206,59,227,47,16,58,17,182,189,28,42,223,183,170,213,119,248,152,2,44,154,163,70,221,
	153,101,155,167,43,172,9,129,22,39,253,19,98,108,110,79,113,224,232,178,185,112,104,218,246,97,228,
	251,34,242,193,238,210,144,12,191,179,162,241,81,51,145,235,249,14,239,107,49,192,214,31,181,199,106,
	157,184,84,204,176,115,121,50,45,127,4,150,254,138,236,205,93,222,114,67,29,24,72,243,141,128,195,78,
	66,215,61,156,180,
}

@(private) _ensure_perm :: proc() {
	if _perm_ready { return }
	for i in 0..<256 {
		_perm[i]     = _default_p[i]
		_perm[256+i] = _default_p[i]
	}
	_perm_ready = true
}

// Reseed the noise field with a deterministic Fisher-Yates shuffle.
noise_seed :: proc(seed: u64) {
	p: [256]int
	for i in 0..<256 { p[i] = i }
	r := Rng{ state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
	for i := 255; i > 0; i -= 1 {
		j := int(rng_next_u64(&r) % u64(i+1))
		p[i], p[j] = p[j], p[i]
	}
	for i in 0..<256 {
		_perm[i]     = p[i]
		_perm[256+i] = p[i]
	}
	_perm_ready = true
}

@(private) _fade :: proc(t: f32) -> f32 { return t*t*t*(t*(t*6-15)+10) }
@(private) _lerpf :: proc(a, b, t: f32) -> f32 { return a + t*(b-a) }

@(private) _grad :: proc(hash: int, x, y, z: f32) -> f32 {
	h := hash & 15
	u := x if h < 8 else y
	v := h < 4 ? y : ((h == 12 || h == 14) ? x : z)
	return (u if (h & 1) == 0 else -u) + (v if (h & 2) == 0 else -v)
}

noise :: proc(x: f32, y: f32 = 0, z: f32 = 0) -> f32 {
	_ensure_perm()
	xi := int(math.floor(x)) & 255
	yi := int(math.floor(y)) & 255
	zi := int(math.floor(z)) & 255
	xf := x - math.floor(x)
	yf := y - math.floor(y)
	zf := z - math.floor(z)
	u := _fade(xf)
	v := _fade(yf)
	w := _fade(zf)

	a  := _perm[xi]   + yi
	aa := _perm[a]    + zi
	ab := _perm[a+1]  + zi
	b  := _perm[xi+1] + yi
	ba := _perm[b]    + zi
	bb := _perm[b+1]  + zi

	res := _lerpf(
		_lerpf(
			_lerpf(_grad(_perm[aa],   xf,   yf,   zf), _grad(_perm[ba],   xf-1, yf,   zf), u),
			_lerpf(_grad(_perm[ab],   xf,   yf-1, zf), _grad(_perm[bb],   xf-1, yf-1, zf), u),
			v),
		_lerpf(
			_lerpf(_grad(_perm[aa+1], xf,   yf,   zf-1), _grad(_perm[ba+1], xf-1, yf,   zf-1), u),
			_lerpf(_grad(_perm[ab+1], xf,   yf-1, zf-1), _grad(_perm[bb+1], xf-1, yf-1, zf-1), u),
			v),
		w)

	return (res + 1) * 0.5 // [-1,1] -> [0,1]
}
