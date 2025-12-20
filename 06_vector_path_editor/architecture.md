# Architecture Guide for Scaling to a Native App

This document outlines architectural patterns and refinements for scaling the vector path editor into a fully-featured native application.

---

## Current Architecture Overview

The existing codebase follows a clean separation:

```
main.odin       - Orchestration, frame loop, platform callbacks
editor.odin     - State machine, input handling, editor state
commands.odin   - Command pattern for undo/redo
geometry.odin   - Transforms domain data into render-ready geometry
render.odin     - GPU resources, renderers, draw calls
camera.odin     - Camera math, coordinate transformations
shader.odin     - Generated shader bindings (sokol-shdc output)
```

**Data flow:**
```
EditorState → generate_*_geometry() → *Geometry → render_update_geometry() → RenderState → render_frame()
```

**Key patterns already in use:**
- State machine for input handling (IDLE, PANNING, ADDING_POINT, POTENTIAL_DRAG, DRAGGING_POINT)
- Command pattern for undoable operations
- Instanced rendering for points
- Separation of stable geometry (regenerated on data change) from transient state (evaluated per-frame)

---

## 1. Layer Organization

For a larger application, organize into explicit layers with clear dependency rules:

```
app/
├── platform/       # Sokol wrappers, window management, input translation
├── core/           # Domain types (Path, Point, Camera), pure logic
├── editor/         # Editor state machine, commands, tools
├── render/         # Renderers, shaders, GPU resources
└── main.odin       # Orchestration only
```

**Dependency rules:**
- Dependencies flow downward only
- `render/` can import `core/`, but `core/` never imports `render/`
- `editor/` can import `core/`, but not `render/` (communicate via geometry structs)
- `platform/` is imported only by `main.odin` and `render/`

**The geometry layer** sits between `editor/` and `render/`:
- Transforms domain data (paths, points) into render-ready data (vertex arrays, instance buffers)
- Allows editor logic to remain GPU-agnostic
- Enables potential render backend swaps without touching editor code

---

## 2. Event System Refinements

### Current Approach
The state machine with `#partial switch` on event type is solid and should be retained.

### Separating Raw Input from Semantic Actions

For larger applications, consider a two-layer event system:

```odin
// Layer 1: Raw platform events (what Sokol provides)
RawEvent :: sapp.Event

// Layer 2: Semantic editor actions (what tools respond to)
EditorAction :: union {
    SelectPoint,
    StartDrag,
    CommitDrag,
    CancelOperation,
    Pan,
    Zoom,
    AddPoint,
    DeleteSelection,
}

// Translation layer
translate_event :: proc(raw: ^RawEvent, bindings: ^KeyBindings) -> Maybe(EditorAction) {
    // Maps raw input to semantic actions based on current bindings
}
```

**Benefits:**
- Remap keys/mouse bindings without touching tool logic
- Support keyboard shortcuts and menu items with the same action
- Test tools without simulating raw input
- Easier to implement configurable keybindings

### Tool Abstraction

When supporting multiple tools (select, pen, shape, etc.):

```odin
Tool :: struct {
    name:      string,
    cursor:    CursorType,
    on_action: proc(^ToolContext, EditorAction),
    on_enter:  proc(^ToolContext),
    on_exit:   proc(^ToolContext),
}

ToolContext :: struct {
    editor:    ^EditorState,
    tool_data: rawptr,  // Tool-specific state
}
```

Each tool is its own state machine. Switching tools swaps which one receives events. This pattern is used by Blender, Photoshop, Illustrator, and most professional creative software.

---

## 3. Shader Management

### Current Approach
Single `shader.glsl` compiled by sokol-shdc works but will become unwieldy with more shaders.

### Option A: Multiple Source Files

Compile multiple .glsl files into a single output:
```bash
sokol-shdc -i shaders/point.glsl -i shaders/line.glsl -i shaders/fill.glsl -o shader.odin -f sokol_odin -l hlsl5
```

