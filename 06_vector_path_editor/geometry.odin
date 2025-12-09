package main

Point :: struct {
    id:         int,
    handle_in:  WorldVec2,
    pos:        WorldVec2,
    handle_out: WorldVec2,
}

HandleGeometry :: struct {
    lines: [dynamic]WorldVec2,
    anchor_points: [dynamic]WorldVec2,
    handle_points: [dynamic]WorldVec2,
}

PathGeometry :: struct {
    curve_lines: [dynamic]WorldVec2,
}

generate_handle_geometry :: proc(control_points: []Point, out: ^HandleGeometry) {
    clear(&out.lines)
    clear(&out.anchor_points)
    clear(&out.handle_points)

    for point in control_points {
        append(&out.lines, point.handle_in)
        append(&out.lines, point.pos)
        append(&out.lines, point.pos)
        append(&out.lines, point.handle_out)

        append(&out.anchor_points, point.pos)
        append(&out.handle_points, point.handle_in)
        append(&out.handle_points, point.handle_out)
    }
}

generate_path_geometry :: proc(control_points: []Point, out: ^PathGeometry) {
    clear(&out.curve_lines)

    line_segments := 20
    t_delta: f32 = 1 / f32(line_segments)

    for point, i in control_points {
        if i == 0 do continue

        p0 := ([2]f32)(control_points[i-1].pos)
        p1 := ([2]f32)(control_points[i-1].handle_out)
        p2 := ([2]f32)(point.handle_in)
        p3 := ([2]f32)(point.pos)

        // Adaptive sampling
        // Use a stack to hold samples to be evaluated
        curve_samples: [dynamic][4][2]f32
        append(&curve_samples, [4][2]f32{ p0, p1, p2, p3 })

        for {
            if len(curve_samples) < 1 do break

            segment_control_points := pop(&curve_samples)
            if is_flat_enough(
                segment_control_points[0],
                segment_control_points[1],
                segment_control_points[2],
                segment_control_points[3],
                0.001
            ) {
                append(&out.curve_lines, WorldVec2(segment_control_points[0]), WorldVec2(segment_control_points[3]))
            } else {
                left, right := split_bezier_cubic(
                    segment_control_points[0],
                    segment_control_points[1],
                    segment_control_points[2],
                    segment_control_points[3]
                )
                // Add segments to the stack from right to left
                append(&curve_samples, right, left)
            }
        }
    }
}
