package main

import "core:log"
import "core:math/linalg"
import sapp "shared:sokol/app"

Event :: sapp.Event

EditorState :: struct {
    mouse: ScreenVec2,
    camera: Camera,
    paths: [dynamic]Path,
    next_path_id: int,
    next_point_id: int,
    active_path: Maybe(int),
    selected_point: Maybe(PointRef),
    should_rerender: bool,
    input: Input_State, // use set_state() to modify
    history: CommandHistory,
}

get_next_path_id :: proc(state: ^EditorState) -> int {
    id := state.next_path_id
    state.next_path_id += 1
    return id
}

get_next_point_id :: proc(state: ^EditorState) -> int {
    id := state.next_point_id
    state.next_point_id += 1
    return id
}

// Current states:
// IDLE             - nothing's happening
//                    currently this is the only state where hovering points is allowed
// PANNING          - changes where the camera is looking
// ADDING_POINT     - adds point to the list/struct/array/whatever of control points (probably
//                    along with handles)
// DRAGGING_POINT   - changes the position of a pre-existing point

Point_Part :: enum {
    ANCHOR = 0,
    IN,
    OUT
}

PointRef :: struct {
    path_id: int,
    point_id: int,
    part: Point_Part,
}

IDLE :: struct {
    point_hovered: Maybe(PointRef),
}
PANNING :: struct {
    camera_start: WorldVec2,
    mouse_last_pos: ScreenVec2,
}
ADDING_POINT :: struct {
    point: Point,
}
POTENTIAL_DRAG :: struct {
    ref: PointRef,
    original_point: Point,
    mouse_down_pos: ScreenVec2,
}
DRAGGING_POINT :: struct {
    ref: PointRef,
    original_point: Point,
    current_offset: WorldVec2,
}

Input_State :: union {
    IDLE,
    PANNING,
    ADDING_POINT,
    POTENTIAL_DRAG,
    DRAGGING_POINT,
}

find_path :: proc(es: ^EditorState, id: int) -> (^Path, int) {
    for &path, index in es.paths {
        if path.id == id do return &path, index
    }
    return nil, -1
}

// TODO: point ids aren't assigned relative to path, but this is fine for now
// might want to move to a node-based structure in the future
// might also use an R-tree for spatial data
find_point :: proc(path: ^Path, id: int) -> (^Point, int) {
    for &point, index in path.points {
        if point.id == id do return &point, index
    }
    return nil, -1
}

set_state :: proc(es: ^EditorState, new_state: Input_State) {
    // TODO: add some debug logging in here perhaps
    es.input = new_state
}

// Get the effective point for rendering, accounting for drag preview
// TODO: might be better to reverse the direction of this
// e.g. right now this is coded to get the effective point for all points
// but we could organise the code so that if we are in dragging point, we only call this
// for the point in question
get_effective_point :: proc(es: ^EditorState, path_id: int, point_id: int) -> Point {
    path, _ := find_path(es, path_id)
    point, _ := find_point(path, point_id)
    point_effective := point^ // Dereference

    if drag_state, ok := es.input.(DRAGGING_POINT); ok {
        if drag_state.ref.path_id == path_id && drag_state.ref.point_id == point_id {
            switch drag_state.ref.part {
            case .ANCHOR:
                point_effective.pos        += drag_state.current_offset
                point_effective.handle_in  += drag_state.current_offset
                point_effective.handle_out += drag_state.current_offset
            case .IN:
                point_effective.handle_in  += drag_state.current_offset
            case .OUT:
                point_effective.handle_out += drag_state.current_offset
            }
        }
    }

    return point_effective
}

editor_init :: proc(editor_state: ^EditorState) {
    context = default_context

    log.debug("Initialising editor")
    editor_state.history = history_init()
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
    case POTENTIAL_DRAG:
        handle_potential_drag(editor_state, &s, e)
    case DRAGGING_POINT:
        handle_dragging_point(editor_state, &s, e)
    }
    handle_global_events(editor_state, e)
}

