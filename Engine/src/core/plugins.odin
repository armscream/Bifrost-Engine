// Engine/src/Core/plugins.odin
package Core

import "core:log"
import "core:mem"

import hm "core:container/handle_map"

// ============================================================================
// PLUGIN SYSTEM
// ============================================================================
//
// Plugins = project/tool/editor-side functionality that is not necessarily
// part of the engine's runtime module architecture. They can still use the
// SDK and services, but they shouldn't be treated as "modules with a
// different name".
//
// The Plugin_API / Plugin_Context types below are public so plugins can
// implement against them; the registry/manager plumbing is package-internal.
//
// STATUS: structural plumbing only. The lifecycle procs (load_project /
// register_all / activate_all / deactivate_all / unload_all) currently log
// a warning and return so the engine boots without plugins. DLL loading,
// ABI dispatch, and SDK wiring land when the first real plugin needs them.
// ============================================================================

Plugin_API :: struct {
	api_version: u32,
	load:        proc(ctx: ^Plugin_Context) -> bool,
	register:    proc(ctx: ^Plugin_Context) -> bool,
	activate:    proc(ctx: ^Plugin_Context) -> bool,
	deactivate:  proc(ctx: ^Plugin_Context),
	unload:      proc(ctx: ^Plugin_Context),
}

// Plugin_Context is the plugin's gateway into Core. Mirrors Module_Context
// and Extension_Context so plugins can use the same SDK lookup helpers
// modules and extensions do (lib_context_query for service_registry,
// etc.). The struct is intentionally empty for now; populated when the
// first real plugin lands.
Plugin_Context :: struct {
	registry:          ^Plugin_Registry,
	handle:            PluginHandle,
	module_registry:   ^Module_Registry,
	service_registry:  ^Service_Registry,
	resource_registry: ^Resource_Registry,
	event_registry:    ^Event_Registry,
}

// ============================================================================
// INTERNAL TYPES
// ============================================================================

@(private)
Plugin_Registration :: struct {
	services:  [dynamic]Service_Registration,
	systems:   [dynamic]System_Registration,
	resources: [dynamic]Resource_Registration,
	events:    [dynamic]Event_Registration,
}

// Loaded_Plugin stores a plugin's DLL handle and a copy of its API. The
// DLL is opened by plugin_load_one (not yet implemented) and closed by
// plugin_manager_unload_all. Once Plugin_API migrates onto Loaded_Lib
// (the same way modules and extensions use it) the Dynamic_Library field
// collapses.
@(private)
Loaded_Plugin :: struct {
	handle:       PluginHandle,
	library:      Dynamic_Library,
	api:          Plugin_API,
	ctx:          Plugin_Context,
	state:        Component_State,
	registration: Plugin_Registration,
}

Plugin_Registry :: struct {
	allocator:   mem.Allocator,
	slots:       hm.Dynamic_Handle_Map(Loaded_Plugin, PluginHandle),
	by_name:     map[string]PluginHandle,
	initialized: bool,
}

Plugin_Manager :: struct {
	registry:    Plugin_Registry,
	allocator:   mem.Allocator,
	initialized: bool,
}

// ============================================================================
// REGISTRY HELPERS
// ============================================================================

@(private)
plugin_registry_init :: proc(registry: ^Plugin_Registry, allocator: mem.Allocator) -> bool {
	if registry == nil do return false
	if registry.initialized {
		log.warn("Plugin registry is already initialized")
		return false
	}
	registry.allocator = allocator
	hm.dynamic_init(&registry.slots, allocator)
	registry.by_name = make(map[string]PluginHandle, allocator)
	registry.initialized = true
	log.info("Plugin registry initialized.")
	return true
}

@(private)
plugin_registry_destroy :: proc(registry: ^Plugin_Registry) {
	if registry == nil || !registry.initialized do return

	// Defensively destroy any leftover registrations.
	it := hm.dynamic_iterator_make(&registry.slots)
	for plugin, _ in hm.iterate(&it) {
		if plugin.state != .Unloaded {
			delete(plugin.registration.services)
			delete(plugin.registration.systems)
			delete(plugin.registration.resources)
			delete(plugin.registration.events)
			plugin.registration = {}
		}
	}

	delete(registry.by_name)
	hm.dynamic_destroy(&registry.slots)
	registry.allocator = {}
	registry.initialized = false
}

