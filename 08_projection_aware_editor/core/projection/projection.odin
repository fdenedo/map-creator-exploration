package projection

import "core:math"

Projection :: struct {
    centre: GeoCoord,
    type: ProjectionType,
}

ProjectionType :: enum {
    Equirectangular,
    Orthographic,
}

// The shape of the projection bounds
BoundsShape :: enum {
    Rectangle,
    Circle,
    Ellipse,
}

// The bounding rectangle/shape of the entire projectable world in world coordinates
ProjectionBounds :: struct {
    min_x, max_x: f32,
    min_y, max_y: f32,
    shape: BoundsShape,
}

// Returns the world-coordinate bounds for the full globe under this projection
get_bounds :: proc(proj: Projection) -> ProjectionBounds {
    switch proj.type {
    case .Equirectangular:
        // Full globe: longitude -180 to +180 (x: -π to +π), latitude -90 to +90 (y: -π/2 to +π/2)
        return ProjectionBounds {
            min_x = -math.PI,
            max_x =  math.PI,
            min_y = -math.PI / 2,
            max_y =  math.PI / 2,
            shape = .Rectangle,
        }
    case .Orthographic:
        // Orthographic projects visible hemisphere to a unit circle
        return ProjectionBounds {
            min_x = -1,
            max_x =  1,
            min_y = -1,
            max_y =  1,
            shape = .Circle,
        }
    case:
        return ProjectionBounds {}
    }
}

// TODO: consider moving normalisation to the vertex shader
normalise :: proc(geo: GeoCoord, type: ProjectionType) -> GeoCoord {
    switch type {
    case .Equirectangular:
        return GeoCoord {
            math.mod(geo.x + math.PI, 2 * math.PI) - math.PI,
            clamp(geo.y, -math.PI / 2, math.PI / 2)
        }

    case .Orthographic:
        // TODO: implement this
        return geo

    case:
        // TODO: add log here maybe?
        return geo
    }
}

// Clamp projection centre so the view doesn't go past canvas bounds
// This prevents panning beyond the edge of the map
clamp_centre_to_view :: proc(centre: GeoCoord, camera: Camera, proj_type: ProjectionType) -> GeoCoord {
    bounds := get_bounds(Projection { centre = centre, type = proj_type })
    left, right, bottom, top := camera_get_view_bounds(camera)

    view_half_width  := (right - left) / 2
    view_half_height := (top - bottom) / 2
    canvas_half_width  := (bounds.max_x - bounds.min_x) / 2
    canvas_half_height := (bounds.max_y - bounds.min_y) / 2

    result := centre

    // Clamp Y (latitude) - don't allow view to go past poles
    if view_half_height >= canvas_half_height {
        // View is taller than canvas - lock to centre
        result.y = 0
    } else {
        max_centre_y := bounds.max_y - view_half_height
        min_centre_y := bounds.min_y + view_half_height
        result.y = clamp(centre.y, min_centre_y, max_centre_y)
    }

    // X (longitude) wraps, so no clamping needed - just normalise
    result.x = math.mod(centre.x + math.PI, 2 * math.PI) - math.PI

    return result
}

project_f32 :: proc(geo: GeoCoord, proj: Projection) -> WorldVec2 {
    switch proj.type {
    case .Equirectangular:
        return WorldVec2 {
            geo[0] - proj.centre[0],
            geo[1] - proj.centre[1] // TODO: this probably needs to be inverted
        }
    case .Orthographic:
        lambda := geo[0]
        phi    := geo[1]

        return WorldVec2 {
            math.cos(phi) * math.sin(lambda - proj.centre[0]),
            math.cos(proj.centre[1]) * math.sin(phi) -
            math.sin(proj.centre[1]) * math.cos(phi) * math.cos(lambda - proj.centre[0])
        }
    case: return WorldVec2 {}
    }
}

