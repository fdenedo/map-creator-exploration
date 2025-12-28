package app

import "../core"
import "../core/projection"
import "../core/geojson"
import "../platform"

map_layer_update :: proc(self: ^MapLayer) {
    // Only running this on init right now, need to change this
    self.camera = projection.create_camera()
    projection.camera_update_aspect_ratio(&self.camera)
    self.data_projected_cache = geojson.project_geojson(self.data, self.projection) // Don't do this every frame
}

map_layer_render :: proc(self: ^MapLayer, render_state: ^platform.RenderState) {
    view_proj := projection.view_proj_matrix(self.camera)
    uniforms := platform.make_uniforms(view_proj)

    // Collect all line segments from polygons (drawing outlines only for now)
    clear(&self.line_buffer)
    collect_polygon_lines(&self.line_buffer, self.data_projected_cache.polygons)
    collect_lines(&self.line_buffer, self.data_projected_cache.lines)

    // Update and draw
    platform.line_renderer_update(&render_state.line_renderer, self.line_buffer[:])
    platform.line_renderer_draw(&render_state.line_renderer, &uniforms, 1.0)
}

// Converts polygon rings into line segments for the line renderer
collect_polygon_lines :: proc(buffer: ^[dynamic]core.WorldVec2, polygons: [][][][2]f32) {
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
collect_lines :: proc(buffer: ^[dynamic]core.WorldVec2, lines: [][][2]f32) {
    for line in lines {
        if len(line) < 2 do continue
        for i in 0..<len(line) - 1 {
            append(buffer, line[i])
            append(buffer, line[i + 1])
        }
    }
}
