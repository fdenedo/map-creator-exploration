package editor

EditorState :: struct {
    mouse: ScreenVec2,
    camera: Camera,
    should_rerender: bool,
    input: Input_State, // use set_state() to modify
    history: CommandHistory,
}
