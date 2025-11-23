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
}

render_init :: proc(r: ^RenderState) {
    context = default_context

    log.debug("Initialising renderer")
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
        size = c.size_t(12 * size_of(Triangle)),
        usage = { dynamic_update = true }
    })

    log.debug("Finished renderer")
}

render_update_geometry :: proc(r: ^RenderState, geo: ^CurveGeometry) {
    context = default_context

    log.debug("Updating render geometry")
    r.curve_samples = geo.curve_point_count
    r.handle_vert_count = len(geo.handle_lines)
    r.triangle_count = len(geo.triangle_wireframe_lines)

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
    log.debug("Renderer geo updated")
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

    sg.apply_pipeline(r.curve_pipeline)
    sg.apply_bindings({ vertex_buffers = { 0 = r.curve_buffer } })
    sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })
	sg.draw(0, r.curve_samples, 1)

	sg.apply_pipeline(r.handle_pipeline)
	sg.apply_bindings({ vertex_buffers = { 0 = r.handle_buffer } })
	sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })
	sg.draw(0, r.handle_vert_count, 1)

	sg.apply_pipeline(r.triangle_pipeline)
	sg.apply_bindings({ vertex_buffers = { 0 = r.triangle_buffer } })
	sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })
	sg.draw(0, r.triangle_count * 3, 1)

	sg.end_pass()
    sg.commit()
}
