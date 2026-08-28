// Engine\src\Core\module_interface.odin
package Core

import "core:dynlib"
import "core:log"
import "core:mem"

// ============================================================================
// SUPPORTED IDENTITY / DEPENDENCY LITERAL SUBSET (for rbs manifest codegen)
// ============================================================================
//
// rbs manifest codegen scans the package's .odin source for the canonical
// IDENTITY and DEPENDENCIES literals below and emits a deterministic
// <PackageName>.toml manifest. The scanner only understands a strict, frozen
// subset of Odin literal syntax. Anything outside this subset is rejected with
// a precise error pointing at the offending line.
//
// ─────────────────────────────────────────────────────────────────────────
// IDENTITY block
// ─────────────────────────────────────────────────────────────────────────
//
// Marker comments are required and must wrap the literal exactly like this:
//
//     // === MODULE_IDENTITY (parsed by rbs) ===
//     IDENTITY :: Core.Module_Identity{
//         name        = "Bifrost_Renderer",
//         version     = Core.Version{0, 1, 0},
//         author      = "czvan",
//         description = "PBR forward+ renderer.",
//         type        = .Renderer,
//         flags       = {.Runtime},
//         capabilities = {.Renderer, .GPU, .Materials, .Textures},
//     }
//     // === END MODULE_IDENTITY ===
//
// Field rules (any unlisted shape is a parse error):
//
//   name        — Odin string literal "..."; no concatenation, no string ops.
//   version     — Either `Core.Version{major, minor, patch}` or
//                 `Core.Version{major = N, minor = N, patch = N}`.
//                 Bare integer literals only. Expressions like `1 + 2` are not
//                 allowed.
//   author      — String literal.
//   description — String literal. May be empty "" but must be present.
//   type        — A single Odin enum identifier with the leading dot,
//                 e.g. .Renderer, .Input, .ECS. The scanner does not resolve
//                 the enum value; it only validates that the identifier is in
//                 the known set of Module_Type members.
//   flags       — A bit_set literal: `{.Runtime}` or `{.Editor_Only, .Runtime}`.
//                 Members must be from Module_Flag.
//   capabilities — Same shape as flags. Members must be from
//                  Module_Capability.
//
// ─────────────────────────────────────────────────────────────────────────
// DEPENDENCIES block
// ─────────────────────────────────────────────────────────────────────────
//
//     // === DEPENDENCIES (parsed by rbs) ===
//     DEPENDENCIES := [?]Core.DLL_Dependency{
//         {
//             name        = "Default_Input",
//             min_version = Core.Version{0, 0, 1},
//             max_version = Core.Version{0, 0, 999},
//             has_min_version = true,
//             has_max_version = false,
//             optional    = false,
//         },
//         ...more...
//     }
//     // === END DEPENDENCIES ===
//
// Array is `[?]Core.DLL_Dependency{ ... }` (pointer-style to match the ABI
// layout used by Module_API.dependencies). Each element is a struct literal
// in any field order, with these rules:
//
//   name            — String literal.
//   min_version     — Core.Version{} literal.
//   max_version     — Core.Version{} literal.
//   has_min_version — `true` or `false` (bool literal).
//   has_max_version — `true` or `false`.
//   optional        — `true` or `false`.
//
// ─────────────────────────────────────────────────────────────────────────
// TARGETS block (extensions only; ignored for Modules and Plugins)
// ─────────────────────────────────────────────────────────────────────────
//
//     // === TARGETS (parsed by rbs) ===
//     TARGETS := [?]Core.Extension_Target{
//         {
//             module        = "Bifrost_Renderer",
//             min_version   = Core.Version{0, 1, 0},
//             max_version   = Core.Version{0, 0, 0},
//             has_min_version = true,
//             has_max_version = true,
//         },
//     }
//     // === END TARGETS ===
//
// ─────────────────────────────────────────────────────────────────────────
// GENERAL LITERAL RULES (apply to every block)
// ─────────────────────────────────────────────────────────────────────────
//
//   - Comma separators are required between elements at the same nesting
//     level. A trailing comma before a closing `}` or `]` is allowed.
//   - Whitespace and newlines are arbitrary and ignored.
//   - `//` and `/* */` comments inside blocks are stripped during scanning.
//   - Qualified identifiers (`Core.Version`, etc.) are accepted but only the
//     suffix is matched; the prefix may be `Core`, `core`, or omitted
//     entirely.
//   - String literals may contain `\\ \" \n \r \t` escapes; everything else is
//     a parse error.
//   - Integer literals may be decimal `0..9` or hex `0x..` with optional
//     underscores between digits (e.g. `1_000_000`).
//   - No function calls, no cast expressions, no arithmetic, no identifiers
//     other than the documented ones.
//
// ANY drift from this subset produces an error of the form:
//
//     <relative-source-path>:<line>:<col>: unsupported literal in <block>: ...
//
// ─────────────────────────────────────────────────────────────────────────
// Why these restrictions matter
// ─────────────────────────────────────────────────────────────────────────
//
// rbs codegen is what guarantees the on-disk manifest matches the source.
// Anything rbs cannot parse is, by definition, also anything rbs cannot
// verify. Keeping the supported subset small and explicit removes ambiguity
// from the build pipeline and makes failed codegen failures informative
// instead of silent drift.
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
// Modules = primary engine/runtime capabilities. They can provide systems, services, resources, events, etc.
// ============================================================================

