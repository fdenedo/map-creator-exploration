package platform

import "base:runtime"
import "core:strings"
import sapp "shared:sokol/app"
import sg "shared:sokol/gfx"
import shelpers "shared:sokol/helpers"

WindowConfig :: struct {
    title: string,
    width, height: int,
}

WindowCallbacks :: struct {
    init:    proc "c" (),
    frame:   proc "c" (),
    cleanup: proc "c" (),
    event:   proc "c" (^Event),
}

window_setup :: proc(ctx: ^runtime.Context) {
    sg.setup({
        environment = shelpers.glue_environment(),
        allocator = sg.Allocator(shelpers.allocator(ctx)),
        logger = sg.Logger(shelpers.logger(ctx)),
    })
}

window_shutdown :: proc() {
    sg.shutdown()
}

window_run :: proc(config: WindowConfig, callbacks: WindowCallbacks, ctx: ^runtime.Context) {
    sapp.run({
        window_title = strings.clone_to_cstring(config.title),
        width = i32(config.width),
        height = i32(config.height),
        init_cb = callbacks.init,
        frame_cb = callbacks.frame,
        cleanup_cb = callbacks.cleanup,
        event_cb = callbacks.event,
        allocator = sapp.Allocator(shelpers.allocator(ctx)),
        logger = sapp.Logger(shelpers.logger(ctx)),
    })
}

width :: proc() -> f32 {
    return sapp.widthf()
}

height :: proc() -> f32 {
    return sapp.heightf()
}
