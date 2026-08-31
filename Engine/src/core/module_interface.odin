// Engine\src\Core\module_interface.odin
package Core

import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:fmt"

import hm "core:container/handle_map"

// ============================================================================
// MODULE INTERFACE
// ============================================================================
//
// Every Bifrost engine module is a dynamically loaded provider of engine
// functionality.
//
// Modules = primary engine/runtime capabilities. They can provide systems,
// services, resources, events, etc.
//
// The only externally visible surface from this file is the registry type
// (passed into the SDK) and the Module_* types that flow through
// Module_Context. Everything else is package-internal.
// ============================================================================

// ============================================================================
// MODULE TYPES
// ============================================================================

// Module_Identity is the registry-side view of a module's identity.
// Constructed from the LIB descriptor in module_manager_load.
@(private)
Module_Identity :: struct {
	name:         string,
	version:      Version,
	type:         Lib_Type,
	flags:        Lib_Flags,
	capabilities: Component_Capabilities,
}

@(private)
Module_Descriptor :: struct {
	identity:         Module_Identity,
	dependencies:     [dynamic]Lib_Dependency,
	dependency_count: u32,
}

// Lib_Visit_State drives the DFS cycle detector in dependency resolution.
@(private)
Lib_Visit_State :: enum {
	Unvisited, // module has not been examined.
	Visiting,  // currently somewhere in the DFS stack.
	Visited,   // completely resolved.
}

// ============================================================================
// MODULE CONTEXT (handed to modules during load/register/activate/etc.)
// ============================================================================

Module_Context :: struct {
	api_version:      u32,
	allocator:        rawptr,
	self:             ModuleHandle,
	module_registry:  rawptr,
	service_registry: rawptr,
	scheduler:        rawptr,
	events:           rawptr,
	registration:     ^Module_Registration_API,
	// Component-type agnostic host context. Owned by-value so the DLL can
	// safely hold a pointer to it for the lifetime of the module.
	// Modules use lib_context_query() to obtain typed interfaces.
	lib_context:      Lib_Context,
}

Module_Registration_API :: struct {
	add_service:  proc(ctx: ^Module_Context, registration: Service_Registration) -> bool,
	add_system:   proc(ctx: ^Module_Context, registration: System_Registration) -> bool,
	add_resource: proc(ctx: ^Module_Context, registration: Resource_Registration) -> bool,
	add_event:    proc(ctx: ^Module_Context, registration: Event_Registration) -> bool,
}

// ============================================================================
// MODULE REGISTRY
// ============================================================================

Module_Registry :: struct {
	allocator:        mem.Allocator,
	slots:            hm.Dynamic_Handle_Map(Loaded_Module, ModuleHandle),
	// dependency_order is a flat array of handles in topological order.
	dependency_order: [dynamic]ModuleHandle,
	// dependency_state is indexed by handle.idx (sized to items.len).
	dependency_state: [dynamic]Lib_Visit_State,
	initialized:      bool,
	by_name:          map[string]ModuleHandle,
	by_type:          [Lib_Type][dynamic]ModuleHandle,
}

@(private)
Loaded_Module :: struct {
	handle:       ModuleHandle,
	lib:          Loaded_Lib,             // Generic physical library.
	descriptor:   Module_Descriptor,      // Module-specific metadata exposed by the DLL.
	ctx:          Module_Context,         // Context supplied to the module lifecycle callbacks.
	state:        Component_State,        // Module lifecycle state
	registration: Module_Registration,    // Registry-owned registrations.
	// Heap-allocated Core_Lib_Context backing ctx.lib_context.user_data.
	// Owned by the manager; freed in module_manager_unload_all.
	core_context:  ^Core_Lib_Context,
}

@(private)
Module_Registration :: struct {
	module:    ModuleHandle,
	services:  [dynamic]Service_Registration,
	systems:   [dynamic]System_Registration,
	resources: [dynamic]Resource_Registration,
	events:    [dynamic]Event_Registration,
}

// ============================================================================
// MODULE MANAGER (public surface — engine drives lifecycle through this)
// ============================================================================

Module_Manager :: struct {
	allocator:   mem.Allocator,
	registry:    Module_Registry,
	initialized: bool,
}

// ============================================================================
// REGISTRY HELPERS
// ============================================================================

