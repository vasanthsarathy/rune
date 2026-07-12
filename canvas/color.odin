package canvas

Color :: struct { r, g, b, a: u8 }

WHITE :: Color{255, 255, 255, 255}
BLACK :: Color{0, 0, 0, 255}

rgb  :: proc(r, g, b: u8) -> Color    { return Color{r, g, b, 255} }
rgba :: proc(r, g, b, a: u8) -> Color { return Color{r, g, b, a} }
gray :: proc(v: u8) -> Color          { return Color{v, v, v, 255} }
