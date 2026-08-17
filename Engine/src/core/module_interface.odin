// Engine\src\Core\module_interface.odin
package Core

import "core:dynlib"
import "core:flags/example"
import "core:log"
import "core:mem"

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

//
Module_Registry :: struct {
	allocator:        mem.Allocator,
	modules:          [dynamic]Loaded_Module,
	generations:      [dynamic]u32,
	free_indices:     [dynamic]u32,
	// Dependency resolution
	dependency_order: [dynamic]ModuleHandle,
	dependency_state: [dynamic]Module_Visit_State,
	// Registration collection
	registrations:    [dynamic]ModuleHandle,
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

Plugin_Registry :: struct {
	Plugins:      [dynamic]Loaded_Module,
	free_indices: [dynamic]u32,
	by_name:      map[string]PluginHandle,
	by_type:      [Module_Type][dynamic]PluginHandle,
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
	name:         cstring,
	version:      Version,
	author:       cstring,
	description:  cstring,
	type:         Module_Type,
	flags:        Module_Flags,
	capabilities: Module_Capabilities,
}
Module_Capabilities :: bit_set[Module_Capability]

// ============================================================================
// MODULE DEPENDENCY
// ============================================================================

Module_Dependency :: struct {
	name:            cstring,
	min_version:     Version,
	max_version:     Version,
	has_min_version: bool,
	has_max_version: bool,
	optional:        bool,
}

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
version_satisfies :: proc(version: Version, dependency: Module_Dependency) -> bool {

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
	// Core-owned allocator.
	allocator:       rawptr,
	module_registry: rawptr,
	// runtime systems.
	scheduler:       rawptr,
	services:        rawptr,
	events:          rawptr,
	//  module registration.
	registration:    rawptr,
}

// ============================================================================
// MODULE API
// ============================================================================
// This is the actual ABI exposed by the DLL.
// ============================================================================

Module_API :: struct {
	api_version:      u32,
	identity:         Module_Identity,
	dependencies:     [^]Module_Dependency,
	dependency_count: u32,
	// DLL lifecycle.
	// load module-owned state/resources
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

// ============================================================================
// LOADED MODULE/PLUGIN
// ============================================================================

Loaded_Module :: struct {
	handle:       ModuleHandle,
	library:      dynlib.Library,
	api:          Module_API,
	ctx:          Module_Context,
	state:        Module_State,
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

	mod.state = Module_State.Loaded


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
	if mod.state != Module_State.Loaded &&
	mod.state != Module_State.Registered {return}
	if mod.api.unload != nil {mod.api.unload(&mod.ctx)}
	if mod.library != nil {dynlib.unload_library(mod.library)}
	mod^ = {}
}
// ============================================================================
// UNLOAD ALL MODULES
// ============================================================================
//
// Unloads modules in reverse dependency order.
//
// Modules must already be deactivated before this function is called.
// ============================================================================
@(private)
module_unload_all :: proc(registry: ^Module_Registry) -> bool {
	if registry == nil || !registry.initialized {return false}
	if len(registry.dependency_order) == 0 {return true}
	for i := len(registry.dependency_order)-1; i >= 0; i -= 1 {
		handle := registry.dependency_order[i]
		module, ok := module_registry_get(registry, handle)
		if !ok {continue}
		// never unload an active module.
		if module.state == Module_State.Active {
			log.error("Cannot unload active module: %s.", "Module must be deactivated first.",
			module.api.identity.name)
			return false
		}
		if module.state != Module_State.Registered &&
		module.state != Module_State.Unloaded {continue}
		log.info("Unloading module: %s.", module.api.identity.name)
		unload_module(module)
		// Release the registry slot.
		module_registry_release_slot(registry, handle)
	}
	clear(&registry.dependency_order)
	log.info("All modules unloaded.")
	return true
}
// ============================================================================
// UPDATE
// ============================================================================
update_module :: proc(mod: ^Loaded_Module, dt: f32) {
	if mod == nil || !mod.state.Loaded {return}
	if mod.api.update != nil {mod.api.update(&mod.ctx, dt)}
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
	registry.registrations = make([dynamic]Module_Registration, 0, allocator)
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
	if registry == nil || !registry.initialized {
		return
	}

	// Destroy module-owned registrations.
	for i := 0; i < len(registry.modules); i += 1 {
		module := &registry.modules[i]
		if module.state != Module_State.Unloaded && module.state != Module_State.Failed {
			module_registration_destroy(&module.registration)
		}
	}
	// destroy dependency state.
	delete(registry.dependency_order)
	delete(registry.dependency_state)
	// destroy registration ordering
	delete(registry.registrations)
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
module_register_loaded :: proc(
	registry: ^Module_Registry,
	module: Loaded_Module,
) -> (
	ModuleHandle,
	bool,
) {

	if registry == nil || !registry.initialized {
		return INVALID_MODULE_HANDLE, false
	}

	// Validate module state
	if module.state != Module_State.Loaded {
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
		registry.free_indices = registry.free_indices[:last]
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
	module.state = Module_State.Registered

	registry.modules[index] = module
	// Name lookup
	registry.by_name[name] = handle
	// Type lookup
	append(&registry.by_type[module.api.identity.type], handle)
	// Registration collection
	append(&registry.registrations, module.registration)
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

	if module.state == Module_State.Unloaded || module.state == Module_State.Failed {
		return nil, false
	}

	return module, true
}

// resolve a dependency name to a registered module. Version validation is seperate.
@(private)
module_find_dependency :: proc(
	registry: ^Module_Registry,
	dependency: Module_Dependency,
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
	dependency: Module_Dependency,
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

	if registry == nil || !registry.initialized {
		return false
	}

	// ------------------------------------------------------------------------
	// Clear previous resolution state.
	// ------------------------------------------------------------------------

	clear(&registry.dependency_order)

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
		if module.state == Module_State.Unloaded || module.state == Module_State.Failed {
			continue
		}

		handle := module.handle

		if !module_resolve_visit(registry, handle) {
			clear(&registry.dependency_order)

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

	if registry == nil || !registry.initialized {
		return false
	}

	module, ok := module_registry_get(registry, handle)

	if !ok {
		return false
	}

	// ------------------------------------------------------------------------
	// A module must not still have a loaded DLL when its registry slot
	// is released.
	// ------------------------------------------------------------------------

	if module.state != Module_State.Unloaded {
		log.error(
			"Cannot release module slot [%d:%d]: module is not unloaded.",
			handle.index,
			handle.generation,
		)

		return false
	}

	// ------------------------------------------------------------------------
	// Remove lookup entries.
	// ------------------------------------------------------------------------

	module_registry_remove_lookup(registry, handle)

	// ------------------------------------------------------------------------
	// Destroy module registration.
	// ------------------------------------------------------------------------

	module_registration_destroy(&module.registration)

	// ------------------------------------------------------------------------
	// Clear module storage.
	// ------------------------------------------------------------------------

	registry.modules[handle.index] = Loaded_Module{}

	// ------------------------------------------------------------------------
	// Return slot to free list.
	// ------------------------------------------------------------------------

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
	if module.state != Module_State.Registered {
		log.error(
			"Cannot collect registration for module '%s': invalid state.",
			module.api.identity.name,
		)
		return false
	}

	// Call the module's registration entry point.
	module.ctx.registration = &module.registration
	if module.api.register != nil {
		if !module.api.register(&module.ctx) {
			log.error("Module '%s' failed registration.", module.api.identity.name)
			module.state = Module_State.Failed
			return false
		}
	}
	// Add module to registration order.
	append(&registry.registrations, handle)
	log.info("Collected registration for module '%s'.", module.api.identity.name)

	return true
}
// ============================================================================
// REGISTER ALL MODULES
// ============================================================================
//
// Calls the registration callback for every module in dependency order.
//
// Registration is intentionally separate from activation.
//
// A module's register() callback should:
//
//     - declare/register services
//     - declare/register systems
//     - declare resources
//     - declare events
//
// It should NOT start runtime execution yet.
//
// This allows Core to collect the complete module graph before the scheduler
// and other runtime systems are constructed.
// ============================================================================
@(private)
module_register_all :: proc(registry: ^Module_Registry) -> bool {
	if registry == nil || !registry.initialized {return false}
	if len(registry.dependency_order) == 0 {
		log.info("No modules registered.")
		return true
	}
	// ------------------------------------------------------------------------
	// Clear any previous registration collection.
	//
	// Normally this should be empty because registration happens once during
	// initialization, but clearing it makes this function deterministic if
	// initialization is retried.
	// ------------------------------------------------------------------------
	for i := 0; i < len(registry.registrations); i += 1 {
		module_registration_destroy(&registry.registrations[i])
	}
	clear(&registry.registrations)
	// ------------------------------------------------------------------------
	// Register in dependency order.
	//
	// Because dependency_order is post-order DFS, dependencies appear before
	// modules that depend on them.
	// ------------------------------------------------------------------------
	for handle in registry.dependency_order {
		module, ok := module_registry_get(registry, handle)
		if !ok {
			log.error(
				"Cannot register module: dependency order contains invalid handle [%d:%d].",
				handle.index,
				handle.generation,
			)
			return false
		}
		// A module should be loaded immediately before registration.
		if module.state != Module_State.Loaded {
			log.error(
				"Cannot register module '%s': expected Loaded state, got %v",
				module.api.identity.name,
				module.state,
			)
			return false
		}
		// Prepare registration collection.
		module.registration = Module_Registration {
			module    = handle,
			services  = make([dynamic]Service_Registration, 0, registry.allocator),
			systems   = make([dynamic]System_Registration, 0, registry.allocator),
			resources = make([dynamic]Resource_Registration, 0, registry.allocator),
			events    = make([dynamic]Event_Registration, 0, registry.allocator),
		}
		// Call module registration callback.
		if module.api.register != nil {
			if !module.api.register(&module.ctx) {
				log.error("Module '%s' failed registration.", module.api.identity.name)
				module.state = Module_State.Failed
				module_registration_destroy(&module.registration)
				return false
			}
		}
		// Registration succeeded.
		module.state = Module_State.Registered
		append(&registry.registrations, handle)
		log.info(
			"Registered module: %s v%d.%d.%d",
			module.api.identity.name,
			module.api.identity.version.major,
			module.api.identity.version.minor,
			module.api.identity.version.patch,
		)
	}
	log.info("Module registration complete. %d modules registered.", len(registry.registrations))
	return true
}
@(private)
module_get_registration :: proc(
	registry: ^Module_Registry,
	handle: ModuleHandle,
) -> (
	^Module_Registration,
	bool,
) {
	module, ok := module_registry_get(registry, handle)
	if !ok {return nil, false}
	if module.state == Module_State.Unloaded ||
	   module.state == Module_State.Failed {return nil, false}
	return &module.registration, true
}
// ============================================================================
// ACTIVATE MODULE
// ============================================================================
//
// Activates one registered module.
//
// Activation is deliberately separate from registration. Registration
// declares the module's contributions to Core; activation starts the module's
// actual runtime behavior.
//
// The caller is responsible for ensuring that global runtime infrastructure
// such as the scheduler has already been constructed.
// ============================================================================
@(private)
module_activate :: proc(registry: ^Module_Registry, handle: ModuleHandle) -> bool {
	if registry == nil || !registry.initialized {return false}

	module, ok := module_registry_get(registry, handle)
	if !ok {log.error("Cannot activate module [%d:%d]: invalid handle.", handle.index, handle.generation)
		return false}
	// Activation is only valid after registration.
	if module.state !=
	   Module_State.Registered {log.error("Cannot activate module '%s': expected Registered state, got %v.", module.api.identity.name, module.state)
		return false}
	// ------------------------------------------------------------------------
	// Nothing to call if the module does not provide an activation callback.
	//
	// A module without activate() is still considered successfully active.
	// This is useful for purely declarative modules.
	// ------------------------------------------------------------------------
	if module.api.activate != nil {
		if !module.api.activate(&module.ctx) {
			log.error("Module '%s' failed activation.", module.api.identity.name)
			module.state = Module_State.Failed
			return false
		}
	}
	// Now activation succeeded.
	module.state = Module_State.Active
	log.info(
		"Activated module: %s v%d.%d.%d",
		module.api.identity.name,
		module.api.identity.version.major,
		module.api.identity.version.minor,
		module.api.identity.version.patch,
	)
	return true
}
// ============================================================================
// ACTIVATE ALL MODULES
// ============================================================================
//
// Activates modules in dependency order.
//
// Because dependency_order contains dependencies before their dependents,
// every module's prerequisites will already be active when its activate()
// callback executes.
// ============================================================================
@(private)
module_activate_all :: proc(registry: ^Module_Registry) -> bool {
	if registry == nil || !registry.initialized {return false}
	// No resolved modules means there is nothing to activate.
	if len(registry.dependency_order) == 0 {
		log.info("No modules to activate.")
		return true
	}
	activated_count := 0
	// Activate each module in dependency order.
	for handle in registry.dependency_order {
		if !module_activate(registry, handle) {
			log.error("Failed to activate module '[%d:%d].", handle.index, handle.generation)

			// Roll back everything activated before the failure.
			for i := activated_count - 1; 1 >= 0; i -= 1 {
				rollback_handle := registry.dependency_order[i]
				module, valid := module_registry_get(registry, rollback_handle)
				if !valid {
					continue
				}
				if module.state == Module_State.Active {
					module_deactivate(registry, rollback_handle)
				}
			}
			return false
		}
		activated_count += 1
	}
	log.info("Module activation complete. %d modules activated.", len(registry.dependency_order))
	return true
}

// ============================================================================
// DEACTIVATE MODULE
// ============================================================================
//
// Deactivates one active module.
//
// Deactivation does not unload the DLL or destroy its registration data.
// The module remains Registered and can potentially be activated again.
// ============================================================================
@(private)
module_deactivate :: proc(
	registry: ^Module_Registry,
	handle: ModuleHandle,
) -> bool {
	if registry == nil || !registry.initialized {return false}
	module, ok := module_registry_get(registry, handle)
	if !ok {return false}
	if module.state != Module_State.Active {return false}
	if module.api.deactivate != nil {module.api.deactivate(&module.ctx)}
	module.state = Module_State.Registered
	log.info("Deactivated module: %s", module.api.identity.name)
	return true
}
// ============================================================================
// DEACTIVATE ALL MODULES
// ============================================================================
//
// Deactivates all active modules in reverse dependency order.
//
// Dependents are therefore stopped before the modules they depend upon.
// ============================================================================
@(private)
module_deactivate_all :: proc(
	registry: ^Module_Registry
) {
	if registry == nil || !registry.initialized {return}
	if len(registry.dependency_order) == 0  {return}
	for i := len(registry.dependency_order) -1; i >= 0; 1 -= 1 {
		handle := registry.dependency_order[i]
		module, ok := module_registry_get(registry, handle)
		if !ok {continue}
		if module.state != Module_State.Active {continue}
		module_deactivate(registry, handle)
	}
	log.info("All modules deactivated.")
}