Organize shaders by purpose:
```
shaders/
├── common.glsl         # Shared functions (include)
├── point.glsl          # Point/handle rendering
├── line.glsl           # Curve/line rendering
├── fill.glsl           # Filled shape rendering
├── textured_quad.glsl  # UI, images
└── sdf_shapes.glsl     # SDF-based shape rendering
```

### Option B: Shader Registry

Centralize shader management:

```odin
ShaderID :: enum {
    Point,
    Line,
    Fill,
    TexturedQuad,
    SDFShape,
}

ShaderRegistry :: struct {
    shaders: [ShaderID]sg.Shader,
}

shader_registry_init :: proc(r: ^ShaderRegistry) {
    r.shaders[.Point] = sg.make_shader(point_shader_desc(sg.query_backend()))
    r.shaders[.Line]  = sg.make_shader(line_shader_desc(sg.query_backend()))
    r.shaders[.Fill]  = sg.make_shader(fill_shader_desc(sg.query_backend()))
    // etc.
}

shader_registry_get :: proc(r: ^ShaderRegistry, id: ShaderID) -> sg.Shader {
    return r.shaders[id]
}
```

### Option C: Uniform Block Standardization

As shaders multiply, standardize uniform block layout:

| Slot | Purpose | Update Frequency |
|------|---------|------------------|
| 0 | Common (camera matrix, viewport, time) | Per-frame |
| 1 | Material (color, texture params) | Per-material |
| 2 | Instance (transform, per-object data) | Per-draw |

```odin
// Slot 0 - shared across all shaders
CommonUniforms :: struct #align(16) {
    camera_matrix: matrix[4,4]f32,
    viewport_size: [2]f32,
    time: f32,
    _padding: f32,
}

// Slot 1 - material-specific
MaterialUniforms :: struct #align(16) {
    color: [4]f32,
    // texture indices, material properties, etc.
}
```

---

## 4. Render Architecture

### Current Approach
`PointRenderer` and `LineRenderer` encapsulate pipeline + buffers + draw logic. This is a good pattern.

### Renderer Abstraction

Generalize for more renderer types:

```odin
Renderer :: struct {
    pipeline: sg.Pipeline,
    bindings: sg.Bindings,
    // Common operations
    update:   proc(^Renderer, rawptr, int),
    draw:     proc(^Renderer, ^CommonUniforms),
    destroy:  proc(^Renderer),
}
```

### Render Pass Organization

For complex scenes with multiple passes:

```odin
RenderPassID :: enum {
    Background,
    Geometry,      // Curves, fills
    Handles,       // Control points, guides
    Overlay,       # Selection highlights, hover states
    UI,            // Menus, toolbars
}

RenderPass :: struct {
    id:           RenderPassID,
    render:       proc(^RenderContext),
    clear_action: sg.Pass_Action,
}

// Ordered execution
render_all_passes :: proc(ctx: ^RenderContext, passes: []RenderPass) {
    for &pass in passes {
        sg.begin_pass(/* ... */)
        pass.render(ctx)
        sg.end_pass()
    }
    sg.commit()
}
```

### Batching Strategies

For performance with many objects:

1. **Static geometry**: Update GPU buffers only when data changes (current approach for curves)
2. **Dynamic geometry**: Double/triple buffer for data changing every frame
3. **Transient state**: Resolve per-frame, minimal GPU upload (current approach for hover/selection)

```odin
// Example: Double-buffered dynamic data
DynamicBuffer :: struct {
    buffers: [2]sg.Buffer,
    current: int,
}

dynamic_buffer_update :: proc(db: ^DynamicBuffer, data: []u8) {
    db.current = 1 - db.current  // Swap
    sg.update_buffer(db.buffers[db.current], {ptr = raw_data(data), size = len(data)})
}
```

---

## 5. Command System Enhancements

### Current Implementation
Well-structured with `Command`, `CommandData` union, and `CommandHistory`.

### Command Composition

Group multiple operations into a single undo step:

