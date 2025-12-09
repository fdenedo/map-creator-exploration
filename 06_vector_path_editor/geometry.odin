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

        for s in 0..<line_segments {
            first  := len(out.curve_lines) > 0 ? out.curve_lines[len(out.curve_lines)-1] : WorldVec2(p0)
            second := WorldVec2(evaluate_bezier_cubic(p0, p1, p2, p3, t_delta * f32(s + 1)))
            append(&out.curve_lines, first, second)
        }
    }
}
