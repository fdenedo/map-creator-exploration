package app

import "../core"
import "../core/geojson"
import "../core/projection"

Layer :: union {
    MapLayer,
}

MapLayer :: struct {
    camera: projection.Camera,
    projection: projection.Projection,
    data: geojson.GeoJSON,
    data_projected_cache: geojson.GeoJSON_Projected,
    line_buffer: [dynamic]core.WorldVec2, // Scratch buffer for collecting line segments
}
