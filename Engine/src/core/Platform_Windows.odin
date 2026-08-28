#+build windows
//Engine/src/Core/Platform_Windows.odin

package Core

import "core:strings"
import "core:sys/windows"
import "core:unicode/utf16"

dynamic_library_open :: proc(path: string) -> (Dynamic_Library, bool) {
	buf := make([dynamic]u16, len(path) + 1)
	defer delete(buf)
	utf16.encode_string(buf[:], path)
	handle := windows.LoadLibraryW(cstring16(raw_data(buf[:])))

	if handle == nil do return Dynamic_Library{}, false

	return Dynamic_Library{handle = transmute(rawptr)handle, path = path, loaded = true}, true
}

dynamic_library_close :: proc(library: ^Dynamic_Library) {
	if library == nil do return
	if !library.loaded do return
	if library.handle == nil do return

	windows.FreeLibrary(transmute(windows.HMODULE)library.handle)

	library.handle = nil
	library.loaded = false
}

dynamic_library_symbol :: proc(library: ^Dynamic_Library, name: string) -> rawptr {
	if library == nil || !library.loaded do return nil
	if library.handle == nil do return nil
	name_c := strings.clone_to_cstring(name)

	return(
		transmute(rawptr)windows.GetProcAddress(transmute(windows.HMODULE)library.handle, name_c) \
	)
}
