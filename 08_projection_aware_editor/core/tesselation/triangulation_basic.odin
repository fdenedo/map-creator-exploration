package tesselation

import "../"

// triangle_fan_from_origin creates triangles by connecting each edge to the origin (0,0)
// This is ideal for stencil-and-cover rendering where the origin is at the center of view
// Works correctly with concave polygons when combined with stencil buffer
triangle_fan_from_origin :: proc(poly_vertices: []core.WorldVec2) -> []Triangle {
	if len(poly_vertices) < 3 do return nil

	origin := core.WorldVec2{0, 0}
	n := len(poly_vertices)
	triangles := make([]Triangle, n)

	for i in 0..<n {
		next := (i + 1) % n
		triangles[i] = Triangle {
			origin,
			poly_vertices[i],
			poly_vertices[next],
		}
	}
	return triangles
}
