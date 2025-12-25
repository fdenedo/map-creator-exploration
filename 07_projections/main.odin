package main

import "base:runtime"
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

    geojson, success_parse := parse_geojson(data)
    log.debug(geojson)
}
