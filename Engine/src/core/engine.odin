// Engine\src\Core\engine.odin
package Core

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"


// ============================================================================
// Project Settings
// ============================================================================

Project_Settings :: struct {
	project_name:  string,
	using version: Version,
	modules:       [dynamic]Project_Module,
	plugins:       [dynamic]Project_Plugin,
}

Project_Module :: struct {
	name:    string,
	enabled: bool,
}

Project_Plugin :: struct {
	name:    string,
	enabled: bool,
}

Version :: struct {
	major: u32,
	minor: u32,
	patch: u32,
}

// ============================================================================
// Global Project State
// ============================================================================

GLOBAL_PROJECT_SETTINGS: Project_Settings = {}


// ============================================================================
// Runtime State
// ============================================================================

RUN_EDITOR: bool = false

GLOBAL_MODULE_REGISTRY: Module_Registry
GLOBAL_PLUGIN_REGISTRY: Plugin_Registry

// ============================================================================
// Application Callback
// ============================================================================

APPRUNHANDLE: proc()


// ============================================================================
// Engine Initialization
// ============================================================================

init :: proc(apprunhandle: proc(), run_editor: bool) -> bool {

	context.logger = log.create_console_logger()

	RUN_EDITOR = run_editor
	APPRUNHANDLE = apprunhandle

	fmt.println("")
	fmt.println("========================================")
	fmt.println(" ENGINE INIT")
	fmt.println("========================================")

	if !load_project_settings() {
		return false
	}

	if !module_registry_init(&GLOBAL_MODULE_REGISTRY, context.allocator) {
		return false
	}

	if !plugin_registry_init(&GLOBAL_PLUGIN_REGISTRY) {
		return false
	}

	if !module_load_project_modules() {
		return false
	}

	if !module_resolve_dependencies(&GLOBAL_MODULE_REGISTRY) {
		return false
	}

	if !module_register_all(&GLOBAL_MODULE_REGISTRY) {
		return false
	}

	if !scheduler_build() {
		return false
	}

	if !module_activate_all(&GLOBAL_MODULE_REGISTRY) {
		return false
	}

	fmt.println("")
	fmt.println("Engine initialization complete.")

	return true
}


// ============================================================================
// Engine Run
// ============================================================================

run :: proc() {
	fmt.println("")
	fmt.println("========================================")
	fmt.println(" ENGINE RUN")
	fmt.println("========================================")

	fmt.println("ENGINE RUN ENTERED")

	if APPRUNHANDLE != nil {
		fmt.println("Calling application callback...")

		APPRUNHANDLE()

		fmt.println("Application callback returned.")
	}

	fmt.println("ENGINE RUN EXITED")
}


// ============================================================================
// Engine Destroy
// ============================================================================

destroy :: proc() -> bool {

	fmt.println("")
	fmt.println("========================================")
	fmt.println(" ENGINE DESTROY")
	fmt.println("========================================")

	// Stop modules while their runtime dependencies still exist.
	module_deactivate_all(&GLOBAL_MODULE_REGISTRY)
	// Destroy Core runtime infrastructure.
	scheduler_shutdown()
	// plugins
	plugin_unload_all()
	// finally unload module DLLs.
	module_unload_all(&GLOBAL_MODULE_REGISTRY)

	module_registry_destroy(&GLOBAL_MODULE_REGISTRY)

	plugin_registry_destroy(&GLOBAL_PLUGIN_REGISTRY)

	APPRUNHANDLE = nil

	log.destroy_console_logger(context.logger)

	return true
}

inject_default_project_settings :: proc() -> Project_Settings {
    // Explicitly allocate the dynamic array on the heap
    modules := make([dynamic]Project_Module, 0, 10) // 0 len, 10 cap
    
    // Populate using append
    append(&modules, Project_Module{name = "Bifrost_Renderer", enabled = true})
    append(&modules, Project_Module{name = "DAG", enabled = true})
    append(&modules, Project_Module{name = "ECS", enabled = true})
    append(&modules, Project_Module{name = "Default_Input", enabled = false})
    append(&modules, Project_Module{name = "Miniaudio", enabled = false})
    append(&modules, Project_Module{name = "Box3D_Physics", enabled = false})
    append(&modules, Project_Module{name = "ATLAS-RMGUI", enabled = false})
    append(&modules, Project_Module{name = "Scripting", enabled = false})
    append(&modules, Project_Module{name = "Editor", enabled = true})
    append(&modules, Project_Module{name = "ENet", enabled = false})

    return Project_Settings {
        project_name = "New Project",
        version = Version{major = 0, minor = 0, patch = 1},
        modules = modules, // Returns the heap-allocated dynamic array
        plugins = {},      // Empty literal is safe if plugins is a slice/dynamic array with 0 len
    }
}   
