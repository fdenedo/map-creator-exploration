package geojson

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:mem/virtual"

GeoJsonLoadError :: struct {
	category: GeoJsonLoadErrorCategory,
	message: string,
	geojson_parse_error: Maybe(GeoJsonParseError)
}

GeoJsonLoadErrorCategory :: enum {
	None,
	FileCouldNotBeRead,
	TempArenaAllocFailed,
	GeoJsonParseFailed,
}

GeoJsonLoadSuccess :: GeoJsonLoadError { category = .None }

load_and_parse_geojson_file :: proc(filepath: string) -> (geo: GeoJSON, err: GeoJsonLoadError) {
    data, ok := os.read_entire_file(filepath)
    if !ok {
    	return geo, GeoJsonLoadError {
     		category = .FileCouldNotBeRead,
       		message = strings.concatenate({ "File at ", filepath, " could not be read" }),
     	}
    }

    temp_arena: virtual.Arena
    if virtual.arena_init_growing(&temp_arena) != .None {
    	return geo, GeoJsonLoadError {
     		category = .TempArenaAllocFailed,
       		message = "Temp arena allocation failed while trying to load GeoJSON file",
     	}
    }
    defer virtual.arena_destroy(&temp_arena)
    context.temp_allocator = virtual.arena_allocator(&temp_arena)

    g, parse_err := parse_geojson(data)
    if parse_err.category != .None {
    	return g, GeoJsonLoadError {
   			category = .GeoJsonParseFailed,
      		message = strings.concatenate({ "Failed to parse file at ", filepath, " as GeoJSON" }),
       		geojson_parse_error = parse_err
     	}
    }

    return g, GeoJsonLoadSuccess
}
