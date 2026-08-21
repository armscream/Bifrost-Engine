// Engine/src/Core/module_registration.odin
package Core

import "core:log"
import "core:mem"

// ============================================================================
// REGISTRATION TYPES
// ============================================================================
//
// Modules and plugins use these descriptions to tell Core what they provide.
// these structures describe things a module contributes to the engine. Registration is metadata owned by Core.
// The actual implementation remains owned by the module.
// Registration is intentionally declarative:
//
//     Module/Plugin
//         |
//         +--> Service_Registration
//         +--> System_Registration
//         +--> Resource_Registration
//         +--> Event_Registration
//         |
//         v
//       Core
//
// Core then installs these into the appropriate runtime registries.
//
// IMPORTANT:
// These structures describe ownership and construction. They do not expose
// the internal registry implementations to modules/plugins.
// ============================================================================

//  ============================================================================
// Services are long-lived interfaces.
//
// Example:
//
//     Bifrost_Renderer
//         -> "Renderer"
//         -> instance = ^Renderer_Service
//
// The instance is owned by the registering module/plugin.
// Core calls destroy() when the service is unregistered.
// ============================================================================
Service_Registration :: struct {
	name: string,
    // service implementation supplied by the module.
    instance: rawptr,

    // called when Core removes the service
    // may be nil if the instance does not req destruction.
    destroy: proc(instance: rawptr),
}

// ============================================================================
// Systems are pieces of executable runtime work.
//
// The scheduler will eventually consume these registrations.
//
// Keep this intentionally generic for now. The DAG/scheduler module can later
// interpret the stage, flags, dependencies and callback.
//
// ============================================================================
System_Registration :: struct {
	name: string,
    // system execution callbac, the scheduler layer will eventually convert this into it's internal task/system representation.
    execute: proc(ctx: rawptr),
    // Optional scheduler metadata.
    state: u32,
    // Execution flags
    flags: u32,
}

// ============================================================================
// Resources are named runtime objects owned by a module/plugin.
//
// Examples:
//
//     "Renderer.Device"
//     "Physics.World"
//     "Animation.Database"
//
// A resource may be retrieved by name later through the resource API.
// ============================================================================
Resource_Registration :: struct {
    name: string, 
    instance: rawptr,
    // Called when Core removes the resource.
    destroy: proc(resource: rawptr),
}

// ============================================================================
// Events describe event types understood by the event system.
// the actual event bus can be implemented later. Core only needs a stable
// registration description at this layer.
// ============================================================================
Event_Registration :: struct {
    name: string,
    // size of the event payload in bytes.
    size: u32,
    // optional allignment requirement.
    allignment: u32,
}
// ============================================================================
// MODULE REGISTRATION
// ============================================================================
//
// Registration is the mechanism through which a loaded module tells Core
// what it provides.
//
// Registration happens after dependency resolution and before activation.
//
// A module should NOT directly manipulate Core registries during load().
// Instead:
//
//     load()
//         -> initialize module-owned state
//
//     register()
//         -> register services/systems/resources/events
//
//     activate()
//         -> begin runtime operation
//
// ============================================================================


// ============================================================================
// REGISTRATION ACCESS
// ============================================================================
@(private)
module_get_registration :: proc(registry: ^Module_Registry, handle: ModuleHandle) -> (^Module_Registration, bool) {
    if registry == nil || !registry.initialized {return nil, false}
    module, ok := module_registry_get(registry, handle)
    if !ok {return nil, false}
    return &module.registration, true
}

// ============================================================================
// REGISTRATION STATE VALIDATION
// ============================================================================
@(private)
module_registration_validate_owner :: proc(
	registry: ^Module_Registry,
	module_handle: ModuleHandle,
) -> (^Module_Registration, bool) {
    if registry == nil || !registry.initialized do return nil, false
    module, ok := module_registry_get(registry, module_handle)
    if !ok do return nil, false
    if module.state != Load_State.Registered {
        log.error("Module [%d:%d] cannot register: module is not in Registered state.",
        module_handle.index, module_handle.generation)
        return nil, false
    }
    return &module.registration, true
}

// ============================================================================
// SERVICE
// ============================================================================
@(private)
module_registration_add_service :: proc(
    registry: ^Module_Registry,
    module: ModuleHandle,
    registration: Service_Registration,
) -> bool {
    module_registration, ok := module_registration_validate_owner(
        registry, module)
        if !ok do return false
    if len(registration.name) == 0 {
        log.error("Module [%d:%d] cannot register service: service has no name.",
        module.index, module.generation)
        return false
    }
    if registration.instance == nil {
        log.error("Module [%d:%d] cannot register service '%s': instance is nil.",
        module.index, module.generation, registration.name)
        return false
    }
    append(&module_registration.services, registration)
    return true
}

