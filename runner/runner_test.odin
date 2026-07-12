package runner

import "core:testing"
import "core:strings"

@(test) test_build_good :: proc(t: ^testing.T) {
	res := build("runner/testdata/good", "build/_test_good.exe")
	defer delete(res.output)
	testing.expect(t, res.ok, "expected the good fixture to compile")
}

@(test) test_build_bad :: proc(t: ^testing.T) {
	res := build("runner/testdata/bad", "build/_test_bad.exe")
	defer delete(res.output)
	testing.expect(t, !res.ok, "expected the bad fixture to fail compilation")
	testing.expect(t, len(strings.trim_space(res.output)) > 0, "expected non-empty compiler output on failure")
}
