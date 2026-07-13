// Package sketch holds the pure filename logic for a sketch's .odin files:
// extension handling, name validation, and main-first ordering. It has no UI or
// raylib dependency so it can be unit-tested with `odin test sketch`.
package sketch

import "core:strings"
import "core:slice"

// True when name ends in the ".odin" extension.
is_odin_file :: proc(name: string) -> bool {
	return strings.has_suffix(name, ".odin")
}

// Return name with a ".odin" suffix, appended only if not already present.
// The result is always freshly allocated in `allocator`.
ensure_odin_ext :: proc(name: string, allocator := context.allocator) -> string {
	if is_odin_file(name) {
		return strings.clone(name, allocator)
	}
	return strings.concatenate({name, ".odin"}, allocator)
}

// True when name is a usable file stem: non-empty and only [A-Za-z0-9_-].
valid_file_name :: proc(name: string) -> bool {
	if len(name) == 0 { return false }
	for i in 0..<len(name) {
		c := name[i]
		ok := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
		      (c >= '0' && c <= '9') || c == '_' || c == '-'
		if !ok { return false }
	}
	return true
}

// Return a new slice ordering `files` with `main` first (when present), then the
// remaining names sorted case-insensitively ascending. Elements are the same
// string values passed in (borrowed, not cloned); only the returned backing
// slice is newly allocated in `allocator`.
order_files :: proc(files: []string, main: string, allocator := context.allocator) -> []string {
	out := make([dynamic]string, 0, len(files), allocator)
	for f in files {
		if f == main { append(&out, f); break } // main leads, if it exists
	}
	rest := make([dynamic]string, 0, len(files), context.temp_allocator)
	for f in files {
		if f != main { append(&rest, f) }
	}
	slice.sort_by(rest[:], less_ci)
	for f in rest { append(&out, f) }
	return out[:]
}

@(private) less_ci :: proc(a, b: string) -> bool {
	n := min(len(a), len(b))
	for i in 0..<n {
		ca := to_lower(a[i]); cb := to_lower(b[i])
		if ca != cb { return ca < cb }
	}
	return len(a) < len(b)
}

@(private) to_lower :: proc(c: u8) -> u8 {
	return c >= 'A' && c <= 'Z' ? c + 32 : c
}
