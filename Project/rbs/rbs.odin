package build

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../../Tools/rbs"


// ============================================================================
// PROJECT CONFIGURATION
// ============================================================================

Project_Config :: struct {
	project_name:  string,
	version:       string,
	renderer_dll:  string,
	input_dll:     string,
	ecs_dll:       string,
	audio_dll:     string,
	physics_dll:   string,
	ui_dll:        string,
	editor_dll:    string,
	plugins:       []string,
	other_modules: []string,
}


// ============================================================================
// PROJECT PATHS
// ============================================================================
//
// IMPORTANT:
//
// rbs.odin lives here:
//
//     Project/rbs/rbs.odin
//
// Therefore all paths are relative to:
//
//     Project/rbs
//
// Project layout:
//
//     Ymir Engine/
//     ├── Engine/
//     │   └── src/
//     │       └── Modules/
//     │
//     ├── Project/
//     │   ├── config/
//     │   ├── modules/
//     │   ├── bin/
//     │   └── rbs/
//     │       └── rbs.odin
//     │
//     └── Tools/
//         └── rbs/
//
// ============================================================================

PROJECT_CONFIG_PATH :: "../config/project.json"

ENGINE_MODULES_PATH :: "../../Engine/src/Modules"
PROJECT_MODULES_PATH :: "../modules"

DEBUG_OUTPUT_PATH :: "../bin/Debug"
EDITOR_OUTPUT_PATH :: "../bin/Editor"
RELEASE_OUTPUT_PATH :: "../bin/Release"


// ============================================================================
// GLOBAL CONFIGURATION
// ============================================================================
//
// RBS pre-build callbacks only receive Context + Profile.
//
// The project configuration is therefore loaded once and kept here for the
// duration of the RBS process.
//

project_config: Project_Config


// ============================================================================
// FATAL ERROR
// ============================================================================

fatal :: proc(message: string) -> ! {
	fmt.eprintln(message)
	os.exit(1)
}


// ============================================================================
// PATH JOIN
// ============================================================================

join_project_path :: proc(a: string, b: string) -> string {
	result, err := filepath.join({a, b}, context.allocator)

	if err != nil {
		fatal(fmt.aprintf("ERROR: Could not join paths:\n  %s\n  %s\n  %s", a, b, err))
	}

	return result
}


// ============================================================================
// COMMAND PATH
// ============================================================================
//
// RBS currently executes commands by splitting them on spaces.
//
// Because the repository itself is located at:
//
//     Ymir Engine
//
// absolute paths would introduce spaces into the Odin command.
//
// Therefore commands use repository-relative paths:
//
//     ../../Engine/src/Modules/...
//     ../bin/Editor/...
//
// Both contain no spaces.
//

command_path :: proc(path: string) -> string {
	result := strings.clone(path)

	result, _ = strings.replace(result, "\\", "/", -1)

	return result
}


// ============================================================================
// LOAD PROJECT CONFIGURATION
// ============================================================================

load_project_config :: proc() -> Project_Config {
	fmt.println("")
	fmt.println("--------------------------------------------------")
	fmt.println("Loading project configuration")
	fmt.println("--------------------------------------------------")

	if !os.exists(PROJECT_CONFIG_PATH) {
		fatal(
			fmt.aprintf("ERROR: Project configuration was not found:\n  %s", PROJECT_CONFIG_PATH),
		)
	}

	// ------------------------------------------------------------------------
	// Read file
	// ------------------------------------------------------------------------

	data, read_err := os.read_entire_file(PROJECT_CONFIG_PATH, context.allocator)

	if read_err != nil {
		fatal(fmt.aprintf("ERROR: Could not read project configuration:\n  %s", read_err))
	}

	defer delete(data)

	// ------------------------------------------------------------------------
	// Parse JSON
	// ------------------------------------------------------------------------

	config: Project_Config

	json_err := json.unmarshal(data, &config)

	if json_err != nil {
		fatal(fmt.aprintf("ERROR: Could not parse project configuration:\n  %s", json_err))
	}

	fmt.printfln("  Project: %s", config.project_name)

	fmt.printfln("  Version: %s", config.version)

	return config
}


// ============================================================================
// NORMALIZE MODULE NAME
// ============================================================================
//
// Accepts:
//
//     Bifrost_Renderer
//
// or:
//
//     Bifrost_Renderer.dll
//
// Internally:
//
//     Bifrost_Renderer
//

