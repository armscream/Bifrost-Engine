// Engine\src\Core\module_interface.odin
package Core

import "core:dynlib"
import "core:log"


// ============================================================================
// MODULE ABI
// ============================================================================
//
// Every Ymir engine module is a dynamically loaded provider of engine
// functionality.
//
// The DLL exposes exactly one required entry point:
//
//     ymir_module_get_api
//
// Everything else is discovered through the returned API table.
//
// ============================================================================

Module_Registry :: struct {
	modules: [dynamic]Loaded_Module,
	free_indices: [dynamic]u32,
	by_name: map[string]ModuleHandle,
	by_type: [Module_Type][dynamic]ModuleHandle,
}

Plugin_Registry :: struct {
	Plugins: [dynamic]Loaded_Module,
	free_indices: [dynamic]u32,
	by_name: map[string]PluginHandle,
	by_type: [Module_Type][dynamic]PluginHandle,
}

// ============================================================================
// VERSION
// ============================================================================

API_VERSION :: 1


// ============================================================================
// MODULE TYPES
// ============================================================================

Module_Type :: enum u32 {
	Engine,
	Renderer,
	Input,
	ECS,
	Physics,
	Audio,
	UI,
	Scripting,
	Replication,
	Editor,
	Debug,
	Other,
}

// ============================================================================
// MODULE FLAGS
// ============================================================================

Module_Flags :: bit_set[Module_Flag]

Module_Flag :: enum u32 {
	None,
	Editor_Only,
	Runtime,
	Optional,
	Hot_Reloadable,
	Provides_Service,
	Provides_Systems,
}


// ============================================================================
// MODULE CAPABILITIES
// ============================================================================
//
// Capabilities describe what a module provides.
//
// Example:
//
// Bifrost_Renderer:
//
//     Renderer
//     GPU
//     Materials
//     Textures
//
// ============================================================================

Module_Capability :: enum u32 {
	Renderer,
	Input,
	ECS,
	Physics,
	Audio,
	UI,
	Scripting,
	Replication,
	Editor,
	Debug,
	Networking,

	GPU,
	Materials,
	Textures,
	Animation,
	Particles,
	Navigation,

	Custom,
}


// ============================================================================
// MODULE IDENTITY
// ============================================================================

Module_Identity :: struct {
	name:        cstring,
	version:     cstring,
	author:      cstring,
	description: cstring,

	type:  Module_Type,
	flags: Module_Flags,
}


// ============================================================================
// MODULE DEPENDENCY
// ============================================================================

Module_Dependency :: struct {
	name:          cstring,
	min_version:   cstring,
	max_version:   cstring,
	optional:      bool,
}

// ============================================================================
// MODULE CONTEXT
// ============================================================================
//
// Passed to the module during loading.
//
// The module should NOT reach directly into arbitrary Core globals.
// Everything it needs should eventually be exposed through the SDK.
//
// ============================================================================

Module_Context :: struct {
	api_version: u32,

	allocator: rawptr,

	module_registry: rawptr,
	scheduler:       rawptr,
	services:        rawptr,
	events:          rawptr,
}

// ============================================================================
// MODULE API
// ============================================================================
//
// This is the actual ABI exposed by the DLL.
//
// Required:
//     load
//
// Optional:
//     unload
//     update
//     render
//
// ============================================================================

Module_API :: struct {
	api_version: u32,

	identity: Module_Identity,

	dependencies: [^]Module_Dependency,
	dependency_count: u32,

	load:     proc(ctx: ^Module_Context) -> bool,
	register: proc(ctx: ^Module_Context) -> bool,
	unload:   proc(ctx: ^Module_Context),
}


// ============================================================================
// DLL ENTRY POINT
// ============================================================================

Module_Get_API :: proc() -> ^Module_API


// ============================================================================
// LOADED MODULE/PLUGIN
// ============================================================================

Loaded_Module :: struct {
	handle: ModuleHandle,
	library: dynlib.Library,
	api: Module_API,
	ctx: Module_Context,
	state: Module_State,
	registration: Module_Registration,
}

Module_State :: enum u32 {
	Unloaded,
	Loaded,
	Registered,
	Active,
	Failed,
}

Module_Registration :: struct {
	module: ModuleHandle,

	services:  [dynamic]Service_Registration,
	systems:   [dynamic]System_Registration,
	resources: [dynamic]Resource_Registration,
	events:    [dynamic]Event_Registration,
}

// ============================================================================
// LOAD MODULE
// ============================================================================

load_module :: proc(
	dll_name: string,
	ctx: Module_Context,
) -> (Loaded_Module, bool) {

	mod := Loaded_Module{}

	// ------------------------------------------------------------------------
	// Load DLL
	// ------------------------------------------------------------------------

	library, ok := dynlib.load_library(dll_name)

	if !ok {
		log.error(
			"Failed to load module '%s': %s\n",
			dll_name,
			dynlib.last_error(),
		)

		return mod, false
	}

	mod.library = library
	mod.ctx = ctx


	// ------------------------------------------------------------------------
	// Resolve API entry point
	// ------------------------------------------------------------------------

	ptr, found := dynlib.symbol_address(
		mod.library,
		"ymir_module_get_api",
	)

	if !found {
		log.error(
			"Module '%s' does not export ymir_module_get_api\n",
			dll_name,
		)

		dynlib.unload_library(mod.library)

		return mod, false
	}


	get_api := cast(Module_Get_API)(ptr)

	api := get_api()

	if api == nil {
		log.error(
			"Module '%s' returned a null API\n",
			dll_name,
		)

		dynlib.unload_library(mod.library)

		return mod, false
	}


	// ------------------------------------------------------------------------
	// Validate API version
	// ------------------------------------------------------------------------

	if api.api_version != API_VERSION {
		log.error(
			"Module '%s' uses unsupported API version %d\n",
			dll_name,
			api.api_version,
		)

		dynlib.unload_library(mod.library)

		return mod, false
	}


	// ------------------------------------------------------------------------
	// Copy API table
	// ------------------------------------------------------------------------

	mod.api = api^

	mod.state.Loaded = true


	// ------------------------------------------------------------------------
	// Load module
	// ------------------------------------------------------------------------

	if mod.api.load != nil {
		if !mod.api.load(&mod.ctx) {
			log.error(
				"Module '%s' failed to initialize\n",
				dll_name,
			)

			dynlib.unload_library(mod.library)

			mod = {}

			return mod, false
		}
	}


	log.info(
		"Loaded module: %s v%s\n",
		mod.api.identity.name,
		mod.api.identity.version,
	)

	return mod, true
}


// ============================================================================
// UNLOAD MODULE
// ============================================================================

unload_module :: proc(
	mod: ^Loaded_Module,
) {

	if mod == nil {
		return
	}

	if !mod.state.loaded {
		return
	}


	if mod.api.unload != nil {
		mod.api.unload(&mod.ctx)
	}


	if mod.library != nil {
		dynlib.unload_library(mod.library)
	}


	mod = {}
}


// ============================================================================
// UPDATE
// ============================================================================

update_module :: proc(
	mod: ^Loaded_Module,
	dt: f32,
) {

	if mod == nil || !mod.loaded {
		return
	}

	if mod.api.update != nil {
		mod.api.update(&mod.ctx, dt)
	}
}


// ============================================================================
// RENDER
// ============================================================================

render_module :: proc(
	mod: ^Loaded_Module,
) {

	if mod == nil || !mod.loaded {
		return
	}

	if mod.api.render != nil {
		mod.api.render(&mod.ctx)
	}
}