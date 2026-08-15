package Bifrost

import "core:log"

@export // Required for the host to find this function
module_load :: proc() -> bool {
    log.info("Renderer module loaded")
    return true
}
@export
module_unload  :: proc() {
    log.info("Renderer module unloaded")
}
@export
module_update :: proc(dt: f32) {
    // Update logic
}
@export
module_render :: proc() { 
}