// module_interface.odin
package Core

import "core:dynlib"
import "core:log"

// Standard module entry points that every .dll must export
Module_Load    :: proc() -> bool
Module_Unload :: proc()
Module_Update  :: proc(dt: f32)
Module_Render  :: proc() // Optional, for renderers   

// A generic loaded module container
Loaded_Module :: struct {
    library:    dynlib.Library,
    init:       Module_Load,
    destroy:    Module_Unload,
    update:     Module_Update,
    render:     Module_Render, // May be nil for non-renderers
}

// Load a module from a DLL filename
load_module :: proc(dll_name: string) -> (Loaded_Module, bool) {
    mod : Loaded_Module
    ok : bool

    // 1. Load the dynamic library
    // Assumes DLLs are in the same directory as the executable
    mod.library, ok = dynlib.load_library(dll_name)
    if !ok {
        log.error("Failed to load library '%s': %s\n", dll_name, dynlib.last_error())
        return mod, false
    }

    // 2. Resolve symbols (function exports)
    // We look for standard names like "module_load", "module_update", etc.
    
    // Resolve 'module_load'
    if init_ptr, found := dynlib.symbol_address(mod.library, "module_load"); found {
        mod.init = cast(Module_Load)(init_ptr)
    } else {
        log.error("Module '%s' missing required export: module_load\n", dll_name)
        dynlib.unload_library(mod.library)
        return mod, false
    }

    // Resolve 'module_destroy' (Optional but recommended)
    if dest_ptr, found := dynlib.symbol_address(mod.library, "module_destroy"); found {
        mod.destroy = cast(Module_Unload)(dest_ptr)
    }

    // Resolve 'module_update'
    if upd_ptr, found := dynlib.symbol_address(mod.library, "module_update"); found {
        mod.update = cast(Module_Update)(upd_ptr)
    }

    // Resolve 'module_render' (Optional)
    if rend_ptr, found := dynlib.symbol_address(mod.library, "module_render"); found {
        mod.render = cast(Module_Render)(rend_ptr)
    }

    return mod, true
}

unload_module :: proc(mod: ^Loaded_Module) {
    if mod.library != nil {
        dynlib.unload_library(mod.library)
        mod.library = nil
    }
}   