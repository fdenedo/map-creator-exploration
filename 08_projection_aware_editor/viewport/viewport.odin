package viewport

import doc 		"../core/document"
import platform "../platform"
import proj		"../core/projection"
import geojson "../core/geojson"

Viewport :: struct {
	camera: proj.Camera,
	projection: proj.Projection,
	document: ^doc.Document,

	// TODO: put these in places where they make more sense, or at least organise them...
	vector_line_buffer: [dynamic][2]f32,
	geojson_projected_cache: geojson.GeoJSON_Projected,
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

	case doc.GeoJSON:
		view.geojson_projected_cache = geojson.project_geojson(&data.data, view.projection) // TODO: move to viewport update, check for change
		view_proj := proj.view_proj_matrix(view.camera)
	    uniforms := platform.make_uniforms(view_proj)

	    clear(&view.vector_line_buffer)
	    geojson_collect_polygon_lines(&view.vector_line_buffer, view.geojson_projected_cache.polygons)
	    geojson_collect_lines(&view.vector_line_buffer, view.geojson_projected_cache.lines)

	    platform.line_renderer_update(&view.render_cache.line_renderer, view.vector_line_buffer[:])
	    platform.line_renderer_draw(&view.render_cache.line_renderer, &uniforms, 1.0)
	}
}

// Converts polygon rings into line segments for the line renderer
geojson_collect_polygon_lines :: proc(buffer: ^[dynamic][2]f32, polygons: [][][][2]f32) {
    for polygon in polygons {
        for ring in polygon {
            if len(ring) < 2 do continue
            // Each ring is a closed loop - connect consecutive points
            for i in 0..<len(ring) - 1 {
                append(buffer, ring[i])
                append(buffer, ring[i + 1])
            }
        }
    }
}

// Converts line strings into line segments for the line renderer
geojson_collect_lines :: proc(buffer: ^[dynamic][2]f32, lines: [][][2]f32) {
    for line in lines {
        if len(line) < 2 do continue
        for i in 0..<len(line) - 1 {
            append(buffer, line[i])
            append(buffer, line[i + 1])
        }
    }
}