Module_Registry :: struct {
	allocator:        mem.Allocator,
	modules:          [dynamic]Loaded_Module,
	generations:      [dynamic]u32,
	free_indices:     [dynamic]u32,
	// Dependency resolution
	dependency_order: [dynamic]ModuleHandle,
	dependency_state: [dynamic]Module_Visit_State,
	// Lifecycle
	initialized:      bool,
	// Lookup
	by_name:          map[string]ModuleHandle,
	by_type:          [Module_Type][dynamic]ModuleHandle,
}

// For dependency resolution, we use a simple state machine to track whether each module has been built into the
// dependency graph or not. Module_resolve_dependencies will only examine a module if it is in the Unvisited state.
// if modules visit each-other cyclically, then the state machine will detect a cycle and return an error.
Module_Visit_State :: enum {
	Unvisited, // module has not been examined.
	Visiting, // currently somewhere in the DFS stack.
	Visited, // completely resolved.
}

API_VERSION :: 1

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
// Capabilities describe what a module provides.
// Example: Bifrost_Renderer: Renderer, GPU, Materials, Textures

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

Module_Identity :: struct {
	name:         cstring,
	version:      Version,
	author:       cstring,
	description:  cstring,
	type:         Module_Type,
	flags:        Module_Flags,
	capabilities: Module_Capabilities,
}
Module_Capabilities :: bit_set[Module_Capability]

@(private)
version_equal :: proc(a, b: Version) -> bool {
	return a.major == b.major && a.minor == b.minor && a.patch == b.patch
}
@(private)
version_less :: proc(a, b: Version) -> bool {
	if a.major != b.major {
		return a.major < b.major
	}

	if a.minor != b.minor {
		return a.minor < b.minor
	}

	return a.patch < b.patch
}
@(private)
version_less_equal :: proc(a, b: Version) -> bool {
	return version_less(a, b) || version_equal(a, b)
}
@(private)
version_greater :: proc(a, b: Version) -> bool {
	return !version_less_equal(a, b)
}
@(private)
version_greater_equal :: proc(a, b: Version) -> bool {
	return !version_less(a, b)
}
@(private)
version_satisfies :: proc(version: Version, dependency: DLL_Dependency) -> bool {

	if dependency.has_min_version {
		if version_less(version, dependency.min_version) {
			return false
		}
	}

	if dependency.has_max_version {
		if version_greater(version, dependency.max_version) {
			return false
		}
	}

	return true
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
	api_version:     u32,
	// Core memory allocator.
	allocator:       rawptr,
	// the module's own identity.
	self: ModuleHandle,
	// Core-owned systems.
	module_registry: rawptr,
	service_registry: rawptr,
	// runtime infrastructure.
	scheduler:       rawptr,
	events:          rawptr,
	//  registration API.
	registration:    ^Module_Registration_API,
}

