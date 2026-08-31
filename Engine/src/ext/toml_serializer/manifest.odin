// Engine/src/ext/toml/manifest.odin
//
// Domain model for a Bifrost component manifest, derived from
// Engine/src/Core/Library_Interface.Lib_Descriptor.
//
// Bifrost manifest schema mirrors the Lib_Descriptor ABI exactly:
// every field present in Lib_Descriptor is present here, with cstring
// widened to Odin `string` so the manifest is friendly to TOML and to
// the rbs literal extractor.
//
// Manifest schema:
//
//   name        = "Bifrost_Renderer"
//   type        = "Module"        # "Module" | "Extension" | "Plugin"
//   version     = { major = 0, minor = 1, patch = 0 }
//   author      = "..."           # optional
//   description = "..."           # optional
//
//   flags        = ["Runtime", "Editor_Only"]
//   capabilities = ["Renderer", "GPU", ...]
//
//   [[dependencies]]
//   name            = "Default_Input"
//   min_version     = { major = 0, minor = 0, patch = 1 }
//   max_version     = { major = 0, minor = 0, patch = 0 }
//   has_min_version = true
//   has_max_version = false
//   optional        = false
//
//   [[targets]]                                 # extensions only
//   module         = "Bifrost_Renderer"
//   min_version    = { major = 0, minor = 1, patch = 0 }
//   max_version    = { major = 0, minor = 0, patch = 0 }
//   has_min_version = true
//   has_max_version = true
package toml_serializer

import "core:fmt"

import up05_toml "../toml_parser"

// ------------------------------------------------------------------------
// Local version / Component_Kind
// ------------------------------------------------------------------------
//
// We intentionally avoid importing Core here so this package can be used
// from Core itself without a cycle. The on-disk version format is a stable
// (major, minor, patch) triple; consumers that need the Core.Version type
// convert via field-by-field copy.
//
LIB_API_VERSION :: u32(1) // Must match Core.LIB_API_VERSION.

Component_Kind :: enum int {
	Module    = 0,
	Extension = 1,
	Plugin    = 2,
}

component_kind_to_string :: proc(t: Component_Kind) -> string {
	switch t {
	case .Module:    return "Module"
	case .Extension: return "Extension"
	case .Plugin:    return "Plugin"
	}
	return "Module"
}

component_kind_from_string :: proc(s: string) -> Component_Kind {
	switch s {
	case "Module":    return .Module
	case "Extension": return .Extension
	case "Plugin":    return .Plugin
	}
	return .Module
}

// ------------------------------------------------------------------------
// Domain types — mirrors of Lib_Descriptor / Lib_Dependency
// ------------------------------------------------------------------------

// Module_Manifest is the canonical component descriptor for rbs. Its fields
// mirror Lib_Descriptor's, with cstring widened to string for TOML
// friendliness and dependencies stored in a dynamic array.
//
// `lib_type_name` is the raw identifier text (e.g. "Renderer", "Input",
// "Other") for the Lib_Type sub-classification. The host resolves the
// identifier to a Core.Lib_Type enum value at load time. Storing the
// identifier string keeps the manifest format-agnostic to the exact
// ordering of Core.Lib_Type members.
Module_Manifest :: struct {
	api_version:    u32,
	component_kind: Component_Kind,
	name:           string,
	version:        Version,
	author:         string,
	description:    string,
	lib_type_name:  string,
	flags:          [dynamic]string,
	capabilities:   [dynamic]string,
	dependencies:   [dynamic]Dependency,
	dependency_count: u32,
	targets:        [dynamic]Target,
}

Version :: struct {
	major: u32,
	minor: u32,
	patch: u32,
}

Dependency :: struct {
	name:            string,
	min_version:     Version,
	max_version:     Version,
	has_min_version: bool,
	has_max_version: bool,
	optional:        bool,
}

Target :: struct {
	module:          string,
	min_version:     Version,
	max_version:     Version,
	has_min_version: bool,
	has_max_version: bool,
}

// ------------------------------------------------------------------------
// Lifecycle
// ------------------------------------------------------------------------

manifest_init :: proc(m: ^Module_Manifest) {
	m^ = {}
	m.api_version = LIB_API_VERSION
	m.flags = make([dynamic]string)
	m.capabilities = make([dynamic]string)
	m.dependencies = make([dynamic]Dependency)
	m.targets = make([dynamic]Target)
}

manifest_destroy :: proc(m: ^Module_Manifest) {
	delete(m.flags)
	delete(m.capabilities)
	delete(m.dependencies)
	delete(m.targets)
}

