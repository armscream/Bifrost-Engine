// Engine\src\Core\SDK.odin
package Core


// ============================================================================
// YMIR SDK
// ============================================================================
//
// Public engine API.
//
// Game code, modules and plugins should use SDK procedures rather than
// reaching directly into engine implementation details.
//
// ============================================================================


// ----------------------------------------------------------------------------
// ENGINE
// ----------------------------------------------------------------------------

engine_is_editor :: proc() -> bool
engine_is_running :: proc() -> bool
engine_delta_time :: proc() -> f32


// ============================================================================
// MODULES
// ============================================================================

module_find :: proc(name: string) -> (ModuleHandle, bool)
module_is_loaded :: proc(handle: ModuleHandle) -> bool
module_is_active :: proc(handle: ModuleHandle) -> bool
module_version :: proc(handle: ModuleHandle) -> string
module_type :: proc(handle: ModuleHandle) -> Module_Type
module_has_capability :: proc(
	handle: ModuleHandle,
	capability: Module_Capability,
) -> bool


// ============================================================================
// SERVICES
// ============================================================================

service_find :: proc(name: string) -> (ServiceHandle, bool)
service_is_valid :: proc(handle: ServiceHandle) -> bool
service_get :: proc(handle: ServiceHandle) -> rawptr


// ----------------------------------------------------------------------------
// EVENTS
// ----------------------------------------------------------------------------

emit_event :: proc(event: rawptr)


// ----------------------------------------------------------------------------
// ASSETS
// ----------------------------------------------------------------------------

asset_load :: proc(path: string) -> rawptr
asset_unload :: proc(asset: rawptr)


// ----------------------------------------------------------------------------
// ECS
// ----------------------------------------------------------------------------

entity_create :: proc() -> rawptr
entity_destroy :: proc(entity: rawptr)


// ----------------------------------------------------------------------------
// RENDERING
// ----------------------------------------------------------------------------

renderer_begin_frame :: proc()
renderer_end_frame :: proc()


// ----------------------------------------------------------------------------
// AUDIO
// ----------------------------------------------------------------------------

audio_play :: proc(sound: rawptr)


// ----------------------------------------------------------------------------
// PHYSICS
// ----------------------------------------------------------------------------

physics_raycast :: proc() -> bool