// Engine/src/ext/toml/toml_types.odin
//
// Shared TOML data model used by both the writer and the reader.
//
// We support a strict subset of TOML that covers exactly what Bifrost
// manifests need:
//
//   - scalar values: strings, signed integers, booleans
//   - inline tables: { key = value, key = value }
//   - arrays of scalars or inline tables
//   - tables emitted as [[name]] sections (one Document may hold many)
//
// We intentionally do NOT support: datetimes, multiline strings,
// literal strings, heterogeneous arrays, dotted keys, dotted section names,
// or non-inline tables. Adding any of these later is a non-breaking change
// because higher layers use Module_Manifest, not Document.
package toml_serializer

// ------------------------------------------------------------------------
// Scalar value
// ------------------------------------------------------------------------

Value :: union {
    string,
    int,
    f64,
    bool,
    Inline_Table,
    Array,
}

is_value_string :: proc(v: Value) -> bool  { _, ok := v.(string);       return ok }
is_value_int    :: proc(v: Value) -> bool  { _, ok := v.(int);          return ok }
is_value_float  :: proc(v: Value) -> bool  { _, ok := v.(f64);          return ok }
is_value_bool   :: proc(v: Value) -> bool  { _, ok := v.(bool);         return ok }
is_value_inline :: proc(v: Value) -> bool  { _, ok := v.(Inline_Table); return ok }
is_value_array  :: proc(v: Value) -> bool  { _, ok := v.(Array);        return ok }

// ------------------------------------------------------------------------
// Inline table
// ------------------------------------------------------------------------

Inline_Table :: [dynamic]Key_Value

Key_Value :: struct {
    key:   string,
    value: Value,
}

// ------------------------------------------------------------------------
// Array (of Values, typed via .(T) on each element)
// ------------------------------------------------------------------------

Array :: [dynamic]Value

// ------------------------------------------------------------------------
// Top-level document
// ------------------------------------------------------------------------
//
// Top-level entries keep DECLARATION ORDER. The writer emits them in the
// order they were added. This is what makes the writer idempotent — given
// the same inputs, output is byte-identical.

Document :: struct {
    entries:         [dynamic]Key_Value,
    arrays_of_tables: [dynamic]Array_Of_Tables,
}

Array_Of_Tables :: struct {
    name:   string,
    tables: [dynamic]Inline_Table,
}

// ------------------------------------------------------------------------
// Lifecycle
// ------------------------------------------------------------------------

document_init :: proc(d: ^Document) {
    d.entries         = make([dynamic]Key_Value)
    d.arrays_of_tables = make([dynamic]Array_Of_Tables)
}

document_destroy :: proc(d: ^Document) {
    delete(d.entries)
    delete(d.arrays_of_tables)
}

inline_table_init :: proc(it: ^Inline_Table) {
    it^ = make([dynamic]Key_Value)
}

inline_table_destroy :: proc(it: ^Inline_Table) {
    delete(it^)
}

array_init :: proc(a: ^Array) {
    a^ = make([dynamic]Value)
}

array_destroy :: proc(a: ^Array) {
    delete(a^)
}

array_of_tables_init :: proc(aot: ^Array_Of_Tables, name: string) {
    aot.name = name
    aot.tables = make([dynamic]Inline_Table)
}

array_of_tables_destroy :: proc(aot: ^Array_Of_Tables) {
    for &t in aot.tables {
        inline_table_destroy(&t)
    }
    delete(aot.tables)
}
