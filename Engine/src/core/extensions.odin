// Engine/src/Core/extensions.odin
package Core

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"

import hm "core:container/handle_map"

// ============================================================================
// EXTENSION API

// Extensions augment modules. An extension is not a replacement for a module;
// it attaches additional functionality to an existing module or to a
// module-defined extension point.
//
// Example:    Bifrost_Renderer <- DDGI Extension
//
// The renderer remains the owner of the primary renderer architecture.
// DDGI contributes additional functionality through the renderer's
// extension interface.
//
// Only the `Extension_*` types marked as part of the ABI are visible to
// extensions; the rest of the manager/registry machinery is package-internal.

// Extension_API is what an extension DLL exposes through its
// `bifrost_lib_get_api` entry point. It mirrors LIB_API but takes an
// extension-specific context so the extension can reach the module /
// service registries directly without going through lib_context_query.
//
// Dependencies are NOT declared here — extensions (and all components)
// declare them inside `identity` (a Lib_Descriptor), where the
// `dependencies` and `dependency_count` fields live. This keeps a single
// source of truth for component metadata.
//
// Note: we could unify this with LIB_API by making extensions also use
// Lib_Context + lib_context_query. We keep a parallel struct for now so
// extensions get a more direct view of the registries they actually use;
// see TODO(unify-abi) below.
Extension_API :: struct {
	api_version: u32,
	identity:    Lib_Descriptor,
	load:        proc(ctx: ^Extension_Context) -> bool,
	register:    proc(ctx: ^Extension_Context) -> bool,
	activate:    proc(ctx: ^Extension_Context) -> bool,
	deactivate:  proc(ctx: ^Extension_Context),
	unload:      proc(ctx: ^Extension_Context),
}

// TODO(unify-abi): collapse Extension_API onto LIB_API + Lib_Context.
// Extensions would export the same bifrost_lib_get_api returning ^LIB_API
// and reach module/service/resource registries through lib_context_query.
// The descriptor's component_kind == .Extension drives dispatch. Keep the
// current parallel path until at least one extension ships, then migrate.

// Extension_Context is the extension's gateway into Core. It exposes the
// registries the extension is most likely to need; everything else is
// reachable through lib_context_query.
//
// `registration` is a back-pointer to this extension's bucket in the
// Extension_Registry; extensions append to it (e.g. targets declared
// during register()) and Core drains / destroys it on unload.
Extension_Context :: struct {
	registry:          ^Extension_Registry,
	handle:            ExtensionHandle,
	registration:      ^Extension_Registration,
	module_registry:   ^Module_Registry,
	service_registry:  ^Service_Registry,
	resource_registry: ^Resource_Registry,
	event_registry:    ^Event_Registry,
}

// Extension_Target identifies a module that this extension augments.
Extension_Target :: struct {
	module:      ModuleHandle,
	min_version: Version,
	max_version: Version,
}

Extension_Registry :: struct {
	allocator:   mem.Allocator,
	slots:       hm.Dynamic_Handle_Map(Loaded_Extension, ExtensionHandle),
	by_name:     map[string]ExtensionHandle,
	// dependency_order is a flat array of handles in topological order,
	// built by extension_resolve_dependencies via DFS post-order walk.
	dependency_order: [dynamic]ExtensionHandle,
	initialized:      bool,
}

@(private)
Extension_Registration :: struct {
	services:  [dynamic]Service_Registration,
	systems:   [dynamic]System_Registration,
	resources: [dynamic]Resource_Registration,
	events:    [dynamic]Event_Registration,
	targets:   [dynamic]Extension_Target,
}

@(private)
Loaded_Extension :: struct {
	handle:       ExtensionHandle,
	library:      Dynamic_Library,
	api:          Extension_API,
	// id_name is an Odin-managed copy of api.identity.name so it
	// outlives the DLL. The api.identity.name string aliases DLL
	// static memory; we read id_name after unload.
	id_name:      string,
	ctx:          Extension_Context,
	state:        Component_State,
	registration: Extension_Registration,
}