handle_idle :: proc(es: ^EditorState, is: ^IDLE, e: ^Event) {
    context = default_context

    #partial switch e.type {
    case .MOUSE_MOVE:
        is.point_hovered = nil
        for path in es.paths {
            for point in path.points {
                ref := PointRef {
                    path_id = path.id,
                    point_id = point.id,
                }
                switch {
                case linalg.vector_length(world_to_screen(point.pos, es.camera, true) - es.mouse) < 8:
                    ref.part = .ANCHOR
                    is.point_hovered = ref
                case linalg.vector_length(world_to_screen(point.handle_out, es.camera, true) - es.mouse) < 6:
                    ref.part = .OUT
                    is.point_hovered = ref
                case linalg.vector_length(world_to_screen(point.handle_in, es.camera, true) - es.mouse) < 6:
                    ref.part = .IN
                    is.point_hovered = ref
                }
            }
        }
    case .MOUSE_DOWN:
        if e.mouse_button != .LEFT do break
        if hovered, ok := is.point_hovered.?; ok {
            path, _ := find_path(es, hovered.path_id)
            point, _ := find_point(path, hovered.point_id)
            set_state(es, POTENTIAL_DRAG {
                ref = hovered,
                original_point = point^,
                mouse_down_pos = es.mouse,
            })
        } else {
            es.selected_point = nil
            pos := screen_to_world(es.mouse, es.camera, true)
            set_state(es, ADDING_POINT {
                point = {
                    handle_in   = pos,
                    pos         = pos,
                    handle_out  = pos,
                }
            })
        }
    case .KEY_DOWN:
        if e.key_code == .C && es.active_path != nil {
            path, _ := find_path(es, es.active_path.?)
            cmd := Command {
                name = "Close Path",
                description = "Close an open path",
                data = ToggleClosePath {
                    path_id = es.active_path.?,
                    was_closed = path.closed
                },
            }
            history_execute(&es.history, cmd, es)
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
        es.input = IDLE {}
    }
}

handle_adding_point :: proc(es: ^EditorState, is: ^ADDING_POINT, e: ^Event) {
    #partial switch e.type {
    case .MOUSE_MOVE:
        pos_out            := screen_to_world(es.mouse, es.camera, true)
        is.point.handle_out = pos_out
        is.point.handle_in  = 2 * is.point.pos - pos_out // same as pos + (pos - pos_out)
    case .MOUSE_UP:
        add_point_data: AddPoint
        add_point_data.point = is.point
        add_point_data.point.id = get_next_point_id(es)

        if active_path, ok := es.active_path.?; ok {
            add_point_data.path_id = active_path
            add_point_data.new_path_created = false
        } else {
            add_point_data.path_id = get_next_path_id(es)
            add_point_data.new_path_created = true
        }
        cmd := Command {
            name = "Add Point",
            description = "Add a point to path",
            data = add_point_data,
        }
        history_execute(&es.history, cmd, es)
        set_state(es, IDLE {})
    case .KEY_DOWN:
        if e.key_code == .ESCAPE {
            set_state(es, IDLE {})
        }
    }
}

handle_potential_drag :: proc(es: ^EditorState, is: ^POTENTIAL_DRAG, e: ^Event) {
    DRAG_THRESHOLD :: 5.0 // pixels

    #partial switch e.type {
    case .MOUSE_MOVE:
        mouse_delta := linalg.vector_length(es.mouse - is.mouse_down_pos)

        if mouse_delta > DRAG_THRESHOLD {
            set_state(es, DRAGGING_POINT {
                ref = is.ref,
                original_point = is.original_point,
                current_offset = {0, 0},
            })
        }
    case .MOUSE_UP:
        es.selected_point = is.ref
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
        mouse_world := screen_to_world(es.mouse, es.camera, true)

        original_pos: WorldVec2
        switch is.ref.part {
        case .ANCHOR:
            original_pos = is.original_point.pos
        case .IN:
            original_pos = is.original_point.handle_in
        case .OUT:
            original_pos = is.original_point.handle_out
        }

        // Update offset - don't update actual point yet
        is.current_offset = mouse_world - original_pos
        es.should_rerender = true

    case .MOUSE_UP:
        pos_from, pos_to: WorldVec2
        switch is.ref.part {
        case .ANCHOR:
            pos_from = is.original_point.pos
            pos_to = is.original_point.pos + is.current_offset
        case .IN:
            pos_from = is.original_point.handle_in
            pos_to = is.original_point.handle_in + is.current_offset
        case .OUT:
            pos_from = is.original_point.handle_out
            pos_to = is.original_point.handle_out + is.current_offset
        }

        // Don't commit if nothing changed
        if pos_to == pos_from {
            set_state(es, IDLE {})
            break
        }

        cmd := Command {
            name = "Move Point",
            description = "Move a point to a position",
            data = MovePoint {
                ref = is.ref,
                from = pos_from,
                to = pos_to,
            },
        }
        history_execute(&es.history, cmd, es)
        set_state(es, IDLE {})

    case .KEY_DOWN:
        if e.key_code == .ESCAPE {
            es.should_rerender = true
            set_state(es, IDLE {})
        }
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
    case .KEY_DOWN:
        if e.key_code == .Z && e.modifiers & sapp.MODIFIER_CTRL != 0 { // TODO: add helper for this
            if e.modifiers & sapp.MODIFIER_SHIFT != 0 {
                history_redo(&es.history, es)
            } else {
                history_undo(&es.history, es)
            }
        }
        if e.key_code == .Y && e.modifiers & sapp.MODIFIER_CTRL != 0 {
            history_redo(&es.history, es)
        }
    }
}
