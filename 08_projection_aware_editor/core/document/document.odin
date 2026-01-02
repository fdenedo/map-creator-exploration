package document

import "core:mem/virtual"

import "../geojson"

Document :: struct {
	arena: virtual.Arena,
	layers: [dynamic]DocumentLayer,
	active: int, // Set to -1 to deactivate all layers, only 1 can be active at a time
	// TODO: determine if active layer is a higher concept, owned by the Editor
}

DocumentLayer :: struct {
	visible: bool,
	data: LayerData,
}

LayerData :: union {
	Vector,
	GeoJSON,
}

Vector :: struct {
	paths: [dynamic]Path,
}

Path :: struct {
	points: [dynamic]Point,
	closed: bool,
}

Point :: struct {
	anchor: [2]f32,
	control_in: [2]f32,
	control_out: [2]f32,
}

GeoJSON :: struct {
	data: geojson.GeoJSON,
}

document_create :: proc() -> (doc: Document, error: string) {
	if virtual.arena_init_growing(&doc.arena) != .None {
		return doc, "Arena Init Failed - MAKE AN ERROR TYPE"
	}
	context.allocator = virtual.arena_allocator(&doc.arena)

	doc.layers = make([dynamic]DocumentLayer)
	return doc, ""
}

document_deactivate_all_layers :: proc(doc: ^Document) {
	doc.active = -1
}

document_add_layer :: proc(doc: ^Document, make_active: bool, init_data: LayerData = Vector {}) {
	append(&doc.layers, DocumentLayer {
		visible = true,
		data = init_data
	})
	if make_active {
		doc.active = len(doc.layers) - 1
	}
}

document_destroy :: proc(document: ^Document) {
	virtual.arena_destroy(&document.arena)
}
