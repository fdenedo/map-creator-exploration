@header package main
@header import sg "shared:sokol/gfx"

@vs vs

layout(binding=0) uniform vs_params {
    mat4 u_camera_matrix;
};

in vec2 position;

void main() {
    vec4 pos_homogeneous = vec4(position, 0.0, 1.0);
    vec4 transformed = u_camera_matrix * pos_homogeneous;

    gl_Position = vec4(transformed.xy, 0.0, 1.0);
}
@end

@vs vs_quad_loop_blinn

layout(binding=0) uniform vs_params {
    mat4 u_camera_matrix;
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

@fs fs

out vec4 color;

void main() {
    color = vec4(0.0, 0.0, 0.0, 1.0);
}
@end

@fs fs_quad_loop_blinn

in vec2 v_uv;
out vec4 color;

void main() {
    float t = v_uv.y - v_uv.x * v_uv.x;

    if (t < 0.0) {
        color = vec4(1.0, 0.0, 0.0, 1.0);
    } else {
        color = vec4(0.0, 1.0, 0.0, 1.0);
    }
}
@end

@program main vs fs
@program quad_loop_blinn vs_quad_loop_blinn fs_quad_loop_blinn