// ============================================================================
// MODULE API
// ============================================================================
// This is the actual ABI exposed by the DLL.
// ============================================================================
Module_API :: struct {
	api_version:      u32,
	identity:         Module_Identity,
	dependencies:     [^]DLL_Dependency,
	dependency_count: u32,
	// DLL lifecycle.
	// allocate/initialize module-owned state/resources
	load:             proc(ctx: ^Module_Context) -> bool,
	// Collect/register services, systems, resources, events.
	register:         proc(ctx: ^Module_Context) -> bool,
	// Start runtime operation after all modules have registered and Core
	// has constructed the req'd runtime infrastructure.
	activate:         proc(ctx: ^Module_Context) -> bool,
	// stop runtime operation while keeping the module laoaded.
	deactivate:       proc(ctx: ^Module_Context),
	// release all module-owned state/resources
	unload:           proc(ctx: ^Module_Context),
}

Module_Get_API :: proc() -> ^Module_API

Module_Registration_API :: struct {
	add_service: proc(ctx: ^Module_Context, registration: Service_Registration) -> bool,
	add_system: proc(ctx: ^Module_Context, registration: System_Registration) -> bool,
	add_resource: proc(ctx: ^Module_Context, registration: Resource_Registration) -> bool,
	add_event: proc(ctx: ^Module_Context, registration: Event_Registration) -> bool,
}

// ============================================================================
// LOADED MODULE/PLUGIN
// ============================================================================

Loaded_Module :: struct {
	handle:       ModuleHandle,
	library:      dynlib.Library,
	api:          Module_API,
	ctx:          Module_Context,
	state:        Load_State,
	registration: Module_Registration,
}

Module_Registration :: struct {
	module:    ModuleHandle,
	services:  [dynamic]Service_Registration,
	systems:   [dynamic]System_Registration,
	resources: [dynamic]Resource_Registration,
	events:    [dynamic]Event_Registration,
}

// ============================================================================
// LOAD MODULE
// ============================================================================

load_module :: proc(dll_name: string, ctx: Module_Context) -> (Loaded_Module, bool) {
	mod := Loaded_Module{}
	// ------------------------------------------------------------------------
	// Load DLL
	// ------------------------------------------------------------------------
	library, ok := dynlib.load_library(dll_name)
	if !ok {
		log.error("Failed to load module '%s': %s\n", dll_name, dynlib.last_error())
		return mod, false
	}
	mod.library = library
	mod.ctx = ctx
	// ------------------------------------------------------------------------
	// Resolve API entry point
	// ------------------------------------------------------------------------
	ptr, found := dynlib.symbol_address(mod.library, "ymir_module_get_api")
	if !found {
		log.error("Module '%s' does not export ymir_module_get_api\n", dll_name)
		dynlib.unload_library(mod.library)
		return mod, false
	}
	get_api := cast(Module_Get_API)(ptr)
	api := get_api()
	if api == nil {
		log.error("Module '%s' returned a null API\n", dll_name)
		dynlib.unload_library(mod.library)
		return mod, false
	}
	// ------------------------------------------------------------------------
	// Validate API version
	// ------------------------------------------------------------------------
	if api.api_version != API_VERSION {
		log.error("Module '%s' uses unsupported API version %d\n", dll_name, api.api_version)
		dynlib.unload_library(mod.library)
		return mod, false
	}
	// ------------------------------------------------------------------------
	// Copy API table
	// ------------------------------------------------------------------------
	mod.api = api^
	mod.state = Load_State.Loaded
	// ------------------------------------------------------------------------
	// Load module
	// ------------------------------------------------------------------------
	if mod.api.load != nil {
		if !mod.api.load(&mod.ctx) {
			log.error("Module '%s' failed to initialize\n", dll_name)
			dynlib.unload_library(mod.library)
			mod = {}
			return mod, false
		}
	}
	log.info("Loaded module: %s v%s\n", mod.api.identity.name, mod.api.identity.version)
	return mod, true
}

