// Engine\src\Core\reflection.odin
package Core

MODULE_INDEX_INVALID :: u32(0)
MODULE_GENERATION_INVALID :: u32(0)
ModuleHandle :: struct {
	index:      u32,
	generation: u32,
}
INVALID_MODULE_HANDLE :: ModuleHandle { // Real modules start at 1, if ModuleHandle.index == 0, then it's invalid
	index      = MODULE_INDEX_INVALID,
	generation = MODULE_GENERATION_INVALID,
}

EXTENSION_INDEX_INVALID :: u32(0)
EXTENSION_GENERATION_INVALID :: u32(0)
ExtensionHandle :: struct {
	index:      u32,
	generation: u32,
}
INVALID_EXTENSION_HANDLE :: ExtensionHandle {
    index      = EXTENSION_INDEX_INVALID,
    generation = EXTENSION_GENERATION_INVALID,
}

PLUGIN_INDEX_INVALID :: u32(0)
PLUGIN_GENERATION_INVALID :: u32(0)
PluginHandle :: struct {
	index:      u32,
	generation: u32,
}
INVALID_PLUGIN_HANDLE :: PluginHandle {
    index      = PLUGIN_INDEX_INVALID,
    generation = PLUGIN_GENERATION_INVALID,
}

SERVICE_INDEX_INVALID :: u32(0)
SERVICE_GENERATION_INVALID :: u32(0)
ServiceHandle :: struct {
	index:      u32,
	generation: u32,
}
INVALID_SERVICE_HANDLE :: ServiceHandle {
    index      = SERVICE_INDEX_INVALID,
    generation = SERVICE_GENERATION_INVALID,
}

DLL_Identity :: struct {
	name:         cstring,
	version:      Version,
	author:       cstring,
	description:  cstring,
	type:         Module_Type,
	flags:        Module_Flags,
}

DLL_Dependency :: struct {
	name:            cstring,
	min_version:     Version,
	max_version:     Version,
	has_min_version: bool,
	has_max_version: bool,
	optional:        bool,
}
