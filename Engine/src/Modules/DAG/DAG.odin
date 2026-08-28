// Engine/src/Modules/DAG/DAG.odin
//
// Stub module — full DAG scheduler is being migrated from the previous
// engine. This file exists so rbs manifest codegen has a parseable
// IDENTITY/DEPENDENCIES block and the loader sees a real module at
// <Name>.odin convention.

package DAG

import "core:log"
import "../../Core"

// === MODULE_IDENTITY (parsed by rbs) ===
IDENTITY :: Core.Module_Identity{
    name        = "DAG",
    version     = Core.Version{0, 0, 1},
    author      = "armscream",
    description = "Stub DAG scheduler — Directed Acyclic Graph task and systems scheduler, full impl pending.",
    type        = .Other,
    flags       = {.Runtime},
    capabilities = {.Custom},
}
// === END MODULE_IDENTITY ===

// === DEPENDENCIES (parsed by rbs) ===
DEPENDENCIES := [?]Core.DLL_Dependency{
    // no dependencies — DAG is foundational
}
// === END DEPENDENCIES ===

module_load :: proc() -> bool {
    log.warn("[DAG] stub module loaded — implementation pending")
    return true
}
module_unload :: proc() {
    log.warn("[DAG] stub module unloaded")
}
module_update :: proc(dt: f32) {
}
module_render :: proc() {
}
