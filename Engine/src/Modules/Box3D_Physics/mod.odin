// Engine/src/Modules/Box3D_Physics/Mod.odin
//
// Stub module — full implementation is being migrated from the previous
// engine. This file exists so rbs manifest codegen has a parseable
// IDENTITY/DEPENDENCIES block and the loader sees a real module at
// <Name>.odin convention.

package Box3D_Physics

import "core:log"
import "../../Core"

// === MODULE_IDENTITY (parsed by rbs) ===
IDENTITY :: Core.Module_Identity{
    name        = "Box3D_Physics",
    version     = Core.Version{0, 0, 1},
    author      = "armscream",
    description = "Stub Box3D_Physics module — full impl pending.",
    type        = .Other,
    flags       = {.Runtime},
    capabilities = {.Physics},
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
    log.warn("[BOX3D] stub module loaded — implementation pending")
    return true
}
module_unload :: proc() {
    log.warn("[BOX3D] stub module unloaded")
}
module_update :: proc(dt: f32) {
}
module_render :: proc() {
}