project_f64 :: proc(geo: GeoCoord64, proj: Projection) -> WorldVec2 {
    switch proj.type {
    case .Equirectangular:
        return WorldVec2 {
            f32(geo[0] - f64(proj.centre[0])),
            f32(geo[1] - f64(proj.centre[1])),
        }
    case .Orthographic:
        lambda := geo[0]
        phi    := geo[1]

        centre_lon := f64(proj.centre[0])
        centre_lat := f64(proj.centre[1])

        return WorldVec2 {
            f32(math.cos(phi) * math.sin(lambda - centre_lon)),
            f32(math.cos(centre_lat) * math.sin(phi) -
                math.sin(centre_lat) * math.cos(phi) * math.cos(lambda - centre_lon)),
        }
    case: return WorldVec2 {}
    }
}

// Inverse projection: world coordinates -> geographic coordinates (f32)
// Returns (longitude, latitude) in radians
// For orthographic, returns (0,0) if the point is outside the visible hemisphere (rho > 1)
inverse_f32 :: proc(world: WorldVec2, proj: Projection) -> (geo: GeoCoord, valid: bool) {
    switch proj.type {
    case .Equirectangular:
        return GeoCoord {
            world[0] + proj.centre[0],
            world[1] + proj.centre[1],
        }, true

    case .Orthographic:
        x := world[0]
        y := world[1]
        rho := math.sqrt(x*x + y*y)

        // Point is outside the visible hemisphere
        if rho > 1.0 {
            return GeoCoord {}, false
        }

        // Avoid division by 0 at centre
        if rho < 1e-10 {
            return proj.centre, true
        }

        c := math.asin(rho)
        sin_c := math.sin(c)
        cos_c := math.cos(c)

        lat_0 := proj.centre[1]
        lon_0 := proj.centre[0]

        // Latitude (phi)
        phi := math.asin(cos_c * math.sin(lat_0) + (y * sin_c * math.cos(lat_0)) / rho)

        // Longitude (lambda)
        lambda := lon_0 + math.atan2(x * sin_c, rho * math.cos(lat_0) * cos_c - y * math.sin(lat_0) * sin_c)

        return GeoCoord { lambda, phi }, true

    case:
        return GeoCoord {}, false
    }
}

// For orthographic, returns (0,0) if the point is outside the visible hemisphere (rho > 1)
inverse_f64 :: proc(world: WorldVec2, proj: Projection) -> (geo: GeoCoord64, valid: bool) {
    switch proj.type {
    case .Equirectangular:
        return GeoCoord64 {
            f64(world[0]) + f64(proj.centre[0]),
            f64(world[1]) + f64(proj.centre[1]),
        }, true

    case .Orthographic:
        x := f64(world[0])
        y := f64(world[1])
        rho := math.sqrt(x*x + y*y)

        // Point is outside the visible hemisphere
        if rho > 1.0 {
            return GeoCoord64 {}, false
        }

        // Avoid division by 0 at centre
        if rho < 1e-10 {
            return GeoCoord64 { f64(proj.centre[0]), f64(proj.centre[1]) }, true
        }

        c := math.asin(rho)
        sin_c := math.sin(c)
        cos_c := math.cos(c)

        lat_0 := f64(proj.centre[1])
        lon_0 := f64(proj.centre[0])

        // Latitude (phi)
        phi := math.asin(cos_c * math.sin(lat_0) + (y * sin_c * math.cos(lat_0)) / rho)

        // Longitude (lambda)
        lambda := lon_0 + math.atan2(x * sin_c, rho * math.cos(lat_0) * cos_c - y * math.sin(lat_0) * sin_c)

        return GeoCoord64 { lambda, phi }, true

    case:
        return GeoCoord64 {}, false
    }
}

// Convenience wrapper matching the old signature (returns just the coordinate)
inverse :: proc(world: WorldVec2, proj: Projection) -> GeoCoord {
    geo, _ := inverse_f32(world, proj)
    return geo
}
