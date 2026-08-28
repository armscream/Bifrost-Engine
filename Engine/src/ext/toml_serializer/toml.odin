// Engine/src/ext/toml/toml.odin
//
// Package facade for Bifrost's TOML subset.
//
// The split across toml_types / toml_write / toml_read / manifest keeps
// each file focused on one concern but they all share package `toml`.
// Importing "toml" via this directory gives the caller everything.
package toml_serializer
