// Engine/src/Core/extensions.odin
package Core

import "core:dynlib"
import "core:log"
import "core:mem"

// ============================================================================
// EXTENSION API
// ============================================================================
//
// Extensions augment modules.
//
// An extension is not a replacement for a module. It attaches additional
// functionality to an existing module or module-defined extension point.
//
// Example:
//
//     Bifrost_Renderer
//          ^
//          |
//     DDGI Extension
//
// The renderer remains the owner of the primary renderer architecture.
// DDGI contributes additional functionality through the renderer's
// extension interface.
//
// ============================================================================
Extension_API :: struct {
	api_version:      u32,
	identity:         DLL_Identity,
	dependencies:     [^]DLL_Dependency,
	dependency_count: u32,
	load:             proc(ctx: ^Extension_Context) -> bool,
	register:         proc(ctx: ^Extension_Context) -> bool,
	activate:         proc(ctx: ^Extension_Context) -> bool,
	deactivate:       proc(ctx: ^Extension_Context),
	unload:           proc(ctx: ^Extension_Context),
}

Extension_Registry :: struct {
	allocator:    mem.Allocator,
	extensions:   [dynamic]Loaded_Extension,
	generations:  [dynamic]u32,
	free_indices: [dynamic]u32,
	by_name:      map[string]ExtensionHandle,
	initialized:  bool,
}

Loaded_Extension :: struct {
	handle:       ExtensionHandle,
	library:      dynlib.Library,
	api:          Extension_API,
	ctx:          Extension_Context,
	state:        Load_State,
	registration: Extension_Registration,
}

// ============================================================================
// EXTENSION CONTEXT
// ============================================================================
//
// The context is the extension's gateway into Core.
//
// We will expand this as the extension architecture develops.
//
// In particular, this is where we can eventually expose:
//
//     - extension's own handle
//     - owning module handle
//     - Core SDK
//     - service registry access
//     - module lookup
//     - extension-point lookup
//
// ============================================================================
Extension_Context :: struct {
	registry:         ^Extension_Registry,
	handle:           ExtensionHandle,
	module_registry:  ^Module_Registry,
	service_registry: ^Service_Registry,
}

// Registration is collected during the extension registration phase.
//
// The extension does not directly mutate Core registries. Core consumes these
// declarations and performs the actual registration.
Extension_Registration :: struct {
	services:  [dynamic]Service_Registration,
	systems:   [dynamic]System_Registration,
	resources: [dynamic]Resource_Registration,
	events:    [dynamic]Event_Registration,
	targets:   [dynamic]Extension_Target,
}

// ============================================================================
// EXTENSION TARGET
// ============================================================================
//
// Identifies a module that this extension augments.
//
// Later we can evolve this into an actual extension-point system:
//
//     Bifrost_Renderer::GI
//     Bifrost_Renderer::RenderPass
//     Animation::GraphNode
//     ECS::Component
//
// For now the module identity is enough.
//
// ============================================================================
Extension_Target :: struct {
	module:      ModuleHandle,
	min_version: Version,
	max_version: Version,
}

// Regitry initialization
@(private)
extension_registry_init :: proc(registry: ^Extension_Registry, allocator: mem.Allocator) -> bool {
	if registry == nil do return false
	if registry.initialized {log.warn("Extension registry already initialized.")
		return false}

	registry.allocator = allocator

	//Slot zero is permanently invalid.
	registry.extensions = make([dynamic]Loaded_Extension, 1, allocator)
	append(&registry.extensions, Loaded_Extension{})

	registry.generations = make([dynamic]u32, 1, allocator)
	append(&registry.generations, EXTENSION_GENERATION_INVALID)

	registry.free_indices = make([dynamic]u32, 0, allocator)
	registry.by_name = make(map[string]ExtensionHandle, allocator)
	registry.initialized = true
	log.info("Extension registry initialized.")
	return true
}

