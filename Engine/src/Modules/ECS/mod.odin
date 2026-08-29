// Engine/src/Modules/ECS/mod.odin
//
// Stub module — full implementation is being migrated from the previous
// engine. This file exists so rbs manifest codegen has a parseable
// IDENTITY/DEPENDENCIES block and the loader sees a real module at
// <Name>.odin convention.

package ECS

import "core:log"
import "../../Core"

// === MODULE_IDENTITY (parsed by rbs) ===
IDENTITY :: Core.Module_Identity{
    name        = "ECS",
    version     = Core.Version{0, 0, 1},
    author      = "armscream",
    description = "Stub ECS module — non-archetypal entity component system, full impl pending.",
    type        = .Other,
    flags       = {.Runtime},
    capabilities = {.ECS},
}
// === END MODULE_IDENTITY ===

// === DEPENDENCIES (parsed by rbs) ===
DEPENDENCIES := [?]Core.DLL_Dependency{
    {
        name        = "DAG",
        min_version = Core.Version{0, 0, 1},
        max_version = Core.Version{0, 0, 999},
        has_min_version = true,
        has_max_version = false,
        optional    = false,
    },
}
// === END DEPENDENCIES ===

module_load :: proc() -> bool {
    log.warn("[ECS] stub module loaded — implementation pending")
    return true
}
module_unload :: proc() {
    log.warn("[ECS] stub module unloaded")
}
module_update :: proc(dt: f32) {
}
module_render :: proc() {
}
