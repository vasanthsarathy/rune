package runner

import "core:os"
import "core:strings"
import "core:path/filepath"

Build_Result :: struct {
	ok:     bool,
	output: string, // combined stdout+stderr, allocated in the caller's allocator
}

// Compile the Odin package at src_dir into out_exe (debug). Blocking.
build :: proc(src_dir, out_exe: string, allocator := context.allocator) -> Build_Result {
	out_arg := strings.concatenate({"-out:", out_exe}, context.temp_allocator)
	desc := os.Process_Desc{
		command = []string{"odin", "build", src_dir, out_arg, "-debug"},
	}
	state, stdout, stderr, err := os.process_exec(desc, context.temp_allocator)
	if err != nil {
		return Build_Result{ ok = false, output = strings.clone("failed to run the Odin compiler", allocator) }
	}
	// Compiler diagnostics go to stderr; keep stdout too for completeness.
	// NOTE: state.success means "the process ran to completion", NOT "exit 0".
	// A failed compile has success=true, exit_code=1 — so key off exit_code.
	combined := strings.concatenate({string(stdout), string(stderr)}, allocator)
	return Build_Result{ ok = state.exit_code == 0, output = combined }
}

Runner :: struct {
	running: bool,
	process: os.Process,
}

// Launch an already-built exe as a detached child. Returns whether it started.
launch :: proc(r: ^Runner, exe_path: string) -> bool {
	// process_start needs a native, absolute path: on Windows a forward-slash
	// relative path like "build/hello.exe" resolves to Not_Exist.
	abs_path, abs_err := filepath.abs(exe_path, context.temp_allocator)
	if abs_err != nil {
		abs_path = exe_path
	}
	desc := os.Process_Desc{ command = []string{abs_path} }
	p, err := os.process_start(desc)
	if err != nil {
		return false
	}
	r.process = p
	r.running = true
	return true
}

// Kill the running child if any.
stop :: proc(r: ^Runner) {
	if r.running {
		_ = os.process_kill(r.process)
		_, _ = os.process_wait(r.process) // reap
		r.running = false
	}
}

// Non-blocking check: has the child exited on its own?
poll :: proc(r: ^Runner) {
	if !r.running {
		return
	}
	state, err := os.process_wait(r.process, 0)
	if err == nil && state.exited {
		r.running = false
	}
}
