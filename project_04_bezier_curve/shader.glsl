@header package main
@header import sg "shared:sokol/gfx"

@vs vs_curve

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

@vs vs_handle

layout(binding=0) uniform vs_params {
    mat4 u_camera_matrix;
};

in vec2 position;
in float size;

void main() {
    vec4 pos_homogeneous = vec4(position, 0.0, 1.0);
    vec4 transformed = u_camera_matrix * pos_homogeneous;

    gl_Position = vec4(transformed.xy, 0.0, 1.0);
    gl_PointSize = size;
}
@end

@fs fs

out vec4 color;

void main() {
    color = vec4(0.0, 0.0, 0.0, 1.0);
}
@end

@program curve vs_curve fs
@program handle vs_handle fs
