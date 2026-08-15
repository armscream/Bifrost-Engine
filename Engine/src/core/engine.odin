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
	project_name: string,
	version:      string,
	modules:      []Project_Module,
	plugins:      []Project_Plugin,
}

Project_Module :: struct {
	name:    string,
	enabled: bool,
}

Project_Plugin :: struct {
	name:    string,
	enabled: bool,
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
GLOBAL_MODULE_REGISTRY: Plugin_Registry

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

	if !module_registry_init(&GLOBAL_MODULE_REGISTRY) {
		return false
	}

	if !plugin_registry_init(&GLOBAL_PLUGIN_REGISTRY) {
		return false
	}

	if !module_load_project_modules() {
		return false
	}

	if !module_resolve_dependencies() {
		return false
	}

	if !module_register_all() {
		return false
	}

	if !scheduler_build() {
		return false
	}

	if !module_activate_all() {
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

	scheduler_shutdown()

	plugin_unload_all()

	module_deactivate_all()

	module_unload_all()

	module_registry_destroy(&GLOBAL_MODULE_REGISTRY)

	plugin_registry_destroy(&GLOBAL_PLUGIN_REGISTRY)

	APPRUNHANDLE = nil

	log.destroy_console_logger(context.logger)

	return true
}

inject_default_project_settings :: proc() -> Project_Settings {
	return Project_Settings {
		project_name = "New Project",
		version = "0.0.1",
		modules = {
			Project_Module{name = "Bifrost_Renderer", enabled = true},
			Project_Module{name = "DAG", enabled = true},
			Project_Module{name = "ECS", enabled = true},
			Project_Module{name = "Default_Input", enabled = false},
			Project_Module{name = "Miniaudio", enabled = false},
			Project_Module{name = "Box3D_Physics", enabled = false},
			Project_Module{name = "ATLAS-RMGUI", enabled = false},
			Project_Module{name = "Scripting", enabled = false},
			Project_Module{name = "Editor", enabled = true},
			Project_Module{name = "ENet", enabled = false},
		},
		plugins = {},
	}
}