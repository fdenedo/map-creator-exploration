package main

import "app"
import "core/geojson"
import "platform"

import "base:runtime"
import "core:log"
import "core:mem/virtual"
import "core:os"
import "core:path/filepath"

DATA_DIR :: #directory // For the dir of the current file

// GLOBALS
default_context: runtime.Context
current_app: app.Application
render_state: platform.RenderState

main :: proc() {
    context.logger = log.create_console_logger()
    default_context = context

    config := platform.WindowConfig {
        title = "07 Projections",
        width = 800,
        height = 600,
    }

    current_app   = app.create()
    geojson_data := parse_geojson_file("ne_50m_land.geojson")

    // For debugging
    g_as_fc := geojson_data.(geojson.FeatureCollection)
    log.infof("Parsed FeatureCollection with %d features", len(g_as_fc.features))

    app.add_layer(&current_app, app.MapLayer { data = geojson_data })
    platform.window_run(
        config,
        {
            init = init,
            frame = frame,
            cleanup = cleanup,
            event = event,
        },
        &default_context)
}

parse_geojson_file :: proc(resource_name: string) -> geojson.GeoJSON {
    full_path := filepath.join({DATA_DIR, "resources", resource_name})
    data, ok := os.read_entire_file(full_path)

    log.debug("File path: ", full_path)
    if !ok {
        log.error("Could not read file")
        panic("Aborted as file not read")
    }

    // Set up a larger temp allocator for JSON parsing intermediates
    // The default temp_allocator is small; large GeoJSON files need more space
    temp_arena: virtual.Arena
    if virtual.arena_init_growing(&temp_arena) != .None {
        log.error("Failed to initialise temp arena")
        panic("Aborted as temp arena not initialised")
    }
    defer virtual.arena_destroy(&temp_arena)
    old_temp_allocator := context.temp_allocator
    context.temp_allocator = virtual.arena_allocator(&temp_arena)
    defer context.temp_allocator = old_temp_allocator

    // parse_geojson uses temp_allocator internally for JSON intermediate processing
    // Final domain types use context.allocator (default heap allocator)
    g, err := geojson.parse_geojson(data)
    if err.category != .None {
        if err.path != "" {
            log.errorf("Failed to parse GeoJSON at %s: %s", err.path, err.message)
        } else {
            log.errorf("Failed to parse GeoJSON: %s", err.message)
        }
        panic("Aborted as file not able to be parsed")
    }

    return g
}

init :: proc "c" () {
    context = default_context

    platform.window_setup(&default_context)
    platform.render_init(&render_state)
}

frame :: proc "c" () {
    context = default_context

    app.update(&current_app, 0.0) // Note: not currently using dt

    platform.render_begin_frame(&render_state)
    app.render(&current_app, &render_state)
    platform.render_end_frame(&render_state)
}

cleanup :: proc "c" () {
    context = default_context

    platform.window_shutdown()
}

event :: proc "c" (e: ^platform.Event) {
    context = default_context

    app.on_event(&current_app, e)
}
