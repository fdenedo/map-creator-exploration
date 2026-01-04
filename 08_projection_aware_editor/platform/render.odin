package platform

import "core:c"
import sg "shared:sokol/gfx"
import sapp "shared:sokol/app"
import shelpers "shared:sokol/helpers"

import "shaders"
import "../core"
import "../core/tesselation"

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
    ibuffer_capacity: int,
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

    INITIAL_CAPACITY :: 50000
    r.ibuffer_capacity = INITIAL_CAPACITY
    r.ibuffer = sg.make_buffer({
        size = c.size_t(INITIAL_CAPACITY * size_of(core.WorldVec2)),
        usage = { dynamic_update = true }
    })
}

line_renderer_update :: proc(r: ^LineRenderer, line_points: []core.WorldVec2) {
    r.count = len(line_points) / 2
    if r.count == 0 do return

    // Resize buffer if needed
    if len(line_points) > r.ibuffer_capacity {
        sg.destroy_buffer(r.ibuffer)
        r.ibuffer_capacity = len(line_points) * 2 // Multiply to reduce future reallocations
        r.ibuffer = sg.make_buffer({
            size = c.size_t(r.ibuffer_capacity * size_of(core.WorldVec2)),
            usage = { dynamic_update = true }
        })
    }

    sg.update_buffer(r.ibuffer, {
        ptr = raw_data(line_points),
        size = c.size_t(len(line_points) * size_of(core.WorldVec2))
    })
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
// FillRenderer - uses stencil-and-cover to render filled polygons
// ============================================================================

// Projection types (must match shader)
ProjectionType :: enum i32 {
    Orthographic = 0,
    Equirectangular = 1,
}

FillRenderer :: struct {
    stencil_pipeline: sg.Pipeline,  // Stencil pass: write to stencil buffer only
    land_pipeline: sg.Pipeline,     // Land pass: draw fullscreen quad where stencil != 0
    ocean_pipeline: sg.Pipeline,    // Ocean pass: draw fullscreen quad where stencil == 0
    buffer: sg.Buffer,              // Dynamic buffer for polygon triangles
    buffer_capacity: int,
    vertex_count: int,
    fullscreen_quad: sg.Buffer,     // Static fullscreen quad for cover passes
}

fill_renderer_init :: proc(r: ^FillRenderer) {
    fill_shader := sg.make_shader(shaders.fill_shader_desc(sg.query_backend()))
    cover_shader := sg.make_shader(shaders.cover_shader_desc(sg.query_backend()))

    // Stencil pass pipeline:
    // - No color writes (we're just marking the stencil buffer)
    // - Stencil always passes, INVERT on write (even-odd fill rule)
    r.stencil_pipeline = sg.make_pipeline({
        shader = fill_shader,
        primitive_type = .TRIANGLES,
        colors = {
            0 = {
                write_mask = {},  // Disable all color writes
            },
        },
        stencil = {
            enabled = true,
            front = {
                compare = .ALWAYS,
                pass_op = .INVERT,
            },
            back = {
                compare = .ALWAYS,
                pass_op = .INVERT,
            },
            read_mask = 0xFF,
            write_mask = 0xFF,
            ref = 0,
        },
        layout = {
            attrs = {
                shaders.ATTR_fill_position = { format = .FLOAT2 },
            },
        },
    })

    // Land pass pipeline:
    // - Uses cover shader with projection-aware clipping
    // - Stencil test: only draw where stencil != 0
    // - Don't modify stencil (we need it for ocean pass)
    r.land_pipeline = sg.make_pipeline({
        shader = cover_shader,
        primitive_type = .TRIANGLE_STRIP,
        colors = {
            0 = {
                blend = {
                    enabled = true,
                    src_factor_rgb = .SRC_ALPHA,
                    dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
                    src_factor_alpha = .ONE,
                    dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
                },
            },
        },
        stencil = {
            enabled = true,
            front = {
                compare = .NOT_EQUAL,
                pass_op = .KEEP,
            },
            back = {
                compare = .NOT_EQUAL,
                pass_op = .KEEP,
            },
            read_mask = 0xFF,
            write_mask = 0x00,  // Don't write to stencil
            ref = 0,
        },
        layout = {
            attrs = {
                shaders.ATTR_cover_position = { format = .FLOAT2 },
            },
        },
    })

    // Ocean pass pipeline:
    // - Uses cover shader with projection-aware clipping
    // - Stencil test: only draw where stencil == 0
    r.ocean_pipeline = sg.make_pipeline({
        shader = cover_shader,
        primitive_type = .TRIANGLE_STRIP,
        colors = {
            0 = {
                blend = {
                    enabled = true,
                    src_factor_rgb = .SRC_ALPHA,
                    dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
                    src_factor_alpha = .ONE,
                    dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
                },
            },
        },
        stencil = {
            enabled = true,
            front = {
                compare = .EQUAL,
                pass_op = .KEEP,
            },
            back = {
                compare = .EQUAL,
                pass_op = .KEEP,
            },
            read_mask = 0xFF,
            write_mask = 0x00,
            ref = 0,
        },
        layout = {
            attrs = {
                shaders.ATTR_cover_position = { format = .FLOAT2 },
            },
        },
    })

    // Create dynamic buffer for polygon triangles
    INITIAL_CAPACITY :: 50000
    r.buffer_capacity = INITIAL_CAPACITY
    r.buffer = sg.make_buffer({
        size = c.size_t(INITIAL_CAPACITY * size_of(f32) * 2),
        usage = { dynamic_update = true },
    })

    // Create fullscreen quad (in clip space: -1 to 1)
    fullscreen_quad_verts := [?]f32 {
        -1.0, -1.0,
         1.0, -1.0,
        -1.0,  1.0,
         1.0,  1.0,
    }
    r.fullscreen_quad = sg.make_buffer({
        data = { ptr = &fullscreen_quad_verts, size = size_of(fullscreen_quad_verts) },
    })
}

fill_renderer_update :: proc(r: ^FillRenderer, triangles: []tesselation.Triangle) {
    r.vertex_count = len(triangles) * 3
    if r.vertex_count == 0 do return

    required_floats := r.vertex_count * 2

    if required_floats > r.buffer_capacity {
        sg.destroy_buffer(r.buffer)
        r.buffer_capacity = required_floats * 2
        r.buffer = sg.make_buffer({
            size = c.size_t(r.buffer_capacity * size_of(f32)),
            usage = { dynamic_update = true },
        })
    }

    sg.update_buffer(r.buffer, {
        ptr = raw_data(triangles),
        size = c.size_t(len(triangles) * size_of(tesselation.Triangle)),
    })
}

// Stencil pass: marks land areas in the stencil buffer
fill_renderer_draw_stencil :: proc(r: ^FillRenderer, uniforms: ^Vs_Params) {
    if r.vertex_count == 0 do return

    sg.apply_pipeline(r.stencil_pipeline)
    sg.apply_bindings({ vertex_buffers = { 0 = r.buffer } })
    sg.apply_uniforms(shaders.UB_vs_params, { ptr = uniforms, size = size_of(Vs_Params) })
    sg.draw(0, c.int(r.vertex_count), 1)
}

// Land pass: draws fullscreen quad with land color where stencil != 0
fill_renderer_draw_land :: proc(r: ^FillRenderer, uniforms: ^Vs_Params, land_color: [4]f32, projection: ProjectionType) {
    sg.apply_pipeline(r.land_pipeline)
    sg.apply_bindings({ vertex_buffers = { 0 = r.fullscreen_quad } })
    sg.apply_uniforms(shaders.UB_vs_params, { ptr = uniforms, size = size_of(Vs_Params) })

    fs_uniforms := shaders.Cover_Fs_Params {
        u_fill_color = land_color,
        u_projection_type = i32(projection),
    }
    sg.apply_uniforms(shaders.UB_cover_fs_params, { ptr = &fs_uniforms, size = size_of(shaders.Cover_Fs_Params) })

    sg.draw(0, 4, 1)
}

// Ocean pass: draws fullscreen quad with ocean color where stencil == 0
fill_renderer_draw_ocean :: proc(r: ^FillRenderer, uniforms: ^Vs_Params, ocean_color: [4]f32, projection: ProjectionType) {
    sg.apply_pipeline(r.ocean_pipeline)
    sg.apply_bindings({ vertex_buffers = { 0 = r.fullscreen_quad } })
    sg.apply_uniforms(shaders.UB_vs_params, { ptr = uniforms, size = size_of(Vs_Params) })

    fs_uniforms := shaders.Cover_Fs_Params {
        u_fill_color = ocean_color,
        u_projection_type = i32(projection),
    }
    sg.apply_uniforms(shaders.UB_cover_fs_params, { ptr = &fs_uniforms, size = size_of(shaders.Cover_Fs_Params) })

    sg.draw(0, 4, 1)
}

// ============================================================================
// RenderState - orchestrates all renderers
// ============================================================================

RenderState :: struct {
    pass_action: sg.Pass_Action,
    line_renderer: LineRenderer,
    fill_renderer: FillRenderer,
}

render_init :: proc(r: ^RenderState) {
    r.pass_action = {
        colors = { 0 = { load_action = .CLEAR, clear_value = { 0.1, 0.1, 0.15, 1.0 } } },
        stencil = { load_action = .CLEAR, clear_value = 0 },
    }

    line_renderer_init(&r.line_renderer)
    fill_renderer_init(&r.fill_renderer)
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
