package projection

import "../../core"
import "../../platform"
import "core:math/linalg"

GeoCoord    :: [2]f32           // (λ, φ) in radians
GeoCoord64  :: [2]f64           // (λ, φ) in radians
ScreenVec2  :: core.ScreenVec2  // (x, y) coordinate in the window
WorldVec2   :: core.WorldVec2
Matrix4     :: core.Matrix4

Camera :: struct {
    zoom: f32,
    aspect_ratio: f32,
}

create_camera :: proc() -> Camera {
    return Camera {
        zoom         = 1.0,
        aspect_ratio = 1.0 // Update using camera_update_aspect_ratio() at first opportunity
    }
}

camera_update_aspect_ratio :: proc(camera: ^Camera) {
    new_aspect := platform.width() / platform.height()

    if abs(camera.aspect_ratio - new_aspect) > 0.001 {
        camera.aspect_ratio = new_aspect
    }
}

view_proj_matrix :: proc(camera: Camera) -> Matrix4 {
    z := camera.zoom
    a := camera.aspect_ratio

    return Matrix4 {
        z,   0,   0,   z,
        0, a*z,   0,   a*z,
        0,   0,   1,   0,
        0,   0,   0,   1,
    }
}

// TODO: after a bit of reading, I found that I shoudln't really be converting to NDC here
// although I kinda knew this - "World Space" will eventually be defined by me, and it will
// correspond to the map canvas. So there will be
// World -> Clip (NDC, -1.0 to 1.0) -> Screen
// I imagine we store feature data in world coordinates, and in the future probably (lon/lat)
// We can convert to CLIP SPACE on the GPU
screen_pixel_to_ndc :: proc(vec2: ScreenVec2, translate: bool) -> [2]f32 { // Probably inline to avoid confusion
    translation: f32 = translate ? 1.0 : 0.0
    return [2]f32{
         (vec2.x / platform.width())  * 2.0 - translation,
        -(vec2.y / platform.height()) * 2.0 + translation,
    }
}

ndc_to_screen_pixel :: proc(vec2: [2]f32, translate: bool) -> ScreenVec2 { // Probably inline to avoid confusion
    translation: f32 = translate ? 1.0 : 0.0
    return ScreenVec2{
         ((vec2.x + translation) / 2.0) * platform.width(),
        (-(vec2.y - translation) / 2.0) * platform.height(),
    }
}

screen_to_world :: proc(vec2: ScreenVec2, camera: Camera, translate: bool) -> WorldVec2 {
    homogenous: f32 = translate ? 1.0 : 0.0
    ndc            := screen_pixel_to_ndc(vec2, translate)
    cam_matrix     := view_proj_matrix(camera)
    inverse        := linalg.matrix4_inverse(cam_matrix)

    ndc_homogeneous     := [4]f32{ndc.x, ndc.y, 0.0, homogenous}
    world_homogeneous   := inverse * ndc_homogeneous
    return WorldVec2(world_homogeneous.xy)
}

world_to_screen :: proc(vec2: WorldVec2, camera: Camera, translate: bool) -> ScreenVec2 {
    homogenous: f32 = translate ? 1.0 : 0.0
    vp_mat         := view_proj_matrix(camera)

    world_homogenous    := [4]f32{vec2.x, vec2.y, 0.0, homogenous}
    screen_homogenous   := vp_mat * world_homogenous
    pixel               := ndc_to_screen_pixel(screen_homogenous.xy, translate)
    return ScreenVec2(pixel)
}
