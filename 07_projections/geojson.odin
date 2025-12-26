package main

import "core:encoding/json"
import "core:log"

// The structs and data objects defined in this file follow the RFC 7946 specification
// for GeoJSON: https://datatracker.ietf.org/doc/html/rfc7946

// ========================================
// RAW JSON TYPES
// ========================================

// Note: parsing the JSON in 2 passes, first read to raw feature collections, then parse
// the result

Raw_FeatureCollection :: struct {
    type: string,
    features: []Raw_Feature,
    bbox: Maybe([]f64),
}

Raw_Feature :: struct {
    type: string,
    id: Maybe(json.Value),  // Can be string or number, converted to FeatureId later
    geometry: Maybe(Raw_Geometry),  // Can be null per RFC 7946
    properties: Maybe(map[string]json.Value),
    bbox: Maybe([]f64),
}

Raw_Geometry :: struct {
    type: string,
    coordinates: Maybe(json.Value), // Not present for GeometryCollection
    geometries: Maybe([]Raw_Geometry), // Only for GeometryCollection
    bbox: Maybe([]f64),
}

// ========================================
// DOMAIN TYPES
// ========================================

/*
    Valid GeoJson root types
*/
GeoJSON :: union {
    FeatureCollection,
    Feature,
    Geometry,
}

FeatureCollection :: struct {
    features: []Feature,
    bbox: Maybe(BoundingBox),
}

Feature :: struct {
    id: Maybe(FeatureId),
    geometry: Geometry,
    properties: map[string]json.Value,
    bbox: Maybe(BoundingBox),
}

Geometry :: union {
    Point,
    MultiPoint,
    LineString,
    MultiLineString,
    Polygon,
    MultiPolygon,
    GeometryCollection,
}

BoundingBox :: struct {
    min_lon: f64,
    min_lat: f64,
    max_lon: f64,
    max_lat: f64,
    min_elevation: Maybe(f64),
    max_elevation: Maybe(f64),
}

FeatureId :: union {
    string,
    f64,  // JSON numbers are f64
}

Point :: struct {
    // A single position
    coordinates: Position,
    bbox: Maybe(BoundingBox),
}

MultiPoint :: struct {
    // An array of positions
    coordinates: []Position,
    bbox: Maybe(BoundingBox),
}

LineString :: struct {
    // An array of 2 or more positions
    coordinates: []Position,
    bbox: Maybe(BoundingBox),
}

MultiLineString :: struct {
    // An array of LineString coordinate arrays
    coordinates: [][]Position,
    bbox: Maybe(BoundingBox),
}

// A LinearRing is a closed LineString that conforms to the following constraints:
// - it has 4 or more positions
// - the first and last position are equivalent (exactly identical)
// - it follows the right-hand rule with respect to the area it bounds (exterior ->
// anticlockwise, interior -> clockwise)
//
// Note that for older specifications, linear ring winding order was not specified,
// so for backwards compatibility LinearRings that don't conform to this rule aren't
// rejected, but should be dealt with gracefully
LinearRing :: distinct []Position

Polygon :: struct {
    // An array of linear rings where:
    // - the first is the exterior ring
    // - the following (0 or more) rings are interior rings (holes)
    coordinates: []LinearRing,
    bbox: Maybe(BoundingBox),
}

MultiPolygon :: struct {
    // An array of Polygon coordinate arrays
    coordinates: [][]LinearRing,
    bbox: Maybe(BoundingBox),
}

GeometryCollection :: struct {
    geometries: []Geometry,
    bbox: Maybe(BoundingBox),
}

Position :: [3]f64

// ========================================
// PARSING FUNCTIONS
// ========================================

