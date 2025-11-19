package main

import "core:c"
import "core:log"
import "core:math/linalg"
import "base:runtime"
import sapp "shared:sokol/app"
import sg "shared:sokol/gfx"
import shelpers "shared:sokol/helpers"

SAMPLES_GUESS :: 30 // TODO: Adaptive Sampling

SIZE_HANDLE_ON_CURVE  :: 10
SIZE_HANDLE_OFF_CURVE :: 5

ScreenVec2  :: distinct [2]f32
WorldVec2   :: distinct [2]f32
Matrix4     :: matrix[4, 4]f32

Camera :: struct {
    pos: WorldVec2,
    zoom: f32,
}

ControlPoint :: struct {
    pos: WorldVec2,
    render_size: f32
}

state: struct {
    aspect_ratio: f32,
    camera: Camera,
    pass_action: sg.Pass_Action,
    shader: sg.Shader,
    curve_pipeline, handle_pipeline: sg.Pipeline,
    curve_v_buffer, handle_buffer: sg.Buffer,
    vertices: [SAMPLES_GUESS+1][2]f32,
    handle_data: [16][2]f32,
    control_points: [4]ControlPoint,
    dragging_point: Maybe(int),
    can_pick_up: bool,
}

default_context: runtime.Context

main :: proc() {
    context.logger = log.create_console_logger()
    default_context = context

    sapp.run({
        window_title = "04 Bezier Curve",
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

    state.pass_action = {
        colors = { 0 = { load_action = .CLEAR, clear_value = { 1, 1, 1, 1 } } },
    }

    state.shader = sg.make_shader(main_shader_desc(sg.query_backend()))

    state.control_points = {
        ControlPoint { pos = {-0.75, -0.25}, render_size = SIZE_HANDLE_ON_CURVE  },
        ControlPoint { pos = {-0.5,   0.25}, render_size = SIZE_HANDLE_OFF_CURVE },
        ControlPoint { pos = { 0.5,   0.25}, render_size = SIZE_HANDLE_OFF_CURVE },
        ControlPoint { pos = { 0.75, -0.25}, render_size = SIZE_HANDLE_ON_CURVE  },
    }

    state.curve_pipeline = sg.make_pipeline({
        shader = state.shader,
        primitive_type = .LINE_STRIP,
        layout = {
            attrs = {
                ATTR_main_position = { format = .FLOAT2 }
            }
        },
    })

    t_delta := 1.0 / f32(SAMPLES_GUESS)
    for i in 0..=SAMPLES_GUESS {
        state.vertices[i] = evaluate_bezier_cubic(
            cast([2]f32) state.control_points[0].pos,
            cast([2]f32) state.control_points[1].pos,
            cast([2]f32) state.control_points[2].pos,
            cast([2]f32) state.control_points[3].pos,
            0 + t_delta * f32(i)
        )
    }

    state.curve_v_buffer = sg.make_buffer({
        data = {
            ptr = &state.vertices,
            size = c.size_t(len(state.vertices) * size_of([2]f32))
        },
        usage = { dynamic_update = true }
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

    for point, i in state.control_points {
        state.handle_data[i*4 + 0] = cast([2]f32)(state.control_points[i].pos + screen_to_world({ 3,  3}, false))
        state.handle_data[i*4 + 1] = cast([2]f32)(state.control_points[i].pos - screen_to_world({ 3,  3}, false))
        state.handle_data[i*4 + 2] = cast([2]f32)(state.control_points[i].pos + screen_to_world({-3,  3}, false))
        state.handle_data[i*4 + 3] = cast([2]f32)(state.control_points[i].pos + screen_to_world({ 3, -3}, false))
    }

    state.handle_buffer = sg.make_buffer({
        data = {
            ptr = &state.handle_data,
            size = c.size_t(len(state.handle_data) * size_of([2]f32))
        },
        usage = { dynamic_update = true }
    })

    state.camera.zoom = 1.0
    state.can_pick_up = true
}

frame :: proc "c" () {
    context = default_context
    state.aspect_ratio = sapp.widthf() / sapp.heightf()

    sg.begin_pass({
        action = state.pass_action,
        swapchain = shelpers.glue_swapchain()
    })

    camera_mat := camera_matrix(state.camera, state.aspect_ratio)
    uniforms := Vs_Params {
	    u_camera_matrix = transmute([16]f32)camera_mat,
	}

    sg.apply_pipeline(state.curve_pipeline)
    sg.apply_bindings({ vertex_buffers = { 0 = state.curve_v_buffer } })
    sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })
	sg.draw(0, len(state.vertices), 1)

	sg.apply_pipeline(state.handle_pipeline)
	sg.apply_bindings({ vertex_buffers = { 0 = state.handle_buffer } })
	sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })
	sg.draw(0, len(state.handle_data), 1)

	sg.end_pass()
    sg.commit()
}

cleanup :: proc "c" () {
    context = default_context
    sg.shutdown()
}

