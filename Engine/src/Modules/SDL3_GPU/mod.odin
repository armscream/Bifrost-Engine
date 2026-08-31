// Engine/src/Modules/SDL3_GPU/mod.odin
package SDL3_GPU

import "core:log"
import "../../Core"

// === MODULE_IDENTITY (parsed by rbs) ===
IDENTITY :: Core.Lib_Descriptor {
	api_version    = Core.LIB_API_VERSION,
	name           = "SDL3_GPU",
	version        = Core.Version{0, 0, 1},
	author         = "armscream",
	description    = "stubbed SDL3_GPU module",
	component_kind = .Module,
	type           = .Renderer,
	flags          = {.Runtime},
	capabilities   = {.Renderer, .GPU, .Materials, .Textures},
    dependencies   = {},
    dependency_count = 0,
}
// === END MODULE_IDENTITY ===

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
