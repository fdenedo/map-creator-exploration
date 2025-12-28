package projection

import "core:math"

Projection :: struct {
    centre: GeoCoord,
    type: ProjectionType
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
            f32(geo[1] - f64(proj.centre[1])), // TODO: this probably needs to be inverted
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

inverse :: proc(world: WorldVec2, proj: Projection) -> GeoCoord {
    switch proj.type {
    case .Equirectangular:
        return GeoCoord {
            world[0] + proj.centre[0],
            world[1] + proj.centre[1]
        }
    case .Orthographic:
        return GeoCoord {
            0.0,
            0.0
        }
    case: return GeoCoord {}
    }
}
