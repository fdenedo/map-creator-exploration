package main

import sapp "shared:sokol/app"
import sg "shared:sokol/gfx"
import shelpers "shared:sokol/helpers"
import "base:runtime"
import "core:log"

default_context: runtime.Context

state: struct {
    shader: sg.Shader,
    pipeline: sg.Pipeline,
    v_buffer: sg.Buffer,
}

main :: proc() {
    context.logger = log.create_console_logger()
    default_context = context

    log.debug("Hellope")

	sapp.run({
		init_cb = init,
		frame_cb = frame,
		cleanup_cb = cleanup,
		event_cb = event,
		width = 800,
		height = 600,
		window_title = "01 Hello Square",
		allocator = sapp.Allocator(shelpers.allocator(&default_context)),
		logger = sapp.Logger(shelpers.logger(&default_context)),
	})
}

init :: proc "c" () {
    context = default_context

    // Set up the graphics module
	sg.setup({
	    environment = shelpers.glue_environment(), // What is available to us on the hardware?
		allocator = sg.Allocator(shelpers.allocator(&default_context)),
		logger = sg.Logger(shelpers.logger(&default_context)),
	})

	state.shader = sg.make_shader(main_shader_desc(sg.query_backend()))
	state.pipeline = sg.make_pipeline({
	    shader = state.shader,
		primitive_type = .TRIANGLE_STRIP,
		layout = {
		    attrs = {
				ATTR_main_position = { format = .FLOAT2 },
				ATTR_main_v_color = { format = .FLOAT4 },
			}
		}
	})

	// Coordinates here have (0, 0) at screen centre
	vertices := []f32 {
	    -0.5, -0.5,     1.0, 0.0, 0.0, 1.0,
		-0.5,  0.5,     0.0, 1.0, 0.0, 1.0,
		 0.5, -0.5,     0.0, 1.0, 0.0, 1.0,
		 0.5,  0.5,     0.0, 0.0, 1.0, 1.0,
	}
	state.v_buffer = sg.make_buffer({
	    data = { ptr = raw_data(vertices), size = len(vertices) * size_of(vertices[0])}
	})
}

frame :: proc "c" () {
	context = default_context

	// The frame procedure is where we orchestrate what happens when creating a frame
	// This is usually where we'll have draw calls etc.
	// Remember with most graphics things, we need to make passes (need some way to begin and end a pass)

	// What is a swapchain?
	pass := sg.Pass {
	    swapchain = shelpers.glue_swapchain() // get this swapchain from the app
	}
	sg.begin_pass(pass)

	// To draw things with sokol, we need
	// - a pipeline (a program that specifies how to draw),
	// - a shader (GPU program that knows how to process vertex data),
	// - bindings (some vertex data) stored in buffers - what we want to draw
	sg.apply_pipeline(state.pipeline)
	sg.apply_bindings({
        vertex_buffers = { 0 = state.v_buffer }
	})

	// To get a perfect square, we need to take aspect ratio into account
	// Pass it in as a uniform (applied to all vertices)
	uniforms := Vs_Params {
	    u_aspect_ratio = sapp.widthf() / sapp.heightf()
	}
	sg.apply_uniforms(UB_vs_params, { ptr = &uniforms, size = size_of(uniforms) })

	sg.draw(0, 4, 1)

	sg.end_pass()

	sg.commit() // replace the data currently in the buffer with the new data
}

cleanup :: proc "c" () {
	context = default_context

	sg.destroy_buffer(state.v_buffer) // Is this necessary?
	sg.destroy_pipeline(state.pipeline) // Is this necessary?
	sg.destroy_shader(state.shader) // Is this necessary?

	sg.shutdown() // Don't need this in the normal case, but for hot reloading etc. it's useful
}

event :: proc "c" (event: ^sapp.Event) {
    context = default_context
    // log.debug(event.type)
}
