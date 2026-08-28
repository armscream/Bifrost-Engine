// Engine/src/Modules/Bifrost_Renderer/renderer.odin
package Bifrost_Renderer

import "core:log"
import "../../Core"

// === MODULE_IDENTITY (parsed by rbs) ===
IDENTITY :: Core.Module_Identity{
    name        = "Bifrost_Renderer",
    version     = Core.Version{0, 0, 1},
    author      = "armscream",
    description = "PBR forward+ renderer with Vulkan and MoltenVK backends.",
    type        = .Renderer,
    flags       = {.Runtime},
    capabilities = {.Renderer, .GPU, .Materials, .Textures},
}
// === END MODULE_IDENTITY ===

// === DEPENDENCIES (parsed by rbs) ===
DEPENDENCIES := [?]Core.DLL_Dependency{
    {
    },
}
// === END DEPENDENCIES ===

module_load :: proc() -> bool {
    log.info("Renderer module loaded")
    return true
}
module_unload  :: proc() {
    log.info("Renderer module unloaded")
}
module_update :: proc(dt: f32) {
}
module_render :: proc() {
}
