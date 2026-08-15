package Core

import "core:dynlib"

Plugin_Init_Proc    :: proc() -> bool
Plugin_Destroy_Proc :: proc()
Plugin_Update_Proc  :: proc(dt: f32)

// A generic loaded plugin container
Loaded_Plugin :: struct {
    library:    dynlib.Library,
    init:       Plugin_Init_Proc,
    destroy:    Plugin_Destroy_Proc,
    update:     Plugin_Update_Proc,
}

