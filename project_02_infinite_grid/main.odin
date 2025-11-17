package main

import sapp "shared:sokol/app"
import sg "shared:sokol/gfx"
import shelpers "shared:sokol/helpers"
import "base:runtime"
import "core:c"
import "core:log"
import "core:math"

default_context: runtime.Context

MAX_LINES :: (512 + 216) * 2 // Ultrawide 4K with lines at least 10px apart

Camera :: struct {
    x: f32,
    y: f32,
    zoom: f32,
}

state: struct {
    aspect_ratio: f32,
    shader: sg.Shader,
    pipeline: sg.Pipeline,
    v_buffer: sg.Buffer,
    vertices: [dynamic]f32,
    current_lines: int,
    camera: Camera,
    mouse_pos_last_drag: Maybe([2]f32),
    grid_line_world_spacing: f32,
}

main :: proc() {
    context.logger = log.create_console_logger()
    default_context = context

    sapp.run({
        window_title = "02 Infinite Grid Canvas",
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

    // state.pass_action = {
    //     colors = { 0 = { load_action = .CLEAR, clear_value = { 0, 0, 0, 1 } } },
    // }

    state.shader = sg.make_shader(main_shader_desc(sg.query_backend()))
    state.pipeline = sg.make_pipeline({
        shader = state.shader,
        primitive_type = .LINES,
        layout = {
            attrs = {
                ATTR_main_position = { format = .FLOAT2 }
            }
        },
    })

    // Create the buffer here, but don't add anything to it
    state.v_buffer = sg.make_buffer({
        size = MAX_LINES * size_of([2]f32),
        usage = { stream_update = true }
    })

    // Needs to be initialised so it isn't 0
    state.camera.zoom = 1.0
}

frame :: proc "c" () {
    context = default_context

    state.aspect_ratio = sapp.widthf() / sapp.heightf()
    defer clear(&state.vertices)

    grid_spacing := grid_spacing_world_units()
    first_position := world_lines_start(grid_spacing)
    num_vertical_lines := cast (int) math.ceil((2 / state.camera.zoom) / grid_spacing)
    num_horizontal_lines := cast (int) math.ceil(((2 / state.aspect_ratio) / state.camera.zoom) / grid_spacing)

    // Vertical Lines
    for i := 0; i < num_vertical_lines; i += 1 {
        x := first_position.x + f32(i) * grid_spacing
        append(&state.vertices,
            x, first_position.y - grid_spacing,
            x, first_position.y + grid_spacing * f32(num_horizontal_lines)
        )
    }
    // Horizontal Lines
    for i := 0; i < num_horizontal_lines; i += 1 {
        y := first_position.y + f32(i) * grid_spacing
        append(&state.vertices,
            first_position.x - grid_spacing, y,
            first_position.x + grid_spacing * f32(num_vertical_lines), y
        )
    }

    // Now we need to update the buffer per frame
    // Really we could just listen for camera changes and only update then
    // But this is trivial for the CPU in this case
    sg.update_buffer(state.v_buffer, {
        ptr = raw_data(state.vertices),
        size = c.size_t((num_vertical_lines + num_horizontal_lines) * 4 * size_of(f32))
    })

    sg.begin_pass({ swapchain = shelpers.glue_swapchain() })
    sg.apply_pipeline(state.pipeline)
    sg.apply_bindings({ vertex_buffers = { 0 = state.v_buffer }})

    camera_mat := camera_matrix(state.camera, state.aspect_ratio)
    uniforms := Vs_Params {
	    u_camera_matrix = transmute([16]f32)camera_mat,
	}
	sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })

    sg.draw(0, (num_vertical_lines + num_horizontal_lines) * 2, 1) // Remember, how many vertices to draw (not how many numbers in the array)
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
            state.camera.x += 0.1
        }
        if e.key_code == .LEFT {
            state.camera.x -= 0.1
        }
        if e.key_code == .UP {
            state.camera.y += 0.1
        }
        if e.key_code == .DOWN {
            state.camera.y -= 0.1
        }
    case .MOUSE_SCROLL:
        state.camera.zoom += e.scroll_y * 0.1
        state.camera.zoom = min(20.0, max(state.camera.zoom, 0.5))
    case .MOUSE_DOWN:
        if e.mouse_button != .LEFT do break
        state.mouse_pos_last_drag = [2]f32{ e.mouse_x, e.mouse_y }
    case .MOUSE_MOVE:
        if state.mouse_pos_last_drag != nil {
            mouse := [2]f32{ e.mouse_x, e.mouse_y }
            mouse_delta := mouse - state.mouse_pos_last_drag.?
            state.camera.x -= screen_delta_to_world_delta(mouse_delta).x
            state.camera.y += screen_delta_to_world_delta(mouse_delta).y
            state.mouse_pos_last_drag = mouse
        }
    case .MOUSE_UP:
        if e.mouse_button != .LEFT do break
        state.mouse_pos_last_drag = nil
    }
}

screen_delta_to_world_delta :: proc(screen_delta: [2]f32) -> [2]f32 {
    ndc_delta := [2]f32{
        (screen_delta.x / sapp.widthf()) * 2.0,
        (screen_delta.y / sapp.heightf()) * 2.0,
    }

    return {
        ndc_delta.x / state.camera.zoom,
        (ndc_delta.y / state.aspect_ratio) / state.camera.zoom
    }
}

screen_to_world :: proc(screen_pos: [2]f32) -> [2]f32 {
    ndc := [2]f32{
        (screen_pos.x / sapp.widthf()) * 2.0 - 1.0,
        (screen_pos.y / sapp.heightf()) * 2.0 - 1.0,
    }

    return {
        ndc.x / state.camera.zoom + state.camera.x,
        (ndc.y / state.aspect_ratio) / state.camera.zoom + state.camera.y
    }
}

MINIMUM_SCREEN_SPACING :: 10

grid_spacing_world_units :: proc() -> f32 {
    screen_width := sapp.widthf()
    world_width := 2 / state.camera.zoom

    px_per_world_unit := screen_width / world_width
    min_world_spacing := MINIMUM_SCREEN_SPACING / px_per_world_unit

    expo := math.ceil(math.log10(min_world_spacing))
    return math.pow10(expo) // Note, with this function we can only go up to 1e38 and down to 1e-45
}

world_lines_start :: proc(spacing: f32) -> [2]f32 {
    left_corner_in_world_space := screen_to_world({0, 0})
    factor := left_corner_in_world_space / spacing
    return {
        math.floor(factor.x) * spacing,
        math.floor(factor.y) * spacing
    }
}

Matrix4 :: matrix[4, 4]f32

camera_matrix :: proc(camera: Camera, aspect_ratio: f32) -> Matrix4 {
    z := camera.zoom
    a := aspect_ratio

    // Note: need to pad here as if it has a z-axis (sokol-shdc only supports mat4)
    // In any case, mat4 is necessary for 3D
    return Matrix4{
        z,    0,    0,    -camera.x * z,
        0,  a*z,    0,    -camera.y * a * z,
        0,    0,    1,     0,
        0,    0,    0,     1,
    }
}
