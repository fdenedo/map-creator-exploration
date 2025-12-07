@header package main
@header import sg "shared:sokol/gfx"

/*
========================================================================
    HANDLE VERTEX SHADER
========================================================================
*/
@vs vs_handle

layout(binding=0) uniform vs_params {
    mat4 u_camera_matrix;
    vec2 u_viewport_size;
    float u_point_size;
};

in vec2 position;
in vec2 uv;
in vec2 instance_pos;

out vec2 v_uv;

void main() {
    // Transform control point centre to clip space
    vec4 centre_clip = u_camera_matrix * vec4(instance_pos, 0.0, 1.0);

    // Billboard width/height is u_point_size * 2
    // Can think of this as the radius of the largest circle that can
    // fully fit on the quad

    // Convert pixel size to NDC space (-1 to 1), 2.0 units covers the entire viewport
    vec2 pixel_to_ndc = 2.0 / u_viewport_size;
    vec2 ndc_offset = position * u_point_size * pixel_to_ndc;

    // Offset the clip position by the billboard quad vertex
    gl_Position = vec4(centre_clip.xy + ndc_offset, 0.0, 1.0);

    v_uv = uv;
}
@end

/*
========================================================================
    QUADRATIC LOOP-BLINN VERTEX SHADER
========================================================================
*/
@vs vs_quad_loop_blinn

layout(binding=0) uniform vs_params {
    mat4 u_camera_matrix;
    vec2 u_viewport_size;
    float u_point_size;
};

in vec2 position;
in vec2 uv;

out vec2 v_uv;

void main() {
    vec4 pos_homogeneous = vec4(position, 0.0, 1.0);
    vec4 transformed = u_camera_matrix * pos_homogeneous;

    gl_Position = vec4(transformed.xy, 0.0, 1.0);
    v_uv = uv;
}

@end

/*
========================================================================
    HANDLE FRAGMENT SHADER
========================================================================
*/
@fs fs_handle

in vec2 v_uv;
out vec4 color;

void main() {
    // SDF for a circle: distance from point to circle edge
    // radius 1.0 fills quad
    float circle_radius = 0.8;
    float dist = length(v_uv) - circle_radius;
    float edge_width = fwidth(dist);

    // Smooth step from outside (1.0) to inside (0.0)
    // We want alpha=1 inside, alpha=0 outside
    float alpha = 1.0 - smoothstep(-edge_width, edge_width, dist);

    if (alpha <= 0.0) {
        discard;
    }

    color = vec4(1.0, 0.0, 0.0, alpha);
}
@end

/*
========================================================================
    QUADRATIC LOOP-BLINN FRAGMENT SHADER
========================================================================
*/
@fs fs_quad_loop_blinn

in vec2 v_uv;
out vec4 color;

void main() {
    float f = v_uv.x * v_uv.x - v_uv.y;
    float fw = fwidth(f);

    float distance_in_pixels = f / fw;

    float alpha = clamp(0.5 - distance_in_pixels, 0.0, 1.0);

    if (alpha <= 0.0) {
        discard;
    }

    color = vec4(1.0, 0.0, 0.0, alpha);
}
@end

@program handle vs_handle fs_handle
@program quad_loop_blinn vs_quad_loop_blinn fs_quad_loop_blinn

/*
========================================================================
    SIMPLE PASSTHROUGH VERTEX SHADER
    For rendering lines, wireframes, debug geometry, etc.
========================================================================
*/
@vs vs_simple

layout(binding=0) uniform vs_params {
    mat4 u_camera_matrix;
    vec2 u_viewport_size;
    float u_point_size;
};

in vec2 position;

void main() {
    vec4 transformed = u_camera_matrix * vec4(position, 0.0, 1.0);
    gl_Position = vec4(transformed.xy, 0.0, 1.0);
}
@end

/*
========================================================================
    SIMPLE SOLID COLOR FRAGMENT SHADER
========================================================================
*/
@fs fs_simple

out vec4 color;

void main() {
    color = vec4(0.5, 0.5, 0.5, 1.0);  // Gray color for handle lines
}
@end

@program simple vs_simple fs_simple
