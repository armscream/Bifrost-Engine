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
IDENTITY :: Core.Lib_Descriptor {
	api_version      = Core.LIB_API_VERSION,
	name             = "Box3D_Physics",
	version          = Core.Version{0, 0, 1},
	author           = "armscream",
	description      = "Box3D for Bifrost Engine, stubb module.",
	component_kind   = .Module,
	type             = .Physics,
	flags            = {.Runtime},
	capabilities     = {.Physics},
	dependencies     = {
		{
			name = "BF_DAG",
			min_version = Core.Version{0, 0, 1},
			max_version = Core.Version{9, 9, 9},
			has_max_version = true,
			has_min_version = true,
			optional = false,
		},
	},
	dependency_count = 1,
}
// === END MODULE_IDENTITY ===

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
