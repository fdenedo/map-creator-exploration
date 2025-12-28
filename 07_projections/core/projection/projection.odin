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