// ============================================================================
// UNLOAD MODULE
// ============================================================================
unload_module :: proc(mod: ^Loaded_Module) {
	if mod == nil {return}
	if mod.state != Load_State.Loaded &&
	mod.state != Load_State.Registered {return}
	if mod.api.unload != nil {mod.api.unload(&mod.ctx)}
	if mod.library != nil {dynlib.unload_library(mod.library)}
	mod^ = {}
}
@(private)
module_registry_init :: proc(registry: ^Module_Registry, allocator: mem.Allocator) -> bool {
	if registry == nil {return false}

	if registry.initialized {
		log.warn("Module registry is already initialized.")
		return false
	}

	registry.allocator = allocator

	// Slot 0 is permanently reserved because index 0 is INVALID.
	registry.modules = make([dynamic]Loaded_Module, 1, allocator)
	append(&registry.modules, Loaded_Module{})

	registry.generations = make([dynamic]u32, 1, allocator)
	append(&registry.generations, MODULE_GENERATION_INVALID)

	registry.free_indices = make([dynamic]u32, 0, allocator)
	registry.dependency_order = make([dynamic]ModuleHandle, 0, allocator)
	registry.dependency_state = make([dynamic]Module_Visit_State, 0, allocator)
	registry.by_name = make(map[string]ModuleHandle, allocator)
	for module_type in Module_Type {
		registry.by_type[module_type] = make([dynamic]ModuleHandle, 0, allocator)
	}
	registry.initialized = true
	log.info("Module registry initialized.")
	return true
}
@(private)
module_registry_destroy :: proc(registry: ^Module_Registry) {
	if registry == nil || !registry.initialized {return}

	// Destroy module-owned registrations.
	for i := 0; i < len(registry.modules); i += 1 {
		module := &registry.modules[i]
		if module.state != Load_State.Unloaded && module.state != Load_State.Failed {
			module_registration_destroy(&module.registration)
		}
	}
	// destroy dependency state.
	delete(registry.dependency_order)
	delete(registry.dependency_state)
	// destroy type lookup arrays.
	for module_type in Module_Type {
		delete(registry.by_type[module_type])
	}
	// destory name lookup
	delete(registry.by_name)
	// destroy slot storage.
	delete(registry.free_indices)
	delete(registry.generations)
	delete(registry.modules)

	// Reset registry.
	registry.allocator = {}
	registry.initialized = false
}
@(private)
module_registration_destroy :: proc(registration: ^Module_Registration) {
	if registration == nil {
		return
	}

	delete(registration.services)
	delete(registration.systems)
	delete(registration.resources)
	delete(registration.events)

	registration^ = {}
}
@(private)
module_register_loaded :: proc(registry: ^Module_Registry, module: ^Loaded_Module) -> (ModuleHandle, bool) {

	if registry == nil || !registry.initialized {
		return INVALID_MODULE_HANDLE, false
	}

	// Validate module state
	if module.state != Load_State.Loaded {
		log.error(
			"Cannot register module '%s': module is not in Loaded state.",
			module.api.identity.name,
		)

		return INVALID_MODULE_HANDLE, false
	}

	if module.api.identity.name == nil {
		log.error("Cannot register module: module has no name.")
		return INVALID_MODULE_HANDLE, false
	}

	name := string(module.api.identity.name)

	if len(name) == 0 {
		log.error("Cannot register module: module has an empty name.")
		return INVALID_MODULE_HANDLE, false
	}

	// Reject duplicate names
	if existing, found := registry.by_name[name]; found {
		log.error("Cannot register module '%s': already registered (handle %v).", name, existing)
		return INVALID_MODULE_HANDLE, false
	}

	// Allocate slot
	index: u32

	if len(registry.free_indices) > 0 {
		last := len(registry.free_indices) - 1
		index = registry.free_indices[last]
		resize(&registry.free_indices, last)
	} else {
		index = u32(len(registry.modules))
		append(&registry.modules, Loaded_Module{})
		append(&registry.generations, MODULE_GENERATION_INVALID)
	}

	// Advance generation
	generation := registry.generations[index]

	if generation == MODULE_GENERATION_INVALID {
		generation = 1
	} else {
		generation += 1
		// Generation wrapped around.
		// Zero is reserved as invalid.
		if generation == MODULE_GENERATION_INVALID {
			generation = 1
		}
	}

	registry.generations[index] = generation
	// IMPORTANT:
	// Store the generation back into the registry.
	handle := ModuleHandle {
		index      = index,
		generation = generation,
	}

	// Assign registry identity
	module.handle = handle
	module.registration = Module_Registration {
		module = handle,
	}
	
	// Store module
	module.state = Load_State.Registered

	registry.modules[index] = module^
	// Name lookup
	registry.by_name[name] = handle
	// Type lookup
	append(&registry.by_type[module.api.identity.type], handle)
	// Complete
	log.info(
		"Registered module: %s v%d.%d.%d [%d:%d]",
		module.api.identity.name,
		module.api.identity.version.major,
		module.api.identity.version.minor,
		module.api.identity.version.patch,
		handle.index,
		handle.generation,
	)

	return handle, true
}
// Helper for finding a module by handle.
@(private)
module_registry_get :: proc(
	registry: ^Module_Registry,
	handle: ModuleHandle,
) -> (
	^Loaded_Module,
	bool,
) {

	if registry == nil || !registry.initialized {
		return nil, false
	}

	// ------------------------------------------------------------------------
	// Index 0 is permanently reserved as INVALID.
	// ------------------------------------------------------------------------

	if handle.index == MODULE_INDEX_INVALID {
		return nil, false
	}

	// ------------------------------------------------------------------------
	// Handle must point inside the module storage.
	// ------------------------------------------------------------------------

	if handle.index >= u32(len(registry.modules)) {
		return nil, false
	}

	// ------------------------------------------------------------------------
	// Generation must match the current generation of the slot.
	//
	// This prevents stale handles from accessing a recycled module slot.
	// ------------------------------------------------------------------------

	if handle.generation == MODULE_GENERATION_INVALID {
		return nil, false
	}

	if handle.generation != registry.generations[handle.index] {
		return nil, false
	}

	// ------------------------------------------------------------------------
	// Slot must actually contain a module.
	//
	// An empty slot can exist temporarily after a module has been unloaded
	// but before/re-using its free index.
	// ------------------------------------------------------------------------

	module := &registry.modules[handle.index]

	if module.handle.index != handle.index {
		return nil, false
	}

	if module.handle.generation != handle.generation {
		return nil, false
	}

	if module.state == Load_State.Unloaded || module.state == Load_State.Failed {
		return nil, false
	}

	return module, true
}

