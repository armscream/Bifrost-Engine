// Engine\src\Core\engine.odin
package Core

import "core:encoding/json"
import "core:fmt"
import "core:log"
import "core:os"


// =================
// Project Settings
Project_Settings :: struct {
	project_name:  string,
	using version: Version,
	modules:       [dynamic]Project_Module,
	extensions:    [dynamic]Project_Extension,
	plugins:       [dynamic]Project_Plugin,
}

Project_Module :: struct {
	name:    string,
	version: Version,
	enabled: bool,
}

Project_Extension :: struct {
	name:    string,
	version: Version,
	enabled: bool,
}

Project_Plugin :: struct {
	name:    string,
	version: Version,
	enabled: bool,
}

Version :: struct {
	major: u32,
	minor: u32,
	patch: u32,
}
BASEVERSION: Version = {
	major = 0,
	minor = 0,
	patch = 1,
}

// =====================
// Global Project State
GLOBAL_PROJECT_SETTINGS := Project_Settings{}

// =====================
// Runtime State
RUN_EDITOR: bool = false

GLOBAL_MODULE_REGISTRY: Module_Registry
GLOBAL_PLUGIN_REGISTRY: Plugin_Registry
GLOBAL_EXTENSION_REGISTRY: Extension_Registry
GLOBAL_SERVICE_REGISTRY: Service_Registry

Load_State :: enum u32 {
	Unloaded,
	Loaded,
	Registered,
	Active,
	Failed,
}

// =====================
// Application Callback
APPRUNHANDLE: proc()

// =====================
// Engine Initialization
init :: proc(apprunhandle: proc(), run_editor: bool) -> bool {
	context.logger = log.create_console_logger()
	inject_default_project_settings()

	RUN_EDITOR = run_editor
	APPRUNHANDLE = apprunhandle

	fmt.println("")
	fmt.println("========================================")
	fmt.println(" ENGINE INIT")
	fmt.println("========================================")

	// Project Settings
	if !load_project_settings() {
		setup_default_project_settings_file()
	}

	// Init registries
	if !module_registry_init(&GLOBAL_MODULE_REGISTRY, context.allocator) do return false
	if !extension_registry_init(&GLOBAL_EXTENSION_REGISTRY, context.allocator) do return false
	if !plugin_registry_init(&GLOBAL_PLUGIN_REGISTRY, context.allocator) do return false
	if !service_registry_init(&GLOBAL_SERVICE_REGISTRY, context.allocator) do return false

	// MODULES
	if !module_load_project_modules() do return false
	if !module_resolve_dependencies(&GLOBAL_MODULE_REGISTRY) do return false
	if !module_register_all(&GLOBAL_MODULE_REGISTRY) do return false

	// EXTENSIONS
	if !extension_load_project_extensions() do return false
	// Resolve extension dependencies / targets
	if !extension_resolve_dependencies(&GLOBAL_EXTENSION_REGISTRY, &GLOBAL_MODULE_REGISTRY) do return false
	// Register extensions
	if !extension_register_all(&GLOBAL_EXTENSION_REGISTRY, &GLOBAL_MODULE_REGISTRY) do return false

	// Load Plugins
	// TODO: complete these
	//if !plugin_load_project_plugins() do return false
	//if !plugin_resolve_dependencies(&GLOBAL_PLUGIN_REGISTRY) do return false
	//if !plugin_register_all(&GLOBAL_PLUGIN_REGISTRY) do return false

	// Build engine scheduling after all systems have registered
	if !scheduler_build() do return false

	// ACTIVATION
	if !module_activate_all(&GLOBAL_MODULE_REGISTRY) do return false
	// TODO: complete these
	//if !extension_activate_all(&GLOBAL_EXTENSION_REGISTRY) do return false
	//if !plugin_activate_all(&GLOBAL_PLUGIN_REGISTRY) do return false

	fmt.println("")
	fmt.println("Engine initialization complete.")
	return true
}

// ================
// Engine Run
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

// ==================
// Engine Destroy
destroy :: proc() -> bool {
	fmt.println("")
	fmt.println("========================================")
	fmt.println(" ENGINE DESTROY")
	fmt.println("========================================")

	// DEACTIVATE
	// TODO:
	//plugin_deactivate_all(&GLOBAL_PLUGIN_REGISTRY)
	extension_deactivate_all(&GLOBAL_EXTENSION_REGISTRY)
	// Stop modules while their runtime dependencies still exist.
	module_deactivate_all(&GLOBAL_MODULE_REGISTRY)

	// Destroy Core runtime infrastructure.
	scheduler_shutdown()

	// UNLOAD prior to destroying
	extension_unload_all(&GLOBAL_EXTENSION_REGISTRY)
	plugin_unload_all(&GLOBAL_PLUGIN_REGISTRY)
	service_registry_destroy(&GLOBAL_SERVICE_REGISTRY)
	module_unload_all(&GLOBAL_MODULE_REGISTRY)
	extension_registry_destroy(&GLOBAL_EXTENSION_REGISTRY)
	module_registry_destroy(&GLOBAL_MODULE_REGISTRY)
	plugin_registry_destroy(&GLOBAL_PLUGIN_REGISTRY)


	APPRUNHANDLE = nil

	log.destroy_console_logger(context.logger)

	return true
}

