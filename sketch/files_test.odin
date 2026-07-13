package sketch

import "core:testing"
import "core:slice"

@(test)
test_is_odin_file :: proc(t: ^testing.T) {
	testing.expect(t, is_odin_file("a.odin"))
	testing.expect(t, !is_odin_file("a.txt"))
	testing.expect(t, !is_odin_file("odin"))
	testing.expect(t, !is_odin_file(""))
}

@(test)
test_ensure_odin_ext :: proc(t: ^testing.T) {
	a := ensure_odin_ext("foo");      defer delete(a)
	b := ensure_odin_ext("foo.odin"); defer delete(b)
	c := ensure_odin_ext("foo.od");   defer delete(c)
	testing.expect_value(t, a, "foo.odin")
	testing.expect_value(t, b, "foo.odin")
	testing.expect_value(t, c, "foo.od.odin") // only an exact .odin suffix is kept
}

@(test)
test_valid_file_name :: proc(t: ^testing.T) {
	testing.expect(t, valid_file_name("particles"))
	testing.expect(t, valid_file_name("a_b-2"))
	testing.expect(t, !valid_file_name(""))
	testing.expect(t, !valid_file_name("bad name"))
	testing.expect(t, !valid_file_name("has.dot"))
	testing.expect(t, !valid_file_name("pt/x"))
}

@(test)
test_order_files :: proc(t: ^testing.T) {
	// main first regardless of input order; the rest case-insensitive A–Z
	files := []string{"palette.odin", "myart.odin", "Board.odin", "particles.odin"}
	got := order_files(files, "myart.odin"); defer delete(got)
	testing.expect(t, slice.equal(got, []string{"myart.odin", "Board.odin", "palette.odin", "particles.odin"}))

	// main absent → pure A–Z (case-insensitive)
	g2 := order_files([]string{"b.odin", "A.odin"}, "missing.odin"); defer delete(g2)
	testing.expect(t, slice.equal(g2, []string{"A.odin", "b.odin"}))

	// empty input → empty output
	g3 := order_files([]string{}, "myart.odin"); defer delete(g3)
	testing.expect_value(t, len(g3), 0)
}
