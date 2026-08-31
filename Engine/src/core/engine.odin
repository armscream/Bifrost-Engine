// Engine\src\Core\engine.odin
package Core

import "core:fmt"
import "core:log"

// The engine owns one manager per component type. Modules/Extensions/Plugins
// all use the same Loaded_Lib + Lib_Context pipeline; they differ only in
// the manager that drives their lifecycle.

// Global managers (engine-owned singletons).
// These are package-internal — only the engine, managers, and the SDK can
// touch them. Components MUST go through the SDK rather than reading these directly.
@(private)
GLOBAL_MODULE_MANAGER:    Module_Manager
@(private)
GLOBAL_EXTENSION_MANAGER: Extension_Manager
@(private)
GLOBAL_PLUGIN_MANAGER:    Plugin_Manager
@(private)
GLOBAL_SERVICE_REGISTRY:  Service_Registry
@(private)
GLOBAL_RESOURCE_REGISTRY: Resource_Registry
@(private)
GLOBAL_EVENT_REGISTRY:    Event_Registry

// RUN_EDITOR is set by init when the engine is launched with RUN_EDITOR=true.
// The editor module and a few capability checks read it; treat it as
// read-only from outside engine.init.
RUN_EDITOR: bool = false

// APPRUNHANDLE is the user's main-loop callback invoked from run().
APPRUNHANDLE: proc()

// ENGINE INIT
init :: proc(apprunhandle: proc(), run_editor: bool) -> bool {
	context.logger = log.create_console_logger()
	inject_default_project_settings()

	RUN_EDITOR = run_editor
	APPRUNHANDLE = apprunhandle

	fmt.println("")
	fmt.println("========================================")
	fmt.println(" ENGINE INIT")
	fmt.println("========================================")

	// Project Settings (TOML).
	if !load_project_settings_toml() {
		setup_default_project_settings_toml()
	}

	// Init managers.
	if !module_manager_init(&GLOBAL_MODULE_MANAGER, context.allocator) do return false
	if !extension_manager_init(&GLOBAL_EXTENSION_MANAGER, context.allocator) do return false
	if !plugin_manager_init(&GLOBAL_PLUGIN_MANAGER, context.allocator) do return false
	if !service_registry_init(&GLOBAL_SERVICE_REGISTRY, context.allocator) do return false

	// MODULES
	if !module_manager_load_project(&GLOBAL_MODULE_MANAGER) do return false
	if !module_manager_resolve(&GLOBAL_MODULE_MANAGER) do return false
	if !module_manager_activate_all(&GLOBAL_MODULE_MANAGER) do return false

	// EXTENSIONS
	if !extension_manager_load_project(&GLOBAL_EXTENSION_MANAGER) do return false
	if !extension_manager_resolve(&GLOBAL_EXTENSION_MANAGER) do return false
	if !extension_manager_register_all(&GLOBAL_EXTENSION_MANAGER) do return false
	if !extension_manager_activate_all(&GLOBAL_EXTENSION_MANAGER) do return false

	// PLUGINS
	if !plugin_manager_load_project(&GLOBAL_PLUGIN_MANAGER) do return false
	if !plugin_manager_register_all(&GLOBAL_PLUGIN_MANAGER) do return false
	if !plugin_manager_activate_all(&GLOBAL_PLUGIN_MANAGER) do return false

	// Build engine scheduling after all systems have registered
	if !scheduler_build() do return false

	fmt.println("")
	fmt.println("Engine initialization complete.")
	return true
}

// ENGINE RUN
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

// ENGINE DESTROY
destroy :: proc() -> bool {
	cleanup_project_settings(project_settings_get())
	fmt.println("")
	fmt.println("========================================")
	fmt.println(" ENGINE DESTROY")
	fmt.println("========================================")

	// DEACTIVATE (reverse order)
	plugin_manager_deactivate_all(&GLOBAL_PLUGIN_MANAGER)
	extension_manager_deactivate_all(&GLOBAL_EXTENSION_MANAGER)
	module_manager_deactivate_all(&GLOBAL_MODULE_MANAGER)

	scheduler_shutdown()

	// UNLOAD + DESTROY (reverse order)
	plugin_manager_unload_all(&GLOBAL_PLUGIN_MANAGER)
	plugin_manager_destroy(&GLOBAL_PLUGIN_MANAGER)
	extension_manager_unload_all(&GLOBAL_EXTENSION_MANAGER)
	extension_manager_destroy(&GLOBAL_EXTENSION_MANAGER)
	service_registry_destroy(&GLOBAL_SERVICE_REGISTRY)
	module_manager_unload_all(&GLOBAL_MODULE_MANAGER)
	module_manager_destroy(&GLOBAL_MODULE_MANAGER)

	APPRUNHANDLE = nil

	log.destroy_console_logger(context.logger)

	return true
}


// scheduler_build / scheduler_shutdown are placeholders so engine.odin
// compiles standalone. Once the BF_DAG scheduler module is wired in, these
// will either delegate into the DAG service (preferred) or be removed in
// favour of an explicit scheduler service handle.
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