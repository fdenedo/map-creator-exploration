package geojson

import "core:encoding/json"

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
// ERROR TYPES
// ========================================

Parse_Error_Category :: enum {
    None,                    // Success - no error
    Invalid_JSON,
    Missing_Field,
    Invalid_Type,
    Invalid_Value,
    Constraint_Violation,
    Unknown_Type,
}

Parse_Error :: struct {
    category: Parse_Error_Category,
    message:  string,
    path:     string,  // JSON path where the error occurred
}

// ========================================
// PARSING FUNCTIONS
// ========================================

// TODO: GeoJSON files can be large, so we need to make sure that, when sensible to do so, we process
// as much as possible, and provide clear and expressive errors when objects cannot be processed.
// E.g. it might make sense to render all of the geometry that is valid, and leave out invalid geometry
parse_geojson :: proc(data: []byte, allocator := context.allocator) -> (result: GeoJSON, err: Parse_Error) {
    // Final domain types use the provided allocator (caller owns this memory)
    // JSON parsing intermediates use temp_allocator (freed automatically)
    context.allocator = allocator

    raw_value: json.Value

    // Use temp_allocator for JSON parsing - these intermediates are only needed
    // during conversion to domain types, then can be discarded
    if json_err := json.unmarshal(data, &raw_value, allocator = context.temp_allocator); json_err != nil {
        return GeoJSON {}, Parse_Error {
            category = .Invalid_JSON,
            message = "Failed to unmarshal data as JSON",
            path ="root",
        }
    }
    defer json.destroy_value(raw_value, context.temp_allocator)

    obj, obj_ok := raw_value.(json.Object)
    if !obj_ok {
        return GeoJSON {}, Parse_Error {
            category = .Invalid_Type,
            message = "Expected JSON Object at root",
            path ="root",
        }
    }

    type_value, type_ok := obj["type"]
    if !type_ok {
        return GeoJSON {}, Parse_Error {
            category = .Missing_Field,
            message = "Missing 'type' field in GeoJSON root object",
            path ="root.type",
        }
    }

    type_str, type_str_ok := type_value.(json.String)
    if !type_str_ok {
        return GeoJSON {}, Parse_Error {
            category = .Invalid_Type,
            message = "Expected 'type' to be a string",
            path ="root.type",
        }
    }

    switch type_str {
    case "FeatureCollection":
        fc: Raw_FeatureCollection
        if json_err := json.unmarshal(data, &fc, allocator = context.temp_allocator); json_err != nil {
            return GeoJSON {}, Parse_Error {
                category = .Invalid_JSON,
                message = "Failed to unmarshal FeatureCollection",
                path ="root",
            }
        }
        return raw_to_feature_collection(fc)

    case "Feature":
        f: Raw_Feature
        if json_err := json.unmarshal(data, &f, allocator = context.temp_allocator); json_err != nil {
            return GeoJSON {}, Parse_Error {
                category = .Invalid_JSON,
                message = "Failed to unmarshal Feature",
                path ="root",
            }
        }
        return raw_to_feature(f)

    case "Point", "MultiPoint", "LineString", "MultiLineString", "Polygon", "MultiPolygon", "GeometryCollection":
        g: Raw_Geometry
        if json_err := json.unmarshal(data, &g, allocator = context.temp_allocator); json_err != nil {
            return GeoJSON {}, Parse_Error {
                category = .Invalid_JSON,
                message = "Failed to unmarshal Geometry",
                path ="root",
            }
        }
        return raw_to_geometry(g)

    case:
        return GeoJSON {}, Parse_Error {
            category = .Unknown_Type,
            message = "Unknown GeoJSON type",
            path ="root.type",
        }
    }
}

raw_to_feature_collection :: proc(raw: Raw_FeatureCollection) -> (result: FeatureCollection, err: Parse_Error) {
    processed_features := make([dynamic]Feature)
    // Note: Do NOT defer delete - the returned slice takes ownership of the backing memory

    for feature in raw.features {
        processed, feature_err := raw_to_feature(feature)
        if feature_err.category != .None {
            // Skip invalid features and continue processing (partial success)
            continue
        }
        append(&processed_features, processed)
    }

    return FeatureCollection {
        features = processed_features[:],
        bbox = parse_bbox(raw.bbox),
    }, Parse_Error{category = .None}
}

