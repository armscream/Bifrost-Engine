// Engine/src/Core/module_registration.odin
package Core

import "core:log"
import "core:mem"

// Module registration types
// these structures describe things a module contributes to the engine. Registration is metadata owned by Core.
// The actual implementation remains owned by the module.

Service_Registration :: struct {
	name: string,
    // service implementation supplied by the module.
    instance: rawptr,
    // optional destruction callback.
    destroy: proc(instance: rawptr),
}

System_Registration :: struct {
	name: string,
    // system execution callbac, the scheduler layer will eventually convert this into it's internal task/system representation.
    execute: proc(ctx: rawptr),
    // Optional opaque user data owned by the module.
    user_data: rawptr,
    // Execution flags
    flags: System_Registration_Flags,
}
System_Registration_Flags :: bit_set[System_Registration_Flag]

System_Registration_Flag :: enum u32{
    None,
    Parallel,
    Main_Thread,
    Render,
    Fixed_Update,
    Editor_Only,
    Runtime_Only,
}

Resource_Registration :: struct {
    name: string, 
    // Opaque resource type identifier
    type_id: u64,
    // Optional resource destruction callback
    destroy: proc(resource: rawptr),
    // Optional opaque user data,
    user_data: rawptr,
}

Event_Registration :: struct {
    name: string,
    // stable event type identifier
    type_id: u64,
    // Event dispatch callback
    // The event system will eventually own the dispatch processs.
    dispatch: proc(event: rawptr, user_data: rawptr),
    user_data: rawptr,
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
// SERVICE
// ============================================================================
@(private)
module_registration_add_service :: proc(
    registry: ^Module_Registry,
    module: ModuleHandle,
    registration: Service_Registration,
) -> bool {
    if registry == nil || !registry.initialized  {return false}
    module_registration, ok := module_get_registration(registry, module)
    if !ok {return false}
    owner, owner_ok := module_registry_get(registry, module)
    if !owner_ok {return false}
    if owner.state != Module_State.Registered {
        log.error("Module [%d:%d] cannot register a service: module is not registered.",
        module.index, module.generation)
        return false
    }
    append(&module_registration.services, registration)
    return true
}

// ============================================================================
// SYSTEM
// ============================================================================
@(private)
module_registration_add_system :: proc(
    registry: ^Module_Registry,
    module: ModuleHandle,
    registration: System_Registration,
) -> bool {
    if registry == nil || !registry.initialized {return false}
    module_registration, ok := module_get_registration(registry, module)
    if !ok {return false}
    owner, owner_ok := module_registry_get(registry, module)
    if !owner_ok {return false}
    if owner.state != Module_State.Registered {
        log.error("Module [%d:%d] cannot register a system: module is not registered.",
        module.index, module.generation)
        return false
    }
    append(&module_registration.systems, registration)//did this work?
    return true
}
// ===========================================
// Resource registration
// ===========================================
@(private)
module_registration_add_resource :: proc(registry: ^Module_Registry, module: ModuleHandle, registration: Resource_Registration) -> bool {
    if registry == nil || !registry.initialized {return false}
    module_registration, ok := module_get_registration(registry, module)
    if !ok  {return false} 
    owner, owner_ok := module_registry_get(registry, module)
    if !owner_ok {return false}
    if owner.state != Module_State.Registered {
        log.error("Module [%d:%d] cannot register a resource: module is not Registered.",
        module.index, module.generation)
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
    if registry == nil || !registry.initialized {return false}
    module_registration, ok := module_get_registration(registry, module)
    if !ok {return false}
    owner, owner_ok := module_registry_get(registry, module)
    if !owner_ok {return false}
    if owner.state != Module_State.Registered {
        log.error("Module [%d:%d] cannot register an event: module is not registered.",
        module.index, module.generation)
        return false
    }
    append(&module_registration.events, registration)
    return true
}