@(private)
plugin_registry_get :: proc(
	registry: ^Plugin_Registry,
	handle: PluginHandle,
) -> (
	^Loaded_Plugin,
	bool,
) {
	if registry == nil || !registry.initialized do return nil, false
	if handle == INVALID_PLUGIN_HANDLE do return nil, false
	return hm.get(&registry.slots, handle)
}

// ============================================================================
// PLUGIN MANAGER API
// ============================================================================

plugin_manager_init :: proc(manager: ^Plugin_Manager, allocator: mem.Allocator) -> bool {
	if manager == nil do return false
	if manager.initialized {
		log.warn("Plugin manager is already initialized")
		return false
	}
	manager.allocator = allocator
	if !plugin_registry_init(&manager.registry, allocator) {
		return false
	}
	manager.initialized = true
	log.info("Plugin manager initialized.")
	return true
}

plugin_manager_destroy :: proc(manager: ^Plugin_Manager) {
	if manager == nil || !manager.initialized do return
	plugin_manager_unload_all(manager)
	plugin_registry_destroy(&manager.registry)
	manager.allocator = {}
	manager.initialized = false
}

// plugin_manager_load_project: DLL discovery mirrors module_manager_load_project
// but is not yet implemented. Until it lands, projects simply omit the
// plugins section of project.toml.
plugin_manager_load_project :: proc(manager: ^Plugin_Manager) -> bool {
	if manager == nil || !manager.initialized do return false

	loaded_count := 0
	loaded_failed_required := false
	for p in GLOBAL_PROJECT_SETTINGS.plugins {
		if !p.enabled do continue
		// TODO(plugin-load): open <bin>/<p.name>.dll, find
		// bifrost_lib_get_api, validate descriptor.component_kind ==
		// .Plugin, and call load()/register() against a Plugin_Context
		// populated with the global registries. Mirror
		// extension_load_one once we have one real plugin to drive the
		// design.
		log.warn("plugin_manager_load_project: DLL loading is not implemented yet (%s).", p.name)
		if p.required do loaded_failed_required = true
		_ = loaded_count
	}

	if loaded_failed_required {
		plugin_manager_unload_all(manager)
		return false
	}
	return true
}

plugin_manager_register_all :: proc(manager: ^Plugin_Manager) -> bool {
	if manager == nil || !manager.initialized do return false
	log.warn("plugin_manager_register_all: not implemented yet.")
	return true
}

plugin_manager_activate_all :: proc(manager: ^Plugin_Manager) -> bool {
	if manager == nil || !manager.initialized do return false
	log.warn("plugin_manager_activate_all: not implemented yet.")
	return true
}

plugin_manager_deactivate_all :: proc(manager: ^Plugin_Manager) -> bool {
	if manager == nil || !manager.initialized do return false
	log.warn("plugin_manager_deactivate_all: not implemented yet.")
	return true
}

plugin_manager_unload_all :: proc(manager: ^Plugin_Manager) -> bool {
	if manager == nil || !manager.initialized do return false

	// Reverse iteration so dependents unload before their dependencies.
	order := make([dynamic]PluginHandle, 0, context.temp_allocator)
	defer delete(order)
	it := hm.dynamic_iterator_make(&manager.registry.slots)
	for _, h in hm.iterate(&it) do append(&order, h)

	for i := len(order) - 1; i >= 0; i -= 1 {
		plugin, ok := plugin_registry_get(&manager.registry, order[i])
		if !ok do continue

		if plugin.state == .Active {
			if plugin.api.deactivate != nil do plugin.api.deactivate(&plugin.ctx)
			plugin.state = .Registered
		}
		if plugin.state == .Registered || plugin.state == .Loaded {
			if plugin.api.unload != nil do plugin.api.unload(&plugin.ctx)
			delete(plugin.registration.services)
			delete(plugin.registration.systems)
			delete(plugin.registration.resources)
			delete(plugin.registration.events)
			plugin.registration = {}

			if plugin.library != (Dynamic_Library{}) {
				dynamic_library_close(&plugin.library)
			}
			plugin.state = .Unloaded
			_, _ = hm.remove(&manager.registry.slots, plugin.handle)
		}
	}
	return true
}
