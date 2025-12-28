package platform

import "core:c"
import sg "shared:sokol/gfx"
import sapp "shared:sokol/app"
import shelpers "shared:sokol/helpers"

import "shaders"
import "../core"

// Re-export shader types for convenience
Vs_Params :: shaders.Vs_Params
Fs_Params :: shaders.Fs_Params

// ============================================================================
// LineRenderer - renders antialiased lines between world positions
// ============================================================================

LineRenderer :: struct {
    pipeline: sg.Pipeline,
    buffer_quad: sg.Buffer,
    ibuffer: sg.Buffer,
    count: int,
}

line_renderer_init :: proc(r: ^LineRenderer) {
    r.pipeline = sg.make_pipeline({
        shader = sg.make_shader(shaders.line_shader_desc(sg.query_backend())),
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
                shaders.ATTR_line_position = { format = .FLOAT2, buffer_index = 0 },
                shaders.ATTR_line_line_start = { format = .FLOAT2, buffer_index = 1, offset = 0 },
                shaders.ATTR_line_line_end = { format = .FLOAT2, buffer_index = 1, offset = 8 },
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
        size = c.size_t(50000 * size_of(core.WorldVec2)),
        usage = { dynamic_update = true }
    })
}

line_renderer_update :: proc(r: ^LineRenderer, line_points: []core.WorldVec2) {
    r.count = len(line_points) / 2
    if r.count > 0 {
        sg.update_buffer(r.ibuffer, {
            ptr = raw_data(line_points),
            size = c.size_t(len(line_points) * size_of(core.WorldVec2))
        })
    }
}

line_renderer_draw :: proc(r: ^LineRenderer, uniforms: ^Vs_Params, line_width: f32) {
    if r.count == 0 do return

    sg.apply_pipeline(r.pipeline)
    sg.apply_bindings({ vertex_buffers = { 0 = r.buffer_quad, 1 = r.ibuffer } })
    uniforms.u_point_size = line_width
    sg.apply_uniforms(shaders.UB_vs_params, { ptr = uniforms, size = size_of(Vs_Params) })
    sg.draw(0, 4, r.count)
}

// ============================================================================
// RenderState - orchestrates all renderers
// ============================================================================

RenderState :: struct {
    pass_action: sg.Pass_Action,
    line_renderer: LineRenderer,
}

// clear_value = { 0.1, 0.1, 0.15, 1.0 } - a dark blue I like

render_init :: proc(r: ^RenderState) {
    r.pass_action = {
        colors = { 0 = { load_action = .CLEAR, clear_value = { 1.0, 1.0, 1.0, 1.0 } } },
    }

    line_renderer_init(&r.line_renderer)
}

render_begin_frame :: proc(r: ^RenderState) {
    sg.begin_pass({
        action = r.pass_action,
        swapchain = shelpers.glue_swapchain()
    })
}

render_end_frame :: proc(r: ^RenderState) {
    sg.end_pass()
    sg.commit()
}

// Helper to create uniforms from a view-projection matrix
make_uniforms :: proc(view_proj: core.Matrix4) -> Vs_Params {
    return Vs_Params {
        u_camera_matrix = transmute([16]f32) view_proj,
        u_viewport_size = { sapp.widthf(), sapp.heightf() },
    }
}