Extension_Manager :: struct {
	registry:    Extension_Registry,
	allocator:   mem.Allocator,
	initialized: bool,
}

// ==========================
// REGISTRY HELPERS

@(private)
extension_registry_init :: proc(registry: ^Extension_Registry, allocator: mem.Allocator) -> bool {
	if registry == nil do return false
	if registry.initialized {
		log.warn("Extension registry already initialized.")
		return false
	}

	registry.allocator = allocator
	hm.dynamic_init(&registry.slots, allocator)
	registry.by_name = make(map[string]ExtensionHandle, allocator)
	registry.dependency_order = make([dynamic]ExtensionHandle, 0, allocator)
	registry.initialized = true
	log.info("Extension registry initialized.")
	return true
}

@(private)
extension_registry_destroy :: proc(registry: ^Extension_Registry) {
	if registry == nil || !registry.initialized do return
	// Extensions should normally already have been unloaded.
	// We intentionally do not call unload here — destruction order is
	// handled by engine shutdown.
	delete(registry.by_name)
	delete(registry.dependency_order)
	hm.dynamic_destroy(&registry.slots)
	registry.allocator = {}
	registry.initialized = false
}

@(private)
extension_registration_init :: proc(
	registration: ^Extension_Registration,
	allocator: mem.Allocator,
) {
	if registration == nil do return

	registration.targets   = make([dynamic]Extension_Target, 0, allocator)
	registration.services  = make([dynamic]Service_Registration, 0, allocator)
	registration.systems   = make([dynamic]System_Registration, 0, allocator)
	registration.resources = make([dynamic]Resource_Registration, 0, allocator)
	registration.events    = make([dynamic]Event_Registration, 0, allocator)
}

@(private)
extension_registration_destroy :: proc(registration: ^Extension_Registration) {
	if registration == nil do return

	delete(registration.targets)
	delete(registration.services)
	delete(registration.systems)
	delete(registration.resources)
	delete(registration.events)
}

@(private)
extension_registry_get :: proc(
	registry: ^Extension_Registry,
	handle: ExtensionHandle,
) -> (
	^Loaded_Extension,
	bool,
) {
	if registry == nil || !registry.initialized do return nil, false
	if handle == INVALID_EXTENSION_HANDLE do return nil, false
	return hm.get(&registry.slots, handle)
}

extension_is_valid :: proc(registry: ^Extension_Registry, handle: ExtensionHandle) -> bool {
	_, ok := extension_registry_get(registry, handle)
	return ok
}

@(private)
extension_registry_find :: proc(
	registry: ^Extension_Registry,
	name: string,
) -> (
	ExtensionHandle,
	bool,
) {
	if registry == nil || !registry.initialized do return INVALID_EXTENSION_HANDLE, false
	if len(name) == 0 do return INVALID_EXTENSION_HANDLE, false
	handle, found := registry.by_name[name]
	if !found do return INVALID_EXTENSION_HANDLE, false
	if _, valid := extension_registry_get(registry, handle); !valid do return INVALID_EXTENSION_HANDLE, false
	return handle, true
}

// =======================
// TARGET VALIDATION

@(private)
extension_validate_targets :: proc(
	extension: ^Loaded_Extension,
	module_registry: ^Module_Registry,
) -> bool {
	if extension == nil do return false
	if module_registry == nil || !module_registry.initialized {
		log.error(
			"Extension '%s' cannot validate targets: module registry unavailable.",
			extension.id_name,
		)
		return false
	}

	if len(extension.registration.targets) == 0 {
		log.error("Extension '%s' has no target modules.", extension.id_name)
		return false
	}

	for target in extension.registration.targets {
		module, found := module_registry_get(module_registry, target.module)
		if !found {
			log.error(
				"Extension '%s' targets an invalid module handle [%d:%d].",
				extension.id_name,
				target.module.idx,
				target.module.gen,
			)
			return false
		}

		actual_version := module.descriptor.identity.version

		if !version_in_range(actual_version, target.min_version, target.max_version) {
			log.error(
				"Extension '%s' target module '%s' has incompatible version %d.%d.%d.",
				extension.id_name,
				module.descriptor.identity.name,
				actual_version.major,
				actual_version.minor,
				actual_version.patch,
			)
			return false
		}
	}
	return true
}

