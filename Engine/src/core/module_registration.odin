// Engine/src/Core/module_registration.odin
package Core

import "core:log"

// ============================================================================
// REGISTRATION TYPES
// ============================================================================
//
// Modules and plugins use these descriptions to tell Core what they provide.
// These structures describe things a module contributes to the engine.
// Registration is metadata owned by Core. The actual implementation remains
// owned by the module.
//
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
//   These structures describe ownership and construction. They do not expose
//   the internal registry implementations to modules/plugins. Components
//   receive only Service_Registration / System_Registration / etc. — never
//   a pointer into a Core registry.
// ============================================================================

// ============================================================================
// Services
// ============================================================================
//
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
Service_Registration :: struct {
	name:     string,
	// service implementation supplied by the module.
	instance: rawptr,

	// called when Core removes the service.
	// may be nil if the instance does not require destruction.
	destroy:  proc(instance: rawptr),
}

// Systems are pieces of executable runtime work. The scheduler will
// eventually consume these registrations.
//
// Kept intentionally generic for now; the DAG/scheduler module can later
// interpret stage, flags, dependencies, and the execute callback.
System_Registration :: struct {
	name:    string,
	// system execution callback; the scheduler layer will convert this into
	// its internal task/system representation.
	execute: proc(ctx: rawptr),
	// Optional scheduler metadata.
	state:   u32,
	// Execution flags.
	flags:   u32,
}

// ============================================================================
// Resources
// ============================================================================
//
// Resources are named runtime objects owned by a module/plugin.
//
// Examples:
//
//     "Renderer.Device"
//     "Physics.World"
//     "Animation.Database"
//
// A resource may be retrieved by name later through the resource API.
Resource_Registration :: struct {
	name:     string,
	instance: rawptr,
	// Called when Core removes the resource.
	destroy:  proc(resource: rawptr),
}

// ============================================================================
// Events
// ============================================================================
//
// Events describe event types understood by the event system.
// The actual event bus can be implemented later. Core only needs a stable
// registration description at this layer.
Event_Registration :: struct {
	name:       string,
	// size of the event payload in bytes.
	size:       u32,
	// optional alignment requirement.
	allignment: u32,
}

// ============================================================================
// MODULE REGISTRATION API (ABI surface)
// ============================================================================
//
// This is the interface exposed to modules. The module receives a
// Module_Context containing a pointer to this API; the API routes each
// registration request to the correct registry bucket.
// ============================================================================

@(private)
module_context_add_service :: proc(
	ctx: ^Module_Context,
	registration: Service_Registration,
) -> bool {
	if ctx == nil do return false
	registry := cast(^Module_Registry)(ctx.module_registry)
	return module_registration_add_service(registry, ctx.self, registration)
}

@(private)
module_context_add_system :: proc(
	ctx: ^Module_Context,
	registration: System_Registration,
) -> bool {
	if ctx == nil do return false
	registry := cast(^Module_Registry)(ctx.module_registry)
	return module_registration_add_system(registry, ctx.self, registration)
}

@(private)
module_context_add_resource :: proc(
	ctx: ^Module_Context,
	registration: Resource_Registration,
) -> bool {
	if ctx == nil do return false
	registry := cast(^Module_Registry)(ctx.module_registry)
	return module_registration_add_resource(registry, ctx.self, registration)
}

@(private)
module_context_add_event :: proc(
	ctx: ^Module_Context,
	registration: Event_Registration,
) -> bool {
	if ctx == nil do return false
	registry := cast(^Module_Registry)(ctx.module_registry)
	return module_registration_add_event(registry, ctx.self, registration)
}

// ============================================================================
// CORE REGISTRATION API INSTANCE
// ============================================================================
//
// Globally-installed Module_Registration_API. lib_context_query() hands a
// pointer to this struct to modules that ask for "module_registration".
// ============================================================================

@(private)
GLOBAL_MODULE_REGISTRATION_API: Module_Registration_API = {
	add_service  = module_context_add_service,
	add_system   = module_context_add_system,
	add_resource = module_context_add_resource,
	add_event    = module_context_add_event,
}

// ============================================================================
// INTERNAL ADD HELPERS
// ============================================================================
//
// Each helper validates ownership and pushes the registration into the
// appropriate bucket on Module_Registration. Modules reach these only
// through the context_add_* procs above.

@(private)
module_registration_validate_owner :: proc(
	registry: ^Module_Registry,
	module_handle: ModuleHandle,
) -> (
	^Module_Registration,
	bool,
) {
	if registry == nil || !registry.initialized do return nil, false
	module, ok := module_registry_get(registry, module_handle)
	if !ok do return nil, false
	if module.state != Component_State.Registered {
		log.error(
			"Module [%d:%d] cannot register: module is not in Registered state.",
			module_handle.idx,
			module_handle.gen,
		)
		return nil, false
	}
	return &module.registration, true
}

@(private)
module_registration_add_service :: proc(
	registry: ^Module_Registry,
	module: ModuleHandle,
	registration: Service_Registration,
) -> bool {
	module_registration, ok := module_registration_validate_owner(registry, module)
	if !ok do return false
	if len(registration.name) == 0 {
		log.error(
			"Module [%d:%d] cannot register service: service has no name.",
			module.idx,
			module.gen,
		)
		return false
	}
	if registration.instance == nil {
		log.error(
			"Module [%d:%d] cannot register service '%s': instance is nil.",
			module.idx,
			module.gen,
			registration.name,
		)
		return false
	}
	append(&module_registration.services, registration)
	return true
}

@(private)
module_registration_add_system :: proc(
	registry: ^Module_Registry,
	module: ModuleHandle,
	registration: System_Registration,
) -> bool {
	module_registration, ok := module_registration_validate_owner(registry, module)
	if !ok do return false
	if len(registration.name) == 0 {
		log.error(
			"Module [%d:%d] cannot register system: system has no name.",
			module.idx,
			module.gen,
		)
		return false
	}
	if registration.execute == nil {
		log.error(
			"Module [%d:%d] cannot register system '%s': execute callback is nil.",
			module.idx,
			module.gen,
			registration.name,
		)
		return false
	}
	append(&module_registration.systems, registration)
	return true
}

@(private)
module_registration_add_resource :: proc(
	registry: ^Module_Registry,
	module: ModuleHandle,
	registration: Resource_Registration,
) -> bool {
	if registry == nil || !registry.initialized {return false}
	module_registration, ok := module_registration_validate_owner(registry, module)
	if !ok do return false
	if len(registration.name) == 0 {
		log.error(
			"Module [%d:%d] cannot register resource: resource has no name.",
			module.idx,
			module.gen,
		)
		return false
	}
	if registration.instance == nil {
		log.error(
			"Module [%d:%d] cannot register resource '%s': instance is nil.",
			module.idx,
			module.gen,
			registration.name,
		)
		return false
	}
	append(&module_registration.resources, registration)
	return true
}

@(private)
module_registration_add_event :: proc(
	registry: ^Module_Registry,
	module: ModuleHandle,
	registration: Event_Registration,
) -> bool {
	module_registration, ok := module_registration_validate_owner(registry, module)
	if !ok do return false
	if len(registration.name) == 0 {
		log.error(
			"Module [%d:%d] cannot register event with empty name.",
			module.idx,
			module.gen,
		)
		return false
	}
	if registration.size == 0 {
		log.error(
			"Module [%d:%d] cannot register event '%s' with size 0.",
			module.idx,
			module.gen,
			registration.name,
		)
		return false
	}
	append(&module_registration.events, registration)
	return true
}