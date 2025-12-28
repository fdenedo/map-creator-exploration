package app

import "../platform"

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
    new_layer := &app.layers[len(app.layers) - 1]
    switch &l in new_layer {
    case MapLayer:
        map_layer_create(&l)
    }
}

update :: proc(app: ^Application, dt: f32) {
    for &layer in app.layers {
        layer_update(&layer)
    }
}

render :: proc(app: ^Application, render_state: ^platform.RenderState) {
    for &layer in app.layers {
        layer_render(&layer, render_state)
    }
}

on_event :: proc(app: ^Application, event: ^platform.Event) {
    #reverse for &layer in app.layers {
        if layer_on_event(&layer, event) do return
    }
}

layer_update :: proc(layer: ^Layer) {
    switch &l in layer {
    case MapLayer:
        map_layer_update(&l)
    }
}

layer_render :: proc(layer: ^Layer, render_state: ^platform.RenderState) {
    switch &l in layer {
    case MapLayer:
        map_layer_render(&l, render_state)
    }
}

layer_on_event :: proc(layer: ^Layer, event: ^platform.Event) -> (handled: bool) {
    switch &l in layer {
    case MapLayer:
        return map_layer_on_event(&l, event)
    }
    return true // TODO: could be that we return false here, not sure yet
}
