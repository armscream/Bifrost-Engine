// Engine\src\Core\SDK.odin
package Core

import "core:mem"

// ============================================================================
// SDK
// ============================================================================
//
// Public engine API.
//
// Game code, modules, and plugins should use SDK procedures rather than
// reaching directly into engine implementation details. The SDK deliberately
// accepts `^Module_Registry`, `^Extension_Registry`, `^Service_Registry` so it
// can be tested with isolated registries; the engine passes its globals
// through these entry points.
//
// Forward-declared procedures (e.g. emit_event, asset_load) are intentionally
// only signatures here — their implementations live in the modules that
// own each subsystem.
// ============================================================================

// ============================================================================
// ENGINE
// ============================================================================
engine_is_editor  :: proc() -> bool
engine_is_running :: proc() -> bool
engine_delta_time :: proc() -> f32

// ============================================================================
// MODULES
// ============================================================================

// module_find resolves a module by name.
module_find :: proc(registry: ^Module_Registry, name: string) -> (ModuleHandle, bool) {
	if registry == nil || !registry.initialized do return INVALID_MODULE_HANDLE, false
	if len(name) == 0 do return INVALID_MODULE_HANDLE, false
	handle, found := registry.by_name[name]
	if !found do return INVALID_MODULE_HANDLE, false

	// Validate the lookup result. This protects against stale/corrupt
	// lookup entries.
	if !module_is_valid(registry, handle) do return INVALID_MODULE_HANDLE, false

	return handle, true
}

// module_is_valid returns true if the module is still valid.
module_is_valid :: proc(registry: ^Module_Registry, handle: ModuleHandle) -> bool {
	_, ok := module_registry_get(registry, handle)
	return ok
}

// module_is_loaded returns true if the module is loaded, registered, or active.
module_is_loaded :: proc(registry: ^Module_Registry, handle: ModuleHandle) -> bool {
	module, ok := module_registry_get(registry, handle)
	if !ok do return false
	switch module.state {
	case .Loaded, .Registered, .Active:
		return true
	case .Unloaded, .Failed:
		return false
	}
	return false
}

// module_is_active returns true if the module is active.
module_is_active :: proc(registry: ^Module_Registry, handle: ModuleHandle) -> bool {
	module, ok := module_registry_get(registry, handle)
	if !ok do return false
	return module.state == Component_State.Active
}

// module_version returns the module's declared version.
module_version :: proc(registry: ^Module_Registry, handle: ModuleHandle) -> Version {
	module, ok := module_registry_get(registry, handle)
	if !ok do return Version{}
	return module.descriptor.identity.version
}

// module_type returns the module's declared Lib_Type.
module_type :: proc(registry: ^Module_Registry, handle: ModuleHandle) -> Lib_Type {
	module, ok := module_registry_get(registry, handle)
	if !ok do return Lib_Type.Other
	return module.descriptor.identity.type
}

// module_find_by_type returns every currently-valid module of the requested
// type. The returned collection is owned by the caller's allocator; this is
// intentionally a copy because the registry's internal lookup array may
// contain stale/invalid handles after module removal.
module_find_by_type :: proc(
	registry: ^Module_Registry,
	lib_type: Lib_Type,
	allocator: mem.Allocator,
) -> [dynamic]ModuleHandle {
	return module_collect_by_type(registry, lib_type, allocator)
}

// module_has_capability reports whether the module has the given capability
// in its declared bit set.
module_has_capability :: proc(
	registry: ^Module_Registry,
	handle: ModuleHandle,
	capability: Component_Capability,
) -> bool {
	module, ok := module_registry_get(registry, handle)
	if !ok do return false
	return capability in module.descriptor.identity.capabilities
}

// ============================================================================
// EXTENSIONS
// ============================================================================

