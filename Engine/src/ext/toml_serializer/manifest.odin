// Engine/src/ext/toml/manifest.odin
//
// Domain model for a Bifrost module/extension/plugin manifest, the writer
// that emits the on-disk TOML, and a thin reader that delegates to the
// vendored Up05/toml_parser (Engine/src/ext/toml_parser).
//
// Bifrost manifest schema:
//
//   name        = "Bifrost_Renderer"
//   type        = "Module"        # "Module" | "Extension" | "Plugin"
//   version     = { major = 0, minor = 1, patch = 0 }
//   author      = "..."           # optional
//   description = "..."           # optional
//
//   flags        = ["Runtime", "Editor_Only"]    # subset of Module_Flag names
//   capabilities = ["Renderer", "GPU", ...]      # subset of Module_Capability names
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
// Lib type enum
// ------------------------------------------------------------------------

Lib_Type :: enum int {
    Module    = 0,
    Extension = 1,
    Plugin    = 2,
}

lib_type_to_string :: proc(t: Lib_Type) -> string {
    switch t {
    case .Module:    return "Module"
    case .Extension: return "Extension"
    case .Plugin:    return "Plugin"
    }
    return "Module"
}

lib_type_from_string :: proc(s: string) -> Lib_Type {
    switch s {
    case "Module":    return .Module
    case "Extension": return .Extension
    case "Plugin":    return .Plugin
    }
    return .Module
}

// ------------------------------------------------------------------------
// Domain types
// ------------------------------------------------------------------------

Module_Manifest :: struct {
    name:         string,
    type:         Lib_Type,
    version:      MVersion,
    author:       string,
    description:  string,
    flags:        [dynamic]string,
    capabilities: [dynamic]string,
    dependencies: [dynamic]Dependency,
    targets:      [dynamic]Target,
}

MVersion :: struct {
    major: int,
    minor: int,
    patch: int,
}

Dependency :: struct {
    name:           string,
    min_version:    MVersion,
    max_version:    MVersion,
    has_min_version: bool,
    has_max_version: bool,
    optional:        bool,
}

Target :: struct {
    module:         string,
    min_version:    MVersion,
    max_version:    MVersion,
    has_min_version: bool,
    has_max_version: bool,
}

// ------------------------------------------------------------------------
// Lifecycle
// ------------------------------------------------------------------------

manifest_init :: proc(m: ^Module_Manifest) {
    m^ = {}
    m.flags        = make([dynamic]string)
    m.capabilities = make([dynamic]string)
    m.dependencies = make([dynamic]Dependency)
    m.targets      = make([dynamic]Target)
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

    doc_add_string(&d, "name", m.name)
    doc_add_string(&d, "type", lib_type_to_string(m.type))

    // version
    {
        it: Inline_Table
        inline_table_init(&it)
        it_add_int(&it, "major", m.version.major)
        it_add_int(&it, "minor", m.version.minor)
        it_add_int(&it, "patch", m.version.patch)
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

// Helper for inline-table version fields.
@(private)
it_add_inline_version :: proc(it: ^Inline_Table, key: string, v: ^MVersion) {
    append(it, Key_Value{key = key, value = _version_inline_table(v)})
}

@(private)
_version_inline_table :: proc(v: ^MVersion) -> Value {
    inner: Inline_Table
    inline_table_init(&inner)
    it_add_int(&inner, "major", v.major)
    it_add_int(&inner, "minor", v.minor)
    it_add_int(&inner, "patch", v.patch)
    return Value(inner)
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

    // name
    if v, ok := up05_toml.get(string, table, "name"); ok {
        m.name = v
    }

    // type
    if v, ok := up05_toml.get(string, table, "type"); ok {
        m.type = lib_type_from_string(v)
    }

    // version
    if vt, ok := up05_toml.get(^up05_toml.Table, table, "version"); ok && vt != nil {
        if major, m_ok := up05_toml.get(i64, vt, "major"); m_ok {
            m.version.major = int(major)
        }
        if minor, m_ok := up05_toml.get(i64, vt, "minor"); m_ok {
            m.version.minor = int(minor)
        }
        if patch, m_ok := up05_toml.get(i64, vt, "patch"); m_ok {
            m.version.patch = int(patch)
        }
    }

    // author / description
    if v, ok := up05_toml.get(string, table, "author"); ok do m.author = v
    if v, ok := up05_toml.get(string, table, "description"); ok do m.description = v

    // flags (array of strings)
    if lst, ok := up05_toml.get(^up05_toml.List, table, "flags"); ok && lst != nil {
        for item in lst {
            if s, sok := item.(string); sok do append(&m.flags, s)
        }
    }

    // capabilities (array of strings)
    if lst, ok := up05_toml.get(^up05_toml.List, table, "capabilities"); ok && lst != nil {
        for item in lst {
            if s, sok := item.(string); sok do append(&m.capabilities, s)
        }
    }

    // dependencies (array of tables)
    if lst, ok := up05_toml.get(^up05_toml.List, table, "dependencies"); ok && lst != nil {
        for item in lst {
            dt, tok := item.(^up05_toml.Table)
            if !tok || dt == nil do continue
            dep := _read_dependency_from_table(dt)
            append(&m.dependencies, dep)
        }
    }

    // targets (array of tables)
    if lst, ok := up05_toml.get(^up05_toml.List, table, "targets"); ok && lst != nil {
        for item in lst {
            tt, tok := item.(^up05_toml.Table)
            if !tok || tt == nil do continue
            tgt := _read_target_from_table(tt)
            append(&m.targets, tgt)
        }
    }

    return m, Parse_Error{}
}

@(private)
_read_version_from_table :: proc(t: ^up05_toml.Table) -> MVersion {
    v: MVersion
    if n, ok := up05_toml.get(i64, t, "major"); ok do v.major = int(n)
    if n, ok := up05_toml.get(i64, t, "minor"); ok do v.minor = int(n)
    if n, ok := up05_toml.get(i64, t, "patch"); ok do v.patch = int(n)
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
