// Engine/src/Core/plugins.odin
package Core

import "core:log"
import "core:mem"

// ============================================================================
// PLUGIN SYSTEM
// ============================================================================
//
// Plugins = project/tool/editor-side functionality that is not necessarily
// part of the engine's runtime module architecture. They can still use the
// SDK and services, but they shouldn't be treated as "modules with a
// different name".
//
// The Plugin_API/Plugin_Context types below are public so plugins can
// implement against them; the registry/manager plumbing is package-internal.
// ============================================================================

Plugin_API :: struct {
	api_version: u32,
	load:        proc(ctx: ^Plugin_Context) -> bool,
	register:    proc(ctx: ^Plugin_Context) -> bool,
	activate:    proc(ctx: ^Plugin_Context) -> bool,
	deactivate:  proc(ctx: ^Plugin_Context),
	unload:      proc(ctx: ^Plugin_Context),
}

Plugin_Context :: struct {
	// Will grow to include service/system/event channels once the
	// plugin SDK lands.
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

// Plugin_Library is a placeholder; once Plugin_API migrates onto Loaded_Lib
// this collapses to a plain Loaded_Lib.
@(private)
Plugin_Library :: struct {
	loaded: bool,
}

@(private)
Loaded_Plugin :: struct {
	handle:       PluginHandle,
	library:      Plugin_Library,
	api:          Plugin_API,
	ctx:          Plugin_Context,
	state:        Component_State,
	registration: Plugin_Registration,
}

Plugin_Registry :: struct {
	allocator:    mem.Allocator,
	plugins:      [dynamic]Loaded_Plugin,
	generations:  [dynamic]u32,
	free_indices: [dynamic]u32,
	by_name:      map[string]PluginHandle,
	initialized:  bool,
	// NOTE: Plugin registry is a placeholder. Once Plugin_API migrates onto
	// Loaded_Lib + Dynamic_Handle_Map (mirroring extensions.odin), drop
	// plugins/generations/free_indices and use slots: hm.Dynamic_Handle_Map(...).
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
	registry.allocator = allocator
	registry.plugins = make([dynamic]Loaded_Plugin, 0, allocator)
	registry.generations = make([dynamic]u32, 0, allocator)
	registry.free_indices = make([dynamic]u32, 0, allocator)
	registry.by_name = make(map[string]PluginHandle, allocator)
	registry.initialized = true
	return true
}

@(private)
plugin_registry_destroy :: proc(registry: ^Plugin_Registry) {
	if registry == nil || !registry.initialized do return
	delete(registry.by_name)
	delete(registry.free_indices)
	delete(registry.generations)
	delete(registry.plugins)
	registry.allocator = {}
	registry.initialized = false
}

@(private)
plugin_unload_all :: proc(registry: ^Plugin_Registry) -> bool {
	if registry == nil || !registry.initialized do return false
	return true
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

// TODO: implement DLL discovery mirroring module_manager_load_project.
plugin_manager_load_project :: proc(manager: ^Plugin_Manager) -> bool {
	if manager == nil || !manager.initialized do return false
	log.warn("plugin_manager_load_project: DLL discovery is not implemented yet.")
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
	return plugin_unload_all(&manager.registry)
}