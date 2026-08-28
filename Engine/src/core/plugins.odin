// Engine/src/Core/plugin.odin
package Core

import "core:log"
import "core:mem"
import "core:dynlib"

// Plugins = project/tool/editor-side functionality that is not necessarily part of the engine's runtime module 
// architecture. They can still use the SDK and services, but they shouldn't be treated as "modules with a different name."

Plugin_API :: struct {
    api_version: u32,
    identity: DLL_Identity,
    dependencies: [^]DLL_Dependency,
    dependency_count: u32,
    load: proc(ctx: ^Plugin_Context)  -> bool,
    register: proc(ctx: ^Plugin_Context) -> bool,
    activate: proc(ctx: ^Plugin_Context) -> bool,
    deactivate: proc(ctx: ^Plugin_Context),
    unload: proc(ctx: ^Plugin_Context),
}

Plugin_Registry :: struct { 
    allocator: mem.Allocator,
    plugins: [dynamic]Loaded_Plugin,
    generations: [dynamic]u32,
    free_indices: [dynamic]u32,
    by_name: map[string]PluginHandle,
    initialized: bool,
}

Loaded_Plugin :: struct {
    handle: PluginHandle,
    libary: dynlib.Library,
    api: Plugin_API,
    ctx: Plugin_Context,
    state: Load_State,
    registration: Plugin_Registration, // is it plugin_registration?
}

// Plugin Registration
Plugin_Registration :: struct {
    services: [dynamic]Service_Registration,
    systems: [dynamic]System_Registration,
    resources: [dynamic]Resource_Registration,
    events: [dynamic]Event_Registration,
}

Plugin_Context :: struct {
    //TODO: add more fields. This just makes this compile for now.
}

// TODO: implement all of these plugin lifecycle procs
plugin_registry_init :: proc(registry: ^Plugin_Registry, allocator: mem.Allocator) -> bool {
    log.warn("plugin_registry_init() not implemented")
    return true
}

plugin_unload_all :: proc(registry: ^Plugin_Registry) -> bool {
    log.warn("plugin_unload_all() not implemented")
    return true
}

plugin_registry_destroy :: proc(registry: ^Plugin_Registry) {
    log.warn("plugin_registry_destroy() not implemented")
}

plugin_load_project_plugins :: proc(registry: ^Plugin_Registry) -> bool {
    log.warn("plugin_load_project_plugins() not implemented")
    return true
}

plugin_resolve_dependencies :: proc(registry: ^Plugin_Registry) -> bool {
    log.warn("plugin_resolve_dependencies() not implemented")
    return true
}

plugin_register_all :: proc(registry: ^Plugin_Registry) -> bool {
    log.warn("plugin_register_all() not implemented")
    return true
}

plugin_activate_all :: proc(registry: ^Plugin_Registry) -> bool {
    log.warn("plugin_activate_all() not implemented")
    return true
}

plugin_deactivate_all :: proc(registry: ^Plugin_Registry) -> bool {
    log.warn("plugin_deactivate_all() not implemented")
    return true
}