In Sokol, there are references to `cb_`. What is cb?

We need to precompile shaders to use with sokol (turn Vulkan-style .glsl files into .odin files)

We can use the corresponding .exe file from the `sokol-tools-bin` repo
Now I can run:

```bat
tools\sokol-shdc.exe -i project_01_hello_square/shader.glsl -o project_01_hello_square/shader.odin -f sokol_odin -l hlsl5
```

To make sure the Odin that is generated is well-formed, add a `@header` to add the package name

## Asking AI about Global State/Variables

Start Simple (Months 1-3)

```odin
// Just use a direct global - it's fine!
state: struct {
    pass_action: sg.Pass_Action,
    camera: Camera,
    // ...
}

main :: proc() {
    state.camera.zoom = 1.0
    // ... just use it
}
```

Why: One less thing to think about. You're learning graphics, not memory management.
Add Pointer Later If Needed (Month 4+)

```odin
State :: struct {
    // ... your state
}

g: ^State

main :: proc() {
    g = new(State)
    defer free(g)  // Clean shutdown
    
    // ... rest of code
}
```

To pass attribues to the shader, add them to the .glsl file, and look at the generated shader file to see what the attribute's name is. e.g. here, we have
`ATTR_main_position`

The convention is to use a prefix for attributes, like `a` for `attribute`

Something I just realised is the coordinates I'm passing to the GPU are nromalised, they represent a ratio, relative to the aspect ratio of the window!
Normalised Device Coordinates - NDC

The sokol framework is basically:
  init -> frame -> cleanup