parse_geojson :: proc(data: []byte, allocator := context.allocator) -> (result: GeoJSON, ok: bool) {
    // Final domain types use the provided allocator (caller owns this memory)
    // JSON parsing intermediates use temp_allocator (freed automatically)
    context.allocator = allocator

    raw_value: json.Value

    // Use temp_allocator for JSON parsing - these intermediates are only needed
    // during conversion to domain types, then can be discarded
    if err := json.unmarshal(data, &raw_value, allocator = context.temp_allocator); err != nil {
        log.errorf("Failed to unmarshal data as JSON: %v", err)
        return GeoJSON {}, false
    }
    defer json.destroy_value(raw_value, context.temp_allocator)

    obj, obj_ok := raw_value.(json.Object)
    if !obj_ok {
        log.errorf("Expected JSON Object at root, got %v", raw_value)
        return GeoJSON {}, false
    }

    type_value, type_ok := obj["type"]
    if !type_ok {
        log.error("Missing 'type' field in GeoJSON root object")
        return GeoJSON {}, false
    }

    type_str, type_str_ok := type_value.(json.String)
    if !type_str_ok {
        log.errorf("Expected 'type' to be a string, got %v", type_value)
        return GeoJSON {}, false
    }

    switch type_str {
    case "FeatureCollection":
        fc: Raw_FeatureCollection
        if err := json.unmarshal(data, &fc, allocator = context.temp_allocator); err != nil {
            log.errorf("Failed to unmarshal FeatureCollection: %v", err)
            return GeoJSON {}, false
        }
        return raw_to_feature_collection(fc)

    case "Feature":
        f: Raw_Feature
        if err := json.unmarshal(data, &f, allocator = context.temp_allocator); err != nil {
            log.errorf("Failed to unmarshal Feature: %v", err)
            return GeoJSON {}, false
        }
        return raw_to_feature(f)

    case "Point", "MultiPoint", "LineString", "MultiLineString", "Polygon", "MultiPolygon", "GeometryCollection":
        g: Raw_Geometry
        if err := json.unmarshal(data, &g, allocator = context.temp_allocator); err != nil {
            log.errorf("Failed to unmarshal Geometry: %v", err)
            return GeoJSON {}, false
        }
        return raw_to_geometry(g)

    case:
        log.errorf("Unknown GeoJSON type: %s", type_str)
        return GeoJSON {}, false
    }
}

raw_to_feature_collection :: proc(raw: Raw_FeatureCollection) -> (result: FeatureCollection, ok: bool) {
    processed_features := make([dynamic]Feature)
    defer delete(processed_features)

    for feature in raw.features {
        processed, processed_success := raw_to_feature(feature)
        if !processed_success {
            log.errorf("Failed to process as Feature: %v", feature)
            continue
        }
        append(&processed_features, processed)
    }

    return FeatureCollection {
        features = processed_features[:],
        bbox = parse_bbox(raw.bbox),
    }, true
}

raw_to_feature :: proc(raw: Raw_Feature) -> (result: Feature, ok: bool) {
    feature := Feature {
        id = parse_feature_id(raw.id),
        properties = raw.properties.? or_else nil,
        bbox = parse_bbox(raw.bbox),
    }

    // Geometry can be null for unlocated features
    if raw_geom, has_geom := raw.geometry.?; has_geom {
        geom, geom_ok := raw_to_geometry(raw_geom)
        if !geom_ok {
            log.errorf("Failed to process geometry of Feature")
            return Feature {}, false
        }
        feature.geometry = geom
    }

    return feature, true
}

raw_to_geometry :: proc(raw: Raw_Geometry) -> (result: Geometry, ok: bool) {
    bbox := parse_bbox(raw.bbox)

    switch raw.type {
    case "Point":
        coords, coords_ok := raw.coordinates.?
        if !coords_ok {
            log.error("Point geometry missing coordinates")
            return Geometry {}, false
        }
        pos, pos_ok := parse_position(coords)
        if !pos_ok {
            log.error("Failed to parse Point coordinates")
            return Geometry {}, false
        }
        return Point{coordinates = pos, bbox = bbox}, true

    case "MultiPoint":
        coords, coords_ok := raw.coordinates.?
        if !coords_ok {
            log.error("MultiPoint geometry missing coordinates")
            return Geometry {}, false
        }
        positions, positions_ok := parse_position_array(coords)
        if !positions_ok {
            log.error("Failed to parse MultiPoint coordinates")
            return Geometry {}, false
        }
        return MultiPoint{coordinates = positions, bbox = bbox}, true

    case "LineString":
        coords, coords_ok := raw.coordinates.?
        if !coords_ok {
            log.error("LineString geometry missing coordinates")
            return Geometry {}, false
        }
        positions, positions_ok := parse_position_array(coords)
        if !positions_ok {
            log.error("Failed to parse LineString coordinates")
            return Geometry {}, false
        }
        if len(positions) < 2 {
            log.errorf("LineString must have at least 2 positions, got %d", len(positions))
            return Geometry {}, false
        }
        return LineString{coordinates = positions, bbox = bbox}, true

    case "MultiLineString":
        coords, coords_ok := raw.coordinates.?
        if !coords_ok {
            log.error("MultiLineString geometry missing coordinates")
            return Geometry {}, false
        }
        lines, lines_ok := parse_line_array(coords)
        if !lines_ok {
            log.error("Failed to parse MultiLineString coordinates")
            return Geometry {}, false
        }
        return MultiLineString{coordinates = lines, bbox = bbox}, true

    case "Polygon":
        coords, coords_ok := raw.coordinates.?
        if !coords_ok {
            log.error("Polygon geometry missing coordinates")
            return Geometry {}, false
        }
        rings, rings_ok := parse_ring_array(coords)
        if !rings_ok {
            log.error("Failed to parse Polygon coordinates")
            return Geometry{}, false
        }
        return Polygon{coordinates = rings, bbox = bbox}, true

    case "MultiPolygon":
        coords, coords_ok := raw.coordinates.?
        if !coords_ok {
            log.error("MultiPolygon geometry missing coordinates")
            return Geometry {}, false
        }
        polygons, polygons_ok := parse_polygon_array(coords)
        if !polygons_ok {
            log.error("Failed to parse MultiPolygon coordinates")
            return Geometry {}, false
        }
        return MultiPolygon{coordinates = polygons, bbox = bbox}, true

    case "GeometryCollection":
        raw_geoms, geoms_ok := raw.geometries.?
        if !geoms_ok {
            log.error("GeometryCollection missing geometries array")
            return Geometry {}, false
        }
        geometries := make([]Geometry, len(raw_geoms))
        for raw_geom, i in raw_geoms {
            geom, geom_ok := raw_to_geometry(raw_geom)
            if !geom_ok {
                log.errorf("Failed to parse geometry at index %d in GeometryCollection", i)
                return Geometry {}, false
            }
            geometries[i] = geom
        }
        return GeometryCollection { geometries = geometries, bbox = bbox }, true

    case:
        log.errorf("Unknown geometry type: %s", raw.type)
        return Geometry {}, false
    }
}

