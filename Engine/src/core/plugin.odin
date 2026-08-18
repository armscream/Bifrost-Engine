// Engine/src/Core/plugin.odin
package Core

import "core:log"

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