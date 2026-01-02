package geojson

import "core:log"
import "core:math"
import "core:time"

import "../../core"
import "../../core/projection"

GeoJSON_Projected :: struct {
    points: [][2]f32,       // An array of coordinates
    lines: [][][2]f32,      // An array of lines, where a line is an array of coordinates
    polygons: [][][][2]f32, // An array of polygons, where a polygon is an array of LinearRings, which are lines
}

// TODO: this seems like a great place to implement MapReduce
// make this more parallel

project_geojson :: proc(geojson: ^GeoJSON, proj: projection.Projection) -> GeoJSON_Projected {
    when ODIN_DEBUG {
        start := time.now()
        defer {
            elapsed := time.diff(start, time.now())
            log.debugf("project_geojson took %v", elapsed)
        }
    }

    points_proj := make([dynamic][2]f32)
    lines_proj := make([dynamic][][2]f32)
    polygons_proj := make([dynamic][][][2]f32)
    // Note: Do NOT defer delete - the returned slices take ownership of the backing memory

    switch &g in geojson {
    case FeatureCollection:
        for &feature in g.features {
            collect_projected_geometry(&feature.geometry, proj, &points_proj, &lines_proj, &polygons_proj)
        }
    case Feature:
        collect_projected_geometry(&g.geometry, proj, &points_proj, &lines_proj, &polygons_proj)
    case Geometry:
        collect_projected_geometry(&g, proj, &points_proj, &lines_proj, &polygons_proj)
    case:
    }

    return GeoJSON_Projected {
        points_proj[:],
        lines_proj[:],
        polygons_proj[:],
    }
}

collect_projected_geometry :: proc(
    geometry: ^Geometry,
    proj: projection.Projection,
    projected_points: ^[dynamic][2]f32,
    projected_lines: ^[dynamic][][2]f32,
    projected_polygons: ^[dynamic][][][2]f32
) {
    switch &geom in geometry^ {
    case GeometryCollection:
        for &g in geom.geometries {
            collect_projected_geometry(&g, proj, projected_points, projected_lines, projected_polygons)
        }

    case Point:
        append(projected_points, project_geojson_coordinate(geom.coordinates, proj))

    case MultiPoint:
        for point in geom.coordinates {
            append(projected_points, project_geojson_coordinate(point, proj))
        }

    case LineString:
        line := make([]core.WorldVec2, len(geom.coordinates))
        for point, index in geom.coordinates {
            line[index] = project_geojson_coordinate(point, proj)
        }
        append(projected_lines, line)

    case MultiLineString:
        for line in geom.coordinates {
            line_proj := make([]core.WorldVec2, len(line))
            for point, index in line {
                line_proj[index] = project_geojson_coordinate(point, proj)
            }
            append(projected_lines, line_proj)
        }

    case Polygon:
        poly_proj := make([][]core.WorldVec2, len(geom.coordinates))
        for ring, ring_index in geom.coordinates {
            ring_proj := make([]core.WorldVec2, len(ring))
            for point, point_index in ring {
                ring_proj[point_index] = project_geojson_coordinate(point, proj)
            }
            poly_proj[ring_index] = ring_proj
        }
        append(projected_polygons, poly_proj)

    case MultiPolygon:
        for polygon in geom.coordinates {
            poly_proj := make([][]core.WorldVec2, len(polygon))
            for ring, ring_index in polygon {
                ring_proj := make([]core.WorldVec2, len(ring))
                for point, point_index in ring {
                    ring_proj[point_index] = project_geojson_coordinate(point, proj)
                }
                poly_proj[ring_index] = ring_proj
            }
            append(projected_polygons, poly_proj)
        }

    }
}

project_geojson_coordinate :: proc(coord: Position, proj: projection.Projection) -> core.WorldVec2 {
    coord_radians := (coord * math.PI / 180).xy
    return projection.project_f64(projection.GeoCoord64(coord_radians), proj)
}
