package build

import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "../../Engine/src/Tools/rbs"
import toml "../../Engine/src/ext/toml_parser"

import "../../Engine/src/Core"


// ============================================================================
// PROJECT CONFIGURATION
// ============================================================================
//
// The project configuration schema is owned by the engine
// (Engine/src/Core/engine.odin). We import and reuse those types here so the
// build system and runtime always agree on what project.toml contains.
//


// ============================================================================
// PROJECT PATHS
// ============================================================================
//
// IMPORTANT:
//
// rune.exe is launched from the Project/ directory, so all relative paths
// below are resolved against Project/, not Project/rbs/ where this file
// lives.
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

PROJECT_CONFIG_PATH :: "config/project.toml"

ENGINE_MODULES_PATH :: "../Engine/src/Modules"
PROJECT_MODULES_PATH :: "modules"

DEBUG_OUTPUT_PATH :: "bin/Debug"
EDITOR_OUTPUT_PATH :: "bin/Editor"
RELEASE_OUTPUT_PATH :: "bin/Release"

ConfigState :: enum {
	None, // none found, continue and lets the engine create one
	Failed,
	Loaded, // loaded successfully
}
CONFIG_STATE := ConfigState.None
// ============================================================================
// GLOBAL CONFIGURATION
// ============================================================================
//
// RBS pre-build callbacks only receive Context + Profile.
//
// The project configuration is therefore loaded once and kept here for the
// duration of the RBS process.
//
project_config: Core.Project_Settings


// ============================================================================
// FATAL ERROR
// ============================================================================
fatal :: proc(message: string) -> ! {
	log.error(message)
	os.exit(1)
}