@(private)
extension_registration_init :: proc(
	registration: ^Extension_Registration,
	allocator: mem.Allocator,
) {
	if registration == nil do return

	registration.targets = make([dynamic]Extension_Target, 0, allocator)
	registration.services = make([dynamic]Service_Registration, 0, allocator)
	registration.systems = make([dynamic]System_Registration, 0, allocator)
	registration.resources = make([dynamic]Resource_Registration, 0, allocator)
	registration.events = make([dynamic]Event_Registration, 0, allocator)
}

@(private)
extension_registry_destroy :: proc(registry: ^Extension_Registry) {
	if registry == nil || !registry.initialized do return
	// Extensions should normally already have been unloaded
	// we intentionally do no call unload here. Destruction order should
	// already have been handled by engine shutdown.
	delete(registry.by_name)
	delete(registry.free_indices)
	delete(registry.generations)
	delete(registry.extensions)
	registry.allocator = {}
	registry.initialized = false
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
// ext lookup
@(private)
extension_registry_get :: proc(
	registry: ^Extension_Registry,
	handle: ExtensionHandle,
) -> (
	^Loaded_Extension,
	bool,
) {
	if registry == nil || !registry.initialized do return nil, false
	if handle.index == EXTENSION_INDEX_INVALID do return nil, false
	if handle.index >= u32(len(registry.extensions)) do return nil, false
	if handle.generation == EXTENSION_GENERATION_INVALID || handle.generation != registry.generations[handle.index] do return nil, false

	extension := &registry.extensions[handle.index]
	if extension.handle.index != handle.index do return nil, false
	if extension.handle.generation != handle.generation do return nil, false
	return extension, true
}
// find by name
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
extension_is_valid :: proc(registry: ^Extension_Registry, handle: ExtensionHandle) -> bool {
	_, ok := extension_registry_get(registry, handle)
	return ok
}

@(private)
extension_registry_allocate_handle :: proc(registry: ^Extension_Registry) -> ExtensionHandle {
	if registry == nil || !registry.initialized do return INVALID_EXTENSION_HANDLE
	index: u32

	// Reuse a previously released slot.
	if len(registry.free_indices) > 0 {
		last := len(registry.free_indices) - 1
		index = registry.free_indices[last]
		// [dynamic] cannot be assigned a sliced value.
		pop(&registry.free_indices)
	} else {
		index = u32(len(registry.extensions))
		append(&registry.extensions, Loaded_Extension{})
		append(&registry.generations, EXTENSION_GENERATION_INVALID)
	}

	// Advance generation.
	generation := registry.generations[index]
	if generation == EXTENSION_GENERATION_INVALID {
		generation = 1
	} else {
		generation += 1
		if generation == EXTENSION_GENERATION_INVALID {generation = 1}
	}
	registry.generations[index] = generation
	return ExtensionHandle{index = index, generation = generation}
}

// Extension slot release
@(private)
extension_registry_release_handle :: proc(
	registry: ^Extension_Registry,
	handle: ExtensionHandle,
) -> bool {
	if registry == nil || !registry.initialized do return false
	if handle.index == EXTENSION_INDEX_INVALID || handle.index >= u32(len(registry.extensions)) do return false
	if registry.generations[handle.index] != handle.generation do return false
	registry.generations[handle.index] = EXTENSION_GENERATION_INVALID
	append(&registry.free_indices, handle.index)
	return true
}

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
				target.module.index,
				target.module.generation,
			)
			return false
		}

		actual_version := module.api.identity.version

		if !version_in_range(actual_version, target.min_version, target.max_version) {
			log.error(
				"Extension '%s' target module '%s' has incompatible version %d.%d.%d.",
				extension.api.identity.name,
				module.api.identity.name,
				actual_version.major,
				actual_version.minor,
				actual_version.patch,
			)
			return false
		}
	}
	return true
}
@(private)
extension_get_registration :: proc(
	registry: ^Extension_Registry,
	handle: ExtensionHandle,
) -> (
	^Extension_Registration,
	bool,
) {
	if registry == nil || !registry.initialized do return nil, false
	extension, ok := extension_registry_get(registry, handle)
	if !ok do return nil, false
	return &extension.registration, true
}

