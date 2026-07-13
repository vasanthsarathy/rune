package canvas

// Print tooling: paper sizes at a chosen resolution (DPI), à la canvas-sketch.
// Pair a lower DPI for on-screen preview with a high DPI for export.

Paper :: enum { A5, A4, A3, Letter, Tabloid, Square }

// Physical size of a paper in millimeters (portrait).
@(private) _paper_mm :: proc(p: Paper) -> (w, h: f32) {
	switch p {
	case .A5:      return 148, 210
	case .A4:      return 210, 297
	case .A3:      return 297, 420
	case .Letter:  return 215.9, 279.4  // 8.5 x 11 in
	case .Tabloid: return 279.4, 431.8  // 11 x 17 in
	case .Square:  return 210, 210
	}
	return 210, 297
}

// Pixel dimensions of a paper at the given DPI.
paper_px :: proc(p: Paper, dpi: f32) -> (w, h: int) {
	mw, mh := _paper_mm(p)
	return int(mw/25.4*dpi + 0.5), int(mh/25.4*dpi + 0.5)
}

// Set the canvas to a paper size at the given DPI (default 300 = print quality).
// e.g. c.size_paper(.A4)  or  c.size_paper(.A4, 96) for a screen-sized preview.
size_paper :: proc(p: Paper, dpi: f32 = 300) {
	w, h := paper_px(p, dpi)
	size(w, h)
}