// ============================================================================
// LIFECYCLE PHASES
// ============================================================================

// extension_register_all is now a no-op: extension_load_one drives both
// load() and register() and transitions the extension directly to
// .Registered before returning the handle. Kept in the engine.init
// pipeline for API symmetry with the module manager and so future
// hot-reload paths have a single chokepoint to hang new logic on.
@(private)
extension_register_all :: proc(
	registry: ^Extension_Registry,
	module_registry: ^Module_Registry,
) -> bool {
	_ = module_registry
	if registry == nil || !registry.initialized do return false
	log.info("Register extensions: load-time registration already complete.")
	return true
}

// Extension_Visit_State drives the DFS cycle detector in extension
// dependency resolution.
@(private)
Extension_Visit_State :: enum {
	Unvisited,
	Visiting,
	Visited,
}

// extension_resolve_dependencies walks each extension's declared
// dependencies in DFS post-order, validating both presence and version
// range, and produces a topological dependency_order used by the
// activate/deactivate/unload phases.
@(private)
extension_resolve_dependencies :: proc(
	registry: ^Extension_Registry,
	module_registry: ^Module_Registry,
) -> bool {
	if registry == nil || !registry.initialized do return false
	if module_registry == nil || !module_registry.initialized do return false

	log.info("Resolving extension dependencies...")

	resize(&registry.dependency_order, 0)

	// visit_state is indexed by handle.idx.
	required_state_count := registry.slots.items.len
	visit_state := make([dynamic]Extension_Visit_State, required_state_count, registry.allocator)
	defer delete(visit_state)

	it := hm.dynamic_iterator_make(&registry.slots)
	for extension, handle in hm.iterate(&it) {
		_ = extension
		if !extension_resolve_visit(registry, module_registry, handle, visit_state[:]) {
			resize(&registry.dependency_order, 0)
			log.error("Extension dependency resolution failed.")
			return false
		}
	}

	log.info(
		"Extension dependency resolution complete. %d extensions in load order.",
		len(registry.dependency_order),
	)
	return true
}

