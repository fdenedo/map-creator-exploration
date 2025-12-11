package main

import "core:log"
import "core:math/linalg"
import sapp "shared:sokol/app"

Event :: sapp.Event

EditorState :: struct {
    mouse: ScreenVec2,
    camera: Camera,
    paths: [dynamic]Path,
    active_path: Maybe(int),
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

Point_Part :: enum {
    IN,
    ANCHOR,
    OUT
}

PointRef :: struct {
    path_index: int,
    point_index: int,
}

IDLE :: struct {
    point_hovered: Maybe(PointRef),
    part: Point_Part,
}
PANNING :: struct {
    camera_start: WorldVec2,
    mouse_last_pos: ScreenVec2,
}
ADDING_POINT :: struct {
    handle_in: WorldVec2,
    position_start: WorldVec2,
    handle_out: WorldVec2,
}
DRAGGING_POINT :: struct {
    ref: PointRef,
    part: Point_Part,
    position_last: ScreenVec2,
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
        is.point_hovered = nil
        for path, path_idx in es.paths {
            for point, point_idx in path.points {
                ref := PointRef { path_idx, point_idx }
                switch {
                case linalg.vector_length(world_to_screen(point.handle_in, es.camera, true) - es.mouse) < 6:
                    is.point_hovered = ref
                    is.part = .IN
                case linalg.vector_length(world_to_screen(point.handle_out, es.camera, true) - es.mouse) < 6:
                    is.point_hovered = ref
                    is.part = .OUT
                case linalg.vector_length(world_to_screen(point.pos, es.camera, true) - es.mouse) < 8:
                    is.point_hovered = ref
                    is.part = .ANCHOR
                }
            }
        }
    case .MOUSE_DOWN:
        if e.mouse_button != .LEFT do break
        if hovered, ok := is.point_hovered.?; ok {
            set_state(es, DRAGGING_POINT { hovered, is.part, es.mouse })
        } else {
            // set_state(es, PANNING { es.camera.pos, es.mouse })
            pos := screen_to_world(es.mouse, es.camera, true)
            set_state(es, ADDING_POINT {
                handle_in      = pos,
                position_start = pos,
                handle_out     = pos,
            })
        }
    case .KEY_DOWN:
        if e.key_code == .C && es.active_path != nil {
            es.paths[es.active_path.?].closed = true
            es.active_path = nil
            es.should_rerender = true
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
        pos_out        := screen_to_world(es.mouse, es.camera, true)
        is.handle_out   = pos_out
        is.handle_in    = 2 * is.position_start - pos_out // same as pos_start + (pos_start - pos_out)
    case .MOUSE_UP:
        new_point := Point{
            handle_in  = is.handle_in,
            pos        = is.position_start,
            handle_out = is.handle_out,
        }
        active_path, ok := es.active_path.?
        if ok {
            append(&es.paths[active_path].points, new_point)
        } else {
            new_path := Path {}
            append(&new_path.points, new_point)
            append(&es.paths, new_path)

            es.active_path = len(es.paths) - 1
        }
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
        mouse_world_delta := screen_to_world(is.position_last - es.mouse, es.camera, false)
        point := &es.paths[is.ref.path_index].points[is.ref.point_index]

        switch is.part {
        case .ANCHOR:
            point.handle_in  -= mouse_world_delta
            point.pos        -= mouse_world_delta
            point.handle_out -= mouse_world_delta
        case .IN:
            point.handle_in  -= mouse_world_delta
        case .OUT:
            point.handle_out -= mouse_world_delta
        }
        is.position_last = es.mouse
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
