package main

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
    id: Maybe(json.Value),
    geometry: Maybe(Raw_Geometry),
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

FeatureCollection :: struct {
    features: []Feature
}

Feature :: struct {
    id: Maybe(string),
    geometry: Geometry,
    properties: string, // Placeholder, should deal with any JSON object
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
    // An array of LineString coordinate arrays, represented as an array of LineStrings
    coordinates: []LineString,
    bbox: Maybe(BoundingBox),
}

// A LinearRing is a LineString that conforms to the following contraints:
// - it has 4 or more positions
// - the first and last position are equivalent (exactly identical)
// - it follows the right-hand rule with respect to the area it bounds (exterior ->
// anticlockwise, interior -> clockwise)
//
// Note that for older specifications, linear ring winding order was not specified,
// so for backwards compatibility LinearRings that don't conform to this rule aren't
// rejected, but should be dealt with gracefully
LinearRing :: distinct LineString

Polygon :: struct {
    // An array of linear rings where:
    // - the first is the exterior ring
    // - the proceeding (0 or more) rings are the interior rings
    coordinates: []LinearRing,
    bbox: Maybe(BoundingBox),
}

MultiPolygon :: struct {
    coordinates: []Polygon,
    bbox: Maybe(BoundingBox),
}

GeometryCollection :: struct {
    geometries: []Geometry,
    bbox: Maybe(BoundingBox),
}

Position :: [3]f64
