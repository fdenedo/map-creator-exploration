package main

import "core:encoding/json"
import "core:path/filepath"
import "core:log"
import "core:os"

DATA_DIR :: #directory // For the dir of the current file

main :: proc() {
    context.logger = log.create_console_logger()

    full_path := filepath.join({DATA_DIR, "ne_110m_land.geojson"})
    data, ok := os.read_entire_file(full_path)

    log.debug("File path: ", full_path)
    if !ok {
        log.error("Could not read file")
        return
    }

    // Parse as Raw FeatureCollection
    collection: Raw_FeatureCollection
    json := json.unmarshal(data, &collection)

    log.debug(collection)
    log.debug("Error: ", json)
}