@(private)
load_project_settings :: proc() -> bool {
	if !os.exists("config/project.json") do return false
	//TODO: make this proc find the project.json file and then load the project settings, if unable then return false.
	log.warn("load_project_settings: not yet implemented")
	return true
}
// This injects the default project settings if no project settings are found.
@(private)
inject_default_project_settings :: proc() {
	// Populate using append
	GLOBAL_PROJECT_SETTINGS.project_name = "New Project"
	GLOBAL_PROJECT_SETTINGS.version = BASEVERSION
	// Default Modules
	append(
		&GLOBAL_PROJECT_SETTINGS.modules,
		Project_Module{name = "Bifrost_Renderer", version = BASEVERSION, enabled = true},
	)
	append(
		&GLOBAL_PROJECT_SETTINGS.modules,
		Project_Module{name = "DAG", version = BASEVERSION, enabled = true},
	)
	append(
		&GLOBAL_PROJECT_SETTINGS.modules,
		Project_Module{name = "ECS", version = BASEVERSION, enabled = true},
	)
	append(
		&GLOBAL_PROJECT_SETTINGS.modules,
		Project_Module{name = "Default_Input", version = BASEVERSION, enabled = false},
	)
	append(
		&GLOBAL_PROJECT_SETTINGS.modules,
		Project_Module{name = "Miniaudio", version = BASEVERSION, enabled = false},
	)
	append(
		&GLOBAL_PROJECT_SETTINGS.modules,
		Project_Module{name = "Box3D_Physics", version = BASEVERSION, enabled = false},
	)
	append(
		&GLOBAL_PROJECT_SETTINGS.modules,
		Project_Module{name = "ATLAS-RMGUI", version = BASEVERSION, enabled = false},
	)
	append(
		&GLOBAL_PROJECT_SETTINGS.modules,
		Project_Module{name = "Scripting", version = BASEVERSION, enabled = false},
	)
	append(
		&GLOBAL_PROJECT_SETTINGS.modules,
		Project_Module{name = "Editor", version = BASEVERSION, enabled = true},
	)
	append(
		&GLOBAL_PROJECT_SETTINGS.modules,
		Project_Module{name = "ENet", version = BASEVERSION, enabled = false},
	)
	// Default Extensions
	append(
		&GLOBAL_PROJECT_SETTINGS.extensions,
		Project_Extension{name = "Example Extension", version = BASEVERSION, enabled = false},
	)
	// Default Plugins
	append(
		&GLOBAL_PROJECT_SETTINGS.plugins,
		Project_Plugin{name = "Example Plugin", version = BASEVERSION, enabled = false},
	)
}
// This creates a default project settings file and configs folder if not found.
@(private)
setup_default_project_settings_file :: proc() -> bool {
	// 1. Get the directory where the .exe is located
	exe_dir, err := os.get_executable_directory(context.allocator)
	if err != nil {
		fmt.eprintfln("Failed to get executable directory: %v", err)
		return false
	}
	defer delete(exe_dir)

	// DEBUG: Print the exact base directory being used
	fmt.printfln("DEBUG: Executable Directory = '%s'", exe_dir)

	// 2. Build the path: <exe_dir>/config/project.json
	config_dir, err1 := os.join_path({exe_dir, "config"}, context.allocator)
	if err1 != nil {
		fmt.eprintfln("Failed to join config path: %v", err1)
		return false
	}
	defer delete(config_dir)

	file_path, err2 := os.join_path({config_dir, "project.json"}, context.allocator)
	if err2 != nil {
		fmt.eprintfln("Failed to join file path: %v", err2)
		return false
	}
	defer delete(file_path)

	// DEBUG: Print the full target path
	fmt.printfln("DEBUG: Target File Path = '%s'", file_path)

	// 3. Ensure the 'config' directory exists (RECURSIVELY)
	if !os.exists(config_dir) {
		fmt.printfln("DEBUG: Config dir does not exist, creating...")
		mkdir_err := os.make_directory_all(config_dir)
		if mkdir_err != nil {
			fmt.eprintfln(
				"Failed to create config directory at: %s, error: %v",
				config_dir,
				mkdir_err,
			)
			return false
		}
	} else {
		fmt.printfln("DEBUG: Config dir already exists.")
	}

	// 4. Marshal the global struct to JSON
	json_data, marshal_err := json.marshal(
		GLOBAL_PROJECT_SETTINGS,
		{pretty = true},
		context.allocator,
	)
	if marshal_err != nil {
		fmt.eprintfln("Failed to marshal JSON: %v", marshal_err)
		return false
	}
	defer delete(json_data)

	fmt.printfln("DEBUG: JSON Data Size = %d bytes", len(json_data))

	// 5. Write the JSON data to the file
	write_err := os.write_entire_file(file_path, json_data)
	if write_err != nil {
		// CRITICAL: This will tell you if it's a permission error or path error
		fmt.eprintfln("Failed to write file %s: %v", file_path, write_err)
		return false
	}

	fmt.printfln("Successfully created project settings at: %s", file_path)

	// Double check existence immediately after write
	if os.exists(file_path) {
		fmt.printfln("Verification: File confirmed to exist.")
	} else {
		fmt.eprintfln("Verification: File reported as written but does not exist!")
	}

	return true
}

// TODO: implement the DAG as a module.
@(private)
scheduler_build :: proc() -> bool {
	log.warn("Scheduler build not implemented - scheduler not hooked up yet")
	return true
}
@(private)
scheduler_shutdown :: proc() -> bool {
	log.warn("Scheduler shutdown not implemented - scheduler not hooked up yet")
	return true
}