@(private)
extension_resolve_visit :: proc(
	registry: ^Extension_Registry,
	module_registry: ^Module_Registry,
	handle: ExtensionHandle,
	visit_state: []Extension_Visit_State,
) -> bool {
	if registry == nil do return false
	extension, ok := extension_registry_get(registry, handle)
	if !ok do return false

	if int(handle.idx) >= len(visit_state) {
		log.error(
			"Extension handle [%d:%d] index out of range for visit state.",
			handle.idx,
			handle.gen,
		)
		return false
	}

	switch visit_state[handle.idx] {
	case .Visited:
		return true
	case .Visiting:
		log.error(
			"Cyclic extension dependency detected at '%s'.",
			extension.id_name,
		)
		return false
	case .Unvisited:
	}

	visit_state[handle.idx] = .Visiting

	dep_count := extension.api.identity.dependency_count
	if dep_count > 0 && extension.api.identity.dependencies == nil {
		log.error(
			"Extension '%s' reports %d dependencies but has a null dependency array.",
			extension.id_name,
			dep_count,
		)
		visit_state[handle.idx] = .Unvisited
		return false
	}

	for i: u32 = 0; i < dep_count; i += 1 {
		dependency := extension.api.identity.dependencies[i]
		dep_name := string(dependency.name)

		// Extensions can depend on either other extensions or on
		// modules (which they augment). Search the module registry
		// first — if the dependency is a module, it's already
		// resolved through module_manager_resolve and we don't need
		// to recurse. Fall back to the extension registry and
		// recurse into extension_resolve_visit.
		if mod_handle, mod_found := module_find(module_registry, dep_name); mod_found {
			dep_module, mod_valid := module_registry_get(module_registry, mod_handle)
			if !mod_valid {
				log.error(
					"Extension '%s': dependency '%s' has an invalid module handle.",
					extension.id_name,
					dep_name,
				)
				visit_state[handle.idx] = .Unvisited
				return false
			}
			if !version_satisfies(dep_module.descriptor.identity.version, dependency) {
				if dependency.optional {
					log.warn(
						"Extension '%s': optional module dependency '%s' does not satisfy its version requirement.",
						extension.id_name,
						dep_name,
					)
					continue
				}
				log.error(
					"Extension '%s': module dependency '%s' does not satisfy its version requirement.",
					extension.id_name,
					dep_name,
				)
				visit_state[handle.idx] = .Unvisited
				return false
			}
			// Module satisfied; no recursion needed.
			continue
		}

		dep_handle, found := extension_registry_find(registry, dep_name)
		if !found {
			if dependency.optional {
				log.warn(
					"Extension '%s': optional dependency '%s' not loaded.",
					extension.id_name,
					dep_name,
				)
				continue
			}
			log.error(
				"Extension '%s' requires dependency '%s' (not found as module or extension).",
				extension.id_name,
				dep_name,
			)
			visit_state[handle.idx] = .Unvisited
			return false
		}

		dep_ext, valid := extension_registry_get(registry, dep_handle)
		if !valid {
			log.error(
				"Extension '%s': dependency '%s' has an invalid handle.",
				extension.id_name,
				dep_name,
			)
			visit_state[handle.idx] = .Unvisited
			return false
		}

		if !version_satisfies(dep_ext.api.identity.version, dependency) {
			if dependency.optional {
				log.warn(
					"Extension '%s': optional dependency '%s' does not satisfy its version requirement.",
					extension.id_name,
					dep_name,
				)
				continue
			}
			log.error(
				"Extension '%s': dependency '%s' does not satisfy its version requirement.",
				extension.id_name,
				dep_name,
			)
			visit_state[handle.idx] = .Unvisited
			return false
		}

		if !extension_resolve_visit(registry, module_registry, dep_handle, visit_state) {
			visit_state[handle.idx] = .Unvisited
			return false
		}
	}

	visit_state[handle.idx] = .Visited
	append(&registry.dependency_order, handle)
	return true
}

@(private)
extension_activate_all :: proc(registry: ^Extension_Registry) -> bool {
	if registry == nil || !registry.initialized do return false
	log.info("Activating extensions...")

	order := registry.dependency_order[:]
	for handle in order {
		extension, ok := extension_registry_get(registry, handle)
		if !ok do continue
		if extension.state != .Registered do continue

		log.info("Activating extension: %s", extension.id_name)

		if extension.api.activate == nil {
			log.error(
				"Extension '%s' has no activate callback.",
				extension.id_name,
			)
			extension.state = .Failed
			return false
		}

		if !extension.api.activate(&extension.ctx) {
			log.error(
				"Extension '%s' activation failed.",
				extension.id_name,
			)
			extension.state = .Failed
			return false
		}
		extension.state = .Active
		log.info("Extension active: %s", extension.id_name)
	}
	return true
}

@(private)
extension_deactivate_all :: proc(registry: ^Extension_Registry) -> bool {
	if registry == nil || !registry.initialized do return false
	log.info("Deactivating extensions...")

	order := registry.dependency_order[:]
	for i := len(order) - 1; i >= 0; i -= 1 {
		extension, ok := extension_registry_get(registry, order[i])
		if !ok do continue
		if extension.state != .Active do continue

		log.info("Deactivating extension: %s", extension.id_name)
		if extension.api.deactivate != nil {
			extension.api.deactivate(&extension.ctx)
		}
		extension.state = .Registered
	}
	return true
}

