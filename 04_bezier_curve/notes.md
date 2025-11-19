For cubic Bezier curves, de Casteljau's Algorithm:

```odin
evaluate_bezier_cubic :: proc(p0, p1, p2, p3: [2]f32, t: f32) -> [2]f32 {
    a0 := lerp2d(p0, p1, t)
    a1 := lerp2d(p1, p2, t)
    a2 := lerp2d(p2, p3, t)

    b0 := lerp2d(a0, a1, t)
    b1 := lerp2d(a1, a2, t)

    return lerp2d(b0, b1, t)
}
```

Cool things I learned here were about adaptive sampling, and I got to see multiple pipelines in action

So this is the first time I started using multiple pipelines (.LINE_STRIP, .LINES and .POINTS). I had a few issues with the orchestration of the pipelines at first, as I was using the same shader to draw the handles as I had been using to draw the curve. I added the size attribute, but didn't realise that I then had to pass in the size attribute to every pipeline that uses that shader. That led me towards just making another shader to draw the handles as points.

Then I bumped into another interesting issue. It turns out that the idea of a "point" isn't well supported across GPU backends. For example, with OpenGL, there is a property you need to turn on in order to be able to change the point size of point primitives - something like `glEnable(GL_PROGRAM_POINT_SIZE)`. For DirectX3D11, it's not supported almost at all. Just a bit of digging, however, led me to the solution, which is something I had already worked with going through the Three.js Journey course. In order to draw particles, I could use a buffer to determine the locations of each of the particles, and then I could render an instance of a billboard quad, which I could then use a shader to draw shapes on. That's not limited to 3D. I can do something very similar in 2D as well.

There's also the consideration that even though the position of the handles is defined in world-space, the size and interactivity of them should be defined in screen space (when really zoomed in, you don't want the handles to become imperceptible).

It might be useful here to also think about instancing. For this project, we'll just draw handles as small x's and leave that for Project 6 (where we actually create the base editor).

To make note of the pattern I used to orchestrate the two pipelines:

```odin
sg.begin_pass({
    action = state.pass_action,
    swapchain = shelpers.glue_swapchain()
})

camera_mat := camera_matrix(state.camera, state.aspect_ratio)
uniforms := Vs_Params {
    u_camera_matrix = transmute([16]f32)camera_mat,
}

sg.apply_pipeline(state.curve_pipeline)
sg.apply_bindings({ vertex_buffers = { 0 = state.curve_v_buffer } })
sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })
sg.draw(0, len(state.vertices), 1)

sg.apply_pipeline(state.handle_pipeline)
sg.apply_bindings({ vertex_buffers = { 0 = state.handle_buffer } })
sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })
sg.draw(0, len(state.control_points), 1)

sg.end_pass()
sg.commit()
```
