package main

// import "core:log"

SAMPLES_CURVED   :: 30
SAMPLES_STRAIGHT ::  5
TRIANGLE_SAMPLES ::  2

Point :: struct {
    id:         int,
    handle_in:  WorldVec2,
    pos:        WorldVec2,
    handle_out: WorldVec2,
}

Line :: struct {
    id: int,
    start, end: Point
}

Polygon :: struct {
    lines: [dynamic]Line,
    closed: bool,
}

ControlPoint_Quad :: struct {
    pos: [2]f32,
    tex: [2]f32,
}

CurveGeometry :: struct {
    curve_points: [SAMPLES_CURVED + 1]WorldVec2,
    curve_point_count: int,

    triangle_wireframe_lines: [12][2]f32,
    triangle_vert_count: int,

    handle_lines: [dynamic]WorldVec2,
    handle_vert_count: int,

    control_points_lb_quad: [4]ControlPoint_Quad,
    control_points_handle_temp: [dynamic]WorldVec2,
}

generate_curve_loop_blinn_quad :: proc(control_points: [3][2]f32, camera: Camera, out:^CurveGeometry) {
    context = default_context

    uv0 := [2]f32{ 0.0, 0.0 }
    uv1 := [2]f32{ 0.5, 0.0 }
    uv2 := [2]f32{ 1.0, 1.0 }

    out.control_points_lb_quad[0] = { pos = control_points[0], tex = uv0 }
    out.control_points_lb_quad[1] = { pos = control_points[1], tex = uv1 }
    out.control_points_lb_quad[2] = { pos = control_points[2], tex = uv2 }
}

generate_curve_loop_blinn_cubic :: proc(control_points: [4][2]f32, camera: Camera, out:^CurveGeometry)
where len(control_points) == 4 {
    context = default_context

    // TODO: Not implemented yet
}

generate_curve_geometry :: proc(control_points: []Point, camera: Camera, out: ^CurveGeometry) {
    context = default_context

    // For a naive go at the billboard strategy, for each point I can draw a pair of (instanced) triangles
    // and then I can use shader arithmetic to draw whatever shape I want the points to be in the fragment
    // shader
    // Means I'll pass the control points into the handle buffer, and not generate new geometry
    clear(&out.control_points_handle_temp)
    for point in control_points {
        append(&out.control_points_handle_temp, point.pos)
    }
}