@(private)
extension_unload_all :: proc(registry: ^Extension_Registry) -> bool {
	if registry == nil || !registry.initialized do return false
	log.info("Unloading extensions...")

	order := registry.dependency_order[:]
	for i := len(order) - 1; i >= 0; i -= 1 {
		extension, ok := extension_registry_get(registry, order[i])
		if !ok do continue

		if extension.state == .Active {
			log.error("Cannot unload active extension '%s'.", extension.id_name)
			return false
		}
		if extension.state != .Registered && extension.state != .Loaded {continue}

		log.info("Unloading extension: %s", extension.id_name)

		if extension.api.unload != nil {
			extension.api.unload(&extension.ctx)
		}

		// Remove name lookup.
		if existing, found := registry.by_name[extension.id_name]; found {
			if existing == extension.handle {
				delete_key(&registry.by_name, extension.id_name)
			}
		}

		extension_registration_destroy(&extension.registration)

		if extension.library != (Dynamic_Library{}) {
			dynamic_library_close(&extension.library)
		}

		if len(extension.id_name) > 0 {
			delete(extension.id_name, registry.allocator)
			extension.id_name = ""
		}

		extension.state = .Unloaded
		_, _ = hm.remove(&registry.slots, extension.handle)
	}

	resize(&registry.dependency_order, 0)
	return true
}

// ============================================================================
// EXTENSION MANAGER API
// ============================================================================

extension_manager_init :: proc(manager: ^Extension_Manager, allocator: mem.Allocator) -> bool {
	if manager == nil do return false
	if manager.initialized {
		log.warn("Extension manager is already initialized")
		return false
	}
	manager.allocator = allocator
	if !extension_registry_init(&manager.registry, allocator) {
		log.warn("Failed to initialize extension registry")
		return false
	}
	manager.initialized = true
	log.info("Extension manager initialized.")
	return true
}

extension_manager_destroy :: proc(manager: ^Extension_Manager) {
	if manager == nil || !manager.initialized do return
	extension_manager_unload_all(manager)
	extension_registry_destroy(&manager.registry)
	manager.allocator = {}
	manager.initialized = false
}

// extension_manager_load_project walks GLOBAL_PROJECT_SETTINGS.extensions
// and loads each enabled extension. DLL discovery mirrors the module path;
// see module_manager_load_project.
extension_manager_load_project :: proc(manager: ^Extension_Manager) -> bool {
	if manager == nil || !manager.initialized do return false

	bin_dir, derr := os.get_executable_directory(context.allocator)
	if derr != nil {
		log.error("[Extension] Failed to get executable directory: %v", derr)
		return false
	}
	defer delete(bin_dir)

	loaded_count := 0
	loaded_failed_required := false
	for project_extension in GLOBAL_PROJECT_SETTINGS.extensions {
		if !project_extension.enabled do continue

		dll_name := fmt.tprintf("%s.dll", project_extension.name)
		rel_path, jerr := filepath.join({bin_dir, dll_name}, context.allocator)
		if jerr != nil {
			log.error("[Extension] Failed to join DLL path for '%s': %v", project_extension.name, jerr)
			if project_extension.required do loaded_failed_required = true
			continue
		}

		if !os.exists(rel_path) {
			if project_extension.required {
				log.error(
					"[Extension] Required extension DLL not found: %s (path=%s)",
					project_extension.name,
					rel_path,
				)
				loaded_failed_required = true
			} else {
				log.warn("[Extension] DLL not found, skipping: %s", rel_path)
			}
			delete(rel_path)
			continue
		}

		handle, ok := extension_load_one(&manager.registry, rel_path)
		delete(rel_path)
		if !ok {
			log.error("[Extension] Failed to load extension: %s", project_extension.name)
			if project_extension.required do loaded_failed_required = true
			continue
		}
		loaded_count += 1
		_ = handle
	}

	if loaded_failed_required {
		extension_manager_unload_all(manager)
		return false
	}
	log.infof("[Extension] Loaded %d extension DLLs.", loaded_count)
	return true
}

