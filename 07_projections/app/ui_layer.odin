#+feature dynamic-literals

package app

import imgui "shared:imgui"
import imgui_dx11 "shared:imgui/imgui_impl_dx11"

import "core:strings"
import proj "../core/projection"
import "../platform"

UILayer :: struct {
    projection: proj.ProjectionType,
    supported_projections: map[proj.ProjectionType]string,
    initialised: bool,
}

ui_layer_create :: proc(self: ^UILayer) {
    // Defer initialisation until render backend is ready
    self.initialised = false
}

ui_layer_set_projection :: proc(self: ^UILayer, projection_type: proj.ProjectionType) {
    self.projection = projection_type
}

ui_layer_init_imgui :: proc(self: ^UILayer) {
    if self.initialised do return

    ctx := imgui.CreateContext()
    io := imgui.GetIO()
    io.ConfigFlags += { .DockingEnable }

    device, device_ctx := platform.get_device_and_context_dx11()
    imgui_dx11.Init(device, device_ctx)

    self.supported_projections = map[proj.ProjectionType]string {
        .Orthographic = "Orthographic",
        .Equirectangular = "Equirectangular",
    }

    self.initialised = true
}

ui_layer_update :: proc(self: ^UILayer) {
    ui_layer_init_imgui(self)
}

ui_layer_render :: proc(self: ^UILayer, render_state: ^platform.RenderState) {
    if !self.initialised do return

    io := imgui.GetIO()
    io.DisplaySize = imgui.Vec2 { platform.width(), platform.height() }

    imgui_dx11.NewFrame()
    imgui.NewFrame()

    if imgui.Begin("Projection") {
        current_proj := self.supported_projections[self.projection]
        proj_as_cstring := strings.clone_to_cstring(current_proj, context.temp_allocator)
        if imgui.BeginCombo("Projection", proj_as_cstring) {
            for p in self.supported_projections {
                label := self.supported_projections[p]
                is_selected := label == current_proj
                if imgui.Selectable(strings.clone_to_cstring(label, context.temp_allocator), is_selected) {
                    self.projection = p
                }
                if (is_selected) {
                    imgui.SetItemDefaultFocus()
                }
            }
            imgui.EndCombo()
        }
    }
    imgui.End()

    imgui.Render()
    imgui_dx11.RenderDrawData(imgui.GetDrawData())
}

ui_layer_on_event :: proc(self: ^UILayer, event: ^platform.Event) -> (handled: bool) {
    if !self.initialised do return false

    io := imgui.GetIO()

    #partial switch event.type {
    case .MOUSE_DOWN:
        io.MouseDown[int(event.mouse_button)] = true
    case .MOUSE_UP:
        io.MouseDown[int(event.mouse_button)] = false
    case .MOUSE_MOVE:
        io.MousePos = imgui.Vec2 { event.mouse_x, event.mouse_y }
    }

    #partial switch event.type {
    case .MOUSE_DOWN, .MOUSE_UP, .MOUSE_MOVE, .MOUSE_SCROLL:
        return io.WantCaptureMouse
    case .KEY_DOWN, .KEY_UP, .CHAR:
        return io.WantCaptureKeyboard
    }

    return false
}
