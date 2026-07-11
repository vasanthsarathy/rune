package main

import "core:dynlib"
import "core:fmt"
import "core:os"
import "core:time"

DLL_PATH :: "build/odessa.dll"

Api :: struct {
	init_window:     proc(),
	init:            proc(),
	update:          proc() -> bool,
	shutdown:        proc(),
	shutdown_window: proc(),
	memory:          proc() -> rawptr,
	memory_size:     proc() -> int,
	hot_reloaded:    proc(mem: rawptr),
	force_reload:    proc() -> bool,
	force_restart:   proc() -> bool,

	__handle:    dynlib.Library,
	dll_time:    time.Time,
	api_version: int,
}

copy_dll :: proc(to: string) -> bool {
	data, read_err := os.read_entire_file(DLL_PATH, context.allocator)
	if read_err != nil {
		fmt.eprintfln("Failed to read %s: %v", DLL_PATH, read_err)
		return false
	}
	defer delete(data)
	if write_err := os.write_entire_file(to, data); write_err != nil {
		fmt.eprintfln("Failed to write %s: %v", to, write_err)
		return false
	}
	return true
}

load_api :: proc(version: int) -> (api: Api, ok: bool) {
	dll_time, time_err := os.last_write_time_by_name(DLL_PATH)
	if time_err != nil {
		fmt.eprintfln("Failed to stat %s: %v", DLL_PATH, time_err)
		return
	}
	dll_copy := fmt.tprintf("build/odessa_hot_%d.dll", version)
	if !copy_dll(dll_copy) { return }
	_, init_ok := dynlib.initialize_symbols(&api, dll_copy, "odessa_", "__handle")
	if !init_ok {
		fmt.eprintfln("Failed to init symbols: %s", dynlib.last_error())
		return
	}
	api.dll_time = dll_time
	api.api_version = version
	ok = true
	return
}

unload_api :: proc(api: ^Api) {
	if api.__handle != nil {
		if !dynlib.unload_library(api.__handle) {
			fmt.eprintfln("Failed to unload: %s", dynlib.last_error())
		}
	}
	if os.remove(fmt.tprintf("build/odessa_hot_%d.dll", api.api_version)) != nil {}
}

main :: proc() {
	api, ok := load_api(0)
	if !ok { fmt.eprintln("Failed to load Odessa API on startup."); return }
	version := 1

	api.init_window()
	api.init()

	old_apis := make([dynamic]Api, 0, 8)

	for api.update() {
		reload := api.force_reload() || api.force_restart()
		force_restart := api.force_restart()

		dll_time, err := os.last_write_time_by_name(DLL_PATH)
		if err == nil && dll_time != api.dll_time { reload = true }

		if reload {
			new_api, new_ok := load_api(version)
			if new_ok {
				restart := force_restart || api.memory_size() != new_api.memory_size()
				if restart {
					api.shutdown()
					for &old in old_apis { unload_api(&old) }
					clear(&old_apis)
					unload_api(&api)
					api = new_api
					api.init()
				} else {
					append(&old_apis, api)
					mem := api.memory()
					api = new_api
					api.hot_reloaded(mem)
				}
				version += 1
			}
		}
	}

	api.shutdown()
	api.shutdown_window()
	for &old in old_apis { unload_api(&old) }
	delete(old_apis)
	unload_api(&api)
}
