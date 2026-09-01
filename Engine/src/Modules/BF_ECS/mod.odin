// Engine/src/Modules/BF_ECS/mod.odin
//
// Stub module — full implementation is being migrated from the previous
// engine. This file exists so rbs manifest codegen has a parseable
// IDENTITY/DEPENDENCIES block and the loader sees a real module at
// <Name>.odin convention.

package BF_ECS

import "core:log"
import "../../Core"

// === MODULE_IDENTITY (parsed by rbs) ===
IDENTITY :: Core.Lib_Descriptor {
	api_version    = Core.LIB_API_VERSION,
	name           = "BF_ECS",
	version        = Core.Version{0, 0, 1},
	author         = "armscream",
	description    = "Stub ECS module — non-archetypal entity component system, full impl pending.",
	component_kind = .Module,
	type           = .Other,
	flags          = {.Runtime},
	capabilities   = {.ECS},
	dependencies   = {{
		name            = "BF_DAG",
		min_version     = Core.Version{0, 0, 1},
		max_version     = Core.Version{9, 9, 9},
		has_max_version = true,
		has_min_version = true,
		optional        = false,
	}},
	dependency_count = 1,
}
// === END MODULE_IDENTITY ===

MODULE_API := Core.LIB_API {
	descriptor = IDENTITY,
	load       = module_load,
	register   = module_register,
	activate   = module_activate,
	deactivate = module_deactivate,
	unload     = module_unload,
}

when #config(BUILDING_BF_ECS_DLL, false) {
	@(export)
	bifrost_lib_get_api :: proc() -> ^Core.LIB_API {
		return &MODULE_API
	}
}

module_load :: proc(ctx: ^Core.Lib_Context) -> bool {
	_ = ctx
	log.warn("[ECS] stub module loaded — implementation pending")
	return true
}
module_register :: proc(ctx: ^Core.Lib_Context) -> bool {
	_ = ctx
	return true
}
module_activate :: proc(ctx: ^Core.Lib_Context) -> bool {
	_ = ctx
	return true
}
module_deactivate :: proc(ctx: ^Core.Lib_Context) {
	_ = ctx
}
module_unload :: proc(ctx: ^Core.Lib_Context) {
	_ = ctx
	log.warn("[ECS] stub module unloaded")
}