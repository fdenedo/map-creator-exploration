package main

import "core:math/linalg"

lerp2d :: proc(a, b: [2]f32, t: f32) -> [2]f32 {
    return (b - a) * t + a
}

evaluate_bezier_quadratic :: proc(p0, p1, p2: [2]f32, t: f32) -> [2]f32 {
    a0 := lerp2d(p0, p1, t)
    a1 := lerp2d(p1, p2, t)

    return lerp2d(a0, a1, t)
}

evaluate_bezier_cubic :: proc(p0, p1, p2, p3: [2]f32, t: f32) -> [2]f32 {
    a0 := lerp2d(p0, p1, t)
    a1 := lerp2d(p1, p2, t)
    a2 := lerp2d(p2, p3, t)

    b0 := lerp2d(a0, a1, t)
    b1 := lerp2d(a1, a2, t)

    return lerp2d(b0, b1, t)
}

split_bezier_cubic :: proc(p0, p1, p2, p3: [2]f32) -> (left: [4][2]f32, right: [4][2]f32) {
    a0 := lerp2d(p0, p1, 0.5)
    a1 := lerp2d(p1, p2, 0.5)
    a2 := lerp2d(p2, p3, 0.5)

    b0 := lerp2d(a0, a1, 0.5)
    b1 := lerp2d(a1, a2, 0.5)

    c  := lerp2d(b0, b1, 0.5)

    return { p0, a0, b0, c }, { c, b1, a2, p3 }
}

is_flat_enough :: proc(p0, p1, p2, p3: [2]f32, tolerance: f32) -> bool {
    line := p3 - p0
    line_length := linalg.vector_length(line)

    if line_length < 0.001 do return true

    dist1 := abs(linalg.vector_cross2(p1 - p0, line)) / line_length
    dist2 := abs(linalg.vector_cross2(p2 - p0, line)) / line_length

    return max(dist1, dist2) < tolerance
}