```odin
CompositeCommand :: struct {
    name: string,
    commands: [dynamic]Command,
}

// Add to CommandData union
CommandData :: union {
    AddPoint,
    ToggleClosePath,
    MovePoint,
    CompositeCommand,  // New
}

execute_composite :: proc(cmd: ^CompositeCommand, state: ^EditorState) {
    for &c in cmd.commands {
        command_execute(c, state)
    }
}

undo_composite :: proc(cmd: ^CompositeCommand, state: ^EditorState) {
    // Undo in reverse order
    #reverse for &c in cmd.commands {
        command_undo(c, state)
    }
}
```

**Use cases:**
- "Move 5 selected points" = 5 MovePoint commands composed
- "Paste" = multiple AddPoint commands composed
- "Transform selection" = move + scale + rotate composed

### Command Serialization

Your `CommandData` union is already serialization-friendly. For save/load or collaborative editing:

```odin
// Commands can reconstruct document state from empty
replay_commands :: proc(commands: []Command, state: ^EditorState) {
    for cmd in commands {
        command_execute(cmd, state)
    }
}

// Or serialize current state directly (simpler for save/load)
```

### Macro Recording

Commands enable macro recording naturally:

```odin
MacroRecorder :: struct {
    recording: bool,
    commands:  [dynamic]Command,
}

// Wrap history_execute to also record
history_execute_and_record :: proc(h: ^CommandHistory, cmd: Command, state: ^EditorState, recorder: ^MacroRecorder) {
    history_execute(h, cmd, state)
    if recorder.recording {
        append(&recorder.commands, cmd)
    }
}
```

---

## 6. Resource Management

For textures, fonts, and other GPU resources:

```odin
ResourceID :: distinct u32

ResourceManager :: struct {
    textures: map[ResourceID]sg.Image,
    samplers: map[ResourceID]sg.Sampler,
    fonts:    map[ResourceID]Font,
    next_id:  ResourceID,
}

resource_load_texture :: proc(rm: ^ResourceManager, path: string) -> ResourceID {
    id := rm.next_id
    rm.next_id += 1
    
    // Load image data, create sg.Image
    img := load_and_create_image(path)
    rm.textures[id] = img
    
    return id
}

resource_get_texture :: proc(rm: ^ResourceManager, id: ResourceID) -> sg.Image {
    return rm.textures[id]
}

resource_destroy :: proc(rm: ^ResourceManager) {
    for _, img in rm.textures {
        sg.destroy_image(img)
    }
    // etc.
}
```

---

## 7. Invalidation and Dirty Flags

### Current Approach
`should_rerender` flag triggers full geometry regeneration.

### Fine-Grained Invalidation

For complex scenes, track what specifically changed:

```odin
DirtyFlags :: bit_set[DirtyFlag]

DirtyFlag :: enum {
    PathGeometry,      // Curves need regeneration
    HandleGeometry,    // Control points changed
    Selection,         // Selection changed (cheap update)
    Camera,            // View transform changed
    UI,                // UI layout changed
}

// In EditorState
dirty: DirtyFlags,

// In frame()
if .PathGeometry in state.editor.dirty {
    generate_path_geometry(&state.editor, &state.path_geo)
}
if .HandleGeometry in state.editor.dirty {
    generate_handle_geometry(&state.editor, &state.handle_geo)
}
// etc.
state.editor.dirty = {}
```

---

## 8. Immediate Priorities

Based on the current codebase:

1. **Extract platform layer**
   - Move Sokol-specific types/callbacks to dedicated files
   - Keep `core/` types (Path, Point, Camera) pure Odin

2. **Formalize the geometry pipeline**
   - Document the canonical flow as the pattern for all new features
   - Ensure new features follow: Domain → Geometry → RenderState → Draw

3. **Add shader organization**
   - Split shaders into multiple .glsl files
   - Add common includes for shared functions

4. **Consider a resource manager**
   - Centralize GPU resource creation/destruction
   - Prepare for textures, fonts, icons

---

## Summary

The current architecture is solid. Key strengths to preserve:
- State machine input handling
- Command pattern for undo/redo
- Geometry as intermediate representation
- Separation of stable vs transient render state

Key areas to evolve:
- Explicit layer boundaries with dependency rules
- Semantic action layer above raw input
- Tool abstraction for multiple editing modes
- Shader registry for growing shader count
- Fine-grained invalidation for performance
