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
// Global Project State
// ============================================================================

GLOBAL_PROJECT_SETTINGS: Project_Settings = {}


// ============================================================================
// Runtime State
// ============================================================================

RUN_EDITOR: bool = false

GLOBAL_RENDERER: Loaded_Module
GLOBAL_INPUT: Loaded_Module
GLOBAL_ECS: Loaded_Module
GLOBAL_AUDIO: Loaded_Module
GLOBAL_PHYSICS: Loaded_Module
GLOBAL_UI: Loaded_Module
GLOBAL_EDITOR: Loaded_Module

GLOBAL_PLUGINS: []Loaded_Plugin
GLOBAL_OTHER: []Loaded_Module


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

	// ------------------------------------------------------------------------
	// Locate executable directory
	// ------------------------------------------------------------------------

	exec_dir, dir_err := os.get_executable_directory(context.temp_allocator)

	if dir_err != nil {
		log.error("Failed to get executable directory: %v", dir_err)

		return false
	}

	fmt.println("Executable directory: ", exec_dir)


	// ------------------------------------------------------------------------
	// Locate project configuration
	// ------------------------------------------------------------------------

	file_path, join_err := os.join_path({exec_dir, "config/project.json"}, context.temp_allocator)

	if join_err != nil {
		log.error("Failed to construct project configuration path: %v", join_err)

		return false
	}

	fmt.println("Project configuration: ", file_path)


	// ------------------------------------------------------------------------
	// Create default configuration if necessary
	// ------------------------------------------------------------------------

	if !os.exists(file_path) {
		fmt.println("Project configuration does not exist. Creating default configuration...")

		default_settings := Project_Settings {
			project_name  = "New Project",
			version       = "0.0.1",
			renderer_dll  = "Bifrost_Renderer",
			input_dll     = "",
			ecs_dll       = "",
			audio_dll     = "",
			physics_dll   = "",
			ui_dll        = "",
			editor_dll    = "",
			plugins       = {},
			other_modules = {},
		}

		json_data, marshal_err := json.marshal(default_settings)

		if marshal_err != nil {
			log.error("Failed to marshal default project configuration: %v", marshal_err)

			return false
		}

		write_err := os.write_entire_file(file_path, json_data)

		delete(json_data)

		if write_err != nil {
			log.error("Failed to write project configuration: %v", write_err)

			return false
		}

		fmt.println("Default project configuration created.")
	}


	// ------------------------------------------------------------------------
	// Read project configuration
	//
	// IMPORTANT:
	//
	// Keep this allocation alive for the lifetime of the engine.
	//
	// The JSON decoder creates strings/slices associated with this allocation.
	// We therefore intentionally do not delete the data here.
	// ------------------------------------------------------------------------

	data, read_err := os.read_entire_file(file_path, context.allocator)

	if read_err != nil {
		log.error("Failed to read project configuration: %v", read_err)

		return false
	}

	fmt.println("Project configuration loaded.")


	// ------------------------------------------------------------------------
	// Parse JSON
	// ------------------------------------------------------------------------

	settings := Project_Settings{}

	unmarshal_err := json.unmarshal(data, &settings)

	if unmarshal_err != nil {
		log.error("Failed to parse project configuration: %v", unmarshal_err)

		return false
	}


	// ------------------------------------------------------------------------
	// Store project settings globally
	// ------------------------------------------------------------------------

	GLOBAL_PROJECT_SETTINGS = settings

	fmt.printf("Project Settings Loaded: %s (v%s)\n", settings.project_name, settings.version)


	// ------------------------------------------------------------------------
	// Renderer
	// ------------------------------------------------------------------------

	if settings.renderer_dll != "" {
		fmt.println("")
		fmt.println("Loading renderer module...")

		loaded_renderer, renderer_ok := load_module(settings.renderer_dll)

		if !renderer_ok {
			log.error("Failed to load renderer module: %s", settings.renderer_dll)

			return false
		}

		GLOBAL_RENDERER = loaded_renderer

		fmt.println("Renderer DLL loaded.")

		if GLOBAL_RENDERER.init != nil {
			renderer_init_ok := GLOBAL_RENDERER.init()

			if !renderer_init_ok {
				log.error("Renderer module initialization failed")

				return false
			}

			log.info("Renderer module initialized successfully")
		}
	}


	// ------------------------------------------------------------------------
	// Input
	// ------------------------------------------------------------------------

	if settings.input_dll != "" {
		fmt.println("")
		fmt.println("Loading input module...")

		loaded_input, input_ok := load_module(settings.input_dll)

		if !input_ok {
			log.error("Failed to load input module: %s", settings.input_dll)

			return false
		}

		GLOBAL_INPUT = loaded_input

		if GLOBAL_INPUT.init != nil {
			input_init_ok := GLOBAL_INPUT.init()

			if !input_init_ok {
				log.error("Input module initialization failed")

				return false
			}

			fmt.println("Input module initialized successfully.")
		}
	}


	// ------------------------------------------------------------------------
	// ECS
	// ------------------------------------------------------------------------

	if settings.ecs_dll != "" {
		fmt.println("")
		fmt.println("Loading ECS module...")

		loaded_ecs, ecs_ok := load_module(settings.ecs_dll)

		if !ecs_ok {
			log.error("Failed to load ECS module: %s", settings.ecs_dll)

			return false
		}

		GLOBAL_ECS = loaded_ecs

		if GLOBAL_ECS.init != nil {
			ecs_init_ok := GLOBAL_ECS.init()

			if !ecs_init_ok {
				log.error("ECS module initialization failed")

				return false
			}

			fmt.println("ECS module initialized successfully.")
		}
	}


	// ------------------------------------------------------------------------
	// Audio
	// ------------------------------------------------------------------------

	if settings.audio_dll != "" {
		fmt.println("")
		fmt.println("Loading audio module...")

		loaded_audio, audio_ok := load_module(settings.audio_dll)

		if !audio_ok {
			log.error("Failed to load audio module: %s", settings.audio_dll)

			return false
		}

		GLOBAL_AUDIO = loaded_audio

		if GLOBAL_AUDIO.init != nil {
			audio_init_ok := GLOBAL_AUDIO.init()

			if !audio_init_ok {
				log.error("Audio module initialization failed")

				return false
			}

			fmt.println("Audio module initialized successfully.")
		}
	}


	// ------------------------------------------------------------------------
	// Physics
	// ------------------------------------------------------------------------

	if settings.physics_dll != "" {
		fmt.println("")
		fmt.println("Loading physics module...")

		loaded_physics, physics_ok := load_module(settings.physics_dll)

		if !physics_ok {
			log.error("Failed to load physics module: %s", settings.physics_dll)

			return false
		}

		GLOBAL_PHYSICS = loaded_physics

		if GLOBAL_PHYSICS.init != nil {
			physics_init_ok := GLOBAL_PHYSICS.init()

			if !physics_init_ok {
				log.error("Physics module initialization failed")

				return false
			}

			fmt.println("Physics module initialized successfully.")
		}
	}


	// ------------------------------------------------------------------------
	// UI
	// ------------------------------------------------------------------------

	if settings.ui_dll != "" {
		fmt.println("")
		fmt.println("Loading UI module...")

		loaded_ui, ui_ok := load_module(settings.ui_dll)

		if !ui_ok {
			log.error("Failed to load UI module: %s", settings.ui_dll)

			return false
		}

		GLOBAL_UI = loaded_ui

		if GLOBAL_UI.init != nil {
			ui_init_ok := GLOBAL_UI.init()

			if !ui_init_ok {
				log.error("UI module initialization failed")

				return false
			}

			fmt.println("UI module initialized successfully.")
		}
	}


	// ------------------------------------------------------------------------
	// Editor
	//
	// The editor is ONLY loaded in editor mode.
	// ------------------------------------------------------------------------

	if RUN_EDITOR {
		fmt.println("")
		fmt.println("Editor mode enabled")

		if settings.editor_dll != "" {
			fmt.println("Loading editor module...")

			loaded_editor, editor_ok := load_module(settings.editor_dll)

			if !editor_ok {
				log.error("Failed to load editor module: %s", settings.editor_dll)

				return false
			}

			GLOBAL_EDITOR = loaded_editor

			if GLOBAL_EDITOR.init != nil {
				editor_init_ok := GLOBAL_EDITOR.init()

				if !editor_init_ok {
					log.error("Editor module initialization failed")

					return false
				}

				fmt.println("Editor module initialized successfully.")
			}
		}
	}


	// ------------------------------------------------------------------------
	// Finished
	// ------------------------------------------------------------------------

	fmt.println("")
	fmt.println("Engine.init() completed successfully.")
	fmt.println("Returning from Engine.init()...")

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

	// ------------------------------------------------------------------------
	// Editor
	// ------------------------------------------------------------------------

	if GLOBAL_EDITOR.library != nil {
		if GLOBAL_EDITOR.destroy != nil {
			GLOBAL_EDITOR.destroy()
		}

		unload_module(&GLOBAL_EDITOR)
	}


	// ------------------------------------------------------------------------
	// UI
	// ------------------------------------------------------------------------

	if GLOBAL_UI.library != nil {
		if GLOBAL_UI.destroy != nil {
			GLOBAL_UI.destroy()
		}

		unload_module(&GLOBAL_UI)
	}


	// ------------------------------------------------------------------------
	// Physics
	// ------------------------------------------------------------------------

	if GLOBAL_PHYSICS.library != nil {
		if GLOBAL_PHYSICS.destroy != nil {
			GLOBAL_PHYSICS.destroy()
		}

		unload_module(&GLOBAL_PHYSICS)
	}


	// ------------------------------------------------------------------------
	// Audio
	// ------------------------------------------------------------------------

	if GLOBAL_AUDIO.library != nil {
		if GLOBAL_AUDIO.destroy != nil {
			GLOBAL_AUDIO.destroy()
		}

		unload_module(&GLOBAL_AUDIO)
	}


	// ------------------------------------------------------------------------
	// ECS
	// ------------------------------------------------------------------------

	if GLOBAL_ECS.library != nil {
		if GLOBAL_ECS.destroy != nil {
			GLOBAL_ECS.destroy()
		}

		unload_module(&GLOBAL_ECS)
	}


	// ------------------------------------------------------------------------
	// Input
	// ------------------------------------------------------------------------

	if GLOBAL_INPUT.library != nil {
		if GLOBAL_INPUT.destroy != nil {
			GLOBAL_INPUT.destroy()
		}

		unload_module(&GLOBAL_INPUT)
	}


	// ------------------------------------------------------------------------
	// Renderer
	// ------------------------------------------------------------------------

	if GLOBAL_RENDERER.library != nil {
		if GLOBAL_RENDERER.destroy != nil {
			GLOBAL_RENDERER.destroy()
		}

		unload_module(&GLOBAL_RENDERER)
	}


	// ------------------------------------------------------------------------
	// Application callback
	// ------------------------------------------------------------------------

	APPRUNHANDLE = nil


	// ------------------------------------------------------------------------
	// Logger
	// ------------------------------------------------------------------------

	log.destroy_console_logger(context.logger)

	fmt.println("ENGINE DESTROY EXITED")

	return true
}