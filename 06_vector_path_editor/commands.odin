package main

CommandHistory :: struct {
    commands: [dynamic]Command,
    current_index: int,
    max_history: int,
}

history_init :: proc() -> CommandHistory {
    return CommandHistory{
        commands      = make([dynamic]Command), // TODO: implement circular buffer
        current_index = -1, // No history
        max_history   = 100
    }
}

history_execute :: proc(h: ^CommandHistory, cmd: Command, state: ^EditorState) {
    command_execute(cmd, state)

    if h.current_index < len(h.commands) - 1 {
        resize(&h.commands, h.current_index + 1) // Clear redo history
    }

    append(&h.commands, cmd)
    h.current_index = len(h.commands) - 1

    if len(h.commands) > h.max_history {
        ordered_remove(&h.commands, 0)
        h.current_index -= 1
    }
}

history_undo :: proc(h: ^CommandHistory, state: ^EditorState) -> bool {
    if h.current_index < 0 {
        return false
    }

    command_undo(h.commands[h.current_index], state)
    h.current_index -= 1
    return true
}

history_redo :: proc(h: ^CommandHistory, state: ^EditorState) -> bool {
    if h.current_index >= len(h.commands) - 1 {
        return false
    }

    h.current_index += 1
    command_execute(h.commands[h.current_index], state)
    return true
}

Command :: struct {
   name:        string,
   description: string,

   data: CommandData,
}

CommandData :: union {
    AddPoint,
    ToggleClosePath,
    MovePoint,
}

AddPoint :: struct {
    path_id: int,
    point_id: int,
    point: Point,
    new_path_created: bool,
}

ToggleClosePath :: struct {
    path_id: int,
    was_closed: bool,
}

MovePoint :: struct {
    ref: PointRef,
    from, to: WorldVec2,
}

execute_add_point :: proc(cmd: ^AddPoint, state: ^EditorState) {
    // TODO: there is too much orchestration of editor state here
    // move orchestration - for example, cmd should always have a path id
    // and it shouldn't be populated here
    new_point := cmd.point

    // Only generate new IDs if not already set (first execution, not redo)
    // TODO: this is a mess really, need to make this more explicit
    // could init as -1
    if cmd.point_id == 0 {
        new_point.id = get_next_point_id(state)
        cmd.point_id = new_point.id
    } else {
        new_point.id = cmd.point_id
    }

    if cmd.new_path_created {
        new_path := Path {
            id = cmd.path_id if cmd.path_id != 0 else get_next_path_id(state),
            points = make([dynamic]Point)
        }
        cmd.path_id = new_path.id // TODO: move to Editor

        append(&new_path.points, new_point)
        append(&state.paths, new_path)
        state.active_path = new_path.id
    } else {
        path, _ := find_path(state, cmd.path_id)
        append(&path.points, new_point)
    }
}

undo_add_point :: proc(cmd: ^AddPoint, state: ^EditorState) {
    if cmd.new_path_created {
        path, path_index := find_path(state, cmd.path_id)
        delete(path.points)
        ordered_remove(&state.paths, path_index)
        state.active_path = nil
    } else {
        path, _ := find_path(state, cmd.path_id)
        _, point_index := find_point(path, cmd.point_id)
        ordered_remove(&path.points, point_index)
    }
}

execute_toggle_close_path :: proc(cmd: ^ToggleClosePath, state: ^EditorState) {
    path, _ := find_path(state, cmd.path_id)
    path.closed = !cmd.was_closed
    state.active_path = nil // TODO: editor orchestration, move to caller
}

undo_toggle_close_path :: proc(cmd: ^ToggleClosePath, state: ^EditorState) {
    path, _ := find_path(state, cmd.path_id)
    path.closed = cmd.was_closed
    state.active_path = cmd.path_id // TODO: editor orchestration, move to caller
}

execute_move_point :: proc(cmd: ^MovePoint, state: ^EditorState) {
    path, _ := find_path(state, cmd.ref.path_id)
    point, _ := find_point(path, cmd.ref.point_id)
    switch cmd.ref.part {
    case .ANCHOR:
        delta := cmd.to - cmd.from
        point.pos = cmd.to
        point.handle_in += delta
        point.handle_out += delta
    case .OUT:
        point.handle_out = cmd.to
    case .IN:
        point.handle_in = cmd.to
    }
}

undo_move_point :: proc(cmd: ^MovePoint, state: ^EditorState) {
    path, _ := find_path(state, cmd.ref.path_id)
    point, _ := find_point(path, cmd.ref.point_id)
    switch cmd.ref.part {
    case .ANCHOR:
        delta := cmd.from - cmd.to
        point.pos = cmd.from
        point.handle_in += delta
        point.handle_out += delta
    case .OUT:
        point.handle_out = cmd.from
    case .IN:
        point.handle_in = cmd.from
    }
}

@(private="file")
command_execute :: proc(cmd: Command, state: ^EditorState) {
    switch &c in cmd.data {
    case AddPoint:
        execute_add_point(&c, state)
    case ToggleClosePath:
        execute_toggle_close_path(&c, state)
    case MovePoint:
        execute_move_point(&c, state)
    }
    state.should_rerender = true
}

@(private="file")
command_undo :: proc(cmd: Command, state: ^EditorState) {
    switch &c in cmd.data {
    case AddPoint:
        undo_add_point(&c, state)
    case ToggleClosePath:
        undo_toggle_close_path(&c, state)
    case MovePoint:
        undo_move_point(&c, state)
    }
    state.should_rerender = true
}