raw_to_feature :: proc(raw: Raw_Feature) -> (result: Feature, err: Parse_Error) {
    feature := Feature {
        id = parse_feature_id(raw.id),
        properties = raw.properties.? or_else nil,
        bbox = parse_bbox(raw.bbox),
    }

    // Geometry can be null for unlocated features
    if raw_geom, has_geom := raw.geometry.?; has_geom {
        geom, geom_err := raw_to_geometry(raw_geom)
        if geom_err.category != .None {
            geom_err.path ="Feature.geometry"
            return Feature {}, geom_err
        }
        feature.geometry = geom
    }

    return feature, Parse_Error { category = .None }
}

raw_to_geometry :: proc(raw: Raw_Geometry) -> (result: Geometry, err: Parse_Error) {
    bbox := parse_bbox(raw.bbox)

    switch raw.type {
    case "Point":
        coords, coords_ok := raw.coordinates.?
        if !coords_ok {
            return Geometry {}, Parse_Error {
                category = .Missing_Field,
                message = "Point geometry missing coordinates field",
                path ="Point.coordinates",
            }
        }
        pos, pos_ok := parse_position(coords)
        if !pos_ok {
            return Geometry {}, Parse_Error {
                category = .Invalid_Value,
                message = "Failed to parse Point coordinates",
                path ="Point.coordinates",
            }
        }
        return Point{ coordinates = pos, bbox = bbox }, Parse_Error { category = .None }

    case "MultiPoint":
        coords, coords_ok := raw.coordinates.?
        if !coords_ok {
            return Geometry {}, Parse_Error {
                category = .Missing_Field,
                message = "MultiPoint geometry missing coordinates field",
                path ="MultiPoint.coordinates",
            }
        }
        positions, positions_ok := parse_position_array(coords)
        if !positions_ok {
            return Geometry {}, Parse_Error {
                category = .Invalid_Value,
                message = "Failed to parse MultiPoint coordinates",
                path ="MultiPoint.coordinates",
            }
        }
        return MultiPoint { coordinates = positions, bbox = bbox }, Parse_Error { category = .None }

    case "LineString":
        coords, coords_ok := raw.coordinates.?
        if !coords_ok {
            return Geometry {}, Parse_Error {
                category = .Missing_Field,
                message = "LineString geometry missing coordinates field",
                path ="LineString.coordinates",
            }
        }
        positions, positions_ok := parse_position_array(coords)
        if !positions_ok {
            return Geometry {}, Parse_Error {
                category = .Invalid_Value,
                message = "Failed to parse LineString coordinates",
                path ="LineString.coordinates",
            }
        }
        if len(positions) < 2 {
            return Geometry {}, Parse_Error {
                category = .Constraint_Violation,
                message = "LineString must have at least 2 positions",
                path ="LineString.coordinates",
            }
        }
        return LineString { coordinates = positions, bbox = bbox }, Parse_Error { category = .None }

    case "MultiLineString":
        coords, coords_ok := raw.coordinates.?
        if !coords_ok {
            return Geometry{}, Parse_Error{
                category = .Missing_Field,
                message = "MultiLineString geometry missing coordinates field",
                path ="MultiLineString.coordinates",
            }
        }
        lines, line_err := parse_line_array(coords)
        if line_err.category != .None {
            line_err.path ="MultiLineString.coordinates"
            return Geometry{}, line_err
        }
        return MultiLineString { coordinates = lines, bbox = bbox }, Parse_Error { category = .None }

    case "Polygon":
        coords, coords_ok := raw.coordinates.?
        if !coords_ok {
            return Geometry{}, Parse_Error{
                category = .Missing_Field,
                message = "Polygon geometry missing coordinates field",
                path ="Polygon.coordinates",
            }
        }
        rings, ring_err := parse_ring_array(coords)
        if ring_err.category != .None {
            ring_err.path ="Polygon.coordinates"
            return Geometry {}, ring_err
        }
        if len(rings) == 0 {
            return Geometry {}, Parse_Error {
                category = .Constraint_Violation,
                message = "Polygon must have at least one ring",
                path ="Polygon.coordinates",
            }
        }
        return Polygon { coordinates = rings, bbox = bbox }, Parse_Error { category = .None }

    case "MultiPolygon":
        coords, coords_ok := raw.coordinates.?
        if !coords_ok {
            return Geometry {}, Parse_Error {
                category = .Missing_Field,
                message = "MultiPolygon geometry missing coordinates field",
                path ="MultiPolygon.coordinates",
            }
        }
        polygons, poly_err := parse_polygon_array(coords)
        if poly_err.category != .None {
            poly_err.path ="MultiPolygon.coordinates"
            return Geometry {}, poly_err
        }
        return MultiPolygon { coordinates = polygons, bbox = bbox }, Parse_Error { category = .None }

    case "GeometryCollection":
        raw_geoms, geoms_ok := raw.geometries.?
        if !geoms_ok {
            return Geometry {}, Parse_Error {
                category = .Missing_Field,
                message = "GeometryCollection missing geometries array",
                path ="GeometryCollection.geometries",
            }
        }
        geometries := make([]Geometry, len(raw_geoms))
        for raw_geom, i in raw_geoms {
            geom, geom_err := raw_to_geometry(raw_geom)
            if geom_err.category != .None {
                return Geometry {}, Parse_Error {
                    category = .Invalid_Value,
                    message = "Failed to parse geometry in GeometryCollection",
                    path ="GeometryCollection.geometries",
                }
            }
            geometries[i] = geom
        }
        return GeometryCollection { geometries = geometries, bbox = bbox }, Parse_Error { category = .None }

    case:
        return Geometry {}, Parse_Error {
            category = .Unknown_Type,
            message = "Unknown geometry type",
            path ="type",
        }
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

parse_line_array :: proc(val: json.Value) -> ([][]Position, Parse_Error) {
    arr, arr_ok := val.(json.Array)
    if !arr_ok {
        return nil, Parse_Error {
            category = .Invalid_Type,
            message = "Expected array for LineString coordinates",
        }
    }
    lines := make([][]Position, len(arr))
    for elem, i in arr {
        line, line_ok := parse_position_array(elem)
        if !line_ok {
            return nil, Parse_Error {
                category = .Invalid_Value,
                message = "Failed to parse position array",
            }
        }
        // Each LineString must have at least 2 positions per RFC 7946
        if len(line) < 2 {
            return nil, Parse_Error {
                category = .Constraint_Violation,
                message = "LineString must have at least 2 positions",
            }
        }
        lines[i] = line
    }
    return lines, Parse_Error { category = .None }
}

parse_ring_array :: proc(val: json.Value) -> ([]LinearRing, Parse_Error) {
    arr, arr_ok := val.(json.Array)
    if !arr_ok {
        return nil, Parse_Error {
            category = .Invalid_Type,
            message = "Expected array for LinearRing coordinates",
        }
    }
    rings := make([]LinearRing, len(arr))
    for elem, i in arr {
        positions, pos_ok := parse_position_array(elem)
        if !pos_ok {
            return nil, Parse_Error {
                category = .Invalid_Value,
                message = "Failed to parse position array",
            }
        }

        // Validate LinearRing constraints per RFC 7946
        if len(positions) < 4 {
            return nil, Parse_Error {
                category = .Constraint_Violation,
                message = "LinearRing must have at least 4 positions",
            }
        }

        // Check if ring is closed (first == last)
        first := positions[0]
        last := positions[len(positions)-1]
        if first[0] != last[0] || first[1] != last[1] || first[2] != last[2] {
            return nil, Parse_Error {
                category = .Constraint_Violation,
                message = "LinearRing must be closed (first and last positions must be identical)",
            }
        }

        rings[i] = LinearRing(positions)
    }
    return rings, Parse_Error { category = .None }
}

parse_polygon_array :: proc(val: json.Value) -> ([][]LinearRing, Parse_Error) {
    arr, arr_ok := val.(json.Array)
    if !arr_ok {
        return nil, Parse_Error {
            category = .Invalid_Type,
            message = "Expected array for Polygon coordinates",
        }
    }
    polygons := make([][]LinearRing, len(arr))
    for elem, i in arr {
        rings, err := parse_ring_array(elem)
        if err.category != .None {
            return nil, err
        }
        polygons[i] = rings
    }
    return polygons, Parse_Error { category = .None }
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
