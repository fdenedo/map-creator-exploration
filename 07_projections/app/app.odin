package app

Application :: struct {
    layers: [dynamic]Layer,
}

create :: proc() -> Application {
    return Application {
        layers = make([dynamic]Layer),
    }
}

add_layer :: proc(app: ^Application, layer: Layer) {
    append(&app.layers, layer)
}

update :: proc(app: ^Application, dt: f32) {
    for &layer in app.layers {
        layer_update(&layer)
    }
}

render :: proc(app: ^Application) {
    for &layer in app.layers {
        layer_render(&layer)
    }
}

layer_update :: proc(layer: ^Layer) {
    switch &l in layer {
    case MapLayer:
        map_layer_update(&l)
    }
}

layer_render :: proc(layer: ^Layer) {
    switch &l in layer {
    case MapLayer:
        map_layer_render(&l)
    }
}
