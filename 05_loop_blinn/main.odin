package main

import "core:c"
import "core:log"
import "core:math/linalg"
import "base:runtime"
import sapp "shared:sokol/app"
import sg "shared:sokol/gfx"
import shelpers "shared:sokol/helpers"

SAMPLES_CURVED   :: 30
SAMPLES_STRAIGHT :: 2
TRIANGLE_SAMPLES :: 16

ScreenVec2  :: distinct [2]f32
WorldVec2   :: distinct [2]f32
Matrix4     :: matrix[4, 4]f32

ControlPoint :: struct {
    pos: WorldVec2,
}

state: struct {
    editor: EditorState,

    pass_action: sg.Pass_Action,
    shader: sg.Shader,
    curve_pipeline, handle_pipeline, triangle_pipeline: sg.Pipeline,
    curve_v_buffer, handle_buffer, triangle_buffer: sg.Buffer,
    vertices: [SAMPLES_CURVED + 1][2]f32,
    handle_data: [16][2]f32,
    triangle_data: [TRIANGLE_SAMPLES]Triangle,
    num_samples: int,
}

default_context: runtime.Context

// Begin organisation
// Need editor - handles state and events
// render - handles rendering, gets raw data

main :: proc() {
    context.logger = log.create_console_logger()
    default_context = context

    sapp.run({
        window_title = "05 Loop-Blinn",
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

    state.pass_action = {
        colors = { 0 = { load_action = .CLEAR, clear_value = { 1, 1, 1, 1 } } },
    }

    state.shader = sg.make_shader(main_shader_desc(sg.query_backend()))

    state.curve_pipeline = sg.make_pipeline({
        shader = state.shader,
        primitive_type = .LINE_STRIP,
        layout = {
            attrs = {
                ATTR_main_position = { format = .FLOAT2 }
            }
        },
    })

    state.num_samples = is_flat_enough(
        ([2]f32)(state.editor.control_points[0].pos),
        ([2]f32)(state.editor.control_points[1].pos),
        ([2]f32)(state.editor.control_points[2].pos),
        ([2]f32)(state.editor.control_points[3].pos),
        0.1
    ) ? SAMPLES_STRAIGHT : SAMPLES_CURVED

    t_delta := 1.0 / f32(state.num_samples)
    for i in 0..=state.num_samples {
        state.vertices[i] = evaluate_bezier_cubic(
            cast([2]f32) state.editor.control_points[0].pos,
            cast([2]f32) state.editor.control_points[1].pos,
            cast([2]f32) state.editor.control_points[2].pos,
            cast([2]f32) state.editor.control_points[3].pos,
            0 + t_delta * f32(i)
        )
    }

    state.curve_v_buffer = sg.make_buffer({
        data = {
            ptr = &state.vertices,
            size = c.size_t((state.num_samples + 1) * size_of([2]f32))
        },
        usage = { dynamic_update = true } // sokol won't let us call update_buffer() without this
    })

    state.handle_pipeline = sg.make_pipeline({
        shader = state.shader,
        primitive_type = .LINES,
        layout = {
            attrs = {
                ATTR_main_position = { format = .FLOAT2 },
            }
        },
    })

    for point, i in state.editor.control_points {
        state.handle_data[i*4 + 0] = cast([2]f32)(state.editor.control_points[i].pos + screen_to_world({ 3,  3}, state.editor.camera, false))
        state.handle_data[i*4 + 1] = cast([2]f32)(state.editor.control_points[i].pos - screen_to_world({ 3,  3}, state.editor.camera, false))
        state.handle_data[i*4 + 2] = cast([2]f32)(state.editor.control_points[i].pos + screen_to_world({-3,  3}, state.editor.camera, false))
        state.handle_data[i*4 + 3] = cast([2]f32)(state.editor.control_points[i].pos + screen_to_world({ 3, -3}, state.editor.camera, false))
    }

    state.handle_buffer = sg.make_buffer({
        data = {
            ptr = &state.handle_data,
            size = c.size_t(len(state.handle_data) * size_of([2]f32))
        },
        usage = { dynamic_update = true }
    })

    state.triangle_pipeline = sg.make_pipeline({
        shader = state.shader,
        primitive_type = .TRIANGLES,
        layout = {
            attrs = {
                ATTR_main_position = { format = .FLOAT2 },
            }
        },
    })

    state.triangle_data = triangulate_bezier(
        cast([2]f32)(state.editor.control_points[0].pos),
        cast([2]f32)(state.editor.control_points[1].pos),
        cast([2]f32)(state.editor.control_points[2].pos),
        cast([2]f32)(state.editor.control_points[3].pos),
        TRIANGLE_SAMPLES
    )

    state.triangle_buffer = sg.make_buffer({
        data = {
            ptr = &state.triangle_data,
            size = c.size_t(len(state.triangle_data) * size_of(Triangle))
        },
        usage = { dynamic_update = true }
    })
}

frame :: proc "c" () {
    context = default_context
    state.editor.camera.aspect_ratio = sapp.widthf() / sapp.heightf() // TODO: Calculated on init now, probably listen to window resize event

    sg.begin_pass({
        action = state.pass_action,
        swapchain = shelpers.glue_swapchain()
    })

    camera_mat := camera_matrix(state.editor.camera)
    uniforms := Vs_Params {
	    u_camera_matrix = transmute([16]f32)camera_mat,
	}

    sg.apply_pipeline(state.curve_pipeline)
    sg.apply_bindings({ vertex_buffers = { 0 = state.curve_v_buffer } })
    sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })
	sg.draw(0, state.num_samples + 1, 1)

	sg.apply_pipeline(state.handle_pipeline)
	sg.apply_bindings({ vertex_buffers = { 0 = state.handle_buffer } })
	sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })
	sg.draw(0, len(state.handle_data), 1)

	sg.apply_pipeline(state.triangle_pipeline)
	sg.apply_bindings({ vertex_buffers = { 0 = state.triangle_buffer } })
	sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })
	sg.draw(0, len(state.triangle_data) * 3, 1)

	sg.end_pass()
    sg.commit()
}

