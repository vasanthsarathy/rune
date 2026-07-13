package main

// Built-in reference for the canvas API, shown in the in-app Docs panel (F1).
Doc_Entry :: struct {
	name:    string,
	sig:     string,
	summary: string,
	example: string,
}

@(rodata) DOCS := []Doc_Entry{
	// --- setup / window / loop ---
	{"size", "c.size(w, h: int)", "Set the canvas size in pixels. Call once in setup.", "setup :: proc() {\n\tc.size(800, 600)\n}"},
	{"run", "c.run(setup, draw: proc())", "Open the window and run the sketch. Call from main.", "main :: proc() {\n\tc.run(setup, draw)\n}"},
	{"size_paper", "c.size_paper(p: Paper, dpi=300)", "Set the canvas to a paper size (.A5/.A4/.A3/.Letter/.Tabloid/.Square) at a DPI. Use low DPI for preview, 300 for print.", "setup :: proc() {\n\tc.size_paper(.A4, 96) // screen preview\n}"},
	{"width", "c.width: int", "Canvas width in pixels (read-only). See also height.", "cx := f32(c.width) * 0.5"},
	{"height", "c.height: int", "Canvas height in pixels (read-only).", "cy := f32(c.height) * 0.5"},

	// --- time / input ---
	{"frame_count", "c.frame_count: int", "Number of frames drawn so far (read-only).", "if c.frame_count % 60 == 0 {\n\t// once per second\n}"},
	{"time", "c.time: f32", "Seconds since the sketch started (read-only).", "y := 100 * math.sin(c.time)"},
	{"delta_time", "c.delta_time: f32", "Seconds since the previous frame (read-only).", "t += c.delta_time"},
	{"mouse_x", "c.mouse_x: f32", "Mouse position (read-only). See also mouse_y, mouse, mouse_pressed.", "c.circle(c.mouse_x, c.mouse_y, 20)"},

	// --- color & style ---
	{"background", "c.background(args: ..u8)", "Fill the whole canvas. 1 arg = gray, 3 = r,g,b, 4 = r,g,b,a.\nCall each frame to clear, or once for accumulation.", "c.background(18, 18, 22)     // clear\nc.background(0, 0, 0, 20)     // low alpha = trails"},
	{"fill", "c.fill(args: ..u8)", "Set the fill color for shapes drawn after it.", "c.fill(255, 120, 40)\nc.circle(x, y, 40)"},
	{"no_fill", "c.no_fill()", "Draw following shapes with no fill (outline only).", "c.no_fill()\nc.stroke(255)\nc.circle(x, y, 40)"},
	{"stroke", "c.stroke(args: ..u8)", "Set the outline color for shapes and lines.", "c.stroke(90, 200, 255)\nc.line(0, 0, 100, 100)"},
	{"no_stroke", "c.no_stroke()", "Draw following shapes with no outline.", "c.no_stroke()\nc.fill(255)\nc.circle(x, y, 20)"},
	{"stroke_weight", "c.stroke_weight(w: f32)", "Set line / outline thickness in pixels.", "c.stroke_weight(3)\nc.line(0, 0, 200, 50)"},
	{"rgb", "c.rgb(r, g, b: u8) -> Color", "Make an opaque color. See also rgba, gray, WHITE, BLACK.", "col := c.rgb(255, 100, 0)"},
	{"hsl", "c.hsl(h, s, l: f32) -> Color", "HSL color: hue 0..360, saturation & lightness 0..1. Great for palettes. fill/stroke/background accept a Color.", "c.fill(c.hsl(210, 0.6, 0.5))"},
	{"hsv", "c.hsv(h, s, v: f32) -> Color", "HSV/HSB color: hue 0..360, saturation & value 0..1.", "c.stroke(c.hsv(t*30, 0.8, 1))"},

	// --- shapes ---
	{"circle", "c.circle(x, y, r: f32)", "Draw a circle centered at (x, y) with radius r.", "c.circle(c.mouse_x, c.mouse_y, 30)"},
	{"rect", "c.rect(x, y, w, h: f32)", "Draw a rectangle with its top-left corner at (x, y).", "c.rect(20, 20, 100, 60)"},
	{"line", "c.line(x1, y1, x2, y2: f32)", "Draw a line between two points.", "c.stroke(255)\nc.line(0, 0, c.mouse_x, c.mouse_y)"},
	{"point", "c.point(x, y: f32)", "Draw a single point using the current stroke.", "c.stroke(255)\nc.point(x, y)"},

	// --- math ---
	{"map_range", "c.map_range(v, in0, in1, out0, out1: f32) -> f32", "Re-map a number from one range to another.", "a := c.map_range(c.mouse_x, 0, f32(c.width), 0, c.TAU)"},
	{"lerp", "c.lerp(a, b, t: f32) -> f32", "Linear interpolation between a and b by t in [0,1].", "x = c.lerp(x, target, 0.1)  // smooth follow"},
	{"clamp", "c.clamp(v, lo, hi: f32) -> f32", "Constrain v to the range [lo, hi].", "r := c.clamp(r, 0, 100)"},
	{"dist", "c.dist(x1, y1, x2, y2: f32) -> f32", "Distance between two points.", "d := c.dist(x, y, c.mouse_x, c.mouse_y)"},
	{"radians", "c.radians(deg: f32) -> f32", "Convert degrees to radians. See also degrees.", "a := c.radians(90)"},
	{"PI", "c.PI / c.TAU", "Circle constants. TAU = 2*PI, a full turn.", "for i in 0..<12 {\n\ta := f32(i)/12 * c.TAU\n}"},

	// --- random & noise ---
	{"random", "c.random() -> f32", "Random float in [0, 1).", "if c.random() < 0.5 { ... }"},
	{"random_range", "c.random_range(lo, hi: f32) -> f32", "Random float in [lo, hi).", "x := c.random_range(0, f32(c.width))"},
	{"seed", "c.seed(s: u64)", "Seed the random generator for reproducible art.", "c.seed(42)"},
	{"noise", "c.noise(x, y=0, z=0: f32) -> f32", "Perlin noise in [0, 1): smooth, organic randomness (1-3D).", "n := c.noise(x*0.01, y*0.01)\nangle := n * c.TAU"},
	{"noise_seed", "c.noise_seed(s: u64)", "Reseed the noise field.", "c.noise_seed(7)"},

	// --- vectors ---
	{"vec2", "c.vec2(x, y: f32) -> Vec2", "Make a 2D vector. Vec2 supports +, -, *, .x, .y.", "p := c.vec2(100, 50)\np += c.vec2(1, 0)"},
	{"vlength", "c.vlength(v: Vec2) -> f32", "Length (magnitude) of a vector.", "speed := c.vlength(vel)"},
	{"vnormalize", "c.vnormalize(v: Vec2) -> Vec2", "Unit vector in the same direction (zero-safe).", "dir := c.vnormalize(target - pos)"},
	{"vfrom_angle", "c.vfrom_angle(a: f32) -> Vec2", "Unit vector pointing at angle a (radians).", "step := c.vfrom_angle(angle)"},
	{"vrotate", "c.vrotate(v: Vec2, a: f32) -> Vec2", "Rotate a vector by a radians.", "v = c.vrotate(v, c.radians(5))"},

	// --- easing ---
	{"ease_in_out_sine", "c.ease_in_out_sine(t: f32) -> f32", "Smooth ease in/out on t in [0,1]. Also quad & cubic variants.", "k := c.ease_in_out_sine(t)\ny := c.lerp(a, b, k)"},
}

// Index of the doc entry named `name`, or -1.
doc_index :: proc(name: string) -> int {
	for e, i in DOCS {
		if e.name == name { return i }
	}
	return -1
}