event :: proc "c" (e: ^sapp.Event) {
    context = default_context

    #partial switch e.type {
    case .MOUSE_SCROLL:
        state.camera.zoom += e.scroll_y * 0.1
        state.camera.zoom = min(20.0, max(state.camera.zoom, 0.5))
    case .MOUSE_DOWN:
        if e.mouse_button != .LEFT do break
        if !state.can_pick_up do break

        mouse := ScreenVec2{ e.mouse_x, e.mouse_y }
        for control_point, index in state.control_points {
            if linalg.vector_length(world_to_screen(control_point.pos, true) - mouse) < 8 {
                state.dragging_point = index
            }
        }

        state.can_pick_up = false
    case .MOUSE_MOVE:
        mouse := ScreenVec2{ e.mouse_x, e.mouse_y }
        if state.dragging_point != nil {
            state.control_points[state.dragging_point.?].pos = screen_to_world(mouse, true)
        }
    case .MOUSE_UP:
        if e.mouse_button != .LEFT do break
        state.dragging_point = nil
        state.can_pick_up = true
    }

    update_render()
}

camera_matrix :: proc(camera: Camera, aspect_ratio: f32) -> Matrix4 {
    z := camera.zoom
    a := aspect_ratio

    return Matrix4{
        z,    0,    0,    -camera.pos.x * z,
        0,  a*z,    0,    -camera.pos.y * a * z,
        0,    0,    1,     0,
        0,    0,    0,     1,
    }
}

screen_pixel_to_ndc :: proc(vec2: ScreenVec2, translate: bool) -> [2]f32 {
    translation: f32 = translate ? 1.0 : 0.0
    return [2]f32{
             (vec2.x / sapp.widthf())  * 2.0 - translation,
            -(vec2.y / sapp.heightf()) * 2.0 + translation,
        }
}

ndc_to_screen_pixel :: proc(vec2: [2]f32, translate: bool) -> ScreenVec2 {
    translation: f32 = translate ? 1.0 : 0.0
    return ScreenVec2{
             ((vec2.x + translation) / 2.0) * sapp.widthf(),
            (-(vec2.y - translation) / 2.0) * sapp.heightf(),
        }
}

screen_to_world :: proc(vec2: ScreenVec2, translate: bool) -> WorldVec2 {
    homogenous: f32 = translate ? 1.0 : 0.0
    ndc            := screen_pixel_to_ndc(vec2, translate)
    cam_matrix     := camera_matrix(state.camera, state.aspect_ratio)
    inverse        := linalg.matrix4_inverse(cam_matrix)

    ndc_homogeneous     := [4]f32{ndc.x, ndc.y, 0.0, homogenous}
    world_homogeneous   := inverse * ndc_homogeneous
    return WorldVec2(world_homogeneous.xy)
}

world_to_screen :: proc(vec2: WorldVec2, translate: bool) -> ScreenVec2 {
    homogenous: f32 = translate ? 1.0 : 0.0
    cam_matrix     := camera_matrix(state.camera, state.aspect_ratio)

    world_homogenous    := [4]f32{vec2.x, vec2.y, 0.0, homogenous}
    screen_homogenous   := cam_matrix * world_homogenous
    pixel               := ndc_to_screen_pixel(screen_homogenous.xy, translate)
    return ScreenVec2(pixel)
}

lerp2d :: proc(a, b: [2]f32, t: f32) -> [2]f32 {
    return (b - a) * t + a
}

evaluate_bezier_cubic :: proc(p0, p1, p2, p3: [2]f32, t: f32) -> [2]f32 {
    a0 := lerp2d(p0, p1, t)
    a1 := lerp2d(p1, p2, t)
    a2 := lerp2d(p2, p3, t)

    b0 := lerp2d(a0, a1, t)
    b1 := lerp2d(a1, a2, t)

    return lerp2d(b0, b1, t)
}

update_render :: proc() {
    state.vertices[0] = cast([2]f32) state.control_points[0].pos
    t_delta := 1.0 / f32(SAMPLES_GUESS)
    for i in 0..=SAMPLES_GUESS {
        state.vertices[i] = evaluate_bezier_cubic(
            cast([2]f32) state.control_points[0].pos,
            cast([2]f32) state.control_points[1].pos,
            cast([2]f32) state.control_points[2].pos,
            cast([2]f32) state.control_points[3].pos,
            0 + t_delta * f32(i)
        )
    }

    // Note: for update, I still need to provide pointer and size
    sg.update_buffer(state.curve_v_buffer, {
        ptr = &state.vertices,
        size = c.size_t(len(&state.vertices) * size_of([2]f32))
    })

    for point, i in state.control_points {
        state.handle_data[i*4 + 0] = cast([2]f32)(state.control_points[i].pos + screen_to_world({ 3,  3}, false))
        state.handle_data[i*4 + 1] = cast([2]f32)(state.control_points[i].pos - screen_to_world({ 3,  3}, false))
        state.handle_data[i*4 + 2] = cast([2]f32)(state.control_points[i].pos + screen_to_world({-3,  3}, false))
        state.handle_data[i*4 + 3] = cast([2]f32)(state.control_points[i].pos + screen_to_world({ 3, -3}, false))
    }

    sg.update_buffer(state.handle_buffer, {
        ptr = &state.handle_data,
        size = c.size_t(len(state.handle_data) * size_of([2]f32))
    })
}