// Target module
@(private)
extension_registration_add_target :: proc(
	registry: ^Extension_Registry,
	extension: ExtensionHandle,
	target: Extension_Target,
) -> bool {
	if registry == nil || !registry.initialized do return false
	registration, ok := extension_get_registration(registry, extension)
	if !ok do return false

	instance, instance_ok := extension_registry_get(registry, extension)
	if !instance_ok do return false

	if instance.state != .Registered {
		log.error(
			"Extension [%d:%d] cannot register a target: extension is not registered.",
			extension.index,
			extension.generation,
		)
		return false
	}
	if target.module == INVALID_MODULE_HANDLE {
		log.error(
			"Extension [%d:%d] cannot register an empty target module.",
			extension.index,
			extension.generation,
		)
		return false
	}
	append(&registration.targets, target)
	return true
}

@(private)
extension_registration_add_service :: proc(
	registry: ^Extension_Registry,
	extension: ExtensionHandle,
	registration: Service_Registration,
) -> bool {
	if registry == nil || !registry.initialized do return false

	extension_registration, ok := extension_get_registration(registry, extension)
	if !ok do return false

	instance, instance_ok := extension_registry_get(registry, extension)
	if !instance_ok do return false

	if instance.state != .Registered {
		log.error(
			"Extension [%d:%d] cannot register a service: extension is not Registered.",
			extension.index,
			extension.generation,
		)
		return false
	}

	append(&extension_registration.services, registration)

	return true
}
@(private)
extension_registration_add_system :: proc(
	registry: ^Extension_Registry,
	extension: ExtensionHandle,
	registration: System_Registration,
) -> bool {
	if registry == nil || !registry.initialized do return false

	extension_registration, ok := extension_get_registration(registry, extension)
	if !ok do return false

	instance, instance_ok := extension_registry_get(registry, extension)
	if !instance_ok do return false

	if instance.state != .Registered {
		log.error(
			"Extension [%d:%d] cannot register a system: extension is not Registered.",
			extension.index,
			extension.generation,
		)
		return false
	}

	append(&extension_registration.systems, registration)
	return true
}
@(private)
extension_registration_add_resource :: proc(
	registry: ^Extension_Registry,
	extension: ExtensionHandle,
	registration: Resource_Registration,
) -> bool {
	if registry == nil || !registry.initialized do return false

	extension_registration, ok := extension_get_registration(registry, extension)
	if !ok do return false

	instance, instance_ok := extension_registry_get(registry, extension)
	if !instance_ok do return false
	if instance.state != .Registered {
		log.error(
			"Extension [%d:%d] cannot register a resource: extension is not Registered.",
			extension.index,
			extension.generation,
		)
		return false
	}
	append(&extension_registration.resources, registration)
	return true
}
@(private)
extension_registration_add_event :: proc(
	registry: ^Extension_Registry,
	extension: ExtensionHandle,
	registration: Event_Registration,
) -> bool {
	if registry == nil || !registry.initialized do return false

	extension_registration, ok := extension_get_registration(registry, extension)
	if !ok do return false

	instance, instance_ok := extension_registry_get(registry, extension)

	if !instance_ok do return false
	if instance.state != .Registered {
		log.error(
			"Extension [%d:%d] cannot register an event: extension is not Registered.",
			extension.index,
			extension.generation,
		)
		return false
	}
	append(&extension_registration.events, registration)
	return true
}

@(private)
extension_load_project_extensions :: proc() -> bool {
	registry := &GLOBAL_EXTENSION_REGISTRY
	if registry == nil || !registry.initialized {
		log.error("Cannot load project extensions: registry is not initialized.")
		return false
	}

	for project_extension in GLOBAL_PROJECT_SETTINGS.extensions {
		if !project_extension.enabled do continue
		log.info("Loading project extension: %s", project_extension.name)

		if !extension_load(registry, project_extension) {
			log.error("Failed to load extension '%s'.", project_extension.name)
			return false
		}
	}
	return true
}

