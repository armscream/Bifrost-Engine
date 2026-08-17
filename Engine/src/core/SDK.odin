// Engine\src\Core\SDK.odin
package Core

import "core:mem"
// ============================================================================
// YMIR SDK
// ============================================================================
//
// Public engine API.
//
// Game code, modules and plugins should use SDK procedures rather than
// reaching directly into engine implementation details.
//
// ============================================================================


// ----------------------------------------------------------------------------
// ENGINE
// ----------------------------------------------------------------------------

engine_is_editor :: proc() -> bool
engine_is_running :: proc() -> bool
engine_delta_time :: proc() -> f32


// ============================================================================
// MODULES
// ============================================================================

// Search for a module by name and returns its handle.
module_find :: proc(registry: ^Module_Registry, name: string) -> (ModuleHandle, bool) {

	if registry == nil || !registry.initialized {
		return INVALID_MODULE_HANDLE, false
	}

	if len(name) == 0 {
		return INVALID_MODULE_HANDLE, false
	}

	handle, found := registry.by_name[name]

	if !found {
		return INVALID_MODULE_HANDLE, false
	}

	// ------------------------------------------------------------------------
	// Validate the lookup result.
	//
	// This protects against stale/corrupt lookup entries.
	// ------------------------------------------------------------------------

	if !module_is_valid(registry, handle) {
		return INVALID_MODULE_HANDLE, false
	}

	return handle, true
}
// Returns true if the module is still valid.
module_is_valid :: proc(registry: ^Module_Registry, handle: ModuleHandle) -> bool {
	_, ok := module_registry_get(registry, handle)
	return ok
}
// Self-explanatory. Returns true if the module is loaded.
module_is_loaded :: proc(registry: ^Module_Registry, handle: ModuleHandle) -> bool {
	module, ok := module_registry_get(registry, handle)
	if !ok {
		return false
	}
	switch module.state {
	case .Loaded, .Registered, .Active:
		return true
	case .Unloaded, .Failed:
		return false
	}
	return false
}
// Returns true if the module is active.
module_is_active :: proc(registry: ^Module_Registry, handle: ModuleHandle) -> bool {
	module, ok := module_registry_get(registry, handle)
	if !ok {
		return false
	}
	return module.state == Module_State.Active
}
// Returns module version. Requires module handle.
module_version :: proc(registry: ^Module_Registry, handle: ModuleHandle) -> Version {

	module, ok := module_registry_get(registry, handle)

	if !ok {
		return Version{}
	}

	return module.api.identity.version
}
// Returns module type. Requires module handle.
module_type :: proc(registry: ^Module_Registry, handle: ModuleHandle) -> Module_Type {
	module, ok := module_registry_get(registry, handle)
	if !ok {
		return Module_Type.Other
	}
	return module.api.identity.type
}
// Returns all currently valid modules of the requested type.
//
// The returned collection is owned by the caller's allocator. This is
// intentionally a copy because the registry's internal lookup array may contain
// stale/invalid handles after module removal.
module_find_by_type :: proc(
	registry: ^Module_Registry,
	module_type: Module_Type,
	allocator: mem.Allocator,
) -> [dynamic]ModuleHandle {
	return module_collect_by_type(registry, module_type, allocator)
}
// Capabilities are a bit set list that describes what a module can do. Authored in the Module_Identity struct.
module_has_capability :: proc(
	registry: ^Module_Registry,
	handle: ModuleHandle,
	capability: Module_Capability,
) -> bool {
	module, ok := module_registry_get(registry, handle)
	if !ok {
		return false
	}
	return capability in module.api.identity.capabilities
}


// ============================================================================
// SERVICES
// ============================================================================

service_find :: proc(name: string) -> (ServiceHandle, bool)
service_is_valid :: proc(handle: ServiceHandle) -> bool
service_get :: proc(handle: ServiceHandle) -> rawptr


// ----------------------------------------------------------------------------
// EVENTS
// ----------------------------------------------------------------------------

emit_event :: proc(event: rawptr)


// ----------------------------------------------------------------------------
// ASSETS
// ----------------------------------------------------------------------------

asset_load :: proc(path: string) -> rawptr
asset_unload :: proc(asset: rawptr)


// ----------------------------------------------------------------------------
// ECS
// ----------------------------------------------------------------------------

entity_create :: proc() -> rawptr
entity_destroy :: proc(entity: rawptr)


// ----------------------------------------------------------------------------
// RENDERING
// ----------------------------------------------------------------------------

renderer_begin_frame :: proc()
renderer_end_frame :: proc()


// ----------------------------------------------------------------------------
// AUDIO
// ----------------------------------------------------------------------------

audio_play :: proc(sound: rawptr)


// ----------------------------------------------------------------------------
// PHYSICS
// ----------------------------------------------------------------------------

physics_raycast :: proc() -> bool
