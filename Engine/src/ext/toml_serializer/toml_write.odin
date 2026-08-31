// Engine/src/ext/toml/toml_write.odin
//
// Deterministic TOML writer for the supported subset.
//
// IDEMPOTENCY:
//   Same Document + same Writer settings => byte-identical output.
//   Caller controls declaration order via document_init / doc_add_*.
//
// EMITTED FORM:
//   Top-level entries: scalar / array / inline-table, in declaration order.
//   Section [[name]] headers, then their entries in declaration order.
//   One blank line between [[a]] groups (none between rows inside one
//   group). Single trailing newline at EOF.

package toml_serializer

import "core:fmt"
import "core:io"
import "core:strings"

Writer :: struct {
    w:           io.Writer,
    indent_step: int,
    indent:      int,
    at_bol:      bool,
}

// ------------------------------------------------------------------------
// Lifecycle
// ------------------------------------------------------------------------

writer_init :: proc(w: io.Writer, indent_step := 4) -> Writer {
    return {w = w, indent_step = indent_step, indent = 0, at_bol = true}
}

// ------------------------------------------------------------------------
// High-level: Document -> string
// ------------------------------------------------------------------------

@(require_results)
writer_to_string :: proc(d: ^Document) -> string {
    buf: strings.Builder
    strings.builder_init(&buf)
    w := writer_init(strings.to_writer(&buf))
    _ = write_document(&w, d)
    return strings.to_string(buf)
}

// ------------------------------------------------------------------------
// Document construction helpers
// ------------------------------------------------------------------------

doc_add_string :: proc(d: ^Document, key, value: string) {
    append(&d.entries, Key_Value{key = key, value = value})
}

doc_add_int :: proc(d: ^Document, key: string, value: int) {
    append(&d.entries, Key_Value{key = key, value = value})
}

doc_add_bool :: proc(d: ^Document, key: string, value: bool) {
    append(&d.entries, Key_Value{key = key, value = value})
}

doc_add_string_array :: proc(d: ^Document, key: string, values: []string) {
    a: Array
    array_init(&a)
    for v in values do append(&a, Value(v))
    append(&d.entries, Key_Value{key = key, value = a})
}

// doc_add_inline_table calls `populate` to fill the inline table.
//
// Example:
//
//     toml.doc_add_inline_table(&doc, "version", proc(it: ^toml.Inline_Table) {
//         toml.it_add_int(it, "major", 0)
//         toml.it_add_int(it, "minor", 1)
//         toml.it_add_int(it, "patch", 0)
//     })

doc_add_inline_table :: proc(
	d: ^Document, key: string,
	populate: proc(it: ^Inline_Table),
) {
	it: Inline_Table
	inline_table_init(&it)
	populate(&it)
	append(&d.entries, Key_Value{key = key, value = it})
}

// it_add_inline_table appends a nested inline table (key = nested_table)
// to an existing Inline_Table. Mirrors doc_add_inline_table for nested use.
it_add_inline_table :: proc(
	it: ^Inline_Table, key: string,
	populate: proc(inner: ^Inline_Table),
) {
	inner: Inline_Table
	inline_table_init(&inner)
	populate(&inner)
	append(it, Key_Value{key = key, value = inner})
}

doc_add_array_of_tables :: proc(
    d: ^Document, name: string,
    populate: proc(t: ^Inline_Table, index: int),
    count: int,
) {
    if count <= 0 do return
    aot: Array_Of_Tables
    array_of_tables_init(&aot, name)
    for i in 0 ..< count {
        t: Inline_Table
        inline_table_init(&t)
        populate(&t, i)
        append(&aot.tables, t)
    }
    append(&d.arrays_of_tables, aot)
}

// ------------------------------------------------------------------------
// Inline-table helpers
// ------------------------------------------------------------------------

it_add_string :: proc(it: ^Inline_Table, key, value: string) {
    append(it, Key_Value{key = key, value = value})
}

it_add_int :: proc(it: ^Inline_Table, key: string, value: int) {
    append(it, Key_Value{key = key, value = value})
}

it_add_bool :: proc(it: ^Inline_Table, key: string, value: bool) {
    append(it, Key_Value{key = key, value = value})
}

it_add_string_array :: proc(it: ^Inline_Table, key: string, values: []string) {
    a: Array
    array_init(&a)
    for v in values do append(&a, Value(v))
    append(it, Key_Value{key = key, value = a})
}

// ------------------------------------------------------------------------
// Write Document
// ------------------------------------------------------------------------

write_document :: proc(w: ^Writer, d: ^Document) -> io.Error {
    if err := write_top_entries(w, d); err != nil do return err

    if len(d.arrays_of_tables) > 0 {
        if len(d.entries) > 0 {
            if err := _write_blank_line(w); err != nil do return err
        }
        for &aot, idx in d.arrays_of_tables {
            if idx > 0 {
                if err := _write_blank_line(w); err != nil do return err
            }
            if err := write_array_of_tables(w, &aot); err != nil do return err
        }
    }

    return _write_byte(w, '\n')
}

@(private)
_write_blank_line :: proc(w: ^Writer) -> io.Error {
    if !w.at_bol {
        if err := _io_write_byte(w, '\n'); err != nil do return err
        w.at_bol = true
    }
    return _io_write_byte(w, '\n')
}

