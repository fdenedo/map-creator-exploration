package main

Triangle :: struct {
    p1, p2, p3: [2]f32
}

// Super simple triangulation that "closes" a Bezier curve
// Essentially creates a final triangle whose points are { centre, p3, p0}
//
// $samples is evaluated at compile time (fine for the way I'm using it right now)
// Interesting things to learn here re: memory allocation
// Need a better name instead of samples, as samples denotes the number of points,
// not the number of triangles
triangulate_bezier :: proc(p0, p1, p2, p3: [2]f32, $samples: int) -> [samples]Triangle {
    assert(samples > 2, "Samples must be greater than 2")

    triangles : [samples]Triangle
    evaluated_bezier_points: [samples][2]f32

    t_delta := 1.0 / f32(samples - 1)
    for i in 0..<samples {
        switch {
        case i == 0:
            evaluated_bezier_points[0] = p0
        case i == samples - 1:
            evaluated_bezier_points[i] = p3
        case:
            evaluated_bezier_points[i] = evaluate_bezier_cubic(p0, p1, p2, p3, f32(i) * t_delta)
        }
    }

    sum: [2]f32
    for p in evaluated_bezier_points {
        sum += p
    }
    centroid := sum / f32(samples)

    for i in 0..<samples {
        triangle := Triangle{
            centroid,
            evaluated_bezier_points[i],
            evaluated_bezier_points[(i + 1) % samples]
        }
        triangles[i] = triangle
    }

    return triangles
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
