//Engine/src/Core/Platform_Linux.odin
#+build linux
package Core

// TODO: Make this work in a similar way to platform_windows.odin
// ==========================================
// LINUX
when ODIN_OS == .Linux {
	foreign import libc "system:libdl.so"
	foreign libc {
		dlopen :: proc(filename: cstring, flag: int) -> rawptr ---
		dlclose :: proc(handle: rawptr) -> int ---
		dlsym :: proc(handle: rawptr, symbol: cstring) -> rawptr ---
	}

	DL_LAZY :: 0x00001

	dynamic_library_open :: proc(path: string) -> (Dynamic_Library, bool) {
		c_path := strings.clone_to_cstring(path)
		handle := dlopen(c_path, DL_LAZY)
		delete(c_path)
		if handle == nil do return Dynamic_Library{}, false

		return Dynamic_Library{handle = handle, path = path, loaded = true}, true
	}

	dynamic_library_close :: proc(library: ^Dynamic_Library) {
		if library == nil do return
		if !library.loaded do return
		if library.handle != nil do dlclose(library.handle)
		library.handle = nil
		library.path = ""
		library.loaded = false
	}

	dynamic_library_symbol :: proc(library: ^Dynamic_Library, name: string) -> rawptr {
		if library == nil || !library.loaded do return nil
		if library.handle == nil do return nil
		c_name := strings.clone_to_cstring(name)

		symbol := dlsym(library.handle, c_name)
		delete(c_name)

		return symbol
	}
}