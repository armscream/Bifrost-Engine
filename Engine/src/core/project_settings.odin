// Engine/src/Core/project_settings.odin
package Core

import "core:fmt"
import "core:log"
import "core:os"
import "core:path/filepath"

import toml "../ext/toml_parser"
import ts   "../ext/toml_serializer"

// ============================================================================
// PROJECT SETTINGS (TOML)
//
// Project_Settings is the on-disk schema shared between the engine and rbs.
// The shape MUST stay in sync with the manifest codegen.
// ============================================================================
Project_Settings :: struct {
	project_name: string,
	version:      Version,
	modules:      [dynamic]Project_Module,
	extensions:   [dynamic]Project_Extension,
	plugins:      [dynamic]Project_Plugin,
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

// ===============================
// GLOBAL STATE
//
// Engine-owned singleton. All manager init/destroy is driven from
// engine.init / engine.destroy in engine.odin.
// ===============================
@(private)
GLOBAL_PROJECT_SETTINGS := Project_Settings{}

project_settings_get :: proc() -> ^Project_Settings {
	return &GLOBAL_PROJECT_SETTINGS
}

// ========================
// DEFAULT PROJECT SETTINGS
@(private)
inject_default_project_settings :: proc() {
	GLOBAL_PROJECT_SETTINGS.project_name = "New Project"
	GLOBAL_PROJECT_SETTINGS.version = BASEVERSION

	default_modules := []Project_Module {
		{name = "Bifrost_Renderer", version = BASEVERSION, enabled = true},
		{name = "BF_DAG",              version = BASEVERSION, enabled = true},
		{name = "BF_ECS",              version = BASEVERSION, enabled = true},
		{name = "BF_Input",    version = BASEVERSION, enabled = false},
		{name = "Miniaudio",        version = BASEVERSION, enabled = false},
		{name = "Box3D_Physics",    version = BASEVERSION, enabled = false},
		{name = "ATLAS-RMGUI",      version = BASEVERSION, enabled = false},
		{name = "BF_Scripting",        version = BASEVERSION, enabled = false},
		{name = "BF_Editor",           version = BASEVERSION, enabled = false},
		{name = "ENet",             version = BASEVERSION, enabled = false},
	}
	for m in default_modules {
		append(&GLOBAL_PROJECT_SETTINGS.modules, m)
	}

	default_extensions := []Project_Extension {
		{name = "Example Extension", version = BASEVERSION, enabled = false},
	}
	for e in default_extensions {
		append(&GLOBAL_PROJECT_SETTINGS.extensions, e)
	}

	default_plugins := []Project_Plugin {
		{name = "Example Plugin", version = BASEVERSION, enabled = false},
	}
	for p in default_plugins {
		append(&GLOBAL_PROJECT_SETTINGS.plugins, p)
	}
}

// ============================================================================
// TOML LOAD
// ============================================================================
@(private)
project_config_path :: proc(allocator := context.allocator) -> (string, bool) {
	exe_dir, err := os.get_executable_directory(allocator)
	if err != nil {
		return "", false
	}
	defer delete(exe_dir)
	path, jerr := filepath.join({exe_dir, "config", "project.toml"}, allocator)
	if jerr != nil {
		return "", false
	}
	return path, true
}

@(private)
load_project_settings_toml :: proc() -> bool {
	config_path, ok := project_config_path()
	if !ok {
		log.warn("Could not resolve project configuration path")
		return false
	}
	defer delete(config_path)

	if !os.exists(config_path) {
		log.warnf("Project configuration not found: %s", config_path)
		return false
	}

	data, read_err := os.read_entire_file(config_path, context.allocator)
	if read_err != nil {
		log.errorf("Could not read %s: %v", config_path, read_err)
		return false
	}
	defer delete(data)

	unmarshal_err := toml.unmarshal(data, &GLOBAL_PROJECT_SETTINGS)
	if unmarshal_err != .None {
		log.errorf("Could not parse %s: %v", config_path, unmarshal_err)
		return false
	}

	fmt.printfln("  Project: %s", GLOBAL_PROJECT_SETTINGS.project_name)
	fmt.printfln(
		"  Version: v%d.%d.%d",
		GLOBAL_PROJECT_SETTINGS.version.major,
		GLOBAL_PROJECT_SETTINGS.version.minor,
		GLOBAL_PROJECT_SETTINGS.version.patch,
	)
	return true
}

@(private)
cleanup_project_settings :: proc(s: ^Project_Settings) {
	if s == nil do return
	delete(s.modules)
	delete(s.extensions)
	delete(s.plugins)
	s.modules = nil
	s.extensions = nil
	s.plugins = nil
}

// ============================================
// TOML WRITE (default project.toml generation)
@(private)
setup_default_project_settings_toml :: proc() -> bool {
	exe_dir, err := os.get_executable_directory(context.allocator)
	if err != nil {
		fmt.eprintfln("Failed to get executable directory: %v", err)
		return false
	}
	defer delete(exe_dir)

	config_dir, err1 := filepath.join({exe_dir, "config"}, context.allocator)
	if err1 != nil {
		fmt.eprintfln("Failed to join config path: %v", err1)
		return false
	}
	defer delete(config_dir)

	file_path, err2 := filepath.join({config_dir, "project.toml"}, context.allocator)
	if err2 != nil {
		fmt.eprintfln("Failed to join file path: %v", err2)
		return false
	}
	defer delete(file_path)

	if !os.exists(config_dir) {
		if mkdir_err := os.make_directory_all(config_dir); mkdir_err != nil {
			fmt.eprintfln("Failed to create config directory at %s: %v", config_dir, mkdir_err)
			return false
		}
	}

	toml_text := render_project_settings_toml(GLOBAL_PROJECT_SETTINGS)
	defer delete(toml_text)

	if write_err := os.write_entire_file(file_path, transmute([]byte)toml_text); write_err != nil {
		fmt.eprintfln("Failed to write %s: %v", file_path, write_err)
		return false
	}

	fmt.printfln("Wrote default project configuration to %s", file_path)
	return true
}

// render_project_settings_toml builds the on-disk project.toml from the
// current settings. Driven entirely by Engine/src/ext/toml_serializer's
// Document API, so escaping / formatting / blank-line rules match the rest
// of the manifest pipeline.
@(private)
render_project_settings_toml :: proc(s: Project_Settings) -> string {
	doc: ts.Document
	ts.document_init(&doc)
	defer ts.document_destroy(&doc)

	// Top-level scalars.
	ts.doc_add_string(&doc, "project_name", s.project_name)

	// [version] inline table.
	{
		it: ts.Inline_Table
		ts.inline_table_init(&it)
		ts.it_add_int(&it, "major", int(s.version.major))
		ts.it_add_int(&it, "minor", int(s.version.minor))
		ts.it_add_int(&it, "patch", int(s.version.patch))
		append(&doc.entries, ts.Key_Value{key = "version", value = it})
	}

	// [[modules]]
	if len(s.modules) > 0 {
		aot: ts.Array_Of_Tables
		ts.array_of_tables_init(&aot, "modules")
		for &m in s.modules {
			t: ts.Inline_Table
			ts.inline_table_init(&t)
			ts.it_add_string(&t, "name", m.name)
			ts.it_add_bool(&t, "enabled", m.enabled)
			version_inline_into(&t, m.version)
			append(&aot.tables, t)
		}
		append(&doc.arrays_of_tables, aot)
	}

	// [[extensions]]
	if len(s.extensions) > 0 {
		aot: ts.Array_Of_Tables
		ts.array_of_tables_init(&aot, "extensions")
		for &e in s.extensions {
			t: ts.Inline_Table
			ts.inline_table_init(&t)
			ts.it_add_string(&t, "name", e.name)
			ts.it_add_bool(&t, "enabled", e.enabled)
			version_inline_into(&t, e.version)
			append(&aot.tables, t)
		}
		append(&doc.arrays_of_tables, aot)
	}

	// [[plugins]]
	if len(s.plugins) > 0 {
		aot: ts.Array_Of_Tables
		ts.array_of_tables_init(&aot, "plugins")
		for &p in s.plugins {
			t: ts.Inline_Table
			ts.inline_table_init(&t)
			ts.it_add_string(&t, "name", p.name)
			ts.it_add_bool(&t, "enabled", p.enabled)
			version_inline_into(&t, p.version)
			append(&aot.tables, t)
		}
		append(&doc.arrays_of_tables, aot)
	}

	return ts.writer_to_string(&doc)
}

// version_inline_into writes a 'version = { major = ..., minor = ..., patch = ... }'
// entry into the given inline table.
@(private)
version_inline_into :: proc(t: ^ts.Inline_Table, v: Version) {
	inner: ts.Inline_Table
	ts.inline_table_init(&inner)
	ts.it_add_int(&inner, "major", int(v.major))
	ts.it_add_int(&inner, "minor", int(v.minor))
	ts.it_add_int(&inner, "patch", int(v.patch))
	append(t, ts.Key_Value{key = "version", value = inner})
}