// resolve a dependency name to a registered module. Version validation is seperate.
@(private)
module_find_dependency :: proc(
	registry: ^Module_Registry,
	dependency: DLL_Dependency,
) -> (
	ModuleHandle,
	bool,
) {

	if registry == nil || !registry.initialized {
		return INVALID_MODULE_HANDLE, false
	}

	if dependency.name == nil {
		return INVALID_MODULE_HANDLE, false
	}

	name := string(dependency.name)

	if len(name) == 0 {
		return INVALID_MODULE_HANDLE, false
	}

	return module_find(registry, name)
}

// dependency version validation
@(private)
module_version_satisfies_dependency :: proc(
	module: ^Loaded_Module,
	dependency: DLL_Dependency,
) -> bool {

	if module == nil {
		return false
	}

	return version_satisfies(module.api.identity.version, dependency)
}
// Recursive graph traversal -> dependency solve
@(private)
module_resolve_visit :: proc(registry: ^Module_Registry, handle: ModuleHandle) -> bool {

	if registry == nil {
		return false
	}

	if !module_is_valid(registry, handle) {
		return false
	}

	// ------------------------------------------------------------------------
	// Get the module's slot.
	// ------------------------------------------------------------------------

	module, ok := module_registry_get(registry, handle)

	if !ok {
		return false
	}

	index := handle.index

	// ------------------------------------------------------------------------
	// Check graph state.
	// ------------------------------------------------------------------------

	state := registry.dependency_state[index]

	switch state {

	case .Visited:
		// Already completely resolved.
		return true

	case .Visiting:
		// We encountered a module already on the DFS stack.
		//
		// Therefore we have a dependency cycle.
		log.error("Cyclic module dependency detected at '%s'.", module.api.identity.name)

		return false

	case .Unvisited:
	// Continue below.
	}

	// ------------------------------------------------------------------------
	// Mark module as currently being resolved.
	// ------------------------------------------------------------------------

	registry.dependency_state[index] = .Visiting

	// ------------------------------------------------------------------------
	// Resolve every dependency.
	// ------------------------------------------------------------------------

	dependency_count := module.api.dependency_count

	if dependency_count > 0 && module.api.dependencies == nil {

		log.error(
			"Module '%s' reports %d dependencies but has a null dependency array.",
			module.api.identity.name,
			dependency_count,
		)

		registry.dependency_state[index] = .Unvisited

		return false
	}

	for i: u32 = 0; i < dependency_count; i += 1 {

		dependency := module.api.dependencies[i]

		// --------------------------------------------------------------------
		// Find dependency.
		// --------------------------------------------------------------------

		dependency_handle, found := module_find_dependency(registry, dependency)

		if !found {

			if dependency.optional {
				log.warn(
					"Optional dependency '%s' for module '%s' ",
					"is not loaded.",
					dependency.name,
					module.api.identity.name,
				)

				continue
			}

			log.error(
				"Required dependency '%s' for module '%s' ",
				"is not loaded.",
				dependency.name,
				module.api.identity.name,
			)

			registry.dependency_state[index] = .Unvisited

			return false
		}

		// --------------------------------------------------------------------
		// Validate dependency version.
		// --------------------------------------------------------------------

		dependency_module, valid := module_registry_get(registry, dependency_handle)

		if !valid {
			log.error(
				"Dependency '%s' for module '%s' resolved to an invalid ",
				"module handle.",
				dependency.name,
				module.api.identity.name,
			)

			registry.dependency_state[index] = .Unvisited

			return false
		}

		if !module_version_satisfies_dependency(dependency_module, dependency) {

			if dependency.optional {
				log.warn(
					"Optional dependency '%s' for module '%s' ",
					"does not satisfy its version requirement.",
					dependency.name,
					module.api.identity.name,
				)

				continue
			}

			log.error(
				"Dependency '%s' for module '%s' does not satisfy ",
				"its version requirement.",
				dependency.name,
				module.api.identity.name,
			)

			registry.dependency_state[index] = .Unvisited

			return false
		}

		// --------------------------------------------------------------------
		// Recursively resolve dependency.
		// --------------------------------------------------------------------

		if !module_resolve_visit(registry, dependency_handle) {
			registry.dependency_state[index] = .Unvisited
			return false
		}
	}

	// ------------------------------------------------------------------------
	// All dependencies are resolved.
	// ------------------------------------------------------------------------

	registry.dependency_state[index] = .Visited

	// ------------------------------------------------------------------------
	// Post-order insertion.
	//
	// Dependencies are therefore placed before the module that depends on
	// them.
	// ------------------------------------------------------------------------

	append(&registry.dependency_order, handle)

	return true
}

