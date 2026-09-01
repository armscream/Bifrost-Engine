// Engine/src/Core/component_registration.odin
//
// Unified component registration API. Replaces the legacy
// Module_Registration_API and the parallel Extension_API / Plugin_API
// that lived in module_registration.odin / extensions.odin /
// plugins.odin.
//
// Components (module, extension, plugin) obtain the registration API
// from Core by calling lib_context_query(ctx, "component_registration").
// The returned pointer is a Component_Registration_API vtable; each
// proc recovers the Component_Context from the DLL's Lib_Context and
// routes the registration into the matching Component_Registration
// bucket.
//
// This is the single source of truth for component-side bookkeeping.
// ============================================================================
package Core

import "core:log"

// ============================================================================
// SERVICE / SYSTEM / RESOURCE / EVENT REGISTRATIONS
// ============================================================================
//
// These structs describe what a component contributes. They are
// declared once here so modules, extensions, and plugins can all
// push entries through the same add_* procs.

Service_Registration :: struct {
	name:     string,
	instance: rawptr,
	// destroy is called by the service registry when the component
	// is unloaded. May be nil.
	destroy:  proc(instance: rawptr),
}

System_Registration :: struct {
	name:    string,
	execute: proc(ctx: rawptr),
	info:    System_Info,
	flags:   u32,
}

Resource_Registration :: struct {
	name:     string,
	instance: rawptr,
	destroy:  proc(instance: rawptr),
}

Event_Registration :: struct {
	name:       string,
	size:       u32,
	allignment: u32,
}

// ============================================================================
// COMPONENT REGISTRATION API (ABI surface)
// ============================================================================

// Component_Registration_API is the vtable components use to register
// services / systems / resources / events / targets with their own
// Component_Registration bucket (which the engine later promotes into
// the global registries on activation).
Component_Registration_API :: struct {
	add_service:  proc(lib_ctx: ^Lib_Context, registration: Service_Registration) -> bool,
	add_system:   proc(lib_ctx: ^Lib_Context, registration: System_Registration) -> bool,
	add_resource: proc(lib_ctx: ^Lib_Context, registration: Resource_Registration) -> bool,
	add_event:    proc(lib_ctx: ^Lib_Context, registration: Event_Registration) -> bool,
	add_target:   proc(lib_ctx: ^Lib_Context, target: Extension_Target) -> bool,
}

@(private)
component_context_add_service :: proc(
	lib_ctx: ^Lib_Context,
	registration: Service_Registration,
) -> bool {
	ctx, ok := registration_component_ctx(lib_ctx)
	if !ok do return false
	return component_add_service(ctx, registration)
}

@(private)
component_context_add_system :: proc(
	lib_ctx: ^Lib_Context,
	registration: System_Registration,
) -> bool {
	ctx, ok := registration_component_ctx(lib_ctx)
	if !ok do return false
	return component_add_system(ctx, registration)
}

@(private)
component_context_add_resource :: proc(
	lib_ctx: ^Lib_Context,
	registration: Resource_Registration,
) -> bool {
	ctx, ok := registration_component_ctx(lib_ctx)
	if !ok do return false
	return component_add_resource(ctx, registration)
}

@(private)
component_context_add_event :: proc(
	lib_ctx: ^Lib_Context,
	registration: Event_Registration,
) -> bool {
	ctx, ok := registration_component_ctx(lib_ctx)
	if !ok do return false
	return component_add_event(ctx, registration)
}

@(private)
component_context_add_target :: proc(
	lib_ctx: ^Lib_Context,
	target: Extension_Target,
) -> bool {
	ctx, ok := registration_component_ctx(lib_ctx)
	if !ok do return false
	if ctx.kind != .Extension {
		log.errorf("[Core] add_target called from non-extension component (kind=%s).", component_kind_name(ctx.kind))
		return false
	}
	append(&ctx.registration.targets, target)
	return true
}

// registration_component_ctx unpacks the Component_Context out of the
// Lib_Context the DLL handed us.
@(private)
registration_component_ctx :: proc(lib_ctx: ^Lib_Context) -> (^Component_Context, bool) {
	if lib_ctx == nil do return nil, false
	core_ctx := cast(^Core_Lib_Context)lib_ctx.user_data
	if core_ctx == nil || core_ctx.component_context == nil do return nil, false
	return core_ctx.component_context, true
}

@(private)
GLOBAL_COMPONENT_REGISTRATION_API: Component_Registration_API = {
	add_service  = component_context_add_service,
	add_system   = component_context_add_system,
	add_resource = component_context_add_resource,
	add_event    = component_context_add_event,
	add_target   = component_context_add_target,
}

// ============================================================================
// INTERNAL ADD HELPERS
// ============================================================================

component_add_service :: proc(
	ctx: ^Component_Context,
	registration: Service_Registration,
) -> bool {
	if ctx == nil do return false
	if len(registration.name) == 0 {
		log.errorf("[%s] cannot register service: empty name.", component_kind_name(ctx.kind))
		return false
	}
	if registration.instance == nil {
		log.errorf("[%s] cannot register service '%s': instance is nil.", component_kind_name(ctx.kind), registration.name)
		return false
	}
	append(&ctx.registration.services, registration)
	return true
}

component_add_system :: proc(
	ctx: ^Component_Context,
	registration: System_Registration,
) -> bool {
	if ctx == nil do return false
	if len(registration.name) == 0 {
		log.errorf("[%s] cannot register system: empty name.", component_kind_name(ctx.kind))
		return false
	}
	if registration.execute == nil {
		log.errorf("[%s] cannot register system '%s': execute callback is nil.", component_kind_name(ctx.kind), registration.name)
		return false
	}
	append(&ctx.registration.systems, registration)
	return true
}

component_add_resource :: proc(
	ctx: ^Component_Context,
	registration: Resource_Registration,
) -> bool {
	if ctx == nil do return false
	if len(registration.name) == 0 {
		log.errorf("[%s] cannot register resource: empty name.", component_kind_name(ctx.kind))
		return false
	}
	if registration.instance == nil {
		log.errorf("[%s] cannot register resource '%s': instance is nil.", component_kind_name(ctx.kind), registration.name)
		return false
	}
	append(&ctx.registration.resources, registration)
	return true
}

component_add_event :: proc(
	ctx: ^Component_Context,
	registration: Event_Registration,
) -> bool {
	if ctx == nil do return false
	if len(registration.name) == 0 {
		log.errorf("[%s] cannot register event: empty name.", component_kind_name(ctx.kind))
		return false
	}
	if registration.size == 0 {
		log.errorf("[%s] cannot register event '%s' with size 0.", component_kind_name(ctx.kind), registration.name)
		return false
	}
	append(&ctx.registration.events, registration)
	return true
}