@(private)
write_top_entries :: proc(w: ^Writer, d: ^Document) -> io.Error {
    for &kv, i in d.entries {
        if i > 0 {
            if err := _write_newline(w); err != nil do return err
        }
        write_kv(w, &kv)
    }
    return nil
}

@(private)
write_array_of_tables :: proc(w: ^Writer, aot: ^Array_Of_Tables) -> io.Error {
    for &t, i in aot.tables {
        if i > 0 {
            if err := _write_newline(w); err != nil do return err
        }
        if err := _write_aot_header(w, aot.name); err != nil do return err
        for &kv, j in t {
            if j > 0 {
                if err := _write_newline(w); err != nil do return err
            }
            write_kv(w, &kv)
        }
    }
    return nil
}

@(private)
write_kv :: proc(w: ^Writer, kv: ^Key_Value) {
    _emit(w, kv.key)
    _emit(w, " = ")
    _write_value(w, kv.value)
}

@(private)
_write_value :: proc(w: ^Writer, v: Value) {
    // Direct case-dispatch on the anonymous Value union trips a spurious
    // exhaustiveness error in this Odin version when the union is
    // self-referential (Array -> Value -> Array). Use type-assert helpers
    // instead — equivalent runtime cost, no false-positive diagnostics.
    if is_value_string(v) {
        s, _ := v.(string)
        _emit(w, "\"")
        _write_escaped(w, s)
        _emit(w, "\"")
        return
    }
    if i, ok := v.(int); ok {
        _emit(w, fmt.tprintf("%d", i))
        return
    }
    if b, ok := v.(bool); ok {
        _emit(w, b ? "true" : "false")
        return
    }
    if it, ok := v.(Inline_Table); ok {
        _write_inline_table(w, &it)
        return
    }
    if a, ok := v.(Array); ok {
        _write_array(w, &a)
        return
    }
}

@(private)
_write_inline_table :: proc(w: ^Writer, it: ^Inline_Table) {
    _emit(w, "{ ")
    for &kv, i in it {
        if i > 0 do _emit(w, ", ")
        _emit(w, kv.key)
        _emit(w, " = ")
        _write_value(w, kv.value)
    }
    _emit(w, " }")
}

@(private)
_write_array :: proc(w: ^Writer, a: ^Array) {
    _emit(w, "[")
    for &v, i in a {
        if i > 0 do _emit(w, ", ")
        _write_value(w, v)
    }
    _emit(w, "]")
}

@(private)
_write_aot_header :: proc(w: ^Writer, name: string) -> io.Error {
    _emit(w, "[[")
    _emit(w, name)
    _emit(w, "]]")
    return _write_newline(w)
}

// ------------------------------------------------------------------------
// Primitive emitters
// ------------------------------------------------------------------------

@(private)
_emit :: proc(w: ^Writer, s: string) {
    if len(s) == 0 do return
    _flush_indent(w)
    _, _ = io.write_string(w.w, s)
}

@(private)
_flush_indent :: proc(w: ^Writer) {
    if !w.at_bol do return
    total := w.indent * w.indent_step
    if total > 0 {
        buf := make([]byte, total)
        defer delete(buf)
        for i in 0 ..< total do buf[i] = ' '
        _, _ = io.write(w.w, buf)
    }
    w.at_bol = false
}

@(private)
_write_newline :: proc(w: ^Writer) -> io.Error {
    _flush_indent(w)
    err := _io_write_byte(w, '\n')
    w.at_bol = true
    return err
}

@(private)
_write_byte :: proc(w: ^Writer, b: byte) -> io.Error {
    _flush_indent(w)
    return _io_write_byte(w, b)
}

@(private)
_write_escaped :: proc(w: ^Writer, s: string) {
    for r in s {
        switch r {
        case '\\': _emit(w, `\\`)
        case '"':  _emit(w, `\"`)
        case '\n': _emit(w, `\n`)
        case '\r': _emit(w, `\r`)
        case '\t': _emit(w, `\t`)
        case:
            // UTF-8 encode any other rune; for the Bifrost manifest schema
            // this only fires on non-ASCII descriptions/names.
            for b in _utf8_encode_bytes(r) {
                _ = io.write_byte(w.w, b)
            }
        }
    }
}

// ------------------------------------------------------------------------
// io.Writer glue
// ------------------------------------------------------------------------

@(private)
_io_write_byte :: proc(w: ^Writer, b: byte) -> io.Error {
    return io.write_byte(w.w, b)
}

// Minimal UTF-8 encoder.
@(private)
_utf8_encode_bytes :: proc(r: rune) -> []byte {
    buf: [4]byte
    n := 0
    switch {
    case r < 0x80:
        buf[0] = byte(r)
        n = 1
    case r < 0x800:
        buf[0] = 0xC0 | byte(r >> 6)
        buf[1] = 0x80 | byte(r & 0x3F)
        n = 2
    case r < 0x10000:
        buf[0] = 0xE0 | byte(r >> 12)
        buf[1] = 0x80 | byte((r >> 6) & 0x3F)
        buf[2] = 0x80 | byte(r & 0x3F)
        n = 3
    case:
        buf[0] = 0xF0 | byte(r >> 18)
        buf[1] = 0x80 | byte((r >> 12) & 0x3F)
        buf[2] = 0x80 | byte((r >> 6) & 0x3F)
        buf[3] = 0x80 | byte(r & 0x3F)
        n = 4
    }
    out := make([]byte, n)
    copy(out, buf[:n])
    return out
}