// ========================================
// PARSING HELPERS
// ========================================

parse_feature_id :: proc(val: Maybe(json.Value)) -> Maybe(FeatureId) {
    v, has_val := val.?
    if !has_val {
        return nil
    }
    #partial switch id in v {
    case json.String:
        return FeatureId(string(id))
    case json.Float:
        return FeatureId(f64(id))
    case json.Integer:
        return FeatureId(f64(id))
    }
    return nil
}

parse_bbox :: proc(val: Maybe([]f64)) -> Maybe(BoundingBox) {
    arr, has_val := val.?
    if !has_val || len(arr) < 4 {
        return nil
    }
    bbox := BoundingBox {
        min_lon = arr[0],
        min_lat = arr[1],
        max_lon = arr[2],
        max_lat = arr[3],
    }
    // 3D bbox has 6 elements
    if len(arr) >= 6 {
        bbox.min_elevation = arr[2]
        bbox.max_elevation = arr[5]
        bbox.max_lon = arr[3]
        bbox.max_lat = arr[4]
    }
    return bbox
}

parse_position :: proc(val: json.Value) -> (result: Position, ok: bool) {
    arr, arr_ok := val.(json.Array)
    if !arr_ok || len(arr) < 2 {
        return Position {}, false
    }
    lon, lon_ok := json_to_f64(arr[0])
    if !lon_ok {
        return Position {}, false
    }
    lat, lat_ok := json_to_f64(arr[1])
    if !lat_ok {
        return Position {}, false
    }
    elev: f64 = 0
    if len(arr) > 2 {
        elev, _ = json_to_f64(arr[2])  // Elevation is optional, ignore failure
    }
    return Position { lon, lat, elev }, true
}

parse_position_array :: proc(val: json.Value) -> ([]Position, bool) {
    arr, arr_ok := val.(json.Array)
    if !arr_ok {
        return nil, false
    }
    positions := make([]Position, len(arr))
    for elem, i in arr {
        pos, pos_ok := parse_position(elem)
        if !pos_ok {
            return nil, false
        }
        positions[i] = pos
    }
    return positions, true
}

parse_line_array :: proc(val: json.Value) -> ([][]Position, bool) {
    arr, arr_ok := val.(json.Array)
    if !arr_ok {
        return nil, false
    }
    lines := make([][]Position, len(arr))
    for elem, i in arr {
        line, line_ok := parse_position_array(elem)
        if !line_ok {
            return nil, false
        }
        lines[i] = line
    }
    return lines, true
}

parse_ring_array :: proc(val: json.Value) -> ([]LinearRing, bool) {
    arr, arr_ok := val.(json.Array)
    if !arr_ok {
        return nil, false
    }
    rings := make([]LinearRing, len(arr))
    for elem, i in arr {
        positions, pos_ok := parse_position_array(elem)
        if !pos_ok {
            return nil, false
        }
        rings[i] = LinearRing(positions)
    }
    return rings, true
}

parse_polygon_array :: proc(val: json.Value) -> ([][]LinearRing, bool) {
    arr, arr_ok := val.(json.Array)
    if !arr_ok {
        return nil, false
    }
    polygons := make([][]LinearRing, len(arr))
    for elem, i in arr {
        rings, rings_ok := parse_ring_array(elem)
        if !rings_ok {
            return nil, false
        }
        polygons[i] = rings
    }
    return polygons, true
}

json_to_f64 :: proc(val: json.Value) -> (f64, bool) {
    #partial switch v in val {
    case json.Float:
        return f64(v), true
    case json.Integer:
        return f64(v), true
    }
    return 0, false
}