// public resolver
module_resolve_dependencies :: proc(registry: ^Module_Registry) -> bool {
	if registry == nil || !registry.initialized do return false
	// ------------------------------------------------------------------------
	// Clear previous resolution state.
	// ------------------------------------------------------------------------
	resize(&registry.dependency_order, 0)

	required_state_count := len(registry.modules)

	if len(registry.dependency_state) != required_state_count {
		resize(&registry.dependency_state, required_state_count)
	}

	for i := 0; i < len(registry.dependency_state); i += 1 {
		registry.dependency_state[i] = .Unvisited
	}

	// ------------------------------------------------------------------------
	// Resolve every registered module.
	// ------------------------------------------------------------------------
	for i := 1; i < len(registry.modules); i += 1 {
		module := &registry.modules[i]
		// Slot is empty.
		if module.state == Load_State.Unloaded || module.state == Load_State.Failed do continue
		handle := module.handle
		if !module_resolve_visit(registry, handle) {
			resize(&registry.dependency_order, 0)
			log.error("Module dependency resolution failed.")
			return false
		}
	}

	log.info(
		"Module dependency resolution complete. %d modules in load order.",
		len(registry.dependency_order),
	)

	return true
}
// ============================================================================
// GET MODULE LOAD ORDER
// ============================================================================
//
// Returns the resolved dependency order.
//
// The returned slice belongs to the registry and must not be modified.
// Dependencies always appear before their dependents.
// ============================================================================
module_get_dependency_order :: proc(registry: ^Module_Registry) -> []ModuleHandle {
	if registry == nil || !registry.initialized {
		return nil
	}
	return registry.dependency_order[:]
}
// a reliable way to release a module slot.
@(private)
module_registry_remove_lookup :: proc(registry: ^Module_Registry, handle: ModuleHandle) {
	if registry == nil {return}
	module, ok := module_registry_get(registry, handle)
	if !ok {return}
	// ------------------------------------------------------------------------
	// Remove name lookup.
	// ------------------------------------------------------------------------
	if module.api.identity.name != nil {
		name := string(module.api.identity.name)
		if existing, found := registry.by_name[name]; found {
			if existing == handle {
				delete_key(&registry.by_name, name)
			}
		}
	}
	// ------------------------------------------------------------------------
	// Remove type lookup.
	// ------------------------------------------------------------------------
	module_type := module.api.identity.type
	handles := &registry.by_type[module_type]
	for i := 0; i < len(handles^); i += 1 {
		if handles[i] == handle {
			unordered_remove(handles, i)
			break
		}
	}
}
@(private)
module_registry_release_slot :: proc(registry: ^Module_Registry, handle: ModuleHandle) -> bool {
	if registry == nil || !registry.initialized {return false}
	module, ok := module_registry_get(registry, handle)
	if !ok {return false}
	// A module must not still have a loaded DLL when its registry slot is released.
	if module.state != Load_State.Unloaded {
		log.error(
			"Cannot release module slot [%d:%d]: module is not unloaded.",
			handle.index,
			handle.generation,
		)
		return false
	}
	// Remove lookup entries.
	module_registry_remove_lookup(registry, handle)
	// Destroy module registration.
	module_registration_destroy(&module.registration)
	if handle.index < u32(len(registry.dependency_state)){
		registry.dependency_state[handle.index] = .Unvisited}
		registry.modules[handle.index] = Loaded_Module{}
		append(&registry.free_indices, handle.index)
	return true
}
// registration collection
@(private)
module_collect_registration :: proc(registry: ^Module_Registry, handle: ModuleHandle) -> bool {
	if registry == nil || !registry.initialized {
		return false
	}
	module, ok := module_registry_get(registry, handle)
	if !ok {
		return false
	}
	if module.state != Load_State.Registered {
		log.error(
			"Cannot collect registration for module '%s': invalid state.",
			module.api.identity.name,
		)
		return false
	}
	// Construct module context.
	module.ctx.self = handle
	module.ctx.module_registry = registry
	// The service registry is supplied later from Core's global runtime state.
	// for now, leave the existing value intact if it has already been set
	// during module loading.
	module.ctx.registration = &GLOBAL_MODULE_REGISTRATION_API
	// Call the module's registration entry point.
	if module.api.register != nil {
		if !module.api.register(&module.ctx) {
			log.error("Module '%s' failed registration.", module.api.identity.name)
			module.state = Load_State.Failed
			return false
		}
	}
	log.info("Collected registration for module '%s'.", module.api.identity.name)

	return true
}
@(private)
module_collect_by_type :: proc(registry: ^Module_Registry, module_type: Module_Type, allocator: mem.Allocator) -> [dynamic]ModuleHandle {
	result := make([dynamic]ModuleHandle, 0, allocator)
	if registry == nil || !registry.initialized do return result
	for handle in registry.by_type[module_type] {
		if module_is_valid(registry, handle) {append(&result, handle)}
	}
	return result
}

