package main

import "core:log"
import "core:math/linalg"
import sapp "shared:sokol/app"

Event :: sapp.Event

CurveType :: enum {
    QUADRATIC = 0,
    CUBIC
}

EditorState :: struct {
    camera: Camera,
    control_points: []WorldVec2,
    can_pick_up: bool,
    dragging_point: Maybe(int),
    should_rerender: bool,
    curve_type: CurveType,
}

control_points_cubic := [4]WorldVec2 {
    { -0.75, -0.25 },
    { -0.5,   0.25 },
    {  0.5,   0.25 },
    {  0.75, -0.25 },
}

control_points_quad := [3]WorldVec2 {
    { -0.75, -0.25 },
    {  0,     0.25 },
    {  0.75, -0.25 },
}

editor_init :: proc(editor_state: ^EditorState) {
    context = default_context

    log.debug("Initialising editor")
    editor_state.camera = create_camera()
    editor_state.control_points = control_points_cubic[:]
    editor_state.can_pick_up = true
    editor_state.dragging_point = nil
    editor_state.should_rerender = true
    editor_state.curve_type = .CUBIC
}

editor_reset_curve :: proc(editor_state: ^EditorState) {
    switch (editor_state.curve_type) {
    case .QUADRATIC:
        editor_state.control_points = control_points_quad[:]
    case .CUBIC:
        editor_state.control_points = control_points_cubic[:]
    }
}

editor_handle_event :: proc(editor_state: ^EditorState, e: ^Event) {
    #partial switch e.type {
    case .KEY_DOWN:
        if e.key_code == .C {
            editor_state.curve_type = .CUBIC
            editor_reset_curve(editor_state)
            editor_state.should_rerender = true
        }
        if e.key_code == .Q {
            editor_state.curve_type = .QUADRATIC
            editor_reset_curve(editor_state)
            editor_state.should_rerender = true
        }
    case .MOUSE_SCROLL:
        editor_state.camera.zoom += e.scroll_y * 0.1
        editor_state.camera.zoom = min(20.0, max(editor_state.camera.zoom, 0.5))
        editor_state.should_rerender = true
    case .MOUSE_DOWN:
        if e.mouse_button != .LEFT do break
        if !editor_state.can_pick_up do break

        mouse := ScreenVec2{ e.mouse_x, e.mouse_y }
        for control_point, index in editor_state.control_points {
            if linalg.vector_length(world_to_screen(control_point, editor_state.camera, true) - mouse) < 8 {
                editor_state.dragging_point = index
            }
        }
        editor_state.can_pick_up = false
    case .MOUSE_MOVE:
        mouse := ScreenVec2{ e.mouse_x, e.mouse_y }
        if editor_state.dragging_point != nil {
            editor_state.control_points[editor_state.dragging_point.?] = screen_to_world(mouse, editor_state.camera, true)
            editor_state.should_rerender = true
        }
    case .MOUSE_UP:
        if e.mouse_button != .LEFT do break
        editor_state.dragging_point = nil
        editor_state.can_pick_up = true
    case .RESIZED:
        editor_state.camera.aspect_ratio = sapp.widthf() / sapp.heightf()
        editor_state.should_rerender = true
    }
}
