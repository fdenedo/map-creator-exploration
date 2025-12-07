package main

import "core:log"
import "core:math/linalg"
import sapp "shared:sokol/app"

Event :: sapp.Event

EditorState :: struct {
    mouse: ScreenVec2,
    camera: Camera,
    control_points: [dynamic]Point,
    should_rerender: bool,
    input: Input_State, // use set_state() to modify
}

// Current states:
// IDLE             - nothing's happening
//                    currently this is the only state where hovering points is allowed
// PANNING          - changes where the camera is looking
// ADDING_POINT     - not yet implemented, adds point to the list/struct/array/whatever
//                    of control points (probably along with handles)
// DRAGGING_POINT   - changes the position of a pre-existing point

IDLE :: struct {
    point_hovered: Maybe(int)
}
PANNING :: struct {
    camera_start: WorldVec2,
    mouse_last_pos: ScreenVec2
}
ADDING_POINT :: struct {
    position_start: WorldVec2
}
DRAGGING_POINT :: struct {
    id: int,
    position_start: ScreenVec2,
}

Input_State :: union {
    IDLE,
    PANNING,
    ADDING_POINT,
    DRAGGING_POINT,
}

set_state :: proc(es: ^EditorState, new_state: Input_State) {
    // TODO: add some debug logging in here perhaps
    es.input = new_state
}

editor_init :: proc(editor_state: ^EditorState) {
    context = default_context

    log.debug("Initialising editor")
    editor_state.camera = create_camera()
    editor_state.should_rerender = true
    editor_state.input = IDLE {}
}

editor_handle_event :: proc(editor_state: ^EditorState, e: ^Event) {
    editor_state.mouse = ScreenVec2{ e.mouse_x, e.mouse_y }

    switch &s in &editor_state.input {
    case IDLE:
        handle_idle(editor_state, &s, e)
    case PANNING:
        handle_panning(editor_state, &s, e)
    case ADDING_POINT:
        handle_adding_point(editor_state, &s, e)
    case DRAGGING_POINT:
        handle_dragging_point(editor_state, &s, e)
    }
    handle_global_events(editor_state, e)
}

handle_idle :: proc(es: ^EditorState, is: ^IDLE, e: ^Event) {
    #partial switch e.type {
    case .MOUSE_MOVE:
        is.point_hovered = nil // No point hovered
        for control_point, index in es.control_points {
            if linalg.vector_length(world_to_screen(control_point.pos, es.camera, true) - es.mouse) < 8 {
                is.point_hovered = index
                break
            }
        }
    case .MOUSE_DOWN:
        if e.mouse_button != .LEFT do break
        if hovered, ok := is.point_hovered.?; ok {
            set_state(es, DRAGGING_POINT { hovered, es.mouse })
        } else {
            // set_state(es, PANNING { es.camera.pos, es.mouse })
            set_state(es, ADDING_POINT { screen_to_world(es.mouse, es.camera, true) })
        }
    }
}

handle_panning :: proc(es: ^EditorState, is: ^PANNING, e: ^Event) {
    #partial switch e.type {
    case .MOUSE_MOVE:
        mouse_delta := es.mouse - is.mouse_last_pos
        es.camera.pos -= screen_to_world(mouse_delta, es.camera, false)
        is.mouse_last_pos = es.mouse
    case .MOUSE_UP:
        es.input = IDLE {} // TODO: point_hovered is initialised to 0 here
    }
}

handle_adding_point :: proc(es: ^EditorState, is: ^ADDING_POINT, e: ^Event) {
    #partial switch e.type {
    case .MOUSE_MOVE:
        // TODO: move the handles for the added point
    case .MOUSE_UP:
        append(&es.control_points, Point{ pos = is.position_start })
        es.should_rerender = true
        set_state(es, IDLE {})
    case .KEY_DOWN:
        if e.key_code == .ESCAPE {
            set_state(es, IDLE {})
        }
    }
}

handle_dragging_point :: proc(es: ^EditorState, is: ^DRAGGING_POINT, e: ^Event) {
    #partial switch e.type {
    case .MOUSE_MOVE:
        es.control_points[is.id].pos = screen_to_world(es.mouse, es.camera, true)
        es.should_rerender = true
    case .MOUSE_UP:
        es.input = IDLE {} // TODO: point_hovered is initialised to 0 here
    }
}

handle_global_events :: proc(es: ^EditorState, e: ^Event) {
    #partial switch e.type {
    case .RESIZED:
        es.camera.aspect_ratio = sapp.widthf() / sapp.heightf()
        es.should_rerender = true
    case .MOUSE_SCROLL:
        es.camera.zoom += e.scroll_y * 0.1
        es.camera.zoom = min(20.0, max(es.camera.zoom, 0.5))
        es.should_rerender = true
    }
}
