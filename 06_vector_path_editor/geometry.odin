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

    // TODO: Sample bezier curves between consecutive points
}
