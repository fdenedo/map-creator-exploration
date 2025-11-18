package main

import "base:runtime"
import "core:c"
import "core:log"
import "core:math/linalg"
import sapp "shared:sokol/app"
import sg "shared:sokol/gfx"
import shelpers "shared:sokol/helpers"

default_context: runtime.Context

ScreenVec2  :: distinct [2]f32
WorldVec2   :: distinct [2]f32
Matrix4     :: matrix[4, 4]f32

Path :: struct {
    points: [dynamic]WorldVec2,
    closed: bool,
}

Camera :: struct {
    pos: WorldVec2,
    zoom: f32,
}

MAX_REASONABLE_POINTS :: 500

logged: bool = false

state: struct {
    aspect_ratio: f32,
    pass_action: sg.Pass_Action,
    shader: sg.Shader,
    path_pipeline: sg.Pipeline,
    v_buffer: sg.Buffer,
    camera: Camera,
    mouse_down_start: Maybe(ScreenVec2),
    mouse_pos_last_drag: Maybe(ScreenVec2),
    paths: [dynamic]Path,
    path_data: [dynamic]WorldVec2,
    active_path_index: Maybe(int),
}

main :: proc() {
    context.logger = log.create_console_logger()
    default_context = context

    sapp.run({
        window_title = "03 Blocky Coastlines",
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

    // Here, we can start using different pipelines to draw different features
    state.path_pipeline = sg.make_pipeline({
        shader = state.shader,
        primitive_type = .LINE_STRIP,
        layout = {
            attrs = {
                ATTR_main_position = { format = .FLOAT2 }
            }
        },
    })

    state.v_buffer = sg.make_buffer({
        size = MAX_REASONABLE_POINTS * size_of(WorldVec2),
        usage = { dynamic_update = true } // Updates when user makes edits
    })

    state.camera.zoom = 1.0
}

frame :: proc "c" () {
    context = default_context
    state.aspect_ratio = sapp.widthf() / sapp.heightf()

    sg.begin_pass({
        action = state.pass_action,
        swapchain = shelpers.glue_swapchain()
    })
    sg.apply_pipeline(state.path_pipeline)
    sg.apply_bindings({ vertex_buffers = { 0 = state.v_buffer } })

    camera_mat := camera_matrix(state.camera, state.aspect_ratio)
    uniforms := Vs_Params {
	    u_camera_matrix = transmute([16]f32)camera_mat,
	}
	sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })

	next_index: int = 0

	for path in state.paths {
	    num_elements := path.closed ? len(path.points) + 1 : len(path.points)
	    sg.draw(next_index, num_elements, 1)
		next_index += num_elements
	}

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
    case .KEY_DOWN:
        if e.key_code == .RIGHT {
            state.camera.pos.x += 0.1
        }
        if e.key_code == .LEFT {
            state.camera.pos.x -= 0.1
        }
        if e.key_code == .UP {
            state.camera.pos.y += 0.1
        }
        if e.key_code == .DOWN {
            state.camera.pos.y -= 0.1
        }
        if e.key_code == .C {
            close_active_path()
        }
    case .MOUSE_SCROLL:
        state.camera.zoom += e.scroll_y * 0.1
        state.camera.zoom = min(20.0, max(state.camera.zoom, 0.5))
    case .MOUSE_DOWN:
        if e.mouse_button != .LEFT do break
        state.mouse_down_start = ScreenVec2{ e.mouse_x, e.mouse_y }
    case .MOUSE_MOVE:
        mouse := ScreenVec2{ e.mouse_x, e.mouse_y }
        if state.mouse_pos_last_drag != nil {
            mouse_delta := mouse - state.mouse_pos_last_drag.?
            state.camera.pos -= screen_to_world(mouse_delta, false)
            state.mouse_pos_last_drag = mouse
        } else {
            if state.mouse_down_start != nil && linalg.vector_length(mouse - state.mouse_down_start.?) > 6 {
                state.mouse_down_start = nil
                state.mouse_pos_last_drag = mouse
            }
        }
    case .MOUSE_UP:
        if e.mouse_button != .LEFT do break
        if state.mouse_down_start != nil {
            add_point(ScreenVec2{ e.mouse_x, e.mouse_y })
        }
        state.mouse_down_start = nil
        state.mouse_pos_last_drag = nil
    }
}

camera_matrix :: proc(camera: Camera, aspect_ratio: f32) -> Matrix4 {
    z := camera.zoom
    a := aspect_ratio

    // Note: need to pad here as if it has a z-axis (sokol-shdc only supports mat4)
    // In any case, mat4 is necessary for 3D
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
            -(vec2.y / sapp.heightf()) * 2.0 + translation, // Invert
        }
}

// Translate determines if the vector is homogeneous, meaning that the vec2
// represents a position and needs to take the camera offset into account.
// Set it to false for deltas, directions etc.
screen_to_world :: proc(vec2: ScreenVec2, translate: bool) -> WorldVec2 {
    homogenous: f32 = translate ? 1.0 : 0.0
    ndc            := screen_pixel_to_ndc(vec2, translate)
    cam_matrix     := camera_matrix(state.camera, state.aspect_ratio)
    inverse        := linalg.matrix4_inverse(cam_matrix)

    ndc_homogeneous     := [4]f32{ndc.x, ndc.y, 0.0, homogenous}
    world_homogeneous   := inverse * ndc_homogeneous
    return WorldVec2(world_homogeneous.xy)
}

add_point :: proc(mouse_pos: ScreenVec2) {
    point_in_world := screen_to_world(mouse_pos, true)
    current_path: Path
    if state.active_path_index != nil {
        assert(state.active_path_index.? >= 0)
        assert(state.active_path_index.? < len(state.paths))

        append(&state.paths[state.active_path_index.?].points, point_in_world)
    } else {
        append(&current_path.points, point_in_world)
        append(&state.paths, current_path)
        state.active_path_index = len(state.paths) - 1
    }
    update_buffers()
}

close_active_path :: proc() {
    if state.active_path_index != nil {
        state.paths[state.active_path_index.?].closed = true
    }
    state.active_path_index = nil
    update_buffers()
}

update_buffers :: proc() {
    clear(&state.path_data)

    for path, index in state.paths {
        append(&state.path_data, ..path.points[:])
        if path.closed do append(&state.path_data, path.points[0])
    }

    sg.update_buffer(state.v_buffer, {
        ptr = raw_data(state.path_data),
        size = c.size_t(len(state.path_data) * size_of(WorldVec2))
    })
}
