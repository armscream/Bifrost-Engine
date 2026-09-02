// Engine/src/Core/module_interface.odin
//
// Legacy Module-side ABI surface. The unified Component_Manager (in
// component.odin) replaces the old Module_Manager / Extension_Manager /
// Plugin_Manager triple. This file now contains only the Module_Context
// struct and a thin compatibility shim that maps Module_Registry onto
// the unified Component_Registry.
//
// New modules should use Component_Context directly and pull the
// registration API through CORE_LIB_INTERFACE_COMPONENT_REGISTRATION.
// Legacy modules that still reference Module_Registry / Module_Handle
// keep compiling because those types are now aliases over the unified
// ones.
package Core

import "core:mem"

Module_Context :: struct {
	api_version:       u32,
	allocator:         rawptr,
	self:              ComponentHandle,
	module_registry:   ^Module_Registry,
	service_registry:  ^Service_Registry,
	resource_registry: ^Resource_Registry,
	event_registry:    ^Event_Registry,
	scheduler:         rawptr,
	registration:      ^Component_Registration,
	lib_context:       Lib_Context,
}

Module_Registration_API :: Component_Registration_API

// Module_Registry is a bit-identical layout view of Component_Registry.
//
// Originally redeclared here as a full struct with the same field list,
// including `slots: hm.Dynamic_Handle_Map(Loaded_Component, ComponentHandle)`.
// That duplication forced the Odin constraint solver to walk the
// `Dynamic_Handle_Map` `where` clause twice against `Loaded_Component`,
// which combined with the rest of the package's type graph produced an
// exponential blowup that deadlocked the parser's worker threads during
// `odin check` on Core. (Workaround was `-thread-count:1`; the fix is to
// share the instantiation.)
//
// Now embedded as a single-field struct over Component_Registry so the
// generic instantiation lives in only one place. Layout is bit-identical
// (single field, same alignment/size rules as the underlying struct), so
// the existing casts `(^Component_Registry)(registry)` in this file's
// helpers and `cast(^Module_Registry)&GLOBAL_MODULE_MANAGER.registry` in
// component.odin remain valid — Odin accepts the cross-cast between
// layout-identical single-field-wrapper structs and the wrapped type.
Module_Registry :: struct {
	_: Component_Registry,
}

Loaded_Module       :: Loaded_Component
Module_Registration :: Component_Registration

// ============================================================================
// LEGACY HELPERS (forward to component.odin)
// ============================================================================

module_registry_get :: proc(
	registry: ^Module_Registry,
	handle: ComponentHandle,
) -> (^Loaded_Component, bool) {
	if registry == nil do return nil, false
	return component_registry_get((^Component_Registry)(registry), handle)
}

module_is_valid :: proc(registry: ^Module_Registry, handle: ComponentHandle) -> bool {
	if registry == nil do return false
	return component_is_valid((^Component_Registry)(registry), handle)
}

module_is_loaded :: proc(registry: ^Module_Registry, handle: ComponentHandle) -> bool {
	if registry == nil do return false
	return component_is_loaded((^Component_Registry)(registry), handle)
}

module_is_active :: proc(registry: ^Module_Registry, handle: ComponentHandle) -> bool {
	if registry == nil do return false
	return component_is_active((^Component_Registry)(registry), handle)
}

module_find :: proc(registry: ^Module_Registry, name: string) -> (ComponentHandle, bool) {
	if registry == nil do return INVALID_COMPONENT_HANDLE, false
	return component_lookup_by_name((^Component_Registry)(registry), name)
}

module_collect_by_type :: proc(
	registry: ^Module_Registry,
	lib_type: Lib_Type,
	allocator: mem.Allocator,
) -> [dynamic]ComponentHandle {
	if registry == nil {
		return make([dynamic]ComponentHandle, 0, allocator)
	}
	return component_collect_by_type((^Component_Registry)(registry), lib_type, allocator)
}

module_version :: proc(registry: ^Module_Registry, handle: ComponentHandle) -> Version {
	comp, ok := module_registry_get(registry, handle)
	if !ok do return Version{}
	return comp.descriptor.version
}

module_type :: proc(registry: ^Module_Registry, handle: ComponentHandle) -> Lib_Type {
	comp, ok := module_registry_get(registry, handle)
	if !ok do return .Other
	return comp.descriptor.type
}

module_has_capability :: proc(
	registry: ^Module_Registry,
	handle: ComponentHandle,
	capability: Component_Capability,
) -> bool {
	comp, ok := module_registry_get(registry, handle)
	if !ok do return false
	return capability in comp.descriptor.capabilities
}