// ======================
// Module Library Loading
//
// Module Lib
// Runtime representation of a module loaded from a DLL.
//
// Module_Loader is responsible for the DLL boundary.
// Module_Registry remains responsible for module identity, handles,
// dependencies, and registration state.

Module_Lib :: struct {
	lib: Loaded_Lib,
	handle: ModuleHandle,
}

Module_Runtime :: struct {
	handle: ModuleHandle,
	Library: Loaded_Lib,
	ctx: Core_Lib_Context,
}

module_lib_load :: proc(module: ^Module_Lib, path: string, ctx: ^Lib_Context) -> bool {
	if module == nil || ctx == nil do return false
	// already loaded.
	if module.lib.state != .Unloaded do return false

	// load the physical library and execute it's load callback.
	if !loaded_lib_load(&module.lib, ctx, path) {
		log.error("[Module] Failed to load library:", path)
		return false
	}

	// Obtain the API descriptor.
	descriptor := loaded_lib_get_descriptor(&module.lib)
	if descriptor == nil {
		log.error("[Module] Has no descriptor:", path)
		loaded_lib_shutdown(&module.lib, ctx)
		return false
	}

	// This Lib must actually identify itself as a module.
	if descriptor.lib_type != .Module {
		log.error("[Module] Is not a module:", path)
		loaded_lib_shutdown(&module.lib, ctx)
		return false
	}

	log.info("[Module] Loaded:", path)
	return true
}

