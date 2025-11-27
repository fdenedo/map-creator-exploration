package main

Triangle :: struct {
    p1, p2, p3: [2]f32
}

// This is all I need to do for a single Bezier curve, don't need to sample
// as the GPU will work out the actual pixels to colour
triangulate_quad :: proc(p0, p1, p2, p3: [2]f32) -> [2]Triangle {
    return {
        Triangle{ p0, p1, p3 },
        Triangle{ p1, p2, p3 },
    }
}

triangle_to_lines :: proc(t: Triangle) -> [6][2]f32 {
    return { t.p1,t.p2, t.p2,t.p3, t.p1,t.p3 }
}
