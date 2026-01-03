package projection

import "core:math"

import ".."

Mat3 :: core.Matrix3
Vec3 :: core.Vector3

// Turns a coordinate expressed as (lon, lat), or (λ, φ), to a 3D
// coordinate on a unit circle
geo_to_sphere :: proc(geo: GeoCoord) -> Vec3 {
	return {
		math.cos(geo[0]) * math.cos(geo[1]),
		math.sin(geo[0]) * math.cos(geo[1]),
		math.sin(geo[1]),
	}
}

// Turns a 3D coordinate on a unit circle to a spherical (λ, φ)
// coordinate
sphere_to_geo :: proc(coord: Vec3) -> GeoCoord {
	return {
		math.atan2(coord[1], coord[0]),
		math.asin(coord[2]),
	}
}

// Build the rotation matrix that rotates the given vector onto the
// vector (0, 0, 1)
build_view_rotation_matrix :: proc(centre: GeoCoord) -> Mat3 {
	lon := centre[0]
	lat := centre[1]

 	sin_lon := math.sin(lon)
    cos_lon := math.cos(lon)
    sin_lat := math.sin(lat)
    cos_lat := math.cos(lat)

    return Mat3 {
         cos_lon,            sin_lon,           0,
        -sin_lat * sin_lon,  sin_lat * cos_lon, cos_lat,
         cos_lat * sin_lon, -cos_lat * cos_lon, sin_lat,
    }
}

rotate_to_view_space :: proc(points: []Vec3, rotation: Mat3) -> []Vec3 {
	result := make([]Vec3, len(points))

	for point, i in points {
		result[i] = rotation * point
	}

	return result
}

PolygonVisibility :: enum {
	Visible,
	Partial,
	Occluded,
}

polygon_visibility :: proc(points: []Vec3) -> PolygonVisibility {
	total := len(points)
	visible: int = 0

	for point in points {
		if point.z > 0 {
			visible += 1
		}
	}

	switch {
	case visible == 0: 		return .Occluded
	case visible < total: 	return .Partial
	case: 					return .Visible
	}
}

// Note that 1 polygon could become multiple polygons (e.g. if the polygon is
// some shape with a concave section where part of the concavity
// becomes occluded)
clip_polygon_to_hemisphere :: proc(points: []Vec3) -> []Vec3 {
 	result := make([dynamic]Vec3)
    n := len(points)

    for i in 0..<n {
        curr := points[i]
        next := points[(i + 1) % n]

        curr_visible := curr.z > 0
        next_visible := next.z > 0

        if curr_visible {
            append(&result, curr)
        }

        if curr_visible != next_visible {
            intersection := great_circle_horizon_intersection(curr, next)
            append(&result, intersection)
        }
    }

    return result[:]
}

// Find intersection of great circle arc with z = 0 plane
//
// Note, this only works if both endpoints of the arc are on opposite sides
// of the z = 0 plane.
great_circle_horizon_intersection :: proc(a, b: Vec3) -> Vec3 {
	// Find the t for which, when lerping between a and b, gives a
	// z value of 0
	t := a.z / (a.z - b.z)

	// Interpolate using linear lerp
	p := Vec3 {
		a.x + t * (b.x - a.x),
        a.y + t * (b.y - a.y),
        0
	}

	// Project back onto unit sphere
	len := math.sqrt(p.x * p.x + p.y * p.y)
    return Vec3 { p.x / len, p.y / len, 0 }
}

// Spherical linear interpolation - finds a point along the great circle arc
slerp :: proc(a, b: Vec3, t: f32) -> Vec3 {
	dot := a.x * b.x + a.y * b.y + a.z * b.z
	dot = clamp(dot, -1, 1)

	theta := math.acos(dot)

	// If points are nearly identical, use linear interpolation
	if theta < 1e-6 {
		return Vec3 {
			a.x + t * (b.x - a.x),
			a.y + t * (b.y - a.y),
			a.z + t * (b.z - a.z),
		}
	}

	sin_theta := math.sin(theta)
	wa := math.sin((1 - t) * theta) / sin_theta
	wb := math.sin(t * theta) / sin_theta

	return Vec3 {
		wa * a.x + wb * b.x,
		wa * a.y + wb * b.y,
		wa * a.z + wb * b.z,
	}
}

// Project from view space (where projection centre is at 0,0,1) to 2D
project_view_to_2d :: proc(p: Vec3, proj_type: ProjectionType) -> WorldVec2 {
	switch proj_type {
	case .Orthographic:
		return WorldVec2 { p.x, p.y }
	case .Equirectangular:
		// Convert back to geo coords for equirectangular
		geo := sphere_to_geo(p)
		return WorldVec2 { geo[0], geo[1] }
	}
	return WorldVec2 {}
}

// Check if a great circle arc is flat enough after projection
// Compares the projected midpoint to the linear midpoint in 2D
arc_is_flat_enough :: proc(a, b: Vec3, proj_type: ProjectionType, tolerance: f32) -> bool {
	mid_sphere := slerp(a, b, 0.5)

	a_2d := project_view_to_2d(a, proj_type)
	b_2d := project_view_to_2d(b, proj_type)
	mid_2d := project_view_to_2d(mid_sphere, proj_type)

	linear_mid := WorldVec2 {
		(a_2d.x + b_2d.x) * 0.5,
		(a_2d.y + b_2d.y) * 0.5,
	}

	dx := mid_2d.x - linear_mid.x
	dy := mid_2d.y - linear_mid.y
	dist_sq := dx * dx + dy * dy

	return dist_sq < tolerance * tolerance
}

// Recursively subdivide a single arc until flat enough
subdivide_arc :: proc(a, b: Vec3, proj_type: ProjectionType, tolerance: f32, result: ^[dynamic]Vec3) {
	if arc_is_flat_enough(a, b, proj_type, tolerance) {
		append(result, a)
	} else {
		mid := slerp(a, b, 0.5)
		subdivide_arc(a, mid, proj_type, tolerance, result)
		subdivide_arc(mid, b, proj_type, tolerance, result)
	}
}

// Subdivide a polygon's edges into great circle arcs
subdivide_polygon :: proc(points: []Vec3, proj_type: ProjectionType, tolerance: f32) -> []Vec3 {
	result := make([dynamic]Vec3)
	n := len(points)

	for i in 0..<n {
		curr := points[i]
		next := points[(i + 1) % n]
		subdivide_arc(curr, next, proj_type, tolerance, &result)
	}

	return result[:]
}
