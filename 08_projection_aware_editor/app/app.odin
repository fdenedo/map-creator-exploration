package app

import "core:log"
import "core:path/filepath"

import doc 	"../core/document"
import ui   "../ui"
import view "../viewport"
import geo	"../core/geojson"

Application :: struct {
	document: doc.Document,
	viewport: view.Viewport,
	ui:		  ui.UI,
}

app_init :: proc(app: ^Application) {
    app.document, _ = doc.document_create()

    current_dir := #directory
    filepath := filepath.join({current_dir, "ne_50m_land.geojson"})
    loaded_geojson, err := geo.load_and_parse_geojson_file(filepath)
    if err.category != .None {
     	log.error(err)
    }

    // add layer with data
    doc.document_add_layer(
    	&app.document,
	    true,
	    doc.GeoJSON { loaded_geojson }
    )

    app.viewport = view.viewport_create(&app.document)
    app.ui = ui.ui_create()
    // app.active_tool = create_pen_tool()
}
