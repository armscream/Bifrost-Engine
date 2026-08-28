// Engine/src/Core/Library_Interface.odin
package Core

import "core:log"

Dynamic_Library :: struct {
	handle: rawptr,
	path:   string,
	loaded: bool,
}

Loaded_Lib :: struct {
	loader: Lib_Loader,
	state:  Lib_State,
	ctx:    Lib_Context,
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
// Load and initialize this library into the engine.
loaded_lib_load :: proc(lib: ^Loaded_Lib, ctx: ^Lib_Context, path: string) -> bool {
	if lib == nil do return false
	// Must start unloaded.
	if lib.state != .Unloaded || ctx == nil do return false
	if !lib_loader_load(&lib.loader, path) do return false

	api := lib.loader.api
	if api == nil {
		lib_loader_unload(&lib.loader)
		return false
	}
	if !api.load(ctx) {
		lib_loader_unload(&lib.loader)
		return false
	}

	lib.state = .Loaded
	return true
}

loaded_lib_register :: proc(lib: ^Loaded_Lib, ctx: ^Lib_Context) -> bool {
	if lib == nil do return false
	if lib.loader.api == nil do return false
	if lib.state != .Loaded || ctx == nil do return false
	if !lib.loader.api.register(ctx) do return false

	lib.state = .Registered
	return true
}

loaded_lib_activate :: proc(lib: ^Loaded_Lib, ctx: ^Lib_Context) -> bool {
	if lib == nil || lib.loader.api == nil do return false
	if lib.state != .Registered || ctx == nil do return false
	if !lib.loader.api.activate(ctx) do return false

	lib.state = .Active
	return true

}

loaded_lib_deactivate :: proc(lib: ^Loaded_Lib, ctx: ^Lib_Context) -> bool {
	if lib == nil || lib.loader.api == nil do return false
	if lib.state != .Active || ctx == nil do return false
	lib.loader.api.deactivate(ctx)

	lib.state = .Registered
	return true
}

loaded_lib_unload :: proc(lib: ^Loaded_Lib, ctx: ^Lib_Context) -> bool {
	if lib == nil || lib.loader.api == nil do return false
	if lib.state == .Active || ctx == nil do return false
	if lib.state != .Registered && lib.state != .Loaded do return false
	// if the lib was registered, give it it's unload callback.
	if lib.state == .Registered do lib.loader.api.unload(ctx)

	lib_loader_unload(&lib.loader)
	lib.state = .Unloaded
	return true
}

lib_loader_unload :: proc(loader: ^Lib_Loader) {
	if loader == nil || !loader.library.loaded do return
	// Library's unload callback is called by Mod/Ext/Plugin manager who owns lifecycle.
	loader.api = nil
	// This only releases the dyn lib itself.
	dynamic_library_close(&loader.library)
}

// Convienient shutdown proc
loaded_lib_shutdown :: proc(lib: ^Loaded_Lib, ctx: ^Lib_Context) {
	if lib == nil do return
	if lib.state == .Active do loaded_lib_deactivate(lib, ctx)
	if lib.state == .Registered || lib.state == .Loaded do loaded_lib_unload(lib, ctx)
}

// state helpers
loaded_lib_is_loaded :: proc(lib: ^Loaded_Lib) -> bool {
	if lib == nil do return false
	return lib.state != .Unloaded
}
loaded_lib_is_registered :: proc(lib: ^Loaded_Lib) -> bool {
	if lib == nil do return false
	return lib.state == .Registered || lib.state == .Active
}
loaded_lib_is_active :: proc(lib: ^Loaded_Lib) -> bool {
	if lib == nil do return false
	return lib.state == .Active
}

loaded_lib_get_api :: proc(lib: ^Loaded_Lib) -> ^LIB_API {
	if lib == nil do return nil
	return lib.loader.api
}
loaded_lib_get_descriptor :: proc(lib: ^Loaded_Lib) -> ^Lib_Descriptor {
	if lib == nil do return nil
	return lib_loader_get_descriptor(&lib.loader)
}
// ============================================

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

// =============================================
// LIB Context API
// =============================================
//
// The LIB receives this API through LIB_Context.
//
// LIBs do NOT directly access Core registries or engine internals.
// They communicate with Core through this SDK boundary.
//
// Keep this ABI conservative:
//   - rawptr
//   - cstring
//   - fixed-width integers
//   - function pointers
//
// Do not put:
//   - string
//   - [dynamic]T
//   - map
//   - mem.Allocator
//   - Odin-specific containers
//
// directly into the ABI.
// ===========================

LIB_CONTEXT_API_VERSION :: u32(1)
Lib_Context :: struct {
	api:       ^Lib_Context_API,
	user_data: rawptr,
}

// Module registration data
Lib_Module_Registration :: struct {
	name:         cstring,
	version:      Version,
	module_type:  u32,
	flags:        u32,
	capabilities: u64,
}

Lib_Module_Dependency :: struct {
	name:        cstring,
	min_version: Version,
	max_version: Version,
}

// registration procedures
Lib_Module_Register_Proc :: proc(user_data: rawptr, registration: ^Lib_Module_Registration) -> bool
Lib_Module_Add_Dependency_Proc :: proc(
	user_data: rawptr,
	dependency: ^Lib_Module_Dependency,
) -> bool

Lib_Context_API :: struct {
	api_version:           u32,
	module_register:       Lib_Module_Register_Proc,
	module_add_dependency: Lib_Module_Add_Dependency_Proc,
}

// context validation
lib_context_is_valid :: proc(ctx: ^Lib_Context) -> bool {
	if ctx == nil || ctx.api == nil do return false
	if ctx.api.api_version != LIB_CONTEXT_API_VERSION do return false
	if ctx.api.module_register == nil || ctx.api.module_add_dependency == nil do return false
	return true
}

// convenience accessors
lib_context_register_module :: proc(
	ctx: ^Lib_Context,
	registration: ^Lib_Module_Registration,
) -> bool {
	if !lib_context_is_valid(ctx) do return false
	if registration == nil do return false
	return ctx.api.module_register(ctx.user_data, registration)
}

lib_context_add_module_dependency :: proc(
	ctx: ^Lib_Context,
	dependency: ^Lib_Module_Dependency,
) -> bool {
	if !lib_context_is_valid(ctx) do return false
	if dependency == nil do return false
	return ctx.api.module_add_dependency(ctx.user_data, dependency)
}

// Core registration API
Core_Lib_Context :: struct {
	registry: ^Module_Registry,
	registration: Module_Registration,
	has_registration: bool,
}

CORE_LIB_CONTEXT_API := Lib_Context_API {
	api_version           = LIB_CONTEXT_API_VERSION,
	module_register       = core_lib_module_register,
	module_add_dependency = core_lib_module_add_dependency,
}

core_lib_module_register :: proc(
	user_data: rawptr,
	registration: ^Lib_Module_Registration,
) -> bool {
	if user_data == nil || registration == nil do return false
	core_context := cast(^Core_Lib_Context)user_data
	if core_context.registry == nil || registration.name == nil do return false

	// Module_Registration is intentionally a minimal registration context;
	// identity/flags/capabilities are exposed by the DLL's Module_API
	// directly, not by the registration struct.
	core_context.registration = Module_Registration {}

	core_context.has_registration = true
	log.info("[Module] Registration prepared:", registration.name)

	return true
}

core_lib_module_add_dependency :: proc(
	user_data: rawptr,
	dependency: ^Lib_Module_Dependency,
) -> bool {
	if user_data == nil || dependency == nil do return false
	core_context := cast(^Core_Lib_Context)user_data
	if core_context == nil || core_context.registry == nil || dependency.name == nil do return false

	if !core_context.has_registration{
		log.error("[Module] Dependency declared before module registration.")
		return false
	}

	// Dependencies are exposed via the DLL's Module_API.dependencies; the
	// registration context does not store them.
	_ = dependency
	return true
}

core_lib_context_create :: proc(registry: ^Module_Registry) -> Lib_Context {
	return Lib_Context {
		api = &CORE_LIB_CONTEXT_API,
		user_data = cast(rawptr)&Core_Lib_Context{registry = registry},
	}
}

core_lib_module_commit_registration :: proc(ctx: ^Core_Lib_Context, handle: ModuleHandle) -> bool {
	if ctx == nil || ctx.registry == nil || !ctx.has_registration do return false

	// this is where the existing module registry API takes over, using existing module_register_loaded()
	return true
}