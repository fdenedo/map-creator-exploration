package main

import "core:c"
import sapp "shared:sokol/app"
import sg "shared:sokol/gfx"
import shelpers "shared:sokol/helpers"

// ============================================================================
// PointRenderer - renders billboarded circles at world positions
// ============================================================================

PointRenderer :: struct {
    pipeline: sg.Pipeline,
    buffer_quad: sg.Buffer,
    ibuffer: sg.Buffer,
    count: int,
}

point_renderer_init :: proc(r: ^PointRenderer, shader: sg.Shader) {
    r.pipeline = sg.make_pipeline({
        shader = shader,
        primitive_type = .TRIANGLE_STRIP,
        colors = {
            0 = {
                blend = {
                    enabled = true,
                    src_factor_rgb = .SRC_ALPHA,
                    dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
                    src_factor_alpha = .ONE,
                    dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
                }
            }
        },
        layout = {
            attrs = {
                ATTR_handle_position = { format = .FLOAT2, buffer_index = 0, offset = 0 },
                ATTR_handle_uv = { format = .FLOAT2, buffer_index = 0, offset = 8 },
                ATTR_handle_instance_pos = { format = .FLOAT2, buffer_index = 1 },
            },
            buffers = {
                1 = { step_func = .PER_INSTANCE },
            }
        },
    })

    vertices := [?]f32 {
        -1.0, -1.0,  -1.0, -1.0,
         1.0, -1.0,   1.0, -1.0,
        -1.0,  1.0,  -1.0,  1.0,
         1.0,  1.0,   1.0,  1.0,
    }

    r.buffer_quad = sg.make_buffer({
        data = { ptr = &vertices, size = size_of(vertices) }
    })

    r.ibuffer = sg.make_buffer({
        size = c.size_t(1024 * size_of(WorldVec2)),
        usage = { dynamic_update = true }
    })
}

point_renderer_update :: proc(r: ^PointRenderer, points: []WorldVec2) {
    r.count = len(points)
    if r.count > 0 {
        sg.update_buffer(r.ibuffer, {
            ptr = raw_data(points),
            size = c.size_t(r.count * size_of(WorldVec2))
        })
    }
}

point_renderer_draw :: proc(r: ^PointRenderer, uniforms: ^Vs_Params, point_size: f32, color: [4]f32 = {0.75, 0.75, 1.0, 1.0}) {
    if r.count == 0 do return

    sg.apply_pipeline(r.pipeline)
    sg.apply_bindings({ vertex_buffers = { 0 = r.buffer_quad, 1 = r.ibuffer } })
    uniforms.u_point_size = point_size
    sg.apply_uniforms(UB_vs_params, { ptr = uniforms, size = size_of(Vs_Params) })

    fs_uniforms := Fs_Params { u_color = color }
    sg.apply_uniforms(UB_fs_params, { ptr = &fs_uniforms, size = size_of(Fs_Params) })

    sg.draw(0, 4, r.count)
}

// ============================================================================
// LineRenderer - renders antialiased lines between world positions
// ============================================================================

LineRenderer :: struct {
    pipeline: sg.Pipeline,
    buffer_quad: sg.Buffer,
    ibuffer: sg.Buffer,
    count: int,
}

line_renderer_init :: proc(r: ^LineRenderer, shader: sg.Shader) {
    r.pipeline = sg.make_pipeline({
        shader = shader,
        primitive_type = .TRIANGLE_STRIP,
        colors = {
            0 = {
                blend = {
                    enabled = true,
                    src_factor_rgb = .SRC_ALPHA,
                    dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
                    src_factor_alpha = .ONE,
                    dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
                }
            }
        },
        layout = {
            attrs = {
                ATTR_line_position = { format = .FLOAT2, buffer_index = 0 },
                ATTR_line_line_start = { format = .FLOAT2, buffer_index = 1, offset = 0 },
                ATTR_line_line_end = { format = .FLOAT2, buffer_index = 1, offset = 8 },
            },
            buffers = {
                1 = { step_func = .PER_INSTANCE, stride = 16 },
            }
        },
    })

    line_quad := [?]f32 {
        0.0, -1.0,
        1.0, -1.0,
        0.0,  1.0,
        1.0,  1.0,
    }

    r.buffer_quad = sg.make_buffer({
        data = { ptr = &line_quad, size = size_of(line_quad) }
    })

    r.ibuffer = sg.make_buffer({
        size = c.size_t(2048 * size_of(WorldVec2)),
        usage = { dynamic_update = true }
    })
}