// ============================================================================
// PATH JOIN
// ============================================================================
join_project_path :: proc(a: string, b: string) -> string {
	result, err := filepath.join({a, b}, context.allocator)
	if err != nil {
		fatal(fmt.aprintf("Could not join paths:\n  %s\n  %s\n  %s", a, b, err))
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
load_project_config :: proc() -> Core.Project_Settings {
	fmt.println("")
	fmt.println("--------------------------------------------------")
	fmt.println("Loading project configuration")
	fmt.println("--------------------------------------------------")

	if !os.exists(PROJECT_CONFIG_PATH) {
		log.error("Project configuration was not found:\n  %s", PROJECT_CONFIG_PATH)
		CONFIG_STATE = .None
		return Core.Project_Settings{}
	}

	// ------------------------------------------------------------------------
	// Read file
	// ------------------------------------------------------------------------
	data, read_err := os.read_entire_file(PROJECT_CONFIG_PATH, context.allocator)
	config: Core.Project_Settings

	if read_err != nil {
		log.error("Could not read project configuration:\n  %s", read_err)
		CONFIG_STATE = .Failed
		return config
	}

	defer delete(data)

	// ------------------------------------------------------------------------
	// Parse TOML
	// ------------------------------------------------------------------------
	toml_err := toml.unmarshal(data, &config)

	if toml_err != nil {
		log.error("Could not parse project configuration:\n  %s", toml_err)
		CONFIG_STATE = .Failed
		return config
	}

	fmt.printfln("  Project: %s", config.project_name)

	fmt.printfln(
		"  Version: v%d.%d.%d",
		config.major,
		config.minor,
		config.patch,
	)
	CONFIG_STATE = .Loaded
	return config
}


// ============================================================================
// CLEANUP PROJECT CONFIGURATION
// ============================================================================
//
// Core.Project_Settings owns three [dynamic] arrays TOML unmarshalling fills
// them with heap allocations that we own. Free them here.
//
cleanup_project_config :: proc(s: ^Core.Project_Settings) {
	delete(s.modules)
	delete(s.extensions)
	delete(s.plugins)
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
// EDITOR MODULE NAME
// ============================================================================
//
// The Editor entry lives in settings.modules. A single constant lets us filter
// it consistently for non-editor profiles.
//
EDITOR_MODULE_NAME :: "Editor"


// ============================================================================
// SHOULD BUILD MODULE
// ============================================================================
//
// Centralized gating policy for a (module, profile) pair.
//
//   - If the module is disabled in project.toml, skip it.
//   - If the module is the Editor and the profile is not the editor build,
//     skip it. The Editor DLL only ships with the editor executable.
//
should_build_module :: proc(name: string, enabled: bool, profile_name: string) -> bool {
	if !enabled do return false
	if name == EDITOR_MODULE_NAME && profile_name != "Project-Editor" do return false
	return true
}


// ============================================================================
// BUILD MODULES
// ============================================================================
build_modules :: proc(settings: ^Core.Project_Settings, profile: rbs.Profile) {
	fmt.println("")
	fmt.println("==================================================")
	fmt.println(" ENGINE MODULES")
	fmt.println("==================================================")

	for m in settings.modules {
		if !should_build_module(m.name, m.enabled, profile.name) do continue
		build_module(m.name, profile)
	}
}


// ============================================================================
// BUILD EXTENSIONS
// ============================================================================
build_extensions :: proc(settings: ^Core.Project_Settings, profile: rbs.Profile) {
	if len(settings.extensions) == 0 {
		return
	}

	fmt.println("")
	fmt.println("==================================================")
	fmt.println(" EXTENSIONS")
	fmt.println("==================================================")

	for e in settings.extensions {
		if !e.enabled do continue
		build_module(e.name, profile)
	}
}


// ============================================================================
// BUILD PLUGINS
// ============================================================================
build_plugins :: proc(settings: ^Core.Project_Settings, profile: rbs.Profile) {
	if len(settings.plugins) == 0 {
		return
	}

	fmt.println("")
	fmt.println("==================================================")
	fmt.println(" PLUGINS")
	fmt.println("==================================================")

	for p in settings.plugins {
		if !p.enabled do continue
		build_module(p.name, profile)
	}
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

	err := rbs.copy(profile, "config", "config")

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

copy_project_scripts :: proc(profile: rbs.Profile) {
	fmt.println("")
	fmt.println("--------------------------------------------------")
	fmt.println("Copying project scripts")
	fmt.println("--------------------------------------------------")

	err := rbs.copy(profile, "scripts", "scripts")

	if err != nil {
		fatal(
			fmt.aprintf(
				"ERROR: Failed to copy project scripts:\n\n" +
				"  Source: ../scripts\n" +
				"  Destination: %s/scripts\n" +
				"  Error: %s",
				profile.output,
				err,
			),
		)
	}

	fmt.printfln("  ../assets -> %s/assets", profile.output)
}

copy_project_assets :: proc(profile: rbs.Profile) {
	fmt.println("")
	fmt.println("--------------------------------------------------")
	fmt.println("Copying project assets")
	fmt.println("--------------------------------------------------")

	err := rbs.copy(profile, "assets", "assets")

	if err != nil {
		fatal(
			fmt.aprintf(
				"ERROR: Failed to copy project assets:\n\n" +
				"  Source: ../assets\n" +
				"  Destination: %s/assets\n" +
				"  Error: %s",
				profile.output,
				err,
			),
		)
	}

	fmt.printfln("  ../assets -> %s/assets", profile.output)
}


// ============================================================================
// VERIFY MANIFESTS
// ============================================================================
//
// Runs `rbs manifest codegen --check` semantics: every package on disk
// must produce a <PackageName>.toml that matches what its IDENTITY/
// DEPENDENCIES blocks declare. Fails the build if anything is stale or
// missing.

verify_manifests :: proc() {
    if rbs.manifest_codegen_run_check() != 0 {
        fatal(
            "ERROR: Manifest check failed. Run `rune manifest` to regenerate, " +
            "or fix the offending IDENTITY/DEPENDENCIES blocks before building.",
        )
    }
}


// ============================================================================
// DEBUG PRE-BUILD
// ============================================================================

pre_build_debug :: proc(ctx: rbs.Context, profile: rbs.Profile) {
	_ = ctx

	verify_manifests()

	build_modules(&project_config, profile)

	build_extensions(&project_config, profile)

	build_plugins(&project_config, profile)

	copy_project_config(profile)

	copy_project_scripts(profile)

	copy_project_assets(profile)
}


// ============================================================================
// EDITOR PRE-BUILD
// ============================================================================

pre_build_editor :: proc(ctx: rbs.Context, profile: rbs.Profile) {
	_ = ctx

	verify_manifests()

	build_modules(&project_config, profile)

	build_extensions(&project_config, profile)

	build_plugins(&project_config, profile)

	copy_project_config(profile)

	copy_project_scripts(profile)

	copy_project_assets(profile)
}


// ============================================================================
// RELEASE PRE-BUILD
// ============================================================================

pre_build_release :: proc(ctx: rbs.Context, profile: rbs.Profile) {
	_ = ctx

	verify_manifests()

	build_modules(&project_config, profile)

	build_extensions(&project_config, profile)

	build_plugins(&project_config, profile)

	copy_project_config(profile)

	copy_project_scripts(profile)

	copy_project_assets(profile)
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
	context.logger = log.create_console_logger()
	// ------------------------------------------------------------------------
	// RBS context
	// ------------------------------------------------------------------------
	ctx := rbs.init_context()
	defer rbs.dispose_context(ctx)

	// ------------------------------------------------------------------------
	// Load project configuration
	// ------------------------------------------------------------------------
	project_config = load_project_config()

	// Free the dynamic arrays owned by Core.Project_Settings at exit. Safe to
	// call on the zero-value returned by the .None / failed-read paths.
	defer cleanup_project_config(&project_config)

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

	switch CONFIG_STATE {
	case .None:
		log.warn("Starting engine without project.toml..")
		return
	case .Failed:
		log.error(
			"Failed to load project configuration, please check your project.toml file format.",
		)
		log.destroy_console_logger(context.logger)
		os.exit(1)
	case .Loaded:
		log.info("Loaded project configuration.")
		// ------------------------------------------------------------------------
		// Header
		// ------------------------------------------------------------------------

		fmt.println("")
		fmt.println("==================================================")
		fmt.println(" Odin Practice Build System")
		fmt.println("==================================================")

		fmt.printfln(" Project: %s", project_config.project_name)

		fmt.printfln(
			" Version: v%d.%d.%d",
			project_config.major,
			project_config.minor,
			project_config.patch,
		)

		fmt.printfln(" Config:  %s", PROJECT_CONFIG_PATH)

		fmt.println("==================================================")
	}

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
	// MANIFEST COMMAND
	// ========================================================================
	//
	// `rbs manifest` walks Engine/src/Modules, Engine/src/Extensions, and
	// Project/Plugins, extracts the IDENTITY/DEPENDENCIES/TARGETS blocks
	// from each package's .odin source, and emits <PackageName>.toml next
	// to the source.
	//
	// Usage:
	//     rune manifest                       # generate everything
	//     rune manifest Bifrost_Renderer      # one package, relative path
	//     rune manifest --check               # exit 1 if any manifest is stale
	//
	rbs.add_command(&ctx, "manifest", proc(ctx: rbs.Context, profile: rbs.Profile) {
		rbs.manifest_codegen_run(ctx, profile)
	})

	// ========================================================================
	// PROCESS CLI
	// ========================================================================
	rbs.process(ctx)
	log.destroy_console_logger(context.logger)
}
