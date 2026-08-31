// Engine\src\Core\reflection.odin
package Core

// ============================================================================
// FOUNDATIONAL TYPES
// ============================================================================
//
// Handle types and the Version triple used everywhere in Core.
//
// Handle layout matches `core:container/handle_map`'s expectations:
//   - field names: `idx`, `gen` (both u32 for Handle32-equivalent)
//   - idx == 0 is the reserved invalid slot
//   - gen == 0 is reserved as the "freed" sentinel inside the handle map
//
// We use 32-bit indices to leave room for the realistic number of components
// Bifrost will ever load; widening to Handle64 only requires changing the
// underlying integer type and the index mask in helpers that read it.
//
// Version is the only numeric triple carried through the public ABI; it is
// intentionally minimal (major/minor/patch u32) so it round-trips through
// C-compatible layouts without alignment surprises.
// ============================================================================

Version :: struct {
	major: u32,
	minor: u32,
	patch: u32,
}

// BASEVERSION is the default 0.0.1 used when a project/module does not
// declare one explicitly.
@(private)
BASEVERSION: Version = {
	major = 0,
	minor = 0,
	patch = 1,
}

// ============================================================================
// HANDLES
// ============================================================================

ModuleHandle :: struct {
	idx: u32,
	gen: u32,
}

INVALID_MODULE_HANDLE :: ModuleHandle {
	idx = 0,
	gen = 0,
}

ExtensionHandle :: struct {
	idx: u32,
	gen: u32,
}

INVALID_EXTENSION_HANDLE :: ExtensionHandle {
	idx = 0,
	gen = 0,
}

PluginHandle :: struct {
	idx: u32,
	gen: u32,
}

INVALID_PLUGIN_HANDLE :: PluginHandle {
	idx = 0,
	gen = 0,
}

ServiceHandle :: struct {
	idx: u32,
	gen: u32,
}

INVALID_SERVICE_HANDLE :: ServiceHandle {
	idx = 0,
	gen = 0,
}

ResourceHandle :: struct {
	idx: u32,
	gen: u32,
}

INVALID_RESOURCE_HANDLE :: ResourceHandle {
	idx = 0,
	gen = 0,
}

EventHandle :: struct {
	idx: u32,
	gen: u32,
}

INVALID_EVENT_HANDLE :: EventHandle {
	idx = 0,
	gen = 0,
}