normalize_module_name :: proc(input: string) -> string {
	module := strings.clone(input)

	if strings.has_suffix(module, ".dll") {
		module = strings.trim_suffix(module, ".dll")
	}

	return module
}


// ============================================================================
// RESOLVE MODULE SOURCE
// ============================================================================
//
// Search order:
//
//     1. Project/modules/<module>
//     2. Engine/src/Modules/<module>
//
// Project modules override engine modules.
//
// IMPORTANT:
//
// This returns a RELATIVE path.
//
// Do not convert it to an absolute path because the RBS command runner
// currently splits commands on spaces.
//

resolve_module_source :: proc(input: string) -> string {
	module := normalize_module_name(input)

	// ------------------------------------------------------------------------
	// Project module
	// ------------------------------------------------------------------------

	project_source := join_project_path(PROJECT_MODULES_PATH, module)

	if os.exists(project_source) && os.is_dir(project_source) {

		fmt.printfln("    Project module: %s", project_source)

		return project_source
	}

	// ------------------------------------------------------------------------
	// Engine module
	// ------------------------------------------------------------------------

	engine_source := join_project_path(ENGINE_MODULES_PATH, module)

	if os.exists(engine_source) && os.is_dir(engine_source) {

		fmt.printfln("    Engine module:  %s", engine_source)

		return engine_source
	}

	// ------------------------------------------------------------------------
	// Not found
	// ------------------------------------------------------------------------

	fatal(
		fmt.aprintf(
			"ERROR: Required module source was not found:\n\n" +
			"  %s\n\n" +
			"Searched:\n" +
			"  %s\n" +
			"  %s",
			module,
			project_source,
			engine_source,
		),
	)
}


// ============================================================================
// BUILD ONE MODULE DLL
// ============================================================================

build_module :: proc(input: string, profile: rbs.Profile) {
	if input == "" {
		return
	}

	module := normalize_module_name(input)

	fmt.println("")
	fmt.println("--------------------------------------------------")
	fmt.printfln("Building module: %s", module)
	fmt.println("--------------------------------------------------")

	// ------------------------------------------------------------------------
	// Resolve source
	// ------------------------------------------------------------------------

	source := resolve_module_source(module)

	fmt.printfln("  Source: %s", source)

	// ------------------------------------------------------------------------
	// DLL output
	// ------------------------------------------------------------------------

	dll_name := fmt.aprintf("%s.dll", module)

	defer delete(dll_name)

	output := join_project_path(profile.output, dll_name)

	fmt.printfln("  Output: %s", output)

	// ------------------------------------------------------------------------
	// Ensure output directory
	// ------------------------------------------------------------------------

	if !os.exists(profile.output) {
		err := os.make_directory_all(profile.output)

		if err != nil {
			fatal(
				fmt.aprintf(
					"ERROR: Could not create output directory:\n" + "  %s\n" + "  %s",
					profile.output,
					err,
				),
			)
		}
	}

	// ------------------------------------------------------------------------
	// Remove old DLL
	// ------------------------------------------------------------------------
	//
	// This is important.
	//
	// Otherwise Odin can fail while an old DLL remains on disk and the build
	// system could incorrectly report success merely because the DLL exists.
	//

	if os.exists(output) {
		remove_err := os.remove(output)

		if remove_err != nil {
			fatal(
				fmt.aprintf(
					"ERROR: Could not remove previous module DLL:\n\n" + "  %s\n\n" + "  %s",
					output,
					remove_err,
				),
			)
		}
	}

	// ------------------------------------------------------------------------
	// Module build flags
	// ------------------------------------------------------------------------
	//
	// Do NOT inherit profile.flags.
	//
	// EDITOR contains:
	//
	//     -define:RUN_EDITOR=true
	//
	// That define belongs to the executable, not the module DLL.
	//

	module_flags := "-debug"

	if strings.contains(profile.flags, "-release") {
		module_flags = "-release"
	}

	// ------------------------------------------------------------------------
	// Convert paths for Odin command
	// ------------------------------------------------------------------------

	command_source := command_path(source)
	command_output := command_path(output)

	// ------------------------------------------------------------------------
	// Construct command
	// ------------------------------------------------------------------------
	//
	// No quotes are used because the current RBS runner splits commands on
	// spaces.
	//
	// The relative paths contain no spaces.
	//

	command := fmt.aprintf(
		"odin build %s -build-mode:dll -out:%s %s",
		command_source,
		command_output,
		module_flags,
	)

	defer delete(command)

	fmt.printfln("  Command: %s", command)

	// ------------------------------------------------------------------------
	// Run Odin
	// ------------------------------------------------------------------------

	err := rbs.run_script(command)

	if err != nil {
		fatal(
			fmt.aprintf(
				"ERROR: Failed to build module:\n\n" +
				"  %s\n\n" +
				"Source:\n" +
				"  %s\n\n" +
				"Command:\n" +
				"  %s\n\n" +
				"RBS error:\n" +
				"  %s",
				module,
				source,
				command,
				err,
			),
		)
	}

	// ------------------------------------------------------------------------
	// Verify DLL
	// ------------------------------------------------------------------------

	if !os.exists(output) {
		fatal(
			fmt.aprintf(
				"ERROR: Odin finished, but the DLL was not produced:\n\n" + "  %s",
				output,
			),
		)
	}

	fmt.printfln("  SUCCESS: %s", output)
}


