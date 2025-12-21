package main

Point :: struct {
    id:         int,
    handle_in:  WorldVec2,
    pos:        WorldVec2,
    handle_out: WorldVec2,
}

Path :: struct {
    id:     int,
    points: [dynamic]Point,
    closed: bool,
}

SpecialPoint :: struct {
    pos:  WorldVec2,
    size: f32,
}

HandleGeometry :: struct {
    lines:         [dynamic]WorldVec2,
    anchor_points: [dynamic]WorldVec2,
    handle_points: [dynamic]WorldVec2,
}

PathGeometry :: struct {
    curve_lines: [dynamic]WorldVec2,
}

ANCHOR_SIZE :: 5.0
HANDLE_SIZE :: 3.0

generate_handle_geometry :: proc(es: ^EditorState, out: ^HandleGeometry) {
    clear(&out.lines)
    clear(&out.anchor_points)
    clear(&out.handle_points)

    for path in es.paths {
        for point in path.points {
            point_effective := get_effective_point(es, path.id, point.id)

            append(&out.lines, point_effective.handle_in)
            append(&out.lines, point_effective.pos)
            append(&out.lines, point_effective.pos)
            append(&out.lines, point_effective.handle_out)

            append(&out.anchor_points, point_effective.pos)
            append(&out.handle_points, point_effective.handle_in)
            append(&out.handle_points, point_effective.handle_out)
        }
    }
}

// Resolve a PointRef to a SpecialPoint for rendering (evaluated every frame)
resolve_special_point :: proc(es: ^EditorState, ref: PointRef) -> Maybe(SpecialPoint) {
    path, _ := find_path(es, ref.path_id)
    if path == nil do return nil

    point := get_effective_point(es, ref.path_id, ref.point_id)
    pos: WorldVec2
    base_size: f32
    switch ref.part {
    case .ANCHOR:
        pos = point.pos
        base_size = ANCHOR_SIZE
    case .IN:
        pos = point.handle_in
        base_size = HANDLE_SIZE
    case .OUT:
        pos = point.handle_out
        base_size = HANDLE_SIZE
    }
    return SpecialPoint { pos = pos, size = base_size }
}

generate_path_geometry :: proc(es: ^EditorState, out: ^PathGeometry) {
    clear(&out.curve_lines)

    curve_sample_tolerance := screen_to_world(0.5, es.camera, false).x // half-pixel tolerance

    for path in es.paths {
        for i in 1..<len(path.points) {
            start_point := get_effective_point(es, path.id, path.points[i-1].id)
            end_point := get_effective_point(es, path.id, path.points[i].id)
            append(&out.curve_lines, ..generate_bezier(start_point, end_point, curve_sample_tolerance)[:])
        }
        if path.closed && len(path.points) > 0 {
            start_point := get_effective_point(es, path.id, path.points[len(path.points)-1].id)
            end_point := get_effective_point(es, path.id, path.points[0].id)
            append(&out.curve_lines, ..generate_bezier(start_point, end_point, curve_sample_tolerance)[:])
        }
    }
}

generate_bezier :: proc(start: Point, end: Point, tolerance: f32) -> []WorldVec2 {
    p0 := ([2]f32)(start.pos)
    p1 := ([2]f32)(start.handle_out)
    p2 := ([2]f32)(end.handle_in)
    p3 := ([2]f32)(end.pos)

    // Adaptive sampling
    // Use a stack to hold samples to be evaluated
    curve_samples: [dynamic][4][2]f32
    append(&curve_samples, [4][2]f32{ p0, p1, p2, p3 })

    bezier: [dynamic]WorldVec2

    for {
        if len(curve_samples) < 1 do break

        // Satisfied TODO: now passing in tolerance, calculating using screen_to_world()
        // TODO: can do something cheeky here if filling the polygon, and sample as a bunch of
        // quadratic segments, and then use Loop-Blinn in the frag shader
        segment_control_points := pop(&curve_samples)
        if is_flat_enough(
            segment_control_points[0],
            segment_control_points[1],
            segment_control_points[2],
            segment_control_points[3],
            tolerance
        ) {
            append(&bezier, WorldVec2(segment_control_points[0]), WorldVec2(segment_control_points[3]))
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

    return bezier[:]
}
