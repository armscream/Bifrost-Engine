// Engine/src/Core/plugin.odin
package Core

import "core:log"
import "core:mem"
import "core:dynlib"

Plugin_API :: struct {
    api_version: u32,
    identity: Plugin_Identity,
    dependencies: [^]Plugin_Dependency,
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
    state: Plugin_State,
    registration: Plugin_Registry, // is it plugin_registration?
}

Plugin_Identity :: struct {
    name: string,
    author: string,
    version: Version,
}

Plugin_Dependency :: struct {
    name: string,
    min_version: Version,
    max_version: Version,
}

Plugin_State :: enum u32 {
	Unloaded,
	Loaded,
	Registered,
	Active,
	Failed,
}

Plugin_Context :: struct {
    //TODO: add more fields. This just makes this compile for now.
}

plugin_registry_init :: proc(registry: ^Plugin_Registry) -> bool {
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