// Engine/src/Core/extensions.odin
package Core

import "core:dynlib"
import "core:log"
import "core:mem"

// ============================================================================
// EXTENSION API
// ============================================================================
//
// Extensions augment modules.
//
// An extension is not a replacement for a module. It attaches additional
// functionality to an existing module or module-defined extension point.
//
// Example:
//
//     Bifrost_Renderer
//          ^
//          |
//     DDGI Extension
//
// The renderer remains the owner of the primary renderer architecture.
// DDGI contributes additional functionality through the renderer's
// extension interface.
//
// ============================================================================
Extension_API :: struct {
	api_version:      u32,
	identity:         DLL_Identity,
	dependencies:     [^]DLL_Dependency,
	dependency_count: u32,
	load:             proc(ctx: ^Extension_Context) -> bool,
	register:         proc(ctx: ^Extension_Context) -> bool,
	activate:         proc(ctx: ^Extension_Context) -> bool,
	deactivate:       proc(ctx: ^Extension_Context),
	unload:           proc(ctx: ^Extension_Context),
}

Extension_Registry :: struct {
	allocator:    mem.Allocator,
	extensions:   [dynamic]Loaded_Extension,
	generations:  [dynamic]u32,
	free_indices: [dynamic]u32,
	by_name:      map[string]ExtensionHandle,
	initialized:  bool,
}

Loaded_Extension :: struct {
	handle:       ExtensionHandle,
	libary:       dynlib.Library,
	api:          Extension_API,
	ctx:          Extension_Context,
	state:        Load_State,
	registration: Extension_Registration,
}

// ============================================================================
// EXTENSION CONTEXT
// ============================================================================
//
// The context is the extension's gateway into Core.
//
// We will expand this as the extension architecture develops.
//
// In particular, this is where we can eventually expose:
//
//     - extension's own handle
//     - owning module handle
//     - Core SDK
//     - service registry access
//     - module lookup
//     - extension-point lookup
//
// ============================================================================
Extension_Context :: struct {
	//TODO: add more fields. This just makes this compile for now.
}

// Extension Registration
Extension_Registration :: struct {
	services:  [dynamic]Service_Registration,
	systems:   [dynamic]System_Registration,
	resources: [dynamic]Resource_Registration,
	events:    [dynamic]Event_Registration,
	targets:   [dynamic]Extension_Target,
}

// ============================================================================
// EXTENSION TARGET
// ============================================================================
//
// Identifies a module that this extension augments.
//
// Later we can evolve this into an actual extension-point system:
//
//     Bifrost_Renderer::GI
//     Bifrost_Renderer::RenderPass
//     Animation::GraphNode
//     ECS::Component
//
// For now the module identity is enough.
//
// ============================================================================
Extension_Target :: struct {
	module:      ModuleHandle,
	min_version: Version,
	max_version: Version,
}

// Regitry initialization
@(private)
extension_registry_init :: proc(registry: ^Extension_Registry, allocator: mem.Allocator) -> bool {
	if registry == nil do return false
	if registry.initialized {log.warn("Extension registry already initialized.")
		return false}

	registry.allocator = allocator

	//Slot zero is permanently invalid.
	registry.extensions = make([dynamic]Loaded_Extension, 1, allocator)
	append(&registry.extensions, Loaded_Extension{})

	registry.generations = make([dynamic]u32, 1, allocator)
	append(&registry.generations, EXTENSION_GENERATION_INVALID)

	registry.free_indices = make([dynamic]u32, 0, allocator)
	registry.by_name = make(map[string]ExtensionHandle, allocator)
	registry.initialized = true
	log.info("Extension registry initialized.")
	return true
}

// ext lookup
@(private)
extension_registry_get :: proc(
	registry: ^Extension_Registry,
	handle: ExtensionHandle,
) -> (
	^Loaded_Extension,
	bool,
) {
	if registry == nil || !registry.initialized do return nil, false
	if handle.index == EXTENSION_INDEX_INVALID do return nil, false
	if handle.index >= u32(len(registry.extensions)) do return nil, false
	if handle.generation == EXTENSION_GENERATION_INVALID || handle.generation != registry.generations[handle.index] do return nil, false

	extension := &registry.extensions[handle.index]
	if extension.handle.index != handle.index do return nil, false
	if extension.handle.generation != handle.generation do return nil, false
	return extension, true
}

extension_is_valid :: proc(registry: ^Extension_Registry, handle: ExtensionHandle) -> bool {
	_, ok := extension_registry_get(registry, handle)
	return ok
}