// ============================================================================
// SYSTEM registration
// ============================================================================
@(private)
module_registration_add_system :: proc(
    registry: ^Module_Registry,
    module: ModuleHandle,
    registration: System_Registration,
) -> bool {
    module_registration, ok := module_registration_validate_owner(registry, module)
    if !ok do return false
    if len(registration.name) == 0 {
        log.error("Module [%d:%d] cannot register system: system has no name.",
        module.index, module.generation)
        return false
    }
    if registration.execute == nil {
        log.error("Module [%d:%d] cannot register system '%s': execute callback is nil.",
        module.index, module.generation, registration.name)
        return false
    }
    append(&module_registration.systems, registration)
    return true
}
// ===========================================
// Resource registration
// ===========================================
@(private)
module_registration_add_resource :: proc(registry: ^Module_Registry, module: ModuleHandle, registration: Resource_Registration) -> bool {
    if registry == nil || !registry.initialized {return false}
    module_registration, ok := module_registration_validate_owner(registry, module)
    if !ok do return false
    if len(registration.name) == 0 {
        log.error("Module [%d:%d] cannot register resource: resource has no name.",
        module.index, module.generation)
        return false
    }
    if registration.instance == nil {
        log.error("Module [%d:%d] cannot register resource '%s': instance is nil.",
        module.index, module.generation, registration.name)
        return false
    }
    append(&module_registration.resources, registration)
    return true
}
// =====================================
// Event registration
//===================================
@(private)
module_registration_add_event :: proc(registry: ^Module_Registry, 
    module: ModuleHandle, registration: Event_Registration) -> bool {
    module_registration, ok := module_registration_validate_owner(registry, module)
    if !ok do return false
    if len(registration.name) == 0 {
        log.error("Module [%d:%d] cannot register event with empty name.",
        module.index, module.generation)
        return false
    }
    if registration.size == 0 {
        log.error("Module [%d:%d] cannot register event '%s' with size 0.",
        module.index, module.generation, registration.name)
        return false
    }
    append(&module_registration.events, registration)
    return true
}

@(private)
module_load_project_modules :: proc() -> bool {
    log.warn("module_load_project_modules() is not implemented")
    // TODO: implement me
    return true
}

// ===================================
// MODULE LIFECYCLE load->register->activate->RUNNING->deactivate->unload
// ===================================
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
		if module.state != Load_State.Loaded {
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
				module.state = Load_State.Failed
				module_registration_destroy(&module.registration)
				return false
			}
		}
		// Registration succeeded.
		module.state = Load_State.Registered
		log.info(
			"Registered module: %s v%d.%d.%d",
			module.api.identity.name,
			module.api.identity.version.major,
			module.api.identity.version.minor,
			module.api.identity.version.patch,
		)
	}
	return true
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
	   Load_State.Registered {log.error("Cannot activate module '%s': expected Registered state, got %v.", module.api.identity.name, module.state)
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
			module.state = Load_State.Failed
			return false
		}
	}
	// Now activation succeeded.
	module.state = Load_State.Active
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
				if module.state == Load_State.Active {
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
	if module.state != Load_State.Active {return false}
	if module.api.deactivate != nil {module.api.deactivate(&module.ctx)}
	module.state = Load_State.Registered
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
	for i := len(registry.dependency_order) -1; i >= 0; i -= 1 {
		handle := registry.dependency_order[i]
		module, ok := module_registry_get(registry, handle)
		if !ok {continue}
		if module.state != Load_State.Active {continue}
		module_deactivate(registry, handle)
	}
	log.info("All modules deactivated.")
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
		if module.state == Load_State.Active {
			log.error("Cannot unload active module: %s.", "Module must be deactivated first.",
			module.api.identity.name)
			return false
		}
		if module.state != Load_State.Registered &&
		module.state != Load_State.Unloaded {continue}
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
// MODULE REGISTRATION API
// ============================================================================
//
// This is the ABI-safe interface exposed to modules.
//
// The module receives a Module_Context containing a pointer to this API.
// The API internally routes the registration request to the correct
// Module_Registration object.
// ============================================================================
@(private)
module_context_add_service :: proc(ctx: ^Module_Context, registration: Service_Registration) -> bool {
    if ctx == nil do return false
    registry := cast(^Module_Registry)(ctx.module_registry)
    return module_registration_add_service(registry, ctx.self, registration)
}

@(private)
module_context_add_system :: proc(ctx: ^Module_Context, registration: System_Registration) -> bool {
    if ctx == nil do return false
    registry := cast(^Module_Registry)(ctx.module_registry)
    return module_registration_add_system(registry, ctx.self, registration)
}

@(private)
module_context_add_resource :: proc(ctx: ^Module_Context, registration: Resource_Registration) -> bool {
    if ctx == nil do return false
    registry := cast(^Module_Registry)(ctx.module_registry)
    return module_registration_add_resource(registry, ctx.self, registration)
}

@(private)
module_context_add_event :: proc(ctx: ^Module_Context, registration: Event_Registration) -> bool {
    if ctx == nil do return false
    registry := cast(^Module_Registry)(ctx.module_registry)
    return module_registration_add_event(registry, ctx.self, registration)
}

// ============================================================================
// CORE REGISTRATION API INSTANCE
// ============================================================================
GLOBAL_MODULE_REGISTRATION_API: Module_Registration_API = {
	add_service  = module_context_add_service,
	add_system   = module_context_add_system,
	add_resource = module_context_add_resource,
	add_event    = module_context_add_event,
}