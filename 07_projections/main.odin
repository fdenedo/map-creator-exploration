package main

import "geojson"
import "base:runtime"
import "core:mem/virtual"
import "core:path/filepath"
import "core:log"
import "core:os"


DATA_DIR :: #directory // For the dir of the current file

default_context: runtime.Context

main :: proc() {
    context.logger = log.create_console_logger()
    default_context = context

    full_path := filepath.join({DATA_DIR, "ne_110m_land.geojson"})
    data, ok := os.read_entire_file(full_path)

    log.debug("File path: ", full_path)
    if !ok {
        log.error("Could not read file")
        return
    }

    // Set up a larger temp allocator for JSON parsing intermediates
    // The default temp_allocator is small; large GeoJSON files need more space
    temp_arena: virtual.Arena
    if virtual.arena_init_growing(&temp_arena) != .None {
        log.error("Failed to initialize temp arena")
        return
    }
    defer virtual.arena_destroy(&temp_arena)
    context.temp_allocator = virtual.arena_allocator(&temp_arena)

    // parse_geojson uses temp_allocator internally for JSON intermediate processing
    // Final domain types use context.allocator (default heap allocator)
    g, err := geojson.parse_geojson(data)
    if err.category != .None {
        if err.path != "" {
            log.errorf("Failed to parse GeoJSON at %s: %s", err.path, err.message)
        } else {
            log.errorf("Failed to parse GeoJSON: %s", err.message)
        }
        return
    }

    fc := g.(geojson.FeatureCollection)
    log.infof("Parsed FeatureCollection with %d features", len(fc.features))
}