// ------------------------------------------------------------------------
// Write: domain -> TOML Document -> string
// ------------------------------------------------------------------------

@(require_results)
write_manifest_string :: proc(m: ^Module_Manifest) -> string {
	d := manifest_to_document(m)
	defer document_destroy(&d)
	return writer_to_string(&d)
}

manifest_to_document :: proc(m: ^Module_Manifest) -> Document {
	d: Document
	document_init(&d)

	doc_add_int(&d, "api_version", int(m.api_version))
	doc_add_string(&d, "name", m.name)
	doc_add_string(&d, "component_kind", component_kind_to_string(m.component_kind))
	if m.lib_type_name != "" {
		doc_add_string(&d, "type", m.lib_type_name)
	}

	// [version] inline table (built inline; populate callbacks can't capture).
	{
		it: Inline_Table
		inline_table_init(&it)
		it_add_int(&it, "major", int(m.version.major))
		it_add_int(&it, "minor", int(m.version.minor))
		it_add_int(&it, "patch", int(m.version.patch))
		append(&d.entries, Key_Value{key = "version", value = it})
	}

	doc_add_string(&d, "author", m.author)
	doc_add_string(&d, "description", m.description)

	if len(m.flags) > 0 {
		doc_add_string_array(&d, "flags", m.flags[:])
	}
	if len(m.capabilities) > 0 {
		doc_add_string_array(&d, "capabilities", m.capabilities[:])
	}

	doc_add_int(&d, "dependency_count", int(m.dependency_count))

	// [[dependencies]]
	if len(m.dependencies) > 0 {
		aot: Array_Of_Tables
		array_of_tables_init(&aot, "dependencies")
		for &dep in m.dependencies {
			t: Inline_Table
			inline_table_init(&t)
			it_add_string(&t, "name", dep.name)
			it_add_inline_version(&t, "min_version", &dep.min_version)
			it_add_inline_version(&t, "max_version", &dep.max_version)
			it_add_bool(&t, "has_min_version", dep.has_min_version)
			it_add_bool(&t, "has_max_version", dep.has_max_version)
			it_add_bool(&t, "optional", dep.optional)
			append(&aot.tables, t)
		}
		append(&d.arrays_of_tables, aot)
	}

	// [[targets]]
	if len(m.targets) > 0 {
		aot: Array_Of_Tables
		array_of_tables_init(&aot, "targets")
		for &tgt in m.targets {
			t: Inline_Table
			inline_table_init(&t)
			it_add_string(&t, "module", tgt.module)
			it_add_inline_version(&t, "min_version", &tgt.min_version)
			it_add_inline_version(&t, "max_version", &tgt.max_version)
			it_add_bool(&t, "has_min_version", tgt.has_min_version)
			it_add_bool(&t, "has_max_version", tgt.has_max_version)
			append(&aot.tables, t)
		}
		append(&d.arrays_of_tables, aot)
	}

	return d
}

// Helper for inline-table version fields. Built inline because Odin
// proc literals don't capture outer-scope variables, which would prevent
// callers from passing outer data into the callback.
@(private)
it_add_inline_version :: proc(it: ^Inline_Table, key: string, v: ^Version) {
	inner: Inline_Table
	inline_table_init(&inner)
	it_add_int(&inner, "major", int(v.major))
	it_add_int(&inner, "minor", int(v.minor))
	it_add_int(&inner, "patch", int(v.patch))
	append(it, Key_Value{key = key, value = inner})
}

// ------------------------------------------------------------------------
// Read: TOML file -> domain (via Up05/toml_parser)
// ------------------------------------------------------------------------

Parse_Error :: struct {
	line:    int,
	column:  int,
	message: string,
}

// parse_manifest_file loads and parses a TOML manifest file from disk.
@(require_results)
parse_manifest_file :: proc(path: string) -> (Module_Manifest, Parse_Error) {
	table, err := up05_toml.parse_file(path)
	defer {
		if table != nil {
			up05_toml.deep_delete(up05_toml.Type(table))
		}
	}
	if err.type != .None {
		return {}, Parse_Error{
			line    = err.line,
			column  = 0,
			message = fmt.tprintf("failed to parse %s: %v", path, err.type),
		}
	}
	return manifest_from_table(table)
}

