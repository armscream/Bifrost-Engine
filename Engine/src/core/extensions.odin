// Engine/src/Core/extensions.odin
package Core

import "core:log"
import "core:mem"

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

// Extension_API is what an extension exposes through the LIB entry point.
Extension_API :: struct {
	api_version:      u32,
	identity:         Lib_Descriptor,
	dependencies:     [^]Lib_Dependency,
	dependency_count: u32,
	load:             proc(ctx: ^Extension_Context) -> bool,
	register:         proc(ctx: ^Extension_Context) -> bool,
	activate:         proc(ctx: ^Extension_Context) -> bool,
	deactivate:       proc(ctx: ^Extension_Context),
	unload:           proc(ctx: ^Extension_Context),
}

// Extension_Context is the extension's gateway into Core. Will grow to
// include service registry access, module lookup, and extension-point lookup.
@(private)
Extension_Context :: struct {
	registry:         ^Extension_Registry,
	handle:           ExtensionHandle,
	module_registry:  ^Module_Registry,
	service_registry: ^Service_Registry,
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
	initialized: bool,
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
			extension.api.identity.name,
		)
		return false
	}

	if len(extension.registration.targets) == 0 {
		log.error("Extension '%s' has no target modules.", extension.api.identity.name)
		return false
	}

	for target in extension.registration.targets {
		module, found := module_registry_get(module_registry, target.module)
		if !found {
			log.error(
				"Extension '%s' targets an invalid module handle [%d:%d].",
				extension.api.identity.name,
				target.module.idx,
				target.module.gen,
			)
			return false
		}

		actual_version := module.descriptor.identity.version

		if !version_in_range(actual_version, target.min_version, target.max_version) {
			log.error(
				"Extension '%s' target module '%s' has incompatible version %d.%d.%d.",
				extension.api.identity.name,
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

// extension_register_all runs each extension's register() callback and
// validates its declared targets. Called by extension_manager_register_all.
@(private)
extension_register_all :: proc(
	registry: ^Extension_Registry,
	module_registry: ^Module_Registry,
) -> bool {
	if registry == nil || !registry.initialized do return false

	if module_registry == nil || !module_registry.initialized do return false

	log.info("Registering extensions...")

	it := hm.dynamic_iterator_make(&registry.slots)
	for extension, _ in hm.iterate(&it) {
		if extension.state != .Loaded do continue
		log.info("Registering extension: %s", extension.api.identity.name)

		extension.ctx.registry = registry
		extension.ctx.handle = extension.handle
		extension.ctx.module_registry = module_registry
		extension.ctx.service_registry = &GLOBAL_SERVICE_REGISTRY
		extension_registration_init(&extension.registration, registry.allocator)

		if extension.api.register == nil {
			log.error("Extension '%s' has no register callback.", extension.api.identity.name)
			extension.state = .Failed
			return false
		}

		if !extension.api.register(&extension.ctx) {
			log.error("Extension '%s' registration failed.", extension.api.identity.name)
			extension.state = .Failed
			return false
		}

		if !extension_validate_targets(extension, module_registry) {
			extension.state = .Failed
			return false
		}
		extension.state = .Registered
		log.info("Extension registered: %s", extension.api.identity.name)
	}
	return true
}

// extension_resolve_dependencies walks each extension's declared
// dependencies, validating both presence and version range.
@(private)
extension_resolve_dependencies :: proc(
	registry: ^Extension_Registry,
	module_registry: ^Module_Registry,
) -> bool {
	if registry == nil || !registry.initialized do return false

	if module_registry == nil || !module_registry.initialized do return false

	log.info("Resolving extension dependencies...")

	it := hm.dynamic_iterator_make(&registry.slots)
	for extension, _ in hm.iterate(&it) {
		if extension.state != .Loaded do continue

		for dep_index := u32(0); dep_index < extension.api.dependency_count; dep_index += 1 {
			dependency := extension.api.dependencies[dep_index]
			dependency_name := string(dependency.name)

			dependency_handle, found := extension_registry_find(registry, dependency_name)
			if !found {
				if dependency.optional {
					log.warn(
						"Extension '%s': optional dependency '%s' not loaded.",
						extension.api.identity.name,
						dependency_name,
					)
					continue
				}

				log.error(
					"Extension '%s' requires extension '%s'.",
					extension.api.identity.name,
					dependency_name,
				)

				extension.state = .Failed
				return false
			}

			dependency_extension, valid := extension_registry_get(registry, dependency_handle)
			if !valid {
				log.error(
					"Extension '%s': dependency '%s' has an invalid handle.",
					extension.api.identity.name,
					dependency_name,
				)
				extension.state = .Failed
				return false
			}
			dependency_version := dependency_extension.api.identity.version

			if !version_in_range(
				dependency_version,
				dependency.min_version,
				dependency.max_version,
			) {
				log.error(
					"Extension '%s': dependency '%s' has incompatible version.",
					extension.api.identity.name,
					dependency_name,
				)
				extension.state = .Failed
				return false
			}
		}
	}
	return true
}

@(private)
extension_activate_all :: proc(registry: ^Extension_Registry) -> bool {
	if registry == nil || !registry.initialized do return false
	log.info("Activating extensions...")

	it := hm.dynamic_iterator_make(&registry.slots)
	for extension, _ in hm.iterate(&it) {
		if extension.state != .Registered do continue
		log.info("Activating extension: %s", extension.api.identity.name)

		if extension.api.activate == nil {
			log.error("Extension '%s' has no activate callback.", extension.api.identity.name)
			extension.state = .Failed
			return false
		}

		if !extension.api.activate(&extension.ctx) {
			log.error("Extension '%s' activation failed.", extension.api.identity.name)
			extension.state = .Failed
			return false
		}
		extension.state = .Active
		log.info("Extension active: %s", extension.api.identity.name)
	}
	return true
}

@(private)
extension_deactivate_all :: proc(registry: ^Extension_Registry) -> bool {
	if registry == nil || !registry.initialized do return false
	log.info("Deactivating extensions...")

	// We need reverse iteration; collect valid handles and walk back.
	order := make([dynamic]ExtensionHandle, 0, context.temp_allocator)
	defer delete(order)
	it := hm.dynamic_iterator_make(&registry.slots)
	for _, h in hm.iterate(&it) do append(&order, h)

	for i := len(order) - 1; i >= 0; i -= 1 {
		extension := hm.get(&registry.slots, order[i]) or_continue
		if extension.state != .Active do continue
		log.info("Deactivating extension: %s", extension.api.identity.name)

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

	// Reverse iteration: collect handles then walk back.
	order := make([dynamic]ExtensionHandle, 0, context.temp_allocator)
	defer delete(order)
	it := hm.dynamic_iterator_make(&registry.slots)
	for _, h in hm.iterate(&it) do append(&order, h)

	for i := len(order) - 1; i >= 0; i -= 1 {
		extension := hm.get(&registry.slots, order[i]) or_continue
		if extension.state == .Active {
			log.error("Cannot unload active extension '%s'.", extension.api.identity.name)
			return false
		}

		if extension.state != .Registered && extension.state != .Loaded {continue}

		log.info("Unloading extension: %s", extension.api.identity.name)

		if extension.api.unload != nil {
			extension.api.unload(&extension.ctx)
		}

		// Remove name lookup.
		name := string(extension.api.identity.name)
		if existing, found := registry.by_name[name]; found {
			if existing == extension.handle {
				delete_key(&registry.by_name, name)
			}
		}

		extension_registration_destroy(&extension.registration)

		// Close DLL.
		if extension.library != {} do dynamic_library_close(&extension.library)
		extension.state = .Unloaded
		_, _ = hm.remove(&registry.slots, extension.handle)
	}
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

	for project_extension in GLOBAL_PROJECT_SETTINGS.extensions {
		if !project_extension.enabled do continue
		log.info("Loading project extension: %s", project_extension.name)
		if !extension_load_one(&manager.registry, project_extension) {
			log.error("Failed to load extension '%s'.", project_extension.name)
			return false
		}
	}
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
// EXTENSION LOAD (placeholder)
// ============================================================================
//
// TODO: mirror the module_manager_load_project DLL discovery once the
// extension manifest pipeline lands in rbs.
@(private)
extension_load_one :: proc(registry: ^Extension_Registry, project: Project_Extension) -> bool {
	_ = registry
	log.warn("Extension '%s': DLL loading is not implemented yet.", project.name)
	return false
}