// module_registry_get is the canonical handle validation + slot lookup.
// Used by every function that needs to dereference a ModuleHandle.
@(private)
module_registry_get :: proc(
	registry: ^Module_Registry,
	handle: ModuleHandle,
) -> (
	^Loaded_Module,
	bool,
) {
	if registry == nil || !registry.initialized do return nil, false
	return hm.get(&registry.slots, handle)
}

@(private)
loaded_module_get_api :: proc(module: ^Loaded_Module) -> ^LIB_API {
	if module == nil do return nil
	return loaded_lib_get_api(&module.lib)
}

@(private)
module_registry_init :: proc(registry: ^Module_Registry, allocator: mem.Allocator) -> bool {
	if registry == nil {return false}

	if registry.initialized {
		log.warn("Module registry is already initialized.")
		return false
	}

	registry.allocator = allocator

	hm.dynamic_init(&registry.slots, allocator)
	registry.dependency_order = make([dynamic]ModuleHandle, 0, allocator)
	registry.dependency_state = make([dynamic]Lib_Visit_State, 0, allocator)
	registry.by_name = make(map[string]ModuleHandle, allocator)
	for lib_type in Lib_Type {
		registry.by_type[lib_type] = make([dynamic]ModuleHandle, 0, allocator)
	}
	registry.initialized = true
	log.info("Module registry initialized.")
	return true
}