// ====================
// LOAD ONE EXTENSION
@(private)
extension_load :: proc(registry: ^Extension_Registry, project: Project_Extension) -> bool {
	if registry == nil || !registry.initialized do return false

	if len(project.name) == 0 {
		log.error("Cannot load extension with empty name.")
		return false
	}

	_, found := extension_registry_find(registry, project.name)
	if found {
		log.error("Extension '%s' is already loaded.", project.name)
		return false
	}
	// DLL discovery/loading
	// TODO:
	// Use the same DLL discovery mechanism as module_load_project_modules().
	//
	// We deliberately keep this isolated so the extension registry does not
	// know anything about project paths.
	log.warn("Extension '%s': DLL loading is not implemented yet.", project.name)

	return false
}

@(private)
extension_validate_project_version :: proc(
	extension: ^Loaded_Extension,
	project: Project_Extension,
) -> bool {
	if extension == nil do return false
	actual := extension.api.identity.version
	if version_is_zero(project.version) {return true}

	if version_compare(actual, project.version) != 0 {
		log.error(
			"Extension '%s': project requested version %d.%d.%d but loaded %d.%d.%d.",
			project.name,
			project.version.major,
			project.version.minor,
			project.version.patch,
			actual.major,
			actual.minor,
			actual.patch,
		)
		return false
	}
	return true
}

// ==========================
// REGISTER ALL EXTENSIONS
extension_register_all :: proc(
	registry: ^Extension_Registry,
	module_registry: ^Module_Registry,
) -> bool {
	if registry == nil || !registry.initialized do return false

	if module_registry == nil || !module_registry.initialized do return false

	log.info("Registering extensions...")

	for i := 1; i < len(registry.extensions); i += 1 {
		extension := &registry.extensions[i]
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

// ===============================
// RESOLVE EXTENSION DEPENDENCIES
extension_resolve_dependencies :: proc(
	registry: ^Extension_Registry,
	module_registry: ^Module_Registry,
) -> bool {
	if registry == nil || !registry.initialized do return false

	if module_registry == nil || !module_registry.initialized do return false

	log.info("Resolving extension dependencies...")

	for i := 1; i < len(registry.extensions); i += 1 {
		extension := &registry.extensions[i]
		if extension.state != .Loaded do continue

		// --------------------------------------------------------------------
		// Extension dependencies
		// --------------------------------------------------------------------
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

// =========================
// ACTIVATE ALL EXTENSIONS
extension_activate_all :: proc(registry: ^Extension_Registry) -> bool {
	if registry == nil || !registry.initialized do return false
	log.info("Activating extensions...")

	for i := 1; i < len(registry.extensions); i += 1 {
		extension := &registry.extensions[i]
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

// =========================
// DEACTIVATE ALL EXTENSIONS
extension_deactivate_all :: proc(registry: ^Extension_Registry) -> bool {
	if registry == nil || !registry.initialized do return false
	log.info("Deactivating extensions...")
	// Reverse order.
	for i := len(registry.extensions) - 1; i >= 1; i -= 1 {
		extension := &registry.extensions[i]
		if extension.state != .Active do continue
		log.info("Deactivating extension: %s", extension.api.identity.name)

		if extension.api.deactivate != nil {
			extension.api.deactivate(&extension.ctx)
		}
		extension.state = .Registered
	}
	return true
}

// =======================
// UNLOAD ALL EXTENSIONS
extension_unload_all :: proc(registry: ^Extension_Registry) -> bool {
	if registry == nil || !registry.initialized do return false
	log.info("Unloading extensions...")
	// Reverse order.
	for i := len(registry.extensions) - 1; i >= 1; i -= 1 {
		extension := &registry.extensions[i]
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
				// FIX: 'name' is now a string, matching the map key type
				delete_key(&registry.by_name, name)
			}
		}

		extension_registration_destroy(&extension.registration)

		// Close DLL.
		if extension.library != {} do dynlib.unload_library(extension.library)
		handle := extension.handle
		extension.state = .Unloaded
		extension_registry_release_handle(registry, handle)
	}
	return true
}
