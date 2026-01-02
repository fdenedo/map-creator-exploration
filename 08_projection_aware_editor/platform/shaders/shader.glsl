@header package shaders
@header import sg "shared:sokol/gfx"

/*
========================================================================
    POINT VERTEX SHADER
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
    HANDLE FRAGMENT SHADER
========================================================================
*/
@fs fs_handle

layout(binding=1) uniform fs_params {
    vec4 u_color;
};

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

    color = vec4(u_color.rgb, u_color.a * alpha);
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

/*
========================================================================
    ANTIALIASED LINE VERTEX SHADER
    Renders lines as screen-aligned quads with consistent pixel width
========================================================================
*/
@vs vs_line

layout(binding=0) uniform vs_params {
    mat4 u_camera_matrix;
    vec2 u_viewport_size;
    float u_point_size;
};

in vec2 position;
in vec2 line_start;
in vec2 line_end;

out float v_dist_pixels;
out float v_half_width;

void main() {
    vec2 start_clip = (u_camera_matrix * vec4(line_start, 0.0, 1.0)).xy;
    vec2 end_clip = (u_camera_matrix * vec4(line_end, 0.0, 1.0)).xy;

    vec2 start_screen = start_clip * u_viewport_size * 0.5;
    vec2 end_screen = end_clip * u_viewport_size * 0.5;

    vec2 line_dir = end_screen - start_screen;
    float line_len = length(line_dir);
    vec2 dir_normalized = line_len > 0.0 ? line_dir / line_len : vec2(1.0, 0.0);
    vec2 perp = vec2(-dir_normalized.y, dir_normalized.x);

    float half_width = u_point_size * 0.5 + 1.0;

    float along = position.x;
    float across = position.y;

    vec2 screen_pos = mix(start_screen, end_screen, along) + perp * across * half_width;

    vec2 clip_pos = screen_pos / (u_viewport_size * 0.5);

    gl_Position = vec4(clip_pos, 0.0, 1.0);
    v_dist_pixels = across * half_width;
    v_half_width = u_point_size;
}
@end

/*
========================================================================
    ANTIALIASED LINE FRAGMENT SHADER
========================================================================
*/
@fs fs_line

in float v_dist_pixels;
in float v_half_width;

out vec4 color;

void main() {
    float dist = abs(v_dist_pixels);
    float half_width = v_half_width * 0.5;
    float alpha = 1.0 - smoothstep(half_width - 0.5, half_width + 0.5, dist);

    if (alpha <= 0.0) {
        discard;
    }

    color = vec4(.5, .5, 1.0, alpha);
}
@end

@program line vs_line fs_line

/*
========================================================================
    FILL PASS VERTEX SHADER
    Renders quads for solid fill where stencil test passes
========================================================================
*/
@vs vs_fill

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
    FILL PASS FRAGMENT SHADER
    Outputs solid fill color
========================================================================
*/
@fs fs_fill

layout(binding=1) uniform fill_fs_params {
    vec4 u_fill_color;
};

out vec4 color;

void main() {
    color = u_fill_color;
}
@end

@program fill vs_fill fs_fill