extension_manager_resolve :: proc(manager: ^Extension_Manager) -> bool {
	if manager == nil || !manager.initialized do return false
	return extension_resolve_dependencies(&manager.registry, &GLOBAL_MODULE_MANAGER.registry)
}

extension_manager_register_all :: proc(manager: ^Extension_Manager) -> bool {
	if manager == nil || !manager.initialized do return false
	return extension_register_all(&manager.registry, &GLOBAL_MODULE_MANAGER.registry)
}

extension_manager_activate_all :: proc(manager: ^Extension_Manager) -> bool {
	if manager == nil || !manager.initialized do return false
	return extension_activate_all(&manager.registry)
}

extension_manager_deactivate_all :: proc(manager: ^Extension_Manager) -> bool {
	if manager == nil || !manager.initialized do return false
	return extension_deactivate_all(&manager.registry)
}

extension_manager_unload_all :: proc(manager: ^Extension_Manager) -> bool {
	if manager == nil || !manager.initialized do return false
	return extension_unload_all(&manager.registry)
}

// ============================================================================
// EXTENSION LOAD
// ============================================================================
//
// Mirrors module_manager_load: opens the DLL, finds bifrost_lib_get_api,
// validates the descriptor, drives the lifecycle callbacks, and parks the
// Loaded_Extension in the registry. The DLL's `register()` callback is
// expected to push its declared targets (Extension_Target list) via the
// SDK; we validate those targets here.
//
// TODO(extension-registration-api): currently extensions can register
// services/resources/events only through the parallel Extension_Context
// fields (module_registry / service_registry / etc.). A unified
// extension_registration API surface (mirroring module_registration) is
// the next step. For now extensions can also just call lib_context_query
// inside their load() and reach Core_Lib_Context through their own
// pointer plumbing.
@(private)
extension_load_one :: proc(
	registry: ^Extension_Registry,
	path: string,
) -> (
	out_handle: ExtensionHandle,
	ok: bool,
) {
	if registry == nil || !registry.initialized {
		return INVALID_EXTENSION_HANDLE, false
	}

	library, lib_ok := dynamic_library_open(path)
	if !lib_ok {
		log.error("[Extension] Failed to open DLL: %s", path)
		return INVALID_EXTENSION_HANDLE, false
	}

	sym := dynamic_library_symbol(&library, LIB_ENTRY_POINT_NAME)
	if sym == nil {
		log.error("[Extension] Entry point '%s' not found in %s", LIB_ENTRY_POINT_NAME, path)
		dynamic_library_close(&library)
		return INVALID_EXTENSION_HANDLE, false
	}

	get_api := cast(Lib_Get_API_Proc)sym
	api_ptr := get_api()
	if api_ptr == nil {
		log.error("[Extension] Entry point returned nil API: %s", path)
		dynamic_library_close(&library)
		return INVALID_EXTENSION_HANDLE, false
	}
	api := cast(^Extension_API)api_ptr

	if api.identity.api_version != LIB_API_VERSION {
		log.error(
			"[Extension] Incompatible ABI version: %d (expected %d) in %s",
			api.identity.api_version,
			LIB_API_VERSION,
			path,
		)
		dynamic_library_close(&library)
		return INVALID_EXTENSION_HANDLE, false
	}

	if api.identity.component_kind != .Extension {
		log.error("[Extension] Library is not an extension: %s", path)
		dynamic_library_close(&library)
		return INVALID_EXTENSION_HANDLE, false
	}

	if api.load == nil ||
	   api.register == nil ||
	   api.activate == nil ||
	   api.deactivate == nil ||
	   api.unload == nil {
		log.error("[Extension] Missing required lifecycle proc in %s", path)
		dynamic_library_close(&library)
		return INVALID_EXTENSION_HANDLE, false
	}

	if api.identity.name == nil || len(string(api.identity.name)) == 0 {
		log.error("[Extension] Library has no name: %s", path)
		dynamic_library_close(&library)
		return INVALID_EXTENSION_HANDLE, false
	}

	// Build Loaded_Extension.
	ext := Loaded_Extension{
		library = library,
		api     = api^,
		state   = .Loaded,
		// Clone the identity name into Odin-managed memory so the
		// string survives DLL unload (api.identity.name points into
		// the DLL's static memory).
		id_name = api.identity.name != nil ? strings.clone(string(api.identity.name), registry.allocator) : "",
	}

	// Initialize the registration bucket.
	extension_registration_init(&ext.registration, registry.allocator)

	// Pre-fill Extension_Context with registry pointers so the extension
	// can immediately query modules / services / resources / events
	// from inside its load()/register() callbacks. `handle` is patched
	// in below once the slot exists.
	ext.ctx.registry          = registry
	ext.ctx.handle            = INVALID_EXTENSION_HANDLE
	ext.ctx.registration      = &ext.registration
	ext.ctx.module_registry   = &GLOBAL_MODULE_MANAGER.registry
	ext.ctx.service_registry  = &GLOBAL_SERVICE_REGISTRY
	ext.ctx.resource_registry = &GLOBAL_RESOURCE_REGISTRY
	ext.ctx.event_registry    = &GLOBAL_EVENT_REGISTRY

	if !api.load(&ext.ctx) {
		log.error("[Extension] load() failed: %s", string(api.identity.name))
		extension_registration_destroy(&ext.registration)
		dynamic_library_close(&library)
		return INVALID_EXTENSION_HANDLE, false
	}

	if !api.register(&ext.ctx) {
		log.error("[Extension] register() failed: %s", string(api.identity.name))
		if api.unload != nil do api.unload(&ext.ctx)
		extension_registration_destroy(&ext.registration)
		dynamic_library_close(&library)
		return INVALID_EXTENSION_HANDLE, false
	}

	// Validate declared targets now (modules must already be loaded).
	if !extension_validate_targets(&ext, ext.ctx.module_registry) {
		log.error("[Extension] target validation failed: %s", string(api.identity.name))
		if api.unload != nil do api.unload(&ext.ctx)
		extension_registration_destroy(&ext.registration)
		dynamic_library_close(&library)
		return INVALID_EXTENSION_HANDLE, false
	}

	// Reserve a slot. Reject duplicate names against currently-valid
	// extensions.
	name := string(api.identity.name)
	if existing, found := registry.by_name[name]; found {
		if _, valid := extension_registry_get(registry, existing); valid {
			log.error("[Extension] An extension named '%s' is already loaded.", name)
			if api.unload != nil do api.unload(&ext.ctx)
			extension_registration_destroy(&ext.registration)
			dynamic_library_close(&library)
			return INVALID_EXTENSION_HANDLE, false
		}
		delete_key(&registry.by_name, name)
	}

	handle, alloc_err := hm.add(&registry.slots, ext)
	if alloc_err != nil {
		log.error("[Extension] Failed to allocate extension slot for '%s': %v", name, alloc_err)
		if api.unload != nil do api.unload(&ext.ctx)
		extension_registration_destroy(&ext.registration)
		dynamic_library_close(&library)
		return INVALID_EXTENSION_HANDLE, false
	}

	resident, found := hm.get(&registry.slots, handle)
	if !found {
		log.error("[Extension] Slot lookup failed for '%s' (impossible).", name)
		return INVALID_EXTENSION_HANDLE, false
	}
	resident.handle = handle
	resident.ctx.handle = handle
	resident.state = .Registered
	registry.by_name[name] = handle

	log.info(
		"[Extension] Loaded '%s' [%d:%d].",
		name,
		handle.idx,
		handle.gen,
	)

	return handle, true
}