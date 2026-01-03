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
last_time: u64 = 0

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

    platform.time_setup()
    platform.window_setup(&default_context)
    platform.render_init(&render_state)
    viewport.render_init(&app_instance.viewport)
}

frame :: proc "c" () {
    context = default_context

    delta_time := platform.time_delta_since(last_time)
    last_time += delta_time
    app_update(&app_instance, delta_time)
    app_render(&app_instance)
}

cleanup :: proc "c" () {
    context = default_context

    platform.window_shutdown()
}

event :: proc "c" (e: ^platform.Event) {
    context = default_context

}

app_update :: proc(app: ^app.Application, dt: u64) {
	ui.ui_update(&app_instance.ui)
	viewport.viewport_update(&app_instance.viewport, dt)
}

app_render :: proc(app: ^app.Application) {
	platform.render_begin_frame(&render_state)

    viewport.render(&app_instance.viewport, &app_instance.document)
    ui.ui_render(&app_instance.ui)

    platform.render_end_frame(&render_state)
}