module_lib_register :: proc(module: ^Module_Lib, ctx: ^Lib_Context) -> bool {
	if module == nil || ctx == nil do return false
	if module.lib.state != .Loaded do return false
	if !loaded_lib_register(&module.lib, ctx) {
		log.error("[Module] Registration failed")
		loaded_lib_shutdown(&module.lib, ctx)
		return false
	}
	return true
}

module_lib_activate :: proc(module: ^Module_Lib, ctx: ^Lib_Context) -> bool {
	if module == nil || ctx == nil do return false
	if module.lib.state != .Registered do return false
	if !loaded_lib_activate(&module.lib, ctx) {
		log.error("[Module] Activation failed")
		return false
	}
	return true
}

module_lib_deactivate :: proc(module: ^Module_Lib, ctx: ^Lib_Context) -> bool {
	if module == nil || ctx == nil do return false
	return loaded_lib_deactivate(&module.lib, ctx)
}

module_lib_unload :: proc(module: ^Module_Lib, ctx: ^Lib_Context) -> bool {
	if module == nil || ctx == nil do return false
	if module.lib.state == .Active do return false
	ok := loaded_lib_unload(&module.lib, ctx)
	if !ok {module.handle = ModuleHandle{}}
	return ok
}

module_lib_shutdown :: proc(module: ^Module_Lib, ctx: ^Lib_Context) {
	if module == nil || ctx == nil do return
	loaded_lib_shutdown(&module.lib, ctx)
	module.handle = ModuleHandle{}
}

// Accessors
module_lib_get_api :: proc(module: ^Module_Lib) -> ^LIB_API {
	if module == nil do return nil
	return loaded_lib_get_api(&module.lib)
}
module_lib_get_descriptor :: proc(module: ^Module_Lib) -> ^Lib_Descriptor {	
	if module == nil do return nil
	return loaded_lib_get_descriptor(&module.lib)
}
module_lib_is_active :: proc(module: ^Module_Lib) -> bool {
	if module == nil do return false
	return loaded_lib_is_active(&module.lib)
}