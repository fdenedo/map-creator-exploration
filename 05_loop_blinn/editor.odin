package main

import sapp "shared:sokol/app"
import "core:math/linalg"

Event :: sapp.Event

// Everything from previous state related to data and camera
EditorState :: struct {
    camera: Camera,
    control_points: [4]ControlPoint,
    can_pick_up: bool,
    dragging_point: Maybe(int),
}

editor_init :: proc(editor_state: ^EditorState) {
    editor_state.camera = create_camera()
    editor_state.control_points = {
        ControlPoint { pos = {-0.75, -0.25} },
        ControlPoint { pos = {-0.5,   0.25} },
        ControlPoint { pos = { 0.5,   0.25} },
        ControlPoint { pos = { 0.75, -0.25} },
    }
    editor_state.can_pick_up = true
    editor_state.dragging_point = nil
}

editor_handle_event :: proc(editor_state: ^EditorState, e: ^Event) {
    #partial switch e.type {
    case .MOUSE_SCROLL:
        editor_state.camera.zoom += e.scroll_y * 0.1
        editor_state.camera.zoom = min(20.0, max(editor_state.camera.zoom, 0.5))
        update_render()
    case .MOUSE_DOWN:
        if e.mouse_button != .LEFT do break
        if !editor_state.can_pick_up do break

        mouse := ScreenVec2{ e.mouse_x, e.mouse_y }
        for control_point, index in editor_state.control_points {
            if linalg.vector_length(world_to_screen(control_point.pos, editor_state.camera, true) - mouse) < 8 {
                editor_state.dragging_point = index
            }
        }

        editor_state.can_pick_up = false
    case .MOUSE_MOVE:
        mouse := ScreenVec2{ e.mouse_x, e.mouse_y }
        if editor_state.dragging_point != nil {
            editor_state.control_points[editor_state.dragging_point.?].pos = screen_to_world(mouse, editor_state.camera, true)
            update_render()
        }
    case .MOUSE_UP:
        if e.mouse_button != .LEFT do break
        editor_state.dragging_point = nil
        editor_state.can_pick_up = true
    }
}
