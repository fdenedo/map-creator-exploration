package ui

UI :: struct {}

ui_create :: proc() -> UI {
	return UI {}
}

ui_update :: proc(ui: ^UI) {}

ui_render :: proc(ui: ^UI) {}
