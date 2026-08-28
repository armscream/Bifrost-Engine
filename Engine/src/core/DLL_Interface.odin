// Engine/src/Core/DLL_Interface.odin
package Core

import "core:log"

Dynamic_Library :: struct {
	handle: rawptr,
	path:   string,
	loaded: bool,
}

// Bifrost DLL ABI
// ====================================================================
// This file defines the ABI shared between the Bifrost executable and
// dynamically loaded modules, extensions, and plugins.
//
// IMPORTANT:
// Keep this boundary C-compatible.
// Do not place Odin strings, dynamic arrays, maps, allocators, or other
// runtime-owned structures directly into the ABI.

DLL_API_VERSION :: u32(1)

DLL_ENTRY_POINT_NAME :: "bifrost_dll_get_api"

DLL_Type :: enum u32 {
	Module    = 0,
	Extension = 1,
	Plugin    = 2,
}

// DLL Context
// kept intentionally opaque at the DLL ABI boundary.

DLL_Context :: struct {
	user_data: rawptr,
}

DLL_Descriptor :: struct {
	api_version: u32,
	dll_type:    DLL_Type,
	name:        cstring,
}

// ====================
// Lifecycle Procedures

DLL_Load_Proc :: proc(ctx: ^DLL_Context) -> bool
DLL_Register_Proc :: proc(ctx: ^DLL_Context) -> bool
DLL_Activate_Proc :: proc(ctx: ^DLL_Context) -> bool
DLL_Deactivate_Proc :: proc(ctx: ^DLL_Context)
DLL_Unload_Proc :: proc(ctx: ^DLL_Context)

DLL_API :: struct {
	descriptor: DLL_Descriptor,
	load:       DLL_Load_Proc,
	register:   DLL_Register_Proc,
	activate:   DLL_Activate_Proc,
	deactivate: DLL_Deactivate_Proc,
	unload:     DLL_Unload_Proc,
}

DLL_State :: enum u32 {
	Unloaded,
	Loaded,
	Initialized,
	Registered,
	Active,
}

// ===========================
// Every Bifrost DLL must export:
//
//     bifrost_dll_get_api
//
// which returns a pointer to its static DLL_API.

DLL_Get_API_Proc :: proc() -> ^DLL_API


// DLL Loader
DLL_Loader :: struct {
	library: Dynamic_Library,
	api:     ^DLL_API,
}

dll_loader_load :: proc(loader: ^DLL_Loader, path: string) -> bool {
	if loader == nil do return false
	if loader.library.loaded do return false
	loader.api = nil
	// Open the dynamic library
	library, ok := dynamic_library_open(path)
	if !ok {
		log.error("Bifrost DLL: failed to load:", path)
		return false
	}

	loader.library = library

	//locate the common Bifrost entry point.
	symbol := dynamic_library_symbol(&loader.library, DLL_ENTRY_POINT_NAME)
	if symbol == nil {
		log.error("Bifrost DLL: failed to locate entry point:", DLL_ENTRY_POINT_NAME)
		dynamic_library_close(&loader.library)
		return false
	}

	//convert the raw function pointer into the expected proc type.
	get_api := transmute(DLL_Get_API_Proc)symbol
	api := get_api()
	if api == nil {
		log.error("Bifrost DLL: entry point returned nil API:", path)
		dynamic_library_close(&loader.library)
		return false
	}

	// Validate the ABI version before doing anything else.
	if api.descriptor.api_version != DLL_API_VERSION {
		log.error(
			"Bifrost DLL: Incompatible ABI version:",
			api.descriptor.api_version,
			"expected:",
			DLL_API_VERSION,
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
		log.error("Bifrost DLL: Missing required proc pointer, check the DLL API.")
		dynamic_library_close(&loader.library)
		return false
	}

	loader.api = api
	log.info("[DLL] Loaded:", path)
	return true
}

dll_loader_unload :: proc(loader: ^DLL_Loader) {
	if loader == nil || !loader.library.loaded do return
	// Library's unload callback is called by Mod/Ext/Plugin manager who owns lifecycle.
	loader.api = nil
	// This only releases the dyn lib itself.
	dynamic_library_close(&loader.library)
}

// API access
dll_loader_get_api :: proc(loader: ^DLL_Loader) -> ^DLL_API {
	if loader == nil do return nil
	return loader.api
}

dll_loader_get_descriptor :: proc(loader: ^DLL_Loader) -> ^DLL_Descriptor {
	if loader == nil || loader.api == nil do return nil
	return &loader.api.descriptor
}

// DLL State
dll_loader_is_loaded :: proc(loader: ^DLL_Loader) -> bool {
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