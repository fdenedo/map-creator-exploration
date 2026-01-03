package viewport

import "core:math"

import core     "../core"
import doc 		"../core/document"
import platform "../platform"
import proj		"../core/projection"
import geojson  "../core/geojson"

Viewport :: struct {
	camera: proj.Camera,
	projection: proj.Projection,
	document: ^doc.Document,

	// TODO: put these in places where they make more sense, or at least organise them...
	vector_line_buffer: [dynamic]core.WorldVec2,
	render_cache: platform.RenderState,
}

viewport_create :: proc(doc: ^doc.Document) -> Viewport {
	return Viewport {
		camera = proj.create_camera(),
		projection = proj.Projection {
			centre = { 0.0, 0.0 },
			type = .Orthographic,
		},
		document = doc,
	}
}

viewport_update :: proc(viewport: ^Viewport) {}

render_init :: proc(viewport: ^Viewport) {
	platform.render_init(&viewport.render_cache)
}

render :: proc(viewport: ^Viewport, document: ^doc.Document) {
	for &doc_layer in viewport.document.layers {
		render_document_layer(viewport, &doc_layer)
	}
}

render_document_layer :: proc(view: ^Viewport, layer: ^doc.DocumentLayer) {
	switch &data in layer.data {
	case doc.Vector:
		// TODO: implement vector rendering

	case doc.GeoJSON:
		render_geojson_sphere(view, &data.data)
	}
}

// ============================================================================
// Sphere Pipeline
// ============================================================================

SUBDIVISION_TOLERANCE :: 0.005  // in world units (orthographic is -1 to 1)

// Process a ring of positions through the sphere pipeline
// Returns projected 2D points ready for rendering
process_ring_sphere :: proc(
    positions: []geojson.Position,
    view: ^Viewport,
    rotation: proj.Mat3,
) -> []core.WorldVec2 {
    if len(positions) < 2 do return nil

    // 1. Convert to sphere coordinates
    sphere_points := make([dynamic]proj.Vec3, 0, len(positions))
    defer delete(sphere_points)

    for pos in positions {
        geo := proj.GeoCoord {
            f32(pos[0]) * math.RAD_PER_DEG,
            f32(pos[1]) * math.RAD_PER_DEG,
        }
        append(&sphere_points, proj.geo_to_sphere(geo))
    }

    // 2. Rotate to view space
    view_points := proj.rotate_to_view_space(sphere_points[:], rotation)
    defer delete(view_points)

    // 3. Check visibility (only relevant for projections with occlusion)
    clipped: []proj.Vec3
    did_clip := false
    defer if did_clip do delete(clipped)

    if view.projection.type == .Orthographic {
        visibility := proj.polygon_visibility(view_points)
        if visibility == .Occluded do return nil

        // 4. Clip if partially visible
        if visibility == .Partial {
            clipped = proj.clip_polygon_to_hemisphere(view_points)
            did_clip = true
        } else {
            clipped = view_points
        }
    } else {
        // For Equirectangular, no clipping needed
        clipped = view_points
    }

    if len(clipped) < 2 do return nil

    // 5. Subdivide for great circle arcs
    subdivided := proj.subdivide_polygon(clipped, view.projection.type, SUBDIVISION_TOLERANCE)
    defer delete(subdivided)

    if len(subdivided) < 2 do return nil

    // 6. Project to 2D
    result := make([]core.WorldVec2, len(subdivided))
    for p, i in subdivided {
        result[i] = proj.project_view_to_2d(p, view.projection.type)
    }

    return result
}

// Collect line segments from a processed ring into the line buffer
collect_ring_lines :: proc(buffer: ^[dynamic]core.WorldVec2, ring: []core.WorldVec2) {
    if len(ring) < 2 do return
    for i in 0..<len(ring) {
        next := (i + 1) % len(ring)
        append(buffer, ring[i])
        append(buffer, ring[next])
    }
}

// Render GeoJSON data through the sphere pipeline
render_geojson_sphere :: proc(view: ^Viewport, data: ^geojson.GeoJSON) {
    clear(&view.vector_line_buffer)

    // Build rotation matrix once for all geometry
    rotation := proj.build_view_rotation_matrix(view.projection.centre)

    // Process all geometry in the GeoJSON
    switch &d in data {
    case geojson.FeatureCollection:
        for &feature in d.features {
            process_geometry_sphere(view, &feature.geometry, rotation)
        }
    case geojson.Feature:
        process_geometry_sphere(view, &d.geometry, rotation)
    case geojson.Geometry:
        process_geometry_sphere(view, &d, rotation)
    }

    // Render the collected lines
    view_proj := proj.view_proj_matrix(view.camera)
    uniforms := platform.make_uniforms(view_proj)
    platform.line_renderer_update(&view.render_cache.line_renderer, view.vector_line_buffer[:])
    platform.line_renderer_draw(&view.render_cache.line_renderer, &uniforms, 1.0)
}

// Process a single geometry through the sphere pipeline
process_geometry_sphere :: proc(view: ^Viewport, geom: ^geojson.Geometry, rotation: proj.Mat3) {
    if geom == nil do return

    switch g in geom {
    case geojson.Point:
        // Points don't need subdivision, skip for now

    case geojson.MultiPoint:
        // Points don't need subdivision, skip for now

    case geojson.LineString:
        projected := process_ring_sphere(g.coordinates, view, rotation)
        if projected != nil {
            collect_ring_lines(&view.vector_line_buffer, projected)
            delete(projected)
        }

    case geojson.MultiLineString:
        for line in g.coordinates {
            projected := process_ring_sphere(line, view, rotation)
            if projected != nil {
                collect_ring_lines(&view.vector_line_buffer, projected)
                delete(projected)
            }
        }

    case geojson.Polygon:
        for ring in g.coordinates {
            projected := process_ring_sphere(([]geojson.Position)(ring), view, rotation)
            if projected != nil {
                collect_ring_lines(&view.vector_line_buffer, projected)
                delete(projected)
            }
        }

    case geojson.MultiPolygon:
        for polygon in g.coordinates {
            for ring in polygon {
                projected := process_ring_sphere(([]geojson.Position)(ring), view, rotation)
                if projected != nil {
                    collect_ring_lines(&view.vector_line_buffer, projected)
                    delete(projected)
                }
            }
        }

    case geojson.GeometryCollection:
        for &child in g.geometries {
            process_geometry_sphere(view, &child, rotation)
        }
    }
}