extension_find :: proc(registry: ^Extension_Registry, name: string) -> (ExtensionHandle, bool) {
	if registry == nil || !registry.initialized do return INVALID_EXTENSION_HANDLE, false
	if len(name) == 0 do return INVALID_EXTENSION_HANDLE, false

	handle, found := registry.by_name[name]
	if !found do return INVALID_EXTENSION_HANDLE, false
	if !extension_is_valid(registry, handle) do return INVALID_EXTENSION_HANDLE, false
	return handle, true
}

extension_is_loaded :: proc(registry: ^Extension_Registry, handle: ExtensionHandle) -> bool {
	extension, ok := extension_registry_get(registry, handle)
	if !ok do return false

	switch extension.state {
	case .Loaded, .Registered, .Active: return true
	case .Unloaded, .Failed:           return false
	}
	return false
}

extension_is_active :: proc(registry: ^Extension_Registry, handle: ExtensionHandle) -> bool {
	extension, ok := extension_registry_get(registry, handle)
	if !ok do return false
	return extension.state == .Active
}

extension_version :: proc(registry: ^Extension_Registry, handle: ExtensionHandle) -> Version {
	extension, ok := extension_registry_get(registry, handle)
	if !ok do return Version{}
	return extension.api.identity.version
}

// ============================================================================
// SERVICES
// ============================================================================

service_find :: proc(registry: ^Service_Registry, name: string) -> (ServiceHandle, bool) {
	if registry == nil || !registry.initialized do return INVALID_SERVICE_HANDLE, false
	if len(name) == 0 do return INVALID_SERVICE_HANDLE, false
	handle, found := registry.by_name[name]
	if !found do return INVALID_SERVICE_HANDLE, false
	if _, valid := service_registry_get(registry, handle); !valid do return INVALID_SERVICE_HANDLE, false
	return handle, true
}

// service_get returns the service instance for the given handle.
service_get :: proc(registry: ^Service_Registry, handle: ServiceHandle) -> rawptr {
	service, ok := service_registry_get(registry, handle)
	if !ok do return nil
	return service.instance
}

// ============================================================================
// RESOURCES
// ============================================================================

resource_find :: proc(registry: ^Resource_Registry, name: string) -> (ResourceHandle, bool) {
	if registry == nil || !registry.initialized do return INVALID_RESOURCE_HANDLE, false
	if len(name) == 0 do return INVALID_RESOURCE_HANDLE, false
	handle, found := registry.by_name[name]
	if !found do return INVALID_RESOURCE_HANDLE, false
	if _, valid := resource_registry_get(registry, handle); !valid do return INVALID_RESOURCE_HANDLE, false
	return handle, true
}

resource_get :: proc(registry: ^Resource_Registry, handle: ResourceHandle) -> rawptr {
	resource, ok := resource_registry_get(registry, handle)
	if !ok do return nil
	return resource.instance
}

// ============================================================================
// EVENTS
// ============================================================================

event_find :: proc(registry: ^Event_Registry, name: string) -> (EventHandle, bool) {
	if registry == nil || !registry.initialized do return INVALID_EVENT_HANDLE, false
	if len(name) == 0 do return INVALID_EVENT_HANDLE, false
	handle, found := registry.by_name[name]
	if !found do return INVALID_EVENT_HANDLE, false
	if _, valid := event_registry_get(registry, handle); !valid do return INVALID_EVENT_HANDLE, false
	return handle, true
}

// ============================================================================
// EVENTS
// ============================================================================
emit_event :: proc(event: rawptr)

// ============================================================================
// ASSETS
// ============================================================================
asset_load   :: proc(path: string) -> rawptr
asset_unload :: proc(asset: rawptr)

// ============================================================================
// ECS
// ============================================================================
entity_create  :: proc() -> rawptr
entity_destroy :: proc(entity: rawptr)

// ============================================================================
// RENDERING
// ============================================================================
renderer_begin_frame :: proc()
renderer_end_frame   :: proc()

// ============================================================================
// AUDIO
// ============================================================================
audio_play :: proc(sound: rawptr)

// ============================================================================
// PHYSICS
// ============================================================================
physics_raycast :: proc() -> bool