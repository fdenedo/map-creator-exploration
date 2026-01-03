package main

import "base:runtime"
import "core:log"

import "app"
import "platform"
import "ui"
import "viewport"

default_context: runtime.Context
app_instance: app.Application
render_state: platform.RenderState

main :: proc() {
    context.logger = log.create_console_logger()
    default_context = context

    config := platform.WindowConfig {
        title = "08 Projection-Aware Editor",
        width = 1200,
        height = 800,
    }

    app.app_init(&app_instance)

    platform.window_run(
        config,
        {
            init = init,
            frame = frame,
            cleanup = cleanup,
            event = event,
        },
        &default_context)
}

init :: proc "c" () {
    context = default_context

    platform.window_setup(&default_context)
    platform.render_init(&render_state)
    viewport.render_init(&app_instance.viewport)
}

frame :: proc "c" () {
    context = default_context

    app_update(&app_instance)
    app_render(&app_instance)
}

cleanup :: proc "c" () {
    context = default_context

    platform.window_shutdown()
}

event :: proc "c" (e: ^platform.Event) {
    context = default_context

}

app_update :: proc(app: ^app.Application) {
	ui.ui_update(&app_instance.ui)
	viewport.viewport_update(&app_instance.viewport)
}

app_render :: proc(app: ^app.Application) {
	platform.render_begin_frame(&render_state)

    viewport.render(&app_instance.viewport, &app_instance.document)
    ui.ui_render(&app_instance.ui)

    platform.render_end_frame(&render_state)
}
