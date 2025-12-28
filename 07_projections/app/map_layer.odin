package app

import "../core"
import proj "../core/projection"
import "../core/geojson"
import "../platform"

MapLayer :: struct {
    camera: proj.Camera,
    projection: proj.Projection,
    data: geojson.GeoJSON,
    data_projected_cache: geojson.GeoJSON_Projected,
    line_buffer: [dynamic]core.WorldVec2, // Scratch buffer for collecting line segments

    drag_start_geo: Maybe(proj.GeoCoord),      // Geo coord where drag started
    drag_start_centre: proj.GeoCoord,          // Projection centre when drag started

    camera_dirty: bool,
    projection_dirty: bool,
}

map_layer_create :: proc(self: ^MapLayer) {
    self.camera = proj.create_camera()
    self.projection = proj.Projection { type = .Equirectangular }
    self.camera_dirty = true
    self.projection_dirty = true
}

map_layer_update :: proc(self: ^MapLayer) {
    // Fit camera to show the entire projection bounds (the "canvas")
    if self.camera_dirty {
        bounds := proj.get_bounds(self.projection)
        proj.camera_fit_to_bounds(&self.camera, bounds)
        self.camera_dirty = false
    }

    // Project GeoJSON data to world coordinates
    if self.projection_dirty {
        self.data_projected_cache = geojson.project_geojson(self.data, self.projection)
        self.projection_dirty = false
    }
}

map_layer_render :: proc(self: ^MapLayer, render_state: ^platform.RenderState) {
    view_proj := proj.view_proj_matrix(self.camera)
    uniforms := platform.make_uniforms(view_proj)

    // Collect all line segments from polygons (drawing outlines only for now)
    clear(&self.line_buffer)
    collect_polygon_lines(&self.line_buffer, self.data_projected_cache.polygons)
    collect_lines(&self.line_buffer, self.data_projected_cache.lines)

    platform.line_renderer_update(&render_state.line_renderer, self.line_buffer[:])
    platform.line_renderer_draw(&render_state.line_renderer, &uniforms, 1.0)
}

map_layer_on_event :: proc(self: ^MapLayer, event: ^platform.Event) -> (handled: bool) {
    #partial switch event.type {
    case .MOUSE_DOWN:
        screen_pos := core.ScreenVec2 { event.mouse_x, event.mouse_y }
        world_pos := proj.screen_to_world(screen_pos, self.camera, true)
        geo, valid := proj.inverse_f32(world_pos, self.projection)
        if valid {
            self.drag_start_geo = geo
            self.drag_start_centre = self.projection.centre
        }
        return true

    case .MOUSE_MOVE:
        if drag_start, ok := self.drag_start_geo.?; ok {
            screen_pos := core.ScreenVec2 { event.mouse_x, event.mouse_y }
            world_pos := proj.screen_to_world(screen_pos, self.camera, true)
            original_proj := proj.Projection { centre = self.drag_start_centre, type = self.projection.type }
            drag_current, valid := proj.inverse_f32(world_pos, original_proj)
            if valid {
                delta := drag_current - drag_start
                new_centre := self.drag_start_centre - delta
                self.projection.centre = proj.clamp_centre_to_view(new_centre, self.camera, self.projection.type)
                self.projection_dirty = true
            }
            return true
        }

    case .MOUSE_UP:
        self.drag_start_geo = nil
        return true

    case .MOUSE_SCROLL:
        self.camera.zoom += event.scroll_y * 0.1
        self.camera.zoom = min(20.0, max(self.camera.zoom, 0.5))
        self.camera_dirty = true
        return true
    }

    return false
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
