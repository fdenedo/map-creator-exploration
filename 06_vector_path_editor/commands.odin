package main

CommandHistory :: struct {
    commands: [dynamic]Command,
    current_index: int,
    max_history: int,
}

history_init :: proc() -> CommandHistory {
    return CommandHistory{
        commands      = make([dynamic]Command),
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
    AddPoint
}

AddPoint :: struct {
    path_id: int,
    point: Point,
    new_path_created: bool,
}

execute_add_point :: proc(cmd: ^AddPoint, state: ^EditorState) {
    if cmd.new_path_created {
        new_path := Path{ points = make([dynamic]Point) }
        append(&new_path.points, cmd.point)
        append(&state.paths, new_path)
        cmd.path_id = len(state.paths) - 1
        state.active_path = cmd.path_id
    } else {
        append(&state.paths[cmd.path_id].points, cmd.point)
    }
}

undo_add_point :: proc(cmd: ^AddPoint, state: ^EditorState) {
    if cmd.new_path_created {
        delete(state.paths[len(state.paths) - 1].points)
        pop(&state.paths)
        state.active_path = nil
    } else {
        pop(&state.paths[cmd.path_id].points)
    }
}

@(private="file")
command_execute :: proc(cmd: Command, state: ^EditorState) {
    switch &c in cmd.data {
    case AddPoint:
        execute_add_point(&c, state)
    }
    state.should_rerender = true
}

@(private="file")
command_undo :: proc(cmd: Command, state: ^EditorState) {
    switch &c in cmd.data {
    case AddPoint:
        undo_add_point(&c, state)
    }
    state.should_rerender = true
}
