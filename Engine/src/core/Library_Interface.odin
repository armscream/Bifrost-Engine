// Engine/src/Core/Library_Interface.odin
package Core

import "core:log"

Dynamic_Library :: struct {
	handle: rawptr,
	path:   string,
	loaded: bool,
}

Loaded_Lib :: struct {
	library: Dynamic_Library,
	api:     ^LIB_API,
	state:   Lib_State,
}

// Bifrost Dynamic Library ABI
// ====================================================================
// This file defines the ABI shared between the Bifrost executable and
// dynamically loaded modules, extensions, and plugins.
//
// IMPORTANT:
// Keep this boundary C-compatible.
// Do not place Odin strings, dynamic arrays, maps, allocators, or other
// runtime-owned structures directly into the ABI.

LIB_API_VERSION :: u32(1)

LIB_ENTRY_POINT_NAME :: "bifrost_lib_get_api"

Lib_Type :: enum u32 {
	Module    = 0,
	Extension = 1,
	Plugin    = 2,
}

// Lib Context
// kept intentionally opaque at the LIB ABI boundary.
Lib_Context :: struct {
	user_data: rawptr,
}

Lib_Descriptor :: struct {
	api_version: u32,
	lib_type:    Lib_Type,
	name:        cstring,
}

// ====================
// Lifecycle Procedures
Lib_Load_Proc :: proc(ctx: ^Lib_Context) -> bool
Lib_Register_Proc :: proc(ctx: ^Lib_Context) -> bool
Lib_Activate_Proc :: proc(ctx: ^Lib_Context) -> bool
Lib_Deactivate_Proc :: proc(ctx: ^Lib_Context)
Lib_Unload_Proc :: proc(ctx: ^Lib_Context)

LIB_API :: struct {
	descriptor: Lib_Descriptor,
	load:       Lib_Load_Proc,
	register:   Lib_Register_Proc,
	activate:   Lib_Activate_Proc,
	deactivate: Lib_Deactivate_Proc,
	unload:     Lib_Unload_Proc,
}

Lib_State :: enum u32 {
	Unloaded,
	Loaded,
	Registered,
	Active,
}

// ===========================
// Every Bifrost LIB must export:
//
//     bifrost_LIB_get_api
//
// which returns a pointer to its static LIB_API.
Lib_Get_API_Proc :: proc() -> ^LIB_API


// LIB Loader
Lib_Loader :: struct {
	library: Dynamic_Library,
	api:     ^LIB_API,
}

lib_loader_load :: proc(loader: ^Lib_Loader, path: string) -> bool {
	if loader == nil do return false
	if loader.library.loaded do return false
	loader.api = nil
	// Open the dynamic library
	library, ok := dynamic_library_open(path)
	if !ok {
		log.error("Bifrost LIB: failed to load:", path)
		return false
	}

	loader.library = library

	//locate the common Bifrost entry point.
	symbol := dynamic_library_symbol(&loader.library, LIB_ENTRY_POINT_NAME)
	if symbol == nil {
		log.error("Bifrost LIB: failed to locate entry point:", LIB_ENTRY_POINT_NAME)
		dynamic_library_close(&loader.library)
		return false
	}

	//convert the raw function pointer into the expected proc type.
	get_api := transmute(Lib_Get_API_Proc)symbol
	api := get_api()
	if api == nil {
		log.error("Bifrost LIB: entry point returned nil API:", path)
		dynamic_library_close(&loader.library)
		return false
	}

	// Validate the ABI version before doing anything else.
	if api.descriptor.api_version != LIB_API_VERSION {
		log.error(
			"Bifrost LIB: Incompatible ABI version:",
			api.descriptor.api_version,
			"expected:",
			LIB_API_VERSION,
		)
		dynamic_library_close(&loader.library)
		return false
	}

	// Validate the req'd proc pointers.
	if api.load == nil ||
	   api.register == nil ||
	   api.activate == nil ||
	   api.deactivate == nil ||
	   api.unload == nil {
		log.error("Bifrost LIB: Missing required proc pointer, check the LIB API.")
		dynamic_library_close(&loader.library)
		return false
	}

	loader.api = api
	log.info("[LIB] Loaded:", path)
	return true
}

lib_loader_unload :: proc(loader: ^Lib_Loader) {
	if loader == nil || !loader.library.loaded do return
	// Library's unload callback is called by Mod/Ext/Plugin manager who owns lifecycle.
	loader.api = nil
	// This only releases the dyn lib itself.
	dynamic_library_close(&loader.library)
}

// API access
lib_loader_get_api :: proc(loader: ^Lib_Loader) -> ^LIB_API {
	if loader == nil do return nil
	return loader.api
}

lib_loader_get_descriptor :: proc(loader: ^Lib_Loader) -> ^Lib_Descriptor {
	if loader == nil || loader.api == nil do return nil
	return &loader.api.descriptor
}

// LIB State
lib_loader_is_loaded :: proc(loader: ^Lib_Loader) -> bool {
	if loader == nil do return false
	return loader.library.loaded
}

// ==========================================
// Helpers
dynamic_library_is_loaded :: proc(library: ^Dynamic_Library) -> bool {
	if library == nil do return false
	return library.loaded
}

dynamic_library_path :: proc(library: ^Dynamic_Library) -> string {
	if library == nil do return ""
	return library.path
}