line_renderer_update :: proc(r: ^LineRenderer, line_points: []WorldVec2) {
    r.count = len(line_points) / 2
    if r.count > 0 {
        sg.update_buffer(r.ibuffer, {
            ptr = raw_data(line_points),
            size = c.size_t(len(line_points) * size_of(WorldVec2))
        })
    }
}

line_renderer_draw :: proc(r: ^LineRenderer, uniforms: ^Vs_Params, line_width: f32) {
    if r.count == 0 do return

    sg.apply_pipeline(r.pipeline)
    sg.apply_bindings({ vertex_buffers = { 0 = r.buffer_quad, 1 = r.ibuffer } })
    uniforms.u_point_size = line_width
    sg.apply_uniforms(UB_vs_params, { ptr = uniforms, size = size_of(Vs_Params) })
    sg.draw(0, 4, r.count)
}

// ============================================================================
// RenderState - orchestrates all renderers
// ============================================================================

RenderState :: struct {
    pass_action: sg.Pass_Action,
    shader_point: sg.Shader,
    shader_line: sg.Shader,

    curve_lines: LineRenderer,
    handle_lines: LineRenderer,
    handles: PointRenderer,
    anchors: PointRenderer,

    // Single-point renderer for hovered/selected states
    special_point: PointRenderer,
}

render_init :: proc(r: ^RenderState) {
    context = default_context

    r.pass_action = {
        colors = { 0 = { load_action = .CLEAR, clear_value = { 1, 1, 1, 1 } } },
    }

    r.shader_point = sg.make_shader(handle_shader_desc(sg.query_backend()))
    r.shader_line = sg.make_shader(line_shader_desc(sg.query_backend()))

    line_renderer_init(&r.curve_lines, r.shader_line)
    line_renderer_init(&r.handle_lines, r.shader_line)
    point_renderer_init(&r.handles, r.shader_point)
    point_renderer_init(&r.anchors, r.shader_point)
    point_renderer_init(&r.special_point, r.shader_point)
}

render_update_geometry :: proc(r: ^RenderState, handle_geo: ^HandleGeometry, path_geo: ^PathGeometry) {
    context = default_context

    line_renderer_update(&r.curve_lines, path_geo.curve_lines[:][:])
    line_renderer_update(&r.handle_lines, handle_geo.lines[:])
    point_renderer_update(&r.handles, handle_geo.handle_points[:])
    point_renderer_update(&r.anchors, handle_geo.anchor_points[:])
}

render_frame :: proc(r: ^RenderState, camera: Camera, hovered_point: Maybe(SpecialPoint), selected_point: Maybe(SpecialPoint)) {
    context = default_context

    sg.begin_pass({
        action = r.pass_action,
        swapchain = shelpers.glue_swapchain()
    })

    uniforms := Vs_Params {
        u_camera_matrix = transmute([16]f32) camera_matrix(camera),
        u_viewport_size = { sapp.widthf(), sapp.heightf() },
    }

    HOVER_SCALE        :: 1.4
    SELECTED_DOT_SCALE :: 0.4
    WHITE              :: [4]f32{ 1.0, 1.0, 1.0, 1.0 }

    line_renderer_draw(&r.curve_lines, &uniforms, 1.0)
    line_renderer_draw(&r.handle_lines, &uniforms, 1.0)
    point_renderer_draw(&r.handles, &uniforms, HANDLE_SIZE)
    point_renderer_draw(&r.anchors, &uniforms, ANCHOR_SIZE)

    // Draw hovered point (enlarged)
    if sp, ok := hovered_point.?; ok {
        point_renderer_update(&r.special_point, { sp.pos })
        point_renderer_draw(&r.special_point, &uniforms, sp.size * HOVER_SCALE)
    }

    // Draw selected point (white centre dot)
    if sp, ok := selected_point.?; ok {
        point_renderer_update(&r.special_point, { sp.pos })
        point_renderer_draw(&r.special_point, &uniforms, sp.size * SELECTED_DOT_SCALE, WHITE)
    }

    sg.end_pass()
    sg.commit()
}
