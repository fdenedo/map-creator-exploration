package main

import "core:c"
import "core:log"
import sg "shared:sokol/gfx"
import shelpers "shared:sokol/helpers"

RenderState :: struct {
    pass_action: sg.Pass_Action,
    shader: sg.Shader,
    curve_pipeline, handle_pipeline, triangle_pipeline: sg.Pipeline,
    curve_buffer, handle_buffer, triangle_buffer: sg.Buffer,
    curve_samples, handle_vert_count, triangle_count: int,

    shader_lb_quad: sg.Shader,
    pipeline_lb_quad: sg.Pipeline,
    buffer_lb_quad: sg.Buffer,
}

render_init :: proc(r: ^RenderState) {
    context = default_context

    r.pass_action = {
        colors = { 0 = { load_action = .CLEAR, clear_value = { 1, 1, 1, 1 } } },
    }

    r.shader = sg.make_shader(main_shader_desc(sg.query_backend()))

    r.curve_pipeline = sg.make_pipeline({
        shader = r.shader,
        primitive_type = .LINE_STRIP,
        layout = {
            attrs = {
                ATTR_main_position = { format = .FLOAT2 }
            }
        },
    })

    r.handle_pipeline = sg.make_pipeline({
        shader = r.shader,
        primitive_type = .LINES,
        layout = {
            attrs = {
                ATTR_main_position = { format = .FLOAT2 },
            }
        },
    })

    r.triangle_pipeline = sg.make_pipeline({
        shader = r.shader,
        primitive_type = .LINES,
        layout = {
            attrs = {
                ATTR_main_position = { format = .FLOAT2 },
            }
        },
    })

    r.curve_buffer = sg.make_buffer({
        size = c.size_t((SAMPLES_CURVED + 1) * size_of(WorldVec2)),
        usage = { dynamic_update = true }
    })

    r.handle_buffer = sg.make_buffer({
        size = c.size_t(16 * size_of([2]f32)),
        usage = { dynamic_update = true }
    })

    r.triangle_buffer = sg.make_buffer({
        size = c.size_t(12 * size_of([2]f32)),
        usage = { dynamic_update = true }
    })

    // Shiny new Loop-Blinn Quadratic Shader
    r.shader_lb_quad = sg.make_shader(quad_loop_blinn_shader_desc(sg.query_backend()))

    r.pipeline_lb_quad = sg.make_pipeline({
        shader = r.shader_lb_quad,
        primitive_type = .TRIANGLES,
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
                ATTR_quad_loop_blinn_position = { format = .FLOAT2 },
                ATTR_quad_loop_blinn_uv = { format = .FLOAT2 },
            }
        },
    })

    r.buffer_lb_quad = sg.make_buffer({
        size = c.size_t(3 * size_of([4]f32)),
        usage = { dynamic_update = true }
    })
}

render_update_geometry :: proc(r: ^RenderState, geo: ^CurveGeometry) {
    context = default_context

    r.curve_samples = geo.curve_point_count
    r.handle_vert_count = geo.handle_vert_count
    r.triangle_count = geo.triangle_vert_count

    sg.update_buffer(r.curve_buffer, {
        ptr = &geo.curve_points,
        size = c.size_t(r.curve_samples * size_of(WorldVec2))
    })
    sg.update_buffer(r.handle_buffer, {
        ptr = &geo.handle_lines,
        size = c.size_t(r.handle_vert_count * size_of([2]f32))
    })
    sg.update_buffer(r.triangle_buffer, {
        ptr = &geo.triangle_wireframe_lines,
        size = c.size_t(r.triangle_count * size_of([2]f32))
    })
    sg.update_buffer(r.buffer_lb_quad, {
        ptr = &geo.control_points_lb_quad,
        size = c.size_t(3 * size_of([4]f32))
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
	}

 //    sg.apply_pipeline(r.curve_pipeline)
 //    sg.apply_bindings({ vertex_buffers = { 0 = r.curve_buffer } })
 //    sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })
	// sg.draw(0, r.curve_samples, 1)

	// sg.apply_pipeline(r.triangle_pipeline)
	// sg.apply_bindings({ vertex_buffers = { 0 = r.triangle_buffer } })
	// sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })
	// sg.draw(0, r.triangle_count, 1)

	sg.apply_pipeline(r.pipeline_lb_quad)
	sg.apply_bindings({ vertex_buffers = { 0 = r.buffer_lb_quad } })
	sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })
	sg.draw(0, 3, 1)

	sg.apply_pipeline(r.handle_pipeline)
	sg.apply_bindings({ vertex_buffers = { 0 = r.handle_buffer } })
	sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })
	sg.draw(0, r.handle_vert_count, 1)

	sg.end_pass()
    sg.commit()
}
