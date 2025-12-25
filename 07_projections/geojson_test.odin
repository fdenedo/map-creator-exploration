package main

import "core:encoding/json"
import "core:testing"
import "core:log"

// ========================================
// GEOMETRY TESTS
// ========================================

@(test)
test_point_2d :: proc(t: ^testing.T) {
    // Point with 2D coordinates (longitude, latitude)
    json_data := `{
        "type": "Point",
        "coordinates": [100.0, 0.0]
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse Point")
    
    geom, is_geom := result.(Geometry)
    testing.expect(t, is_geom, "Result is not a Geometry")
    
    point, is_point := geom.(Point)
    testing.expect(t, is_point, "Geometry is not a Point")
    
    testing.expect_value(t, point.coordinates[0], 100.0)
    testing.expect_value(t, point.coordinates[1], 0.0)
    testing.expect_value(t, point.coordinates[2], 0.0) // No elevation
}

@(test)
test_point_3d :: proc(t: ^testing.T) {
    // Point with 3D coordinates (longitude, latitude, elevation)
    json_data := `{
        "type": "Point",
        "coordinates": [100.0, 0.0, 250.5]
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse Point with elevation")
    
    geom := result.(Geometry)
    point := geom.(Point)
    
    testing.expect_value(t, point.coordinates[0], 100.0)
    testing.expect_value(t, point.coordinates[1], 0.0)
    testing.expect_value(t, point.coordinates[2], 250.5)
}

@(test)
test_point_with_bbox :: proc(t: ^testing.T) {
    // Point with bounding box
    json_data := `{
        "type": "Point",
        "coordinates": [100.0, 0.0],
        "bbox": [100.0, 0.0, 100.0, 0.0]
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse Point with bbox")
    
    point := result.(Geometry).(Point)
    bbox, has_bbox := point.bbox.?
    testing.expect(t, has_bbox, "Point should have bbox")
    
    testing.expect_value(t, bbox.min_lon, 100.0)
    testing.expect_value(t, bbox.min_lat, 0.0)
    testing.expect_value(t, bbox.max_lon, 100.0)
    testing.expect_value(t, bbox.max_lat, 0.0)
}

@(test)
test_multipoint :: proc(t: ^testing.T) {
    // MultiPoint with multiple positions
    json_data := `{
        "type": "MultiPoint",
        "coordinates": [
            [100.0, 0.0],
            [101.0, 1.0]
        ]
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse MultiPoint")
    
    mp := result.(Geometry).(MultiPoint)
    testing.expect_value(t, len(mp.coordinates), 2)
    
    testing.expect_value(t, mp.coordinates[0][0], 100.0)
    testing.expect_value(t, mp.coordinates[0][1], 0.0)
    testing.expect_value(t, mp.coordinates[1][0], 101.0)
    testing.expect_value(t, mp.coordinates[1][1], 1.0)
}

@(test)
test_linestring :: proc(t: ^testing.T) {
    // LineString with 2 positions (minimum)
    json_data := `{
        "type": "LineString",
        "coordinates": [
            [100.0, 0.0],
            [101.0, 1.0]
        ]
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse LineString")
    
    ls := result.(Geometry).(LineString)
    testing.expect_value(t, len(ls.coordinates), 2)
    
    testing.expect_value(t, ls.coordinates[0][0], 100.0)
    testing.expect_value(t, ls.coordinates[1][0], 101.0)
}

@(test)
test_linestring_multiple_points :: proc(t: ^testing.T) {
    // LineString with multiple points
    json_data := `{
        "type": "LineString",
        "coordinates": [
            [100.0, 0.0],
            [101.0, 1.0],
            [102.0, 2.0],
            [103.0, 3.0]
        ]
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse LineString with multiple points")
    
    ls := result.(Geometry).(LineString)
    testing.expect_value(t, len(ls.coordinates), 4)
}

@(test)
test_multilinestring :: proc(t: ^testing.T) {
    // MultiLineString with two line strings
    json_data := `{
        "type": "MultiLineString",
        "coordinates": [
            [[100.0, 0.0], [101.0, 1.0]],
            [[102.0, 2.0], [103.0, 3.0]]
        ]
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse MultiLineString")
    
    mls := result.(Geometry).(MultiLineString)
    testing.expect_value(t, len(mls.coordinates), 2)
    testing.expect_value(t, len(mls.coordinates[0]), 2)
    testing.expect_value(t, len(mls.coordinates[1]), 2)
    
    testing.expect_value(t, mls.coordinates[0][0][0], 100.0)
    testing.expect_value(t, mls.coordinates[1][1][0], 103.0)
}

@(test)
test_polygon_simple :: proc(t: ^testing.T) {
    // Polygon with exterior ring only (no holes)
    json_data := `{
        "type": "Polygon",
        "coordinates": [
            [
                [100.0, 0.0],
                [101.0, 0.0],
                [101.0, 1.0],
                [100.0, 1.0],
                [100.0, 0.0]
            ]
        ]
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse simple Polygon")
    
    poly := result.(Geometry).(Polygon)
    testing.expect_value(t, len(poly.coordinates), 1) // Only exterior ring
    
    exterior_ring := poly.coordinates[0]
    testing.expect_value(t, len(exterior_ring), 5) // 4 corners + closing point
    
    // First and last positions should be identical (closed ring)
    testing.expect_value(t, exterior_ring[0][0], exterior_ring[4][0])
    testing.expect_value(t, exterior_ring[0][1], exterior_ring[4][1])
}

@(test)
test_polygon_with_hole :: proc(t: ^testing.T) {
    // Polygon with exterior ring and one interior ring (hole)
    json_data := `{
        "type": "Polygon",
        "coordinates": [
            [
                [100.0, 0.0],
                [101.0, 0.0],
                [101.0, 1.0],
                [100.0, 1.0],
                [100.0, 0.0]
            ],
            [
                [100.2, 0.2],
                [100.8, 0.2],
                [100.8, 0.8],
                [100.2, 0.8],
                [100.2, 0.2]
            ]
        ]
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse Polygon with hole")
    
    poly := result.(Geometry).(Polygon)
    testing.expect_value(t, len(poly.coordinates), 2) // Exterior + 1 hole
    
    exterior_ring := poly.coordinates[0]
    hole_ring := poly.coordinates[1]
    
    testing.expect_value(t, len(exterior_ring), 5)
    testing.expect_value(t, len(hole_ring), 5)
}

@(test)
test_multipolygon :: proc(t: ^testing.T) {
    // MultiPolygon with two polygons
    json_data := `{
        "type": "MultiPolygon",
        "coordinates": [
            [
                [
                    [102.0, 2.0],
                    [103.0, 2.0],
                    [103.0, 3.0],
                    [102.0, 3.0],
                    [102.0, 2.0]
                ]
            ],
            [
                [
                    [100.0, 0.0],
                    [101.0, 0.0],
                    [101.0, 1.0],
                    [100.0, 1.0],
                    [100.0, 0.0]
                ]
            ]
        ]
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse MultiPolygon")
    
    mp := result.(Geometry).(MultiPolygon)
    testing.expect_value(t, len(mp.coordinates), 2) // Two polygons
    
    // Each polygon has one ring (exterior only)
    testing.expect_value(t, len(mp.coordinates[0]), 1)
    testing.expect_value(t, len(mp.coordinates[1]), 1)
    
    // Each ring has 5 positions
    testing.expect_value(t, len(mp.coordinates[0][0]), 5)
    testing.expect_value(t, len(mp.coordinates[1][0]), 5)
}

@(test)
test_geometry_collection :: proc(t: ^testing.T) {
    // GeometryCollection with Point and LineString
    json_data := `{
        "type": "GeometryCollection",
        "geometries": [
            {
                "type": "Point",
                "coordinates": [100.0, 0.0]
            },
            {
                "type": "LineString",
                "coordinates": [
                    [101.0, 0.0],
                    [102.0, 1.0]
                ]
            }
        ]
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse GeometryCollection")
    
    gc := result.(Geometry).(GeometryCollection)
    testing.expect_value(t, len(gc.geometries), 2)
    
    // First geometry should be a Point
    point, is_point := gc.geometries[0].(Point)
    testing.expect(t, is_point, "First geometry should be Point")
    testing.expect_value(t, point.coordinates[0], 100.0)
    
    // Second geometry should be a LineString
    ls, is_ls := gc.geometries[1].(LineString)
    testing.expect(t, is_ls, "Second geometry should be LineString")
    testing.expect_value(t, len(ls.coordinates), 2)
}

// ========================================
// FEATURE TESTS
// ========================================

@(test)
test_feature_with_point :: proc(t: ^testing.T) {
    // Feature with a Point geometry and properties
    json_data := `{
        "type": "Feature",
        "geometry": {
            "type": "Point",
            "coordinates": [125.6, 10.1]
        },
        "properties": {
            "name": "Test Point"
        }
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse Feature")
    
    feature := result.(Feature)
    
    // Check geometry
    point := feature.geometry.(Point)
    testing.expect_value(t, point.coordinates[0], 125.6)
    testing.expect_value(t, point.coordinates[1], 10.1)
    
    // Check properties
    testing.expect(t, feature.properties != nil, "Properties should not be nil")
    name_value := feature.properties["name"]
    name := name_value.(json.String)
    testing.expect_value(t, string(name), "Test Point")
}

@(test)
test_feature_with_string_id :: proc(t: ^testing.T) {
    // Feature with string ID
    json_data := `{
        "type": "Feature",
        "id": "feature-123",
        "geometry": {
            "type": "Point",
            "coordinates": [0.0, 0.0]
        },
        "properties": {}
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse Feature with string ID")
    
    feature := result.(Feature)
    id, has_id := feature.id.?
    testing.expect(t, has_id, "Feature should have ID")
    
    id_str, is_string := id.(string)
    testing.expect(t, is_string, "ID should be string")
    testing.expect_value(t, id_str, "feature-123")
}

@(test)
test_feature_with_numeric_id :: proc(t: ^testing.T) {
    // Feature with numeric ID
    json_data := `{
        "type": "Feature",
        "id": 42,
        "geometry": {
            "type": "Point",
            "coordinates": [0.0, 0.0]
        },
        "properties": {}
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse Feature with numeric ID")
    
    feature := result.(Feature)
    id, has_id := feature.id.?
    testing.expect(t, has_id, "Feature should have ID")
    
    id_num, is_num := id.(f64)
    testing.expect(t, is_num, "ID should be number")
    testing.expect_value(t, id_num, 42.0)
}

@(test)
test_feature_without_id :: proc(t: ^testing.T) {
    // Feature without ID (optional per RFC 7946)
    json_data := `{
        "type": "Feature",
        "geometry": {
            "type": "Point",
            "coordinates": [0.0, 0.0]
        },
        "properties": {}
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse Feature without ID")
    
    feature := result.(Feature)
    _, has_id := feature.id.?
    testing.expect(t, !has_id, "Feature should not have ID")
}

@(test)
test_feature_with_null_geometry :: proc(t: ^testing.T) {
    // Feature with null geometry (unlocated feature per RFC 7946)
    json_data := `{
        "type": "Feature",
        "geometry": null,
        "properties": {
            "name": "Unlocated Feature"
        }
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse Feature with null geometry")
    
    feature := result.(Feature)
    
    // Geometry should be the zero value of the union
    // In Odin, we need to check if any variant is set
    // For now, we just verify the feature parsed successfully
    testing.expect(t, feature.properties != nil, "Properties should exist")
}

@(test)
test_feature_with_bbox :: proc(t: ^testing.T) {
    // Feature with bounding box
    json_data := `{
        "type": "Feature",
        "bbox": [100.0, 0.0, 105.0, 1.0],
        "geometry": {
            "type": "Point",
            "coordinates": [102.5, 0.5]
        },
        "properties": {}
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse Feature with bbox")
    
    feature := result.(Feature)
    bbox, has_bbox := feature.bbox.?
    testing.expect(t, has_bbox, "Feature should have bbox")
    
    testing.expect_value(t, bbox.min_lon, 100.0)
    testing.expect_value(t, bbox.min_lat, 0.0)
    testing.expect_value(t, bbox.max_lon, 105.0)
    testing.expect_value(t, bbox.max_lat, 1.0)
}

// ========================================
// FEATURECOLLECTION TESTS
// ========================================

@(test)
test_feature_collection_simple :: proc(t: ^testing.T) {
    // FeatureCollection with two features
    json_data := `{
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "geometry": {
                    "type": "Point",
                    "coordinates": [102.0, 0.5]
                },
                "properties": {
                    "prop0": "value0"
                }
            },
            {
                "type": "Feature",
                "geometry": {
                    "type": "LineString",
                    "coordinates": [
                        [102.0, 0.0],
                        [103.0, 1.0]
                    ]
                },
                "properties": {
                    "prop1": "value1"
                }
            }
        ]
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse FeatureCollection")
    
    fc := result.(FeatureCollection)
    testing.expect_value(t, len(fc.features), 2)
    
    // First feature has Point geometry
    point := fc.features[0].geometry.(Point)
    testing.expect_value(t, point.coordinates[0], 102.0)
    
    // Second feature has LineString geometry
    ls := fc.features[1].geometry.(LineString)
    testing.expect_value(t, len(ls.coordinates), 2)
}

@(test)
test_feature_collection_empty :: proc(t: ^testing.T) {
    // FeatureCollection with no features
    json_data := `{
        "type": "FeatureCollection",
        "features": []
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse empty FeatureCollection")
    
    fc := result.(FeatureCollection)
    testing.expect_value(t, len(fc.features), 0)
}

@(test)
test_feature_collection_with_bbox :: proc(t: ^testing.T) {
    // FeatureCollection with bounding box
    json_data := `{
        "type": "FeatureCollection",
        "bbox": [100.0, 0.0, 105.0, 1.0],
        "features": [
            {
                "type": "Feature",
                "geometry": {
                    "type": "Point",
                    "coordinates": [102.0, 0.5]
                },
                "properties": {}
            }
        ]
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse FeatureCollection with bbox")
    
    fc := result.(FeatureCollection)
    bbox, has_bbox := fc.bbox.?
    testing.expect(t, has_bbox, "FeatureCollection should have bbox")
    
    testing.expect_value(t, bbox.min_lon, 100.0)
    testing.expect_value(t, bbox.max_lat, 1.0)
}

// ========================================
// BOUNDING BOX TESTS
// ========================================

@(test)
test_bbox_2d :: proc(t: ^testing.T) {
    // 2D bounding box (4 values)
    json_data := `{
        "type": "Point",
        "coordinates": [100.0, 0.0],
        "bbox": [100.0, 0.0, 100.0, 0.0]
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse with 2D bbox")
    
    point := result.(Geometry).(Point)
    bbox, has_bbox := point.bbox.?
    testing.expect(t, has_bbox, "Should have bbox")
    
    testing.expect_value(t, bbox.min_lon, 100.0)
    testing.expect_value(t, bbox.min_lat, 0.0)
    testing.expect_value(t, bbox.max_lon, 100.0)
    testing.expect_value(t, bbox.max_lat, 0.0)
    
    _, has_min_elev := bbox.min_elevation.?
    _, has_max_elev := bbox.max_elevation.?
    testing.expect(t, !has_min_elev, "2D bbox should not have min elevation")
    testing.expect(t, !has_max_elev, "2D bbox should not have max elevation")
}

@(test)
test_bbox_3d :: proc(t: ^testing.T) {
    // 3D bounding box (6 values)
    json_data := `{
        "type": "Point",
        "coordinates": [100.0, 0.0, 50.0],
        "bbox": [100.0, 0.0, 45.0, 100.0, 0.0, 55.0]
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse with 3D bbox")
    
    point := result.(Geometry).(Point)
    bbox, has_bbox := point.bbox.?
    testing.expect(t, has_bbox, "Should have bbox")
    
    min_elev, has_min := bbox.min_elevation.?
    max_elev, has_max := bbox.max_elevation.?
    testing.expect(t, has_min, "3D bbox should have min elevation")
    testing.expect(t, has_max, "3D bbox should have max elevation")
    
    testing.expect_value(t, min_elev, 45.0)
    testing.expect_value(t, max_elev, 55.0)
}

// ========================================
// ERROR CASE TESTS
// ========================================

@(test)
test_invalid_json :: proc(t: ^testing.T) {
    // Invalid JSON syntax - suppress error logging for negative test
    old_logger := context.logger
    context.logger = log.nil_logger()
    defer context.logger = old_logger
    
    json_data := `{type": "Point"}`
    
    _, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, !ok, "Should fail on invalid JSON")
}

@(test)
test_missing_type_field :: proc(t: ^testing.T) {
    // Missing "type" field - suppress error logging for negative test
    old_logger := context.logger
    context.logger = log.nil_logger()
    defer context.logger = old_logger
    
    json_data := `{
        "coordinates": [100.0, 0.0]
    }`
    
    _, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, !ok, "Should fail on missing type field")
}

@(test)
test_unknown_geometry_type :: proc(t: ^testing.T) {
    // Unknown geometry type - suppress error logging for negative test
    old_logger := context.logger
    context.logger = log.nil_logger()
    defer context.logger = old_logger
    
    json_data := `{
        "type": "UnknownGeometry",
        "coordinates": [100.0, 0.0]
    }`
    
    _, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, !ok, "Should fail on unknown geometry type")
}

@(test)
test_linestring_with_one_point :: proc(t: ^testing.T) {
    // LineString must have at least 2 positions - suppress error logging for negative test
    old_logger := context.logger
    context.logger = log.nil_logger()
    defer context.logger = old_logger
    
    json_data := `{
        "type": "LineString",
        "coordinates": [[100.0, 0.0]]
    }`
    
    _, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, !ok, "Should fail on LineString with only 1 point")
}

@(test)
test_point_missing_coordinates :: proc(t: ^testing.T) {
    // Point without coordinates - suppress error logging for negative test
    old_logger := context.logger
    context.logger = log.nil_logger()
    defer context.logger = old_logger
    
    json_data := `{
        "type": "Point"
    }`
    
    _, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, !ok, "Should fail on Point missing coordinates")
}

@(test)
test_position_with_one_value :: proc(t: ^testing.T) {
    // Position must have at least 2 values (lon, lat) - suppress error logging for negative test
    old_logger := context.logger
    context.logger = log.nil_logger()
    defer context.logger = old_logger
    
    json_data := `{
        "type": "Point",
        "coordinates": [100.0]
    }`
    
    _, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, !ok, "Should fail on position with only 1 value")
}

// ========================================
// REAL-WORLD EXAMPLE TESTS
// ========================================

@(test)
test_real_world_feature_collection :: proc(t: ^testing.T) {
    // Realistic FeatureCollection with mixed geometry types
    json_data := `{
        "type": "FeatureCollection",
        "features": [
            {
                "type": "Feature",
                "id": "city-1",
                "geometry": {
                    "type": "Point",
                    "coordinates": [-122.4194, 37.7749]
                },
                "properties": {
                    "name": "San Francisco",
                    "population": 883305
                }
            },
            {
                "type": "Feature",
                "id": 2,
                "geometry": {
                    "type": "Polygon",
                    "coordinates": [
                        [
                            [-122.5, 37.7],
                            [-122.3, 37.7],
                            [-122.3, 37.9],
                            [-122.5, 37.9],
                            [-122.5, 37.7]
                        ]
                    ]
                },
                "properties": {
                    "name": "Bay Area Region",
                    "area_km2": 1000.0
                }
            }
        ]
    }`
    
    result, ok := parse_geojson(transmute([]byte)json_data)
    testing.expect(t, ok, "Failed to parse real-world FeatureCollection")
    
    fc := result.(FeatureCollection)
    testing.expect_value(t, len(fc.features), 2)
    
    // Check first feature (Point with string ID)
    f1 := fc.features[0]
    f1_id, has_id := f1.id.?
    testing.expect(t, has_id, "First feature should have ID")
    id_str := f1_id.(string)
    testing.expect_value(t, id_str, "city-1")
    
    point := f1.geometry.(Point)
    testing.expect_value(t, point.coordinates[0], -122.4194)
    
    // Check second feature (Polygon with numeric ID)
    f2 := fc.features[1]
    f2_id, has_id2 := f2.id.?
    testing.expect(t, has_id2, "Second feature should have ID")
    id_num := f2_id.(f64)
    testing.expect_value(t, id_num, 2.0)
    
    poly := f2.geometry.(Polygon)
    testing.expect_value(t, len(poly.coordinates), 1) // One ring
    testing.expect_value(t, len(poly.coordinates[0]), 5) // 5 positions (closed)
}
