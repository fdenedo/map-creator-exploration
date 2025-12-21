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
    DeletePoint,
}

AddPoint :: struct {
    path_id: int,
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

DeletePoint :: struct {
    ref: PointRef,
    index: int,
    deleted_point: Point,
    path_was_deleted: bool,
}

execute_add_point :: proc(cmd: ^AddPoint, state: ^EditorState) {
    if cmd.new_path_created {
        new_path := Path {
            id = cmd.path_id,
            points = make([dynamic]Point)
        }
        append(&new_path.points, cmd.point)
        append(&state.paths, new_path)
        state.active_path = new_path.id
    } else {
        path, _ := find_path(state, cmd.path_id)
        append(&path.points, cmd.point)
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
        _, point_index := find_point(path, cmd.point.id)
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

execute_delete_point :: proc(cmd: ^DeletePoint, state: ^EditorState) {
    path, path_index := find_path(state, cmd.ref.path_id)
    if path_index == -1 do return

    ordered_remove(&path.points, cmd.index)

    if cmd.path_was_deleted {
        delete(path.points)
        ordered_remove(&state.paths, path_index)
        if state.active_path == cmd.ref.path_id {
            state.active_path = nil
        }
    }
}

undo_delete_point :: proc(cmd: ^DeletePoint, state: ^EditorState) {
    if cmd.path_was_deleted {
        new_path := Path {
            id = cmd.ref.path_id,
            points = make([dynamic]Point),
        }
        append(&new_path.points, cmd.deleted_point)
        append(&state.paths, new_path)
    } else {
        path, _ := find_path(state, cmd.ref.path_id)
        inject_at(&path.points, cmd.index, cmd.deleted_point)
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
    case DeletePoint:
        execute_delete_point(&c, state)
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
    case DeletePoint:
        undo_delete_point(&c, state)
    }
    state.should_rerender = true
}
