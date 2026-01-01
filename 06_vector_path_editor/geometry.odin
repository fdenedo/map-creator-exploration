package main

Point :: struct {
    id:         int,
    handle_in:  WorldVec2,
    pos:        WorldVec2,
    handle_out: WorldVec2,
}

Path :: struct {
    id:         int,
    points:     [dynamic]Point,
    closed:     bool,
    fill_color: [4]f32,
    has_fill:   bool,
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

StencilVertex :: struct {
    pos: WorldVec2,
}

FillGeometry :: struct {
    stencil_fans: [dynamic]StencilVertex,
    fan_counts:   [dynamic]int,
    fill_boxes:   [dynamic][4]WorldVec2,
    colors:       [dynamic][4]f32,
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

generate_stencil_fan :: proc(path: Path, out: ^[dynamic]StencilVertex) -> int {
    if !path.closed || len(path.points) < 3 do return 0

    // Compute centroid as fan center
    centroid := WorldVec2{0, 0}
    for point in path.points {
        centroid += point.pos
    }
    centroid /= f32(len(path.points))

    // Generate explicit triangles (since TRIANGLE_FAN doesn't exist in sokol)
    // Each triangle: centroid, point[i], point[i+1]
    tri_count := 0
    for i in 0..<len(path.points) {
        next_i := (i + 1) % len(path.points)

        // Triangle: centroid -> current -> next
        append(out, StencilVertex{centroid})
        append(out, StencilVertex{path.points[i].pos})
        append(out, StencilVertex{path.points[next_i].pos})

        tri_count += 1
    }

    // Return triangle count
    return tri_count
}

generate_fill_box :: proc(path: Path) -> [4]WorldVec2 {
    if !path.closed || !path.has_fill || len(path.points) < 3 do return {}

    // Compute bounding box of entire path
    min_x, min_y := max(f32), max(f32)
    max_x, max_y := min(f32), min(f32)

    for point in path.points {
        min_x = min(min_x, point.pos.x)
        min_y = min(min_y, point.pos.y)
        max_x = max(max_x, point.pos.x)
        max_y = max(max_y, point.pos.y)
    }

    // Return 4 corners as quad
    return [4]WorldVec2{
        {min_x, min_y},
        {max_x, min_y},
        {max_x, max_y},
        {min_x, max_y},
    }
}

// Simple direct triangulation for testing (no stencil needed)
FillTriangle :: struct {
    v0, v1, v2: WorldVec2,
}

DirectFillGeometry :: struct {
    triangles: [dynamic]FillTriangle,
    colors: [dynamic][4]f32,
}

generate_fill_geometry_direct :: proc(es: ^EditorState, out: ^DirectFillGeometry) {
    clear(&out.triangles)
    clear(&out.colors)

    for path in es.paths {
        if !path.closed || !path.has_fill || len(path.points) < 3 do continue

        // Simple fan triangulation from first point
        for i in 1..<len(path.points)-1 {
            append(&out.triangles, FillTriangle{
                v0 = path.points[0].pos,
                v1 = path.points[i].pos,
                v2 = path.points[i+1].pos,
            })
        }

        append(&out.colors, path.fill_color)
    }
}

generate_fill_geometry :: proc(es: ^EditorState, out: ^FillGeometry) {
    clear(&out.stencil_fans)
    clear(&out.fan_counts)
    clear(&out.fill_boxes)
    clear(&out.colors)

    for path in es.paths {
        if !path.closed || !path.has_fill do continue

        // Stencil pass: generate triangle fan
        tri_count := generate_stencil_fan(path, &out.stencil_fans)
        append(&out.fan_counts, tri_count)

        // Cover pass: generate fill box
        fill_box := generate_fill_box(path)
        append(&out.fill_boxes, fill_box)

        // Store color
        append(&out.colors, path.fill_color)
    }
}