@(private)
module_registry_destroy :: proc(registry: ^Module_Registry) {
	if registry == nil || !registry.initialized {return}

	// Destroy module-owned registrations.
	it := hm.dynamic_iterator_make(&registry.slots)
	for module, _ in hm.iterate(&it) {
		if module.state != Component_State.Unloaded && module.state != Component_State.Failed {
			module_registration_destroy(&module.registration)
		}
	}

	delete(registry.dependency_order)
	delete(registry.dependency_state)
	for lib_type in Lib_Type {
		delete(registry.by_type[lib_type])
	}
	delete(registry.by_name)
	hm.dynamic_destroy(&registry.slots)

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

// ============================================================================
// REGISTRATION (assigns handle + slot to a Loaded_Module)
// ============================================================================

// module_register_loaded adds the module to the handle map and seeds the
// lookup tables. Caller is responsible for filling lib/descriptor/ctx first.
@(private)
module_register_loaded :: proc(
	registry: ^Module_Registry,
	module: ^Loaded_Module,
) -> (
	out_handle: ModuleHandle,
	ok: bool,
) {
	if registry == nil || !registry.initialized do return INVALID_MODULE_HANDLE, false
	if module == nil do return INVALID_MODULE_HANDLE, false
	if module.state != .Loaded {
		log.error("Cannot register module that is not in loaded state.")
		return INVALID_MODULE_HANDLE, false
	}

	if len(module.descriptor.identity.name) == 0 {
		log.error("Cannot register module without name.")
		return INVALID_MODULE_HANDLE, false
	}

	name := module.descriptor.identity.name

	// Reject duplicate module names.
	if existing, found := registry.by_name[name]; found {
		if _, valid := hm.get(&registry.slots, existing); valid {
			log.error("Module with name '%s' already exists.", name)
			return INVALID_MODULE_HANDLE, false
		}
		// Stale by_name entry: drop it.
		delete_key(&registry.by_name, name)
	}

	handle, alloc_err := hm.add(&registry.slots, module^)
	if alloc_err != nil {
		log.error("Cannot register module '%s': allocator failure (%v).", name, alloc_err)
		return INVALID_MODULE_HANDLE, false
	}

	// Re-fetch the now-resident slot and seed per-slot state. We can't
	// pass a pre-built `registration` through hm.add because the handle_map
	// only takes `T` (Loaded_Module) and would copy it into the slot before
	// we know the handle; handle_map then overwrites ptr.handle.{idx,gen}.
	resident, found := hm.get(&registry.slots, handle)
	if !found {
		log.error("Module '%s': handle map add succeeded but lookup failed (impossible).", name)
		return INVALID_MODULE_HANDLE, false
	}
	resident.registration = Module_Registration {
		module = handle,
	}
	resident.ctx.self = handle
	resident.state = .Registered

	registry.by_name[name] = handle

	// Type lookup.
	module_type := module.descriptor.identity.type
	append(&registry.by_type[module_type], handle)

	log.info(
		"registered module: %s v%d.%d.%d [%d:%d]",
		name,
		module.descriptor.identity.version.major,
		module.descriptor.identity.version.minor,
		module.descriptor.identity.version.patch,
		handle.idx,
		handle.gen,
	)

	return handle, true
}

// ============================================================================
// DEPENDENCY RESOLUTION
// ============================================================================

// module_resolve_dependencies walks the registered modules in DFS, building
// dependency_order as a post-order list (dependencies first).
@(private)
module_resolve_dependencies :: proc(registry: ^Module_Registry) -> bool {
	if registry == nil || !registry.initialized do return false

	resize(&registry.dependency_order, 0)

	// dependency_state is indexed by handle.idx, so it must cover every
	// possible idx currently held by the map (including holes from the
	// freelist).
	required_state_count := registry.slots.items.len
	if len(registry.dependency_state) != required_state_count {
		resize(&registry.dependency_state, required_state_count)
	}
	for i := 0; i < len(registry.dependency_state); i += 1 {
		registry.dependency_state[i] = .Unvisited
	}

	it := hm.dynamic_iterator_make(&registry.slots)
	for module, handle in hm.iterate(&it) {
		if module.state == Component_State.Unloaded || module.state == Component_State.Failed do continue
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

@(private)
module_resolve_visit :: proc(registry: ^Module_Registry, handle: ModuleHandle) -> bool {
	if registry == nil {
		return false
	}

	if !module_is_valid(registry, handle) {
		return false
	}

	module, ok := module_registry_get(registry, handle)
	if !ok do return false

	if int(handle.idx) >= len(registry.dependency_state) {
		log.error("Module handle [%d:%d] index out of range for dependency state.", handle.idx, handle.gen)
		return false
	}
	state := registry.dependency_state[handle.idx]

	switch state {
	case .Visited:
		return true
	case .Visiting:
		log.error("Cyclic module dependency detected at '%s'.", module.descriptor.identity.name)
		return false
	case .Unvisited:
	}

	registry.dependency_state[handle.idx] = .Visiting

	dependency_count := module.descriptor.dependency_count

	if dependency_count > 0 && module.descriptor.dependencies == nil {
		log.error(
			"Module '%s' reports %d dependencies but has a null dependency array.",
			module.descriptor.identity.name,
			dependency_count,
		)
		registry.dependency_state[handle.idx] = .Unvisited
		return false
	}

	for i: u32 = 0; i < dependency_count; i += 1 {
		dependency := module.descriptor.dependencies[i]

		dependency_handle, found := module_find_dependency(registry, dependency)
		if !found {
			if dependency.optional {
				log.warn(
					"Optional dependency '%s' for module '%s' is not loaded.",
					dependency.name,
					module.descriptor.identity.name,
				)
				continue
			}

			log.error(
				"Required dependency '%s' for module '%s' is not loaded.",
				dependency.name,
				module.descriptor.identity.name,
			)
			registry.dependency_state[handle.idx] = .Unvisited
			return false
		}

		dependency_module, valid := module_registry_get(registry, dependency_handle)
		if !valid {
			log.error(
				"Dependency '%s' for module '%s' resolved to an invalid module handle.",
				dependency.name,
				module.descriptor.identity.name,
			)
			registry.dependency_state[handle.idx] = .Unvisited
			return false
		}

		if !module_version_satisfies_dependency(dependency_module, dependency) {
			if dependency.optional {
				log.warn(
					"Optional dependency '%s' for module '%s' does not satisfy its version requirement.",
					dependency.name,
					module.descriptor.identity.name,
				)
				continue
			}

			log.error(
				"Dependency '%s' for module '%s' does not satisfy its version requirement.",
				dependency.name,
				module.descriptor.identity.name,
			)
			registry.dependency_state[handle.idx] = .Unvisited
			return false
		}

		if !module_resolve_visit(registry, dependency_handle) {
			registry.dependency_state[handle.idx] = .Unvisited
			return false
		}
	}

	registry.dependency_state[handle.idx] = .Visited

	// Post-order insertion: dependencies appear before dependents.
	append(&registry.dependency_order, handle)

	return true
}

// module_find_dependency resolves a dependency name to a registered module.
@(private)
module_find_dependency :: proc(
	registry: ^Module_Registry,
	dependency: Lib_Dependency,
) -> (
	ModuleHandle,
	bool,
) {
	if registry == nil || !registry.initialized do return INVALID_MODULE_HANDLE, false
	if dependency.name == nil do return INVALID_MODULE_HANDLE, false

	name := string(dependency.name)
	if len(name) == 0 do return INVALID_MODULE_HANDLE, false

	return module_find(registry, name)
}

@(private)
module_version_satisfies_dependency :: proc(
	module: ^Loaded_Module,
	dependency: Lib_Dependency,
) -> bool {
	if module == nil do return false
	return version_satisfies(module.descriptor.identity.version, dependency)
}

// module_get_dependency_order returns the resolved dependency order.
// The slice belongs to the registry and must not be modified.
@(private)
module_get_dependency_order :: proc(registry: ^Module_Registry) -> []ModuleHandle {
	if registry == nil || !registry.initialized {
		return nil
	}
	return registry.dependency_order[:]
}

// ============================================================================
// SLOT RELEASE
// ============================================================================

@(private)
module_registry_remove_lookup :: proc(registry: ^Module_Registry, handle: ModuleHandle) {
	if registry == nil {return}
	module, ok := hm.get(&registry.slots, handle)
	if !ok {return}

	if len(module.descriptor.identity.name) > 0 {
		name := module.descriptor.identity.name
		if existing, found := registry.by_name[name]; found {
			if existing == handle {
				delete_key(&registry.by_name, name)
			}
		}
	}

	module_type := module.descriptor.identity.type
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
	module, ok := hm.get(&registry.slots, handle)
	if !ok {return false}

	if module.state != Component_State.Unloaded {
		log.error(
			"Cannot release module slot [%d:%d]: module is not unloaded.",
			handle.idx,
			handle.gen,
		)
		return false
	}

	module_registry_remove_lookup(registry, handle)
	module_registration_destroy(&module.registration)
	if int(handle.idx) < len(registry.dependency_state) {
		registry.dependency_state[handle.idx] = .Unvisited
	}
	_, _ = hm.remove(&registry.slots, handle)
	return true
}

// module_collect_by_type gathers the currently-valid module handles of a
// given Lib_Type into a caller-owned dynamic array.
@(private)
module_collect_by_type :: proc(
	registry: ^Module_Registry,
	lib_type: Lib_Type,
	allocator: mem.Allocator,
) -> [dynamic]ModuleHandle {
	result := make([dynamic]ModuleHandle, 0, allocator)
	if registry == nil || !registry.initialized do return result
	for handle in registry.by_type[lib_type] {
		if module_is_valid(registry, handle) {append(&result, handle)}
	}
	return result
}

// ============================================================================
// MODULE MANAGER API
// ============================================================================
//
// The public surface used by engine.init/destroy.

module_manager_init :: proc(manager: ^Module_Manager, allocator: mem.Allocator) -> bool {
	if manager == nil do return false
	if manager.initialized {
		log.warn("Module manager is already initialized")
		return false
	}
	manager.allocator = allocator
	if !module_registry_init(&manager.registry, allocator) {
		log.warn("Failed to initialize module registry")
		manager.allocator = {}
		return false
	}
	manager.initialized = true
	log.info("Module manager initialized.")
	return true
}

module_manager_destroy :: proc(manager: ^Module_Manager) {
	if manager == nil || !manager.initialized do return
	module_manager_unload_all(manager)
	module_registry_destroy(&manager.registry)
	manager.allocator = {}
	manager.initialized = false
}

// module_manager_load loads a single DLL into the registry as a module.
module_manager_load :: proc(manager: ^Module_Manager, path: string) -> (ModuleHandle, bool) {
	if manager == nil || !manager.initialized do return INVALID_MODULE_HANDLE, false

	loaded := Loaded_Module{}

	// The Core_Lib_Context user_data must outlive the load() call so the
	// DLL can hold a pointer to it. Allocate it from the manager allocator
	// and stash it on Loaded_Module so we can free it in unload_all.
	core_context := new(Core_Lib_Context, manager.allocator)
	core_context.manager = cast(rawptr)manager
	loaded.core_context = core_context

	lib_context := Lib_Context {
		api       = &CORE_LIB_CONTEXT_API,
		user_data = cast(rawptr)core_context,
	}

	if !loaded_lib_load(&loaded.lib, &lib_context, path) {
		log.error("[Module] Failed to load library: %s", path)
		free(core_context, manager.allocator)
		return INVALID_MODULE_HANDLE, false
	}

	descriptor := loaded_lib_get_descriptor(&loaded.lib)
	if descriptor == nil {
		log.error("[Module] Library has no descriptor: %s", path)
		loaded_lib_shutdown(&loaded.lib, &lib_context)
		free(core_context, manager.allocator)
		return INVALID_MODULE_HANDLE, false
	}
	if descriptor.component_kind != .Module {
		log.error("[Module] Library is not a module: %s", path)
		loaded_lib_shutdown(&loaded.lib, &lib_context)
		free(core_context, manager.allocator)
		return INVALID_MODULE_HANDLE, false
	}

	identity := Module_Identity {
		name         = descriptor.name != nil ? string(descriptor.name) : "",
		version      = descriptor.version,
		type         = descriptor.type,
		flags        = descriptor.flags,
		capabilities = descriptor.capabilities,
	}
	loaded.descriptor.identity         = identity
	loaded.descriptor.dependency_count = descriptor.dependency_count
	if descriptor.dependency_count > 0 {
		loaded.descriptor.dependencies = make(
			[dynamic]Lib_Dependency,
			int(descriptor.dependency_count),
			manager.allocator,
		)
		for i in 0 ..< descriptor.dependency_count {
			loaded.descriptor.dependencies[i] = descriptor.dependencies[i]
		}
	}
	if loaded.descriptor.identity.name == "" {
		log.error("[Module] Library has no name: %s", path)
		loaded_lib_shutdown(&loaded.lib, &lib_context)
		free(core_context, manager.allocator)
		return INVALID_MODULE_HANDLE, false
	}

	loaded.ctx = Module_Context {
		api_version      = 1,
		allocator        = cast(rawptr)&manager.allocator,
		self             = INVALID_MODULE_HANDLE,
		module_registry  = cast(rawptr)&manager.registry,
		service_registry = nil,
		scheduler        = nil,
		events           = nil,
		registration     = &GLOBAL_MODULE_REGISTRATION_API,
		lib_context      = lib_context,
	}
	loaded.state = .Loaded

	// Advance the library lifecycle to .Registered BEFORE adding the slot
	// to the map. module_register_loaded adds the slot via hm.add, which
	// copies the struct; if lib.state were still .Loaded at that point the
	// stored copy would also be .Loaded and downstream loaded_lib_activate()
	// would fail its state check.
	if !loaded_lib_register(&loaded.lib, &lib_context) {
		log.error("[Module] Library register() failed: %s", path)
		loaded_lib_shutdown(&loaded.lib, &lib_context)
		free(core_context, manager.allocator)
		return INVALID_MODULE_HANDLE, false
	}

	handle, ok := module_register_loaded(&manager.registry, &loaded)
	if !ok {
		loaded_lib_shutdown(&loaded.lib, &lib_context)
		free(core_context, manager.allocator)
		return INVALID_MODULE_HANDLE, false
	}

	log.info(
		"[Module] Loaded module '%s' [%d:%d].",
		loaded.descriptor.identity.name,
		handle.idx,
		handle.gen,
	)

	return handle, true
}

module_manager_resolve :: proc(manager: ^Module_Manager) -> bool {
	if manager == nil || !manager.initialized do return false
	return module_resolve_dependencies(&manager.registry)
}

// module_manager_register is idempotent: module_manager_load already
// advances state to .Registered, so this proc is a no-op for the engine's
// normal load path. It exists for callers that load DLLs through some other
// route and need to bring the module into the .Registered state.
module_manager_register :: proc(manager: ^Module_Manager, handle: ModuleHandle) -> bool {
	if manager == nil || !manager.initialized do return false
	module, ok := module_registry_get(&manager.registry, handle)
	if !ok do return false

	if module.state != .Loaded && module.state != .Registered {
		log.error(
			"[Module] Cannot register module '%s': invalid state.",
			module.descriptor.identity.name,
		)
		return false
	}

	if module.state == .Loaded {
		if !loaded_lib_register(&module.lib, &module.ctx.lib_context) {
			log.error("[Module] Module '%s' failed registration.", module.descriptor.identity.name)
			module.state = Component_State.Failed
			return false
		}
		module.state = .Registered
	}
	return true
}

// module_manager_load_all is a convenience for callers (e.g. tests) that
// already know which DLLs to load. Engine uses module_manager_load_project
// instead, which discovers DLLs from project.toml.
module_manager_load_all :: proc(manager: ^Module_Manager, paths: []string) -> bool {
	if manager == nil || !manager.initialized do return false

	for path in paths {
		_, ok := module_manager_load(manager, path)
		if !ok {
			module_manager_unload_all(manager)
			return false
		}
	}

	if !module_manager_resolve(manager) {
		module_manager_unload_all(manager)
		return false
	}

	// Register in dependency order (module_manager_load already advances
	// state, so this is a no-op for those modules; the call is here for
	// callers that used a path that bypassed registration).
	order := module_get_dependency_order(&manager.registry)
	for handle in order {
		if !module_manager_register(manager, handle) {
			module_manager_unload_all(manager)
			return false
		}
	}
	return true
}

module_manager_activate_all :: proc(manager: ^Module_Manager) -> bool {
	if manager == nil || !manager.initialized do return false

	order := module_get_dependency_order(&manager.registry)
	for handle in order {
		module, ok := module_registry_get(&manager.registry, handle)
		if !ok {
			module_manager_deactivate_all(manager)
			return false
		}

		if module.state != .Registered {
			log.error(
				"[Module] Cannot activate '%s': invalid state.",
				module.descriptor.identity.name,
			)
			module_manager_deactivate_all(manager)
			return false
		}

		if !loaded_lib_activate(&module.lib, &module.ctx.lib_context) {
			log.error("[Module] Failed to activate '%s'.", module.descriptor.identity.name)
			module_manager_deactivate_all(manager)
			return false
		}

		module.state = .Active
	}
	return true
}

module_manager_deactivate_all :: proc(manager: ^Module_Manager) {
	if manager == nil || !manager.initialized do return
	order := module_get_dependency_order(&manager.registry)

	for i := len(order) - 1; i >= 0; i -= 1 {
		handle := order[i]
		module, ok := module_registry_get(&manager.registry, handle)
		if !ok do continue

		if module.state != .Active do continue
		loaded_lib_deactivate(&module.lib, &module.ctx.lib_context)
		module.state = .Registered
	}
}

module_manager_unload_all :: proc(manager: ^Module_Manager) {
	if manager == nil || !manager.initialized do return

	module_manager_deactivate_all(manager)

	order := module_get_dependency_order(&manager.registry)
	for i := len(order) - 1; i >= 0; i -= 1 {
		handle := order[i]
		module, ok := module_registry_get(&manager.registry, handle)
		if !ok do continue

		if module.state == .Registered || module.state == .Loaded {
			loaded_lib_unload(&module.lib, &module.ctx.lib_context)
			module.state = .Unloaded
		}

		if len(module.descriptor.dependencies) > 0 {
			delete(module.descriptor.dependencies)
			module.descriptor.dependencies = nil
		}

		if module.core_context != nil {
			free(module.core_context, manager.allocator)
			module.core_context = nil
		}
	}

	for i := len(order) - 1; i >= 0; i -= 1 {
		handle := order[i]
		_ = module_registry_release_slot(&manager.registry, handle)
	}
	resize(&manager.registry.dependency_order, 0)
}

// ============================================================================
// PROJECT LOADING
// ============================================================================
//
// module_manager_load_project reads GLOBAL_PROJECT_SETTINGS.modules, builds
// the DLL path for each enabled module, and feeds it into module_manager_load.
// Resolution order is delegated to module_manager_resolve().
//
// DLL discovery is the simplest possible: <bin>/<module>.dll relative to the
// process's executable directory. This will be replaced by a real rbs-driven
// locator once the rbs manifest pipeline is wired end-to-end.
// ============================================================================

module_manager_load_project :: proc(manager: ^Module_Manager) -> bool {
	if manager == nil || !manager.initialized do return false

	bin_dir, derr := os.get_executable_directory(context.allocator)
	if derr != nil {
		log.error("[Module] Failed to get executable directory: %v", derr)
		return false
	}
	defer delete(bin_dir)

	loaded_ok := true
	loaded_count := 0
	for m in GLOBAL_PROJECT_SETTINGS.modules {
		if !m.enabled do continue

		dll_name := fmt.tprintf("%s.dll", m.name)
		rel_path, jerr := filepath.join({bin_dir, dll_name}, context.allocator)
		if jerr != nil {
			log.error("[Module] Failed to join DLL path for '%s': %v", m.name, jerr)
			loaded_ok = false
			continue
		}

		if !os.exists(rel_path) {
			log.warn("[Module] DLL not found, skipping: %s", rel_path)
			delete(rel_path)
			continue
		}

		handle, ok := module_manager_load(manager, rel_path)
		delete(rel_path)
		if !ok {
			log.error("[Module] Failed to load module: %s", m.name)
			loaded_ok = false
			continue
		}
		loaded_count += 1
		_ = handle
	}

	if !loaded_ok {
		module_manager_unload_all(manager)
		return false
	}
	log.infof("[Module] Loaded %d module DLLs.", loaded_count)
	return true
}