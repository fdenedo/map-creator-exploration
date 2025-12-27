package app

import "../core/geojson"
import "../core/projection"

Layer :: union {
    MapLayer,
}

MapLayer :: struct {
    camera: projection.Camera,
    data: geojson.GeoJSON,
}