// parse_manifest_data parses an in-memory TOML byte slice.
@(require_results)
parse_manifest_data :: proc(data: []u8) -> (Module_Manifest, Parse_Error) {
	table, err := up05_toml.parse_data(data)
	defer {
		if table != nil {
			up05_toml.deep_delete(up05_toml.Type(table))
		}
	}
	if err.type != .None {
		return {}, Parse_Error{
			line    = err.line,
			column  = 0,
			message = fmt.tprintf("failed to parse data: %v", err.type),
		}
	}
	return manifest_from_table(table)
}

manifest_from_table :: proc(table: ^up05_toml.Table) -> (Module_Manifest, Parse_Error) {
	m: Module_Manifest
	manifest_init(&m)

	if n, ok := up05_toml.get(i64, table, "api_version"); ok do m.api_version = u32(n)
	if v, ok := up05_toml.get(string, table, "name"); ok do m.name = v
	if v, ok := up05_toml.get(string, table, "component_kind"); ok do m.component_kind = component_kind_from_string(v)
	if v, ok := up05_toml.get(string, table, "type"); ok do m.lib_type_name = v
	if vt, ok := up05_toml.get(^up05_toml.Table, table, "version"); ok && vt != nil {
		m.version = _read_version_from_table(vt)
	}
	if v, ok := up05_toml.get(string, table, "author"); ok do m.author = v
	if v, ok := up05_toml.get(string, table, "description"); ok do m.description = v
	if n, ok := up05_toml.get(i64, table, "dependency_count"); ok do m.dependency_count = u32(n)
	if lst, ok := up05_toml.get(^up05_toml.List, table, "flags"); ok && lst != nil {
		for item in lst {
			if s, sok := item.(string); sok do append(&m.flags, s)
		}
	}
	if lst, ok := up05_toml.get(^up05_toml.List, table, "capabilities"); ok && lst != nil {
		for item in lst {
			if s, sok := item.(string); sok do append(&m.capabilities, s)
		}
	}
	if lst, ok := up05_toml.get(^up05_toml.List, table, "dependencies"); ok && lst != nil {
		for item in lst {
			dt, tok := item.(^up05_toml.Table)
			if !tok || dt == nil do continue
			append(&m.dependencies, _read_dependency_from_table(dt))
		}
	}
	if lst, ok := up05_toml.get(^up05_toml.List, table, "targets"); ok && lst != nil {
		for item in lst {
			tt, tok := item.(^up05_toml.Table)
			if !tok || tt == nil do continue
			append(&m.targets, _read_target_from_table(tt))
		}
	}
	return m, Parse_Error{}
}

@(private)
_read_version_from_table :: proc(t: ^up05_toml.Table) -> Version {
	v: Version
	if n, ok := up05_toml.get(i64, t, "major"); ok do v.major = u32(n)
	if n, ok := up05_toml.get(i64, t, "minor"); ok do v.minor = u32(n)
	if n, ok := up05_toml.get(i64, t, "patch"); ok do v.patch = u32(n)
	return v
}

@(private)
_read_dependency_from_table :: proc(t: ^up05_toml.Table) -> Dependency {
	dep: Dependency
	if s, ok := up05_toml.get(string, t, "name"); ok do dep.name = s
	if vt, ok := up05_toml.get(^up05_toml.Table, t, "min_version"); ok && vt != nil {
		dep.min_version = _read_version_from_table(vt)
	}
	if vt, ok := up05_toml.get(^up05_toml.Table, t, "max_version"); ok && vt != nil {
		dep.max_version = _read_version_from_table(vt)
	}
	if b, ok := up05_toml.get(bool, t, "has_min_version"); ok do dep.has_min_version = b
	if b, ok := up05_toml.get(bool, t, "has_max_version"); ok do dep.has_max_version = b
	if b, ok := up05_toml.get(bool, t, "optional"); ok do dep.optional = b
	return dep
}

@(private)
_read_target_from_table :: proc(t: ^up05_toml.Table) -> Target {
	tgt: Target
	if s, ok := up05_toml.get(string, t, "module"); ok do tgt.module = s
	if vt, ok := up05_toml.get(^up05_toml.Table, t, "min_version"); ok && vt != nil {
		tgt.min_version = _read_version_from_table(vt)
	}
	if vt, ok := up05_toml.get(^up05_toml.Table, t, "max_version"); ok && vt != nil {
		tgt.max_version = _read_version_from_table(vt)
	}
	if b, ok := up05_toml.get(bool, t, "has_min_version"); ok do tgt.has_min_version = b
	if b, ok := up05_toml.get(bool, t, "has_max_version"); ok do tgt.has_max_version = b
	return tgt
}