// ============================================================================
// BUILD CORE MODULES
// ============================================================================

build_core_modules :: proc(config: Project_Config, profile: rbs.Profile) {
	fmt.println("")
	fmt.println("==================================================")
	fmt.println(" CORE ENGINE MODULES")
	fmt.println("==================================================")

	build_module(config.renderer_dll, profile)

	build_module(config.input_dll, profile)

	build_module(config.ecs_dll, profile)

	build_module(config.audio_dll, profile)

	build_module(config.physics_dll, profile)

	build_module(config.ui_dll, profile)
}


// ============================================================================
// BUILD PLUGINS
// ============================================================================

build_plugins :: proc(config: Project_Config, profile: rbs.Profile) {
	if len(config.plugins) == 0 {
		return
	}

	fmt.println("")
	fmt.println("==================================================")
	fmt.println(" PLUGINS")
	fmt.println("==================================================")

	for plugin in config.plugins {
		build_module(plugin, profile)
	}
}


// ============================================================================
// BUILD OTHER MODULES
// ============================================================================

build_other_modules :: proc(config: Project_Config, profile: rbs.Profile) {
	if len(config.other_modules) == 0 {
		return
	}

	fmt.println("")
	fmt.println("==================================================")
	fmt.println(" OTHER MODULES")
	fmt.println("==================================================")

	for module in config.other_modules {
		build_module(module, profile)
	}
}


// ============================================================================
// BUILD EDITOR MODULE
// ============================================================================

build_editor_module :: proc(config: Project_Config, profile: rbs.Profile) {
	if config.editor_dll == "" {
		return
	}

	fmt.println("")
	fmt.println("==================================================")
	fmt.println(" EDITOR MODULE")
	fmt.println("==================================================")

	build_module(config.editor_dll, profile)
}


// ============================================================================
// COPY CONFIGURATION
// ============================================================================
//
// From:
//
//     Project/config
//
// To:
//
//     Project/bin/<Profile>/config
//
// Since RBS executes from:
//
//     Project/rbs
//
// the source path is:
//
//     ../config
//
// and the destination is relative to profile.output:
//
//     config
//

copy_project_config :: proc(profile: rbs.Profile) {
	fmt.println("")
	fmt.println("--------------------------------------------------")
	fmt.println("Copying project configuration")
	fmt.println("--------------------------------------------------")

	err := rbs.copy(profile, "../config", "config")

	if err != nil {
		fatal(
			fmt.aprintf(
				"ERROR: Failed to copy project configuration:\n\n" +
				"  Source: ../config\n" +
				"  Destination: %s/config\n" +
				"  Error: %s",
				profile.output,
				err,
			),
		)
	}

	fmt.printfln("  ../config -> %s/config", profile.output)
}


// ============================================================================
// DEBUG PRE-BUILD
// ============================================================================

pre_build_debug :: proc(ctx: rbs.Context, profile: rbs.Profile) {
	_ = ctx

	build_core_modules(project_config, profile)

	build_plugins(project_config, profile)

	build_other_modules(project_config, profile)

	copy_project_config(profile)
}


// ============================================================================
// EDITOR PRE-BUILD
// ============================================================================