cleanup :: proc "c" () {
    context = default_context
    sg.shutdown()
}

event :: proc "c" (e: ^sapp.Event) {
    context = default_context
    editor_handle_event(&state.editor, e)
}

update_render :: proc() {
    state.num_samples = is_flat_enough(
        ([2]f32)(state.editor.control_points[0].pos),
        ([2]f32)(state.editor.control_points[1].pos),
        ([2]f32)(state.editor.control_points[2].pos),
        ([2]f32)(state.editor.control_points[3].pos),
        0.1
    ) ? SAMPLES_STRAIGHT : SAMPLES_CURVED

    t_delta := 1.0 / f32(state.num_samples)
    for i in 0..=state.num_samples {
        state.vertices[i] = evaluate_bezier_cubic(
            cast([2]f32) state.editor.control_points[0].pos,
            cast([2]f32) state.editor.control_points[1].pos,
            cast([2]f32) state.editor.control_points[2].pos,
            cast([2]f32) state.editor.control_points[3].pos,
            0 + t_delta * f32(i)
        )
    }

    sg.update_buffer(state.curve_v_buffer, {
        ptr = &state.vertices,
        size = c.size_t((state.num_samples + 1) * size_of([2]f32))
    })

    for point, i in state.editor.control_points {
        state.handle_data[i*4 + 0] = cast([2]f32)(state.editor.control_points[i].pos + screen_to_world({ 3,  3}, state.editor.camera, false))
        state.handle_data[i*4 + 1] = cast([2]f32)(state.editor.control_points[i].pos - screen_to_world({ 3,  3}, state.editor.camera, false))
        state.handle_data[i*4 + 2] = cast([2]f32)(state.editor.control_points[i].pos + screen_to_world({-3,  3}, state.editor.camera, false))
        state.handle_data[i*4 + 3] = cast([2]f32)(state.editor.control_points[i].pos + screen_to_world({ 3, -3}, state.editor.camera, false))
    }

    sg.update_buffer(state.handle_buffer, {
        ptr = &state.handle_data,
        size = c.size_t(len(state.handle_data) * size_of([2]f32))
    })

    state.triangle_data = triangulate_bezier(
        cast([2]f32)(state.editor.control_points[0].pos),
        cast([2]f32)(state.editor.control_points[1].pos),
        cast([2]f32)(state.editor.control_points[2].pos),
        cast([2]f32)(state.editor.control_points[3].pos),
        TRIANGLE_SAMPLES
    )

    sg.update_buffer(state.triangle_buffer, {
        ptr = &state.triangle_data,
        size = c.size_t(len(state.triangle_data) * size_of(Triangle))
    })
}
