package main

import "core:math/linalg"
import sapp "shared:sokol/app" // Would this be here if this was well-organised? Probably, as we need its types

Camera :: struct {
    pos: WorldVec2,
    zoom: f32,
    aspect_ratio: f32,
}

create_camera :: proc() -> Camera {
    return Camera{
        pos          = { 0, 0 },
        zoom         = 1.0,
        aspect_ratio = sapp.widthf() / sapp.heightf()
    }
}

// TODO: cache this, it changes only on zoom/screen resize, which is likely infrequent enough (as in not once
// per frame)
camera_matrix :: proc(camera: Camera) -> Matrix4 {
    z := camera.zoom
    a := camera.aspect_ratio

    return Matrix4{
        z,    0,    0,    -camera.pos.x * z,
        0,  a*z,    0,    -camera.pos.y * a * z,
        0,    0,    1,     0,
        0,    0,    0,     1,
    }
}

screen_pixel_to_ndc :: proc(vec2: ScreenVec2, translate: bool) -> [2]f32 { // Probably inline to avoid confusion
    translation: f32 = translate ? 1.0 : 0.0
    return [2]f32{
         (vec2.x / sapp.widthf())  * 2.0 - translation,
        -(vec2.y / sapp.heightf()) * 2.0 + translation,
    }
}

ndc_to_screen_pixel :: proc(vec2: [2]f32, translate: bool) -> ScreenVec2 { // Probably inline to avoid confusion
    translation: f32 = translate ? 1.0 : 0.0
    return ScreenVec2{
         ((vec2.x + translation) / 2.0) * sapp.widthf(),
        (-(vec2.y - translation) / 2.0) * sapp.heightf(),
    }
}

// TODO: pass in camera matrix rather than looking at state
screen_to_world :: proc(vec2: ScreenVec2, translate: bool) -> WorldVec2 {
    homogenous: f32 = translate ? 1.0 : 0.0
    ndc            := screen_pixel_to_ndc(vec2, translate)
    cam_matrix     := camera_matrix(state.camera)
    inverse        := linalg.matrix4_inverse(cam_matrix)

    ndc_homogeneous     := [4]f32{ndc.x, ndc.y, 0.0, homogenous}
    world_homogeneous   := inverse * ndc_homogeneous
    return WorldVec2(world_homogeneous.xy)
}

// TODO: pass in camera matrix rather than looking at state
world_to_screen :: proc(vec2: WorldVec2, translate: bool) -> ScreenVec2 {
    homogenous: f32 = translate ? 1.0 : 0.0
    cam_matrix     := camera_matrix(state.camera)

    world_homogenous    := [4]f32{vec2.x, vec2.y, 0.0, homogenous}
    screen_homogenous   := cam_matrix * world_homogenous
    pixel               := ndc_to_screen_pixel(screen_homogenous.xy, translate)
    return ScreenVec2(pixel)
}
