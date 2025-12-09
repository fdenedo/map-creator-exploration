package main

import "core:c"
// import "core:log"
import sapp "shared:sokol/app"
import sg "shared:sokol/gfx"
import shelpers "shared:sokol/helpers"

RenderState :: struct {
    pass_action: sg.Pass_Action,
    shader_handle, shader_line: sg.Shader,
    pipeline_handle, pipeline_line: sg.Pipeline,
    buffer_handle, buffer_line_quad: sg.Buffer,

    ibuffer_handle, ibuffer_anchor, ibuffer_lines: sg.Buffer,
    handle_count, anchor_count, line_count: int,
}

render_init :: proc(r: ^RenderState) {
    context = default_context

    r.pass_action = {
        colors = { 0 = { load_action = .CLEAR, clear_value = { 1, 1, 1, 1 } } },
    }

    r.shader_handle = sg.make_shader(handle_shader_desc(sg.query_backend()))
    r.shader_line = sg.make_shader(line_shader_desc(sg.query_backend()))

    r.pipeline_handle = sg.make_pipeline({
        shader = r.shader_handle,
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

    r.pipeline_line = sg.make_pipeline({
        shader = r.shader_line,
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

    // Quad vertices for billboards with UVs (position.xy, uv.xy)
    // UVs go from -1 to 1, centered at origin for easy SDF calculations
    vertices := [?]f32 {
        -1.0, -1.0,  -1.0, -1.0,
         1.0, -1.0,   1.0, -1.0,
        -1.0,  1.0,  -1.0,  1.0,
         1.0,  1.0,   1.0,  1.0,
    }

    r.buffer_handle = sg.make_buffer({
        data = { ptr = &vertices, size = size_of(vertices) }
    })

    line_quad := [?]f32 {
        0.0, -1.0,
        1.0, -1.0,
        0.0,  1.0,
        1.0,  1.0,
    }

    r.buffer_line_quad = sg.make_buffer({
        data = { ptr = &line_quad, size = size_of(line_quad) }
    })

    r.ibuffer_handle = sg.make_buffer({
        size = c.size_t(1024 * size_of(WorldVec2)),
        usage = { dynamic_update = true }
    })

    r.ibuffer_anchor = sg.make_buffer({
        size = c.size_t(1024 * size_of(WorldVec2)),
        usage = { dynamic_update = true }
    })

    r.ibuffer_lines = sg.make_buffer({
        size = c.size_t(2048 * size_of(WorldVec2)),
        usage = { dynamic_update = true }
    })
}

render_update_geometry :: proc(r: ^RenderState, geo: ^CurveGeometry) {
    context = default_context

    r.anchor_count = len(geo.anchor_points)
    r.handle_count = len(geo.handle_points)
    r.line_count = len(geo.handle_lines) / 2

    sg.update_buffer(r.ibuffer_handle, {
        ptr = raw_data(geo.handle_points),
        size = c.size_t(r.handle_count * size_of(WorldVec2))
    })

    sg.update_buffer(r.ibuffer_anchor, {
        ptr = raw_data(geo.anchor_points),
        size = c.size_t(r.anchor_count * size_of(WorldVec2))
    })

    sg.update_buffer(r.ibuffer_lines, {
        ptr = raw_data(geo.handle_lines),
        size = c.size_t(len(geo.handle_lines) * size_of(WorldVec2))
    })
}

render_frame :: proc(r: ^RenderState, camera: Camera) {
    context = default_context

    sg.begin_pass({
        action = r.pass_action,
        swapchain = shelpers.glue_swapchain()
    })

    uniforms := Vs_Params {
        u_camera_matrix = transmute([16]f32) camera_matrix(camera),
        u_viewport_size = { sapp.widthf(), sapp.heightf() },
    }

    sg.apply_pipeline(r.pipeline_line)
    sg.apply_bindings({ vertex_buffers = { 0 = r.buffer_line_quad, 1 = r.ibuffer_lines } })
    uniforms.u_point_size = 1.0
    sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })
    sg.draw(0, 4, r.line_count)

    sg.apply_pipeline(r.pipeline_handle)
    sg.apply_bindings({ vertex_buffers = { 0 = r.buffer_handle, 1 = r.ibuffer_handle } })
    uniforms.u_point_size = 3.0
    sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })
    sg.draw(0, 4, r.handle_count)

    sg.apply_bindings({ vertex_buffers = { 0 = r.buffer_handle, 1 = r.ibuffer_anchor } })
    uniforms.u_point_size = 6.0
    sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })
    sg.draw(0, 4, r.anchor_count)

    sg.end_pass()
    sg.commit()
}
