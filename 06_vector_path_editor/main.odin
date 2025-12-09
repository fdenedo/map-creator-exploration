package main

import "core:log"
import "base:runtime"
import sapp "shared:sokol/app"
import sg "shared:sokol/gfx"
import shelpers "shared:sokol/helpers"

ScreenVec2  :: distinct [2]f32
WorldVec2   :: distinct [2]f32
Matrix4     :: matrix[4, 4]f32

state: struct {
    editor: EditorState,
    render: RenderState,
    handle_geo: HandleGeometry,
    path_geo: PathGeometry,
}

default_context: runtime.Context

main :: proc() {
    context.logger = log.create_console_logger()
    default_context = context

    sapp.run({
        window_title = "06 Vector Path Editor",
        width = 800,
        height = 600,
        init_cb = init,
        frame_cb = frame,
        cleanup_cb = cleanup,
        event_cb = event,
        allocator = sapp.Allocator(shelpers.allocator(&default_context)),
        logger = sapp.Logger(shelpers.logger(&default_context)),
    })
}

init :: proc "c" () {
    context = default_context

    sg.setup({
        environment = shelpers.glue_environment(),
        allocator = sg.Allocator(shelpers.allocator(&default_context)),
        logger = sg.Logger(shelpers.logger(&default_context)),
    })

    editor_init(&state.editor)
    render_init(&state.render)
}

frame :: proc "c" () {
    context = default_context
    if (state.editor.should_rerender) {
        generate_handle_geometry(state.editor.control_points[:], &state.handle_geo)
        generate_path_geometry(state.editor.control_points[:], &state.path_geo)
        render_update_geometry(&state.render, &state.handle_geo, &state.path_geo)
        state.editor.should_rerender = false
    }
    render_frame(&state.render, state.editor.camera)
}

cleanup :: proc "c" () {
    context = default_context
    sg.shutdown()
}

event :: proc "c" (e: ^sapp.Event) {
    context = default_context
    editor_handle_event(&state.editor, e)
}
