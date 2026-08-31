// Engine/src/Modules/BF_DAG/mod.odin
//
// Stub module — full DAG scheduler is being migrated from the previous
// engine. This file exists so rbs manifest codegen has a parseable
// IDENTITY/DEPENDENCIES block and the loader sees a real module at
// <Name>.odin convention.

package BF_DAG

import "core:log"
import "../../Core"

// === MODULE_IDENTITY (parsed by rbs) ===
IDENTITY :: Core.Lib_Descriptor {
	api_version    = Core.LIB_API_VERSION,
	name           = "DAG",
	version        = Core.Version{0, 0, 1},
	author         = "armscream",
	description    = "Stub DAG scheduler — Directed Acyclic Graph task and systems scheduler, full impl pending.",
	component_kind = .Module,
	type           = .Other,
	flags          = {.Runtime},
	capabilities   = {.Custom},
	dependencies   = {},
	dependency_count = 0,
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

@(export)
bifrost_lib_get_api :: proc() -> ^Core.LIB_API {
	return &MODULE_API
}

module_load :: proc(ctx: ^Core.Lib_Context) -> bool {
	_ = ctx
	log.warn("[DAG] stub module loaded — implementation pending")
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
	log.warn("[DAG] stub module unloaded")
}