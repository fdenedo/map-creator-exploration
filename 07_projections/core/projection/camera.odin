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
    // Base view bounds in world coordinates (computed from projection bounds + window aspect)
    // At zoom=1.0, this is exactly what's visible
    base_min_x, base_max_x: f32,
    base_min_y, base_max_y: f32,

    // Zoom level: 1.0 = show full canvas, 2.0 = 2x magnification (half the area visible)
    zoom: f32,
}

create_camera :: proc() -> Camera {
    return Camera {
        base_min_x = -1,
        base_max_x =  1,
        base_min_y = -1,
        base_max_y =  1,
        zoom = 1.0,
    }
}

// Fits the camera base view to the projection bounds (the "canvas")
// The bounds maintain their natural aspect ratio - letterboxing/pillarboxing is handled by the projection matrix
camera_fit_to_bounds :: proc(camera: ^Camera, bounds: ProjectionBounds, padding: f32 = 0.05) {
    bounds_width  := bounds.max_x - bounds.min_x
    bounds_height := bounds.max_y - bounds.min_y
    bounds_center_x := (bounds.min_x + bounds.max_x) / 2
    bounds_center_y := (bounds.min_y + bounds.max_y) / 2

    // Add padding to the bounds
    padded_half_width  := (bounds_width / 2) * (1 + padding)
    padded_half_height := (bounds_height / 2) * (1 + padding)

    camera.base_min_x = bounds_center_x - padded_half_width
    camera.base_max_x = bounds_center_x + padded_half_width
    camera.base_min_y = bounds_center_y - padded_half_height
    camera.base_max_y = bounds_center_y + padded_half_height
}

// Computes the actual view bounds after applying zoom
camera_get_view_bounds :: proc(camera: Camera) -> (left, right, bottom, top: f32) {
    center_x := (camera.base_min_x + camera.base_max_x) / 2
    center_y := (camera.base_min_y + camera.base_max_y) / 2
    half_width  := (camera.base_max_x - camera.base_min_x) / 2 / camera.zoom
    half_height := (camera.base_max_y - camera.base_min_y) / 2 / camera.zoom

    return center_x - half_width, center_x + half_width, center_y - half_height, center_y + half_height
}

// Builds an orthographic projection matrix that maps view bounds to NDC (-1 to +1)
// Maintains the canvas aspect ratio regardless of window shape (letterboxing/pillarboxing)
view_proj_matrix :: proc(camera: Camera) -> Matrix4 {
    left, right, bottom, top := camera_get_view_bounds(camera)

    canvas_width  := right - left
    canvas_height := top - bottom
    canvas_aspect := canvas_width / canvas_height

    window_aspect := platform.width() / platform.height()

    scale_x, scale_y: f32
    if canvas_aspect > window_aspect {
        // Fit to width, letterbox top/bottom
        scale_x = 2 / canvas_width
        scale_y = scale_x * window_aspect
    } else {
        // Fit to height, pillarbox left/right
        scale_y = 2 / canvas_height
        scale_x = scale_y / window_aspect
    }

    center_x := (left + right) / 2
    center_y := (bottom + top) / 2

    return Matrix4 {
        scale_x,  0,        0,  -center_x * scale_x,
        0,        scale_y,  0,  -center_y * scale_y,
        0,        0,        1,  0,
        0,        0,        0,  1,
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
