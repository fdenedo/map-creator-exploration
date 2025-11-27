package main

// import "core:log"

SAMPLES_CURVED   :: 30
SAMPLES_STRAIGHT ::  5
TRIANGLE_SAMPLES ::  2

ControlPoint_Quad :: struct {
    pos: [2]f32,
    tex: [2]f32,
}

CurveGeometry :: struct {
    curve_points: [SAMPLES_CURVED + 1]WorldVec2,
    curve_point_count: int,

    triangle_wireframe_lines: [12][2]f32,
    triangle_vert_count: int,

    handle_lines: [16]WorldVec2,
    handle_vert_count: int,

    // Loop-Blinn Data
    control_points_lb_quad: [4]ControlPoint_Quad
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

generate_curve_geometry :: proc(control_points: []WorldVec2, camera: Camera, out: ^CurveGeometry) {
    context = default_context

    if len(control_points) == 3 {
        samples := SAMPLES_CURVED
        t_delta := 1.0 / f32(samples)
        for i in 0..=samples {
            out.curve_points[i] = WorldVec2(evaluate_bezier_quadratic(
                cast([2]f32) control_points[0],
                cast([2]f32) control_points[1],
                cast([2]f32) control_points[2],
                0 + t_delta * f32(i)
            ))
        }
        out.curve_point_count = samples + 1

        triangulated := Triangle {
            cast([2]f32) control_points[0],
            cast([2]f32) control_points[1],
            cast([2]f32) control_points[2],
        }
        lines := triangle_to_lines(triangulated)
        for j in 0..<6 {
            out.triangle_wireframe_lines[j] = lines[j]
        }
        out.triangle_vert_count = 6
    }
    else
    if len(control_points) == 4 {
        samples := is_flat_enough(
            ([2]f32)(control_points[0]),
            ([2]f32)(control_points[1]),
            ([2]f32)(control_points[2]),
            ([2]f32)(control_points[3]),
            0.1
        ) ? SAMPLES_STRAIGHT : SAMPLES_CURVED

        t_delta := 1.0 / f32(samples)
        for i in 0..=samples {
            out.curve_points[i] = WorldVec2(evaluate_bezier_cubic(
                cast([2]f32) control_points[0],
                cast([2]f32) control_points[1],
                cast([2]f32) control_points[2],
                cast([2]f32) control_points[3],
                0 + t_delta * f32(i)
            ))
        }
        out.curve_point_count = samples + 1

        // For cubics, one line will be duplicated and could be stored once, could just
        // hard-code this
        triangulated := triangulate_quad(
            cast([2]f32)(control_points[0]),
            cast([2]f32)(control_points[1]),
            cast([2]f32)(control_points[2]),
            cast([2]f32)(control_points[3]),
        )
        for i in 0..<len(triangulated) {
            lines := triangle_to_lines(triangulated[i])
            for j in 0..<6 {
                out.triangle_wireframe_lines[i*6 + j] = lines[j]
            }
        }
        out.triangle_vert_count = 12
    }

    // Add this calculation to the shader so we don't have to pass in the camera
    // Matches more closely to what we'll eventually do with the billboard strategy
    // Shouldn't need to pass the camera here
    for point, i in control_points {
        out.handle_lines[i*4 + 0] = WorldVec2(point + screen_to_world({ 3,  3}, camera, false))
        out.handle_lines[i*4 + 1] = WorldVec2(point - screen_to_world({ 3,  3}, camera, false))
        out.handle_lines[i*4 + 2] = WorldVec2(point + screen_to_world({-3,  3}, camera, false))
        out.handle_lines[i*4 + 3] = WorldVec2(point + screen_to_world({ 3, -3}, camera, false))
    }
    out.handle_vert_count = len(control_points) * 4
}
