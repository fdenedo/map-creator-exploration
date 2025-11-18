@header package main
@header import sg "shared:sokol/gfx"

@vs vs

layout(binding=0) uniform vs_params {
    float u_aspect_ratio;
};

in vec2 position;
in vec4 v_color;

out vec4 f_color;

void main() {
    vec2 correctedPosition = vec2(position.x / u_aspect_ratio, position.y);
    gl_Position = vec4(correctedPosition, 0.0, 1.0);
    f_color = v_color;
}
@end

@fs fs

in vec4 f_color;

out vec4 color;

void main() {
    color = f_color;
}
@end

@program main vs fs
