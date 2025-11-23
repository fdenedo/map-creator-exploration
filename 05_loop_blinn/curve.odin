package main

import "core:log"

SAMPLES_CURVED   :: 30
SAMPLES_STRAIGHT ::  5
TRIANGLE_SAMPLES ::  2

CurveGeometry :: struct {
    curve_points: [SAMPLES_CURVED + 1]WorldVec2,
    curve_point_count: int,

    triangle_wireframe_lines: [12][2]f32,

    handle_lines: [16]WorldVec2
}

generate_curve_geometry :: proc(control_points: [4]WorldVec2, camera: Camera, out: ^CurveGeometry) {
    context = default_context

    log.debug("Generating curve geometry")
    out.curve_point_count = is_flat_enough(
        ([2]f32)(control_points[0]),
        ([2]f32)(control_points[1]),
        ([2]f32)(control_points[2]),
        ([2]f32)(control_points[3]),
        0.1
    ) ? SAMPLES_STRAIGHT : SAMPLES_CURVED

    t_delta := 1.0 / f32(out.curve_point_count)
    for i in 0..=out.curve_point_count {
        out.curve_points[i] = WorldVec2(evaluate_bezier_cubic(
            cast([2]f32) control_points[0],
            cast([2]f32) control_points[1],
            cast([2]f32) control_points[2],
            cast([2]f32) control_points[3],
            0 + t_delta * f32(i)
        ))
    }

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

    // Add this calculation to the shader so we don't have to pass in the camera
    // Matches more closely to what we'll eventually do with the billboard strategy
    // Shouldn't need to pass the camera here
    for point, i in control_points {
        out.handle_lines[i*4 + 0] = WorldVec2(point + screen_to_world({ 3,  3}, camera, false))
        out.handle_lines[i*4 + 1] = WorldVec2(point - screen_to_world({ 3,  3}, camera, false))
        out.handle_lines[i*4 + 2] = WorldVec2(point + screen_to_world({-3,  3}, camera, false))
        out.handle_lines[i*4 + 3] = WorldVec2(point + screen_to_world({ 3, -3}, camera, false))
    }
    log.debug("Curve geometry rendered")
}
