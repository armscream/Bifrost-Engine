// Engine/src/Extensions/Example_Extension/mod.odin
//
// Reference extension showing how to attach to Bifrost_Renderer through
// its Renderer.ExtensionPoint service.
//
// Lifecycle:
//   load       — nothing (no module-level setup yet)
//   register   — look up the renderer's extension point service and call
//                attach(self), then register one stub pass + one stub
//                material to prove the round trip works.
//   activate   — already-attached; nothing extra
//   deactivate — detach from the renderer (mirror of register)
//   unload     — nothing
//
// The DLL is loaded as <bin>/Example_Extension.dll by
// extension_manager_load_project when the project's project.toml enables
// it.
//
// Dependencies are declared inline inside the IDENTITY block (Core.Lib_Descriptor);
// not in a separate DEPENDENCIES section — Core.Lib_Descriptor is the single
// source of truth for component metadata.
//
// bifrost_lib_get_api is gated on BUILDING_EXAMPLE_EXTENSION_DLL so this
// DLL doesn't @export the entry twice when the package is also imported
// by something else. rbs auto-passes the flag per DLL build.

package Example_Extension

import "core:log"
import "../../Core"
import "../../Modules/Bifrost_Renderer"

// === MODULE_IDENTITY (parsed by rbs) ===
IDENTITY :: Core.Lib_Descriptor {
	api_version    = Core.LIB_API_VERSION,
	name           = "Example_Extension",
	version        = Core.Version{0, 0, 1},
	author         = "armscream",
	description    = "Reference extension: attaches to Bifrost_Renderer and registers a stub pass + material.",
	component_kind = .Extension,
	type           = .Other,
	flags          = {.Runtime},
	capabilities   = {.Renderer, .Materials},
	dependencies   = {{
		name            = "Bifrost_Renderer",
		min_version     = Core.Version{0, 0, 1},
		max_version     = Core.Version{9, 9, 9},
		has_min_version = true,
		has_max_version = true,
		optional        = false,
	}},
	dependency_count = 1,
}
// === END MODULE_IDENTITY ===

EXT_API := Core.Extension_API {
	api_version = Core.LIB_API_VERSION,
	identity    = IDENTITY,
	load        = ext_load,
	register    = ext_register,
	activate    = ext_activate,
	deactivate  = ext_deactivate,
	unload      = ext_unload,
}

when #config(BUILDING_EXAMPLE_EXTENSION_DLL, false) {
	@(export)
	bifrost_lib_get_api :: proc() -> ^Core.LIB_API {
		return cast(^Core.LIB_API)&EXT_API
	}
}

ext_load :: proc(ctx: ^Core.Extension_Context) -> bool {
	_ = ctx
	log.info("[Example_Extension] loaded")
	return true
}

ext_register :: proc(ctx: ^Core.Extension_Context) -> bool {
	if ctx == nil {
		return false
	}

	// Resolve the renderer module by name and add it as a target. Core's
	// extension_validate_targets checks the target module is alive and
	// version-compatible.
	if ctx.module_registry != nil {
		if handle, found := Core.module_find(ctx.module_registry, "Bifrost_Renderer"); found {
			append(
				&ctx.registration.targets,
				Core.Extension_Target{
					module      = handle,
					min_version = Core.Version{0, 0, 1},
					max_version = Core.Version{9, 9, 9},
				},
			)
		} else {
			log.error("[Example_Extension] Bifrost_Renderer module not loaded.")
			return false
		}
	}

	// Look up the Renderer.ExtensionPoint service and attach.
	sr := ctx.service_registry
	if sr == nil do return false

	ep_handle, ok := Core.service_find(sr, Bifrost_Renderer.RENDERER_EXTENSION_POINT_SERVICE_NAME)
	if !ok {
		log.error("[Example_Extension] Renderer.ExtensionPoint service not found.")
		return false
	}
	ep := cast(^Bifrost_Renderer.Renderer_Extension_Point)Core.service_get(sr, ep_handle)
	if ep == nil do return false

	ep.attach(ep, "Example_Extension")
	ep.register_pass    (ep, "ExampleExtension.GBufferOverlay", nil)
	ep.register_material(ep, "ExampleExtension.DebugMaterial", nil)

	log.info("[Example_Extension] registered (targeting Bifrost_Renderer).")
	return true
}

ext_activate :: proc(ctx: ^Core.Extension_Context) -> bool {
	_ = ctx
	log.info("[Example_Extension] activated")
	return true
}

ext_deactivate :: proc(ctx: ^Core.Extension_Context) {
	_ = ctx
	log.info("[Example_Extension] deactivated")
}

ext_unload :: proc(ctx: ^Core.Extension_Context) {
	_ = ctx
	log.info("[Example_Extension] unloaded")
}