pre_build_editor :: proc(ctx: rbs.Context, profile: rbs.Profile) {
	_ = ctx

	build_core_modules(project_config, profile)

	build_plugins(project_config, profile)

	build_other_modules(project_config, profile)

	// Editor DLL is only built for EDITOR.

	build_editor_module(project_config, profile)

	copy_project_config(profile)
}


// ============================================================================
// RELEASE PRE-BUILD
// ============================================================================

pre_build_release :: proc(ctx: rbs.Context, profile: rbs.Profile) {
	_ = ctx

	build_core_modules(project_config, profile)

	build_plugins(project_config, profile)

	build_other_modules(project_config, profile)

	copy_project_config(profile)
}


// ============================================================================
// PRE-BUILD DISPATCH
// ============================================================================

pre_build :: proc(ctx: rbs.Context, profile: rbs.Profile) {
	switch profile.name {
	case "Project-Debug":
		pre_build_debug(ctx, profile)

	case "Project-Editor":
		pre_build_editor(ctx, profile)

	case "Project":
		pre_build_release(ctx, profile)

	case:
		fatal(fmt.aprintf("ERROR: Unknown build profile: %s", profile.name))
	}
}


// ============================================================================
// MAIN
// ============================================================================

main :: proc() {
	// ------------------------------------------------------------------------
	// RBS context
	// ------------------------------------------------------------------------

	ctx := rbs.init_context()

	defer rbs.dispose_context(ctx)

	// ------------------------------------------------------------------------
	// Load project configuration
	// ------------------------------------------------------------------------

	project_config = load_project_config()

	// ------------------------------------------------------------------------
	// Header
	// ------------------------------------------------------------------------

	fmt.println("")
	fmt.println("==================================================")
	fmt.println(" Odin Practice Build System")
	fmt.println("==================================================")

	fmt.printfln(" Project: %s", project_config.project_name)

	fmt.printfln(" Version: %s", project_config.version)

	fmt.printfln(" Config:  %s", PROJECT_CONFIG_PATH)

	fmt.println("==================================================")

	// ========================================================================
	// DEBUG PROFILE
	// ========================================================================

	rbs.add_profile(
		&ctx,
		"DEBUG",
		{
			entry = "..",
			flags = "-vet -debug",
			mode = .Executable,
			name = "Project-Debug",
			output = DEBUG_OUTPUT_PATH,
			arch = ODIN_ARCH,
			os = ODIN_OS,
		},
	)

	// ========================================================================
	// EDITOR PROFILE
	// ========================================================================

	rbs.add_profile(
		&ctx,
		"EDITOR",
		{
			entry = "..",
			flags = "-vet -debug -define:RUN_EDITOR=true",
			mode = .Executable,
			name = "Project-Editor",
			output = EDITOR_OUTPUT_PATH,
			arch = ODIN_ARCH,
			os = ODIN_OS,
		},
	)

	// ========================================================================
	// RELEASE PROFILE
	// ========================================================================

	rbs.add_profile(
		&ctx,
		"RELEASE",
		{
			entry = "..",
			flags = "-vet -release",
			mode = .Executable,
			name = "Project",
			output = RELEASE_OUTPUT_PATH,
			arch = ODIN_ARCH,
			os = ODIN_OS,
		},
	)

	// ========================================================================
	// PRE-BUILD
	// ========================================================================

	rbs.add_pre_build_step(&ctx, pre_build)

	// ========================================================================
	// DEFAULT RUN COMMAND
	// ========================================================================

	rbs.add_command(&ctx, "", proc(ctx: rbs.Context, profile: rbs.Profile) {
		rbs.exec_odin_cmd(ctx, .Run, profile)
	})

	// ========================================================================
	// RUN COMMAND
	// ========================================================================

	rbs.add_command(&ctx, "run", proc(ctx: rbs.Context, profile: rbs.Profile) {
		rbs.exec_odin_cmd(ctx, .Run, profile)
	})

	// ========================================================================
	// BUILD COMMAND
	// ========================================================================
	rbs.add_command(&ctx, "build", proc(ctx: rbs.Context, profile: rbs.Profile) {
		rbs.exec_odin_cmd(ctx, rbs.Odin_Command.Build, profile)
	})

	// ========================================================================
	// PROCESS CLI
	// ========================================================================

	rbs.process(ctx)
}
