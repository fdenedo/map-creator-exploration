# Polygon Filling Implementation Plan

## Overview
Plan for implementing polygon filling using **true stencil-and-cover** strategy with Loop-Blinn curve rendering. This approach scales to arbitrarily complex paths (landmasses with 10,000+ vertices) without requiring O(n²) triangulation algorithms.

## Why Stencil-and-Cover?

### The Problem with Triangulation
- **Ear clipping**: O(n²) - too slow for large landmasses
- **Delaunay/Sweep-line**: O(n log n) - better, but still complex CPU work
- **Both require**: Distinguishing interior triangles vs curved boundary triangles

### The Stencil-and-Cover Solution
**Key insight**: The GPU stencil buffer IS your triangulation. Let the GPU determine what's "inside"!

**How it works:**
1. **Stencil Pass**: Render simple triangle fan to stencil buffer using winding rules
   - O(n) geometry generation (trivial!)
   - GPU increments/decrements stencil counter per triangle
   - Result: Stencil buffer knows which pixels are inside the polygon

2. **Cover Pass**: Render geometry that "covers" the path
   - For curved segments: Render quads with Loop-Blinn shader
   - For fill: Render one large quad over entire bounding box
   - Only pixels passing stencil test get colored

**Advantages:**
- Scales to landmasses: Only O(n) CPU work regardless of complexity
- GPU does the heavy lifting
- Handles self-intersecting paths via winding numbers
- Industry standard (NV_path_rendering, Skia, modern vector renderers)

---

## Current Architecture Summary

### Data Structures (in `geometry.odin`)
```odin
Point :: struct {
    id:         int,
    handle_in:  WorldVec2,      // Left bezier control handle
    pos:        WorldVec2,      // Anchor point position
    handle_out: WorldVec2,      // Right bezier control handle
}

Path :: struct {
    id:     int,
    points: [dynamic]Point,     // Array of control points
    closed: bool,               // Whether path forms a closed polygon
}
```

### Existing Infrastructure
- **GPU-resident bezier evaluation** - Can use Loop-Blinn shader for curve filling
- **Adaptive curve sampling** - Half-pixel tolerance: `screen_to_world(0.5, camera, false)`
- **Shader system** - sokol-shdc for GLSL compilation
- **Instanced rendering pattern** - Scales to many polygons
- **Command pattern** - Easy to add fill color/pattern commands
- **Camera system** - Full world/screen transformation pipeline

### Reference Implementation
Project 05 (`05_loop_blinn`) contains:
- Quadratic Bezier Loop-Blinn implementation (can adapt for cubic or approximate)
- `ControlPoint_Quad` with UV coordinates
- `quad_loop_blinn_shader_desc()` shader pipeline

---

## Phase 1: Data Structure Extensions

**In `geometry.odin`:**

Add fill properties to `Path`:
```odin
Path :: struct {
    id:         int,
    points:     [dynamic]Point,
    closed:     bool,
    fill_color: [4]f32,          // RGBA fill color
    has_fill:   bool,             // Whether to render fill
}
```

Create new geometry output types for stencil-and-cover:
```odin
// Simple vertex for stencil pass (just position)
StencilVertex :: struct {
    pos: WorldVec2,
}

// Quad for curved segments in cover pass
CurveQuad :: struct {
    // Quad corners (bounding box of curve)
    p0, p1, p2, p3: WorldVec2,
    // Cubic bezier control points (passed to shader)
    cp0, cp1, cp2, cp3: WorldVec2,
}

// Geometry for entire fill operation
FillGeometry :: struct {
    // Stencil pass: triangle fan vertices (one per path)
    stencil_fans: [dynamic]StencilVertex,
    fan_counts:   [dynamic]int,            // Triangles per fan

    // Cover pass: quads for curved segments
    curve_quads:  [dynamic]CurveQuad,

    // Cover pass: bounding boxes for solid fill
    fill_boxes:   [dynamic][4]WorldVec2,   // 4 corners per path

    // Colors per path
    colors:       [dynamic][4]f32,
}
```

---

## Phase 2: Stencil Pass Geometry Generation

**In `geometry.odin`:**

Generate simple triangle fan for winding number computation:
```odin
generate_stencil_fan :: proc(path: Path, out: ^[dynamic]StencilVertex) -> int {
    if !path.closed || len(path.points) < 3 do return 0

    // Compute centroid as fan center
    centroid := WorldVec2{0, 0}
    for point in path.points {
        centroid += point.pos
    }
    centroid /= f32(len(path.points))

    // Generate fan: centroid + each edge vertex
    // GPU will form triangles: (centroid, v[i], v[i+1])
    append(out, StencilVertex{centroid})

    for point in path.points {
        append(out, StencilVertex{point.pos})
    }

    // Close the loop
    append(out, StencilVertex{path.points[0].pos})

    // Return triangle count: n vertices = n-1 triangles
    return len(path.points)
}
```

**Key insight:** This is O(n) and trivially simple. No complex algorithms needed!

---

## Phase 3: Cover Pass Geometry Generation

**In `geometry.odin`:**

### 3A: Curve Quad Generation

For each curved segment, generate a quad that covers the curve's bounding box:
```odin
generate_curve_quads :: proc(path: Path, out: ^[dynamic]CurveQuad) {
    if !path.closed || !path.has_fill do return

    // For each segment in the path
    for i in 0..<len(path.points) {
        p_start := path.points[i]
        p_end   := path.points[(i + 1) % len(path.points)]

        // Check if segment is curved (handles not collinear)
        if !is_segment_linear(p_start, p_end) {
            // Cubic control points
            cp0 := p_start.pos
            cp1 := p_start.handle_out
            cp2 := p_end.handle_in
            cp3 := p_end.pos

            // Compute axis-aligned bounding box
            bbox := compute_bezier_bbox(cp0, cp1, cp2, cp3)

            // Create quad covering the bbox
            append(out, CurveQuad{
                // Quad corners
                p0 = WorldVec2{bbox.min.x, bbox.min.y},
                p1 = WorldVec2{bbox.max.x, bbox.min.y},
                p2 = WorldVec2{bbox.max.x, bbox.max.y},
                p3 = WorldVec2{bbox.min.x, bbox.max.y},
                // Control points (for shader)
                cp0 = cp0, cp1 = cp1, cp2 = cp2, cp3 = cp3,
            })
        }
    }
}

is_segment_linear :: proc(p_start, p_end: Point, epsilon := 0.001) -> bool {
    // Check if handles are collinear with endpoints
    // (i.e., handles lie on the straight line between points)
    // If so, this is just a straight line segment
    // ... implementation details ...
}

compute_bezier_bbox :: proc(p0, p1, p2, p3: WorldVec2) -> struct{min, max: WorldVec2} {
    // Compute tight bounding box for cubic bezier
    // Need to check endpoints + find extrema by solving derivative = 0
    // ... implementation details ...
}
```

### 3B: Fill Box Generation

Generate a single quad covering the entire path for solid fill:
```odin
generate_fill_box :: proc(path: Path) -> [4]WorldVec2 {
    if !path.closed || !path.has_fill do return {}

    // Compute bounding box of entire path
    min_x, min_y := max(f32), max(f32)
    max_x, max_y := min(f32), min(f32)

    for point in path.points {
        min_x = min(min_x, point.pos.x)
        min_y = min(min_y, point.pos.y)
        max_x = max(max_x, point.pos.x)
        max_y = max(max_y, point.pos.y)
    }

    // Return 4 corners as quad
    return [4]WorldVec2{
        {min_x, min_y},
        {max_x, min_y},
        {max_x, max_y},
        {min_x, max_y},
    }
}
```

### 3C: Main Geometry Generation

```odin
generate_fill_geometry :: proc(es: ^EditorState, out: ^FillGeometry) {
    clear(&out.stencil_fans)
    clear(&out.fan_counts)
    clear(&out.curve_quads)
    clear(&out.fill_boxes)
    clear(&out.colors)

    for path in es.paths {
        if !path.closed || !path.has_fill do continue

        // Stencil pass: generate triangle fan
        fan_start := len(out.stencil_fans)
        tri_count := generate_stencil_fan(path, &out.stencil_fans)
        append(&out.fan_counts, tri_count)

        // Cover pass: generate curve quads
        generate_curve_quads(path, &out.curve_quads)

        // Cover pass: generate fill box
        fill_box := generate_fill_box(path)
        append(&out.fill_boxes, fill_box)

        // Store color
        append(&out.colors, path.fill_color)
    }
}
```

---

## Phase 4: Cubic to Quadratic Approximation (Optional)

**In `bezier.odin`:**

If you want to use quadratic Loop-Blinn from project 05 instead of extending to cubic:

```odin
QuadraticBezier :: struct {
    p0, p1, p2: WorldVec2,
}

// Approximates cubic with multiple quadratics
approximate_cubic_with_quadratics :: proc(
    p0, p1, p2, p3: WorldVec2,
    tolerance: f32,
    allocator := context.allocator
) -> []QuadraticBezier {
    // Method 1: Simple subdivision at midpoint
    // Method 2: Least-squares fitting
    // Method 3: Adaptive subdivision based on curvature

    // For now, simple approach: split cubic at t=0.5
    // and approximate each half with a quadratic

    result := make([dynamic]QuadraticBezier, allocator)

    // Split cubic at t=0.5
    left, right := split_bezier_cubic(p0, p1, p2, p3)

    // Approximate each half
    append(&result, fit_quadratic_to_cubic(left[0], left[1], left[2], left[3]))
    append(&result, fit_quadratic_to_cubic(right[0], right[1], right[2], right[3]))

    return result[:]
}

fit_quadratic_to_cubic :: proc(p0, p1, p2, p3: WorldVec2) -> QuadraticBezier {
    // Fit quadratic through endpoints and approximate middle
    // Control point: 3/4 * (p1 + p2) - 1/4 * (p0 + p3)
    q1 := 0.75 * (p1 + p2) - 0.25 * (p0 + p3)
    return QuadraticBezier{p0, q1, p3}
}
```

**Note:** You can also extend Loop-Blinn to handle cubic curves directly. This involves:
- Computing texture coordinates for cubic implicit equation
- Classifying cubic types (serpentine, cusp, loop, etc.)
- More complex fragment shader

For simplicity, start with quadratic approximation.

---

## Phase 5: Fill Renderer Implementation

**In `render.odin`:**

Implement `FillRenderer` with two-pass rendering:

```odin
FillRenderer :: struct {
    // Stencil pass pipeline (no color writes)
    stencil_pip:  sg.Pipeline,
    stencil_bind: sg.Bindings,
    stencil_vbuf: sg.Buffer,

    // Cover pass pipelines
    fill_pip:     sg.Pipeline,      // Simple solid fill
    curve_pip:    sg.Pipeline,      // Loop-Blinn curves
    fill_bind:    sg.Bindings,
    curve_bind:   sg.Bindings,
    fill_vbuf:    sg.Buffer,
    curve_vbuf:   sg.Buffer,

    num_paths:    int,
}

fill_renderer_init :: proc() -> FillRenderer {
    fr: FillRenderer

    // === Stencil Pass Pipeline ===
    stencil_pip_desc := sg.Pipeline_Desc{
        shader = sg.make_shader(stencil_shader_desc(sg.query_backend())),

        // No color writes (stencil only)
        colors = {
            0 = {
                write_mask = .NONE,
            },
        },

        // Stencil settings: non-zero winding rule
        stencil = {
            enabled = true,
            front = {
                fail_op      = .KEEP,
                depth_fail_op = .KEEP,
                pass_op      = .INCR_WRAP,  // Increment on CCW triangles
                compare      = .ALWAYS,
            },
            back = {
                fail_op      = .KEEP,
                depth_fail_op = .KEEP,
                pass_op      = .DECR_WRAP,  // Decrement on CW triangles
                compare      = .ALWAYS,
            },
        },

        depth = {
            compare = .ALWAYS,
            write_enabled = false,
        },

        // Front-face = CCW (counter-clockwise)
        face_winding = .CCW,
        cull_mode = .NONE,  // Don't cull, we need both faces for winding

        layout = {
            attrs = {
                ATTR_stencil_position = {format = .FLOAT2},
            },
        },
    }
    fr.stencil_pip = sg.make_pipeline(stencil_pip_desc)

    // === Cover Pass: Fill Pipeline ===
    fill_pip_desc := sg.Pipeline_Desc{
        shader = sg.make_shader(fill_shader_desc(sg.query_backend())),

        // Color writes enabled
        colors = {
            0 = {
                write_mask = .RGBA,
                blend = {
                    enabled = true,
                    src_factor_rgb = .SRC_ALPHA,
                    dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
                },
            },
        },

        // Stencil test: only draw where stencil != 0
        stencil = {
            enabled = true,
            front = {
                compare = .NOT_EQUAL,
                ref = 0,
            },
            back = {
                compare = .NOT_EQUAL,
                ref = 0,
            },
        },

        depth = {
            compare = .ALWAYS,
            write_enabled = false,
        },

        layout = {
            attrs = {
                ATTR_fill_position = {format = .FLOAT2},
            },
        },
    }
    fr.fill_pip = sg.make_pipeline(fill_pip_desc)

    // === Cover Pass: Curve Pipeline ===
    curve_pip_desc := sg.Pipeline_Desc{
        shader = sg.make_shader(loop_blinn_shader_desc(sg.query_backend())),

        // Similar to fill pipeline, but with Loop-Blinn shader
        colors = {
            0 = {
                write_mask = .RGBA,
                blend = {
                    enabled = true,
                    src_factor_rgb = .SRC_ALPHA,
                    dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
                },
            },
        },

        stencil = {
            enabled = true,
            front = {
                compare = .NOT_EQUAL,
                ref = 0,
            },
            back = {
                compare = .NOT_EQUAL,
                ref = 0,
            },
        },

        depth = {
            compare = .ALWAYS,
            write_enabled = false,
        },

        layout = {
            attrs = {
                ATTR_curve_position = {format = .FLOAT2},
                ATTR_curve_uv = {format = .FLOAT2},  // For Loop-Blinn
            },
        },
    }
    fr.curve_pip = sg.make_pipeline(curve_pip_desc)

    // Create buffers (dynamic)
    fr.stencil_vbuf = sg.make_buffer({
        usage = .DYNAMIC,
        size = size_of(StencilVertex) * 10000,  // Adjust as needed
    })

    fr.fill_vbuf = sg.make_buffer({
        usage = .DYNAMIC,
        size = size_of(WorldVec2) * 4 * 1000,  // 4 verts per quad
    })

    fr.curve_vbuf = sg.make_buffer({
        usage = .DYNAMIC,
        size = size_of(CurveVertex) * 4 * 1000,
    })

    return fr
}

fill_renderer_update :: proc(fr: ^FillRenderer, geom: ^FillGeometry) {
    // Upload stencil fan vertices
    sg.update_buffer(fr.stencil_vbuf, {
        ptr = raw_data(geom.stencil_fans),
        size = len(geom.stencil_fans) * size_of(StencilVertex),
    })

    // Upload fill box vertices
    sg.update_buffer(fr.fill_vbuf, {
        ptr = raw_data(geom.fill_boxes),
        size = len(geom.fill_boxes) * size_of([4]WorldVec2),
    })

    // Upload curve quad vertices
    // ... convert CurveQuad to vertex format ...

    fr.num_paths = len(geom.colors)
}

fill_renderer_render :: proc(fr: ^FillRenderer, camera: Camera, geom: ^FillGeometry) {
    // === PASS 1: Stencil ===
    // Clear stencil buffer to 0
    // (handled by sokol_gfx pass action)

    sg.apply_pipeline(fr.stencil_pip)
    sg.apply_bindings(fr.stencil_bind)

    // Set camera uniform
    sg.apply_uniforms(.VS, 0, {
        ptr = &camera.matrix,
        size = size_of(Matrix4),
    })

    // Draw each triangle fan
    offset := 0
    for i in 0..<fr.num_paths {
        tri_count := geom.fan_counts[i]
        sg.draw(offset, tri_count + 2, 1)  // +2 for centroid + close
        offset += tri_count + 2
    }

    // === PASS 2: Cover (Fill) ===
    sg.apply_pipeline(fr.fill_pip)
    sg.apply_bindings(fr.fill_bind)

    // Draw each fill box
    for i in 0..<fr.num_paths {
        // Set color uniform
        sg.apply_uniforms(.FS, 0, {
            ptr = &geom.colors[i],
            size = size_of([4]f32),
        })

        sg.draw(i * 4, 4, 1)  // 4 vertices per quad
    }

    // === PASS 3: Cover (Curves) ===
    sg.apply_pipeline(fr.curve_pip)
    sg.apply_bindings(fr.curve_bind)

    // Draw each curve quad with Loop-Blinn
    for i in 0..<len(geom.curve_quads) {
        // ... apply uniforms and draw ...
    }

    // === PASS 4: Clear Stencil ===
    // (optional, or handle in next frame's pass action)
}
```

---

## Phase 6: Shader Implementation

**In `shader.glsl`:**

### 6A: Stencil Pass Shader

```glsl
@vs stencil_vs
in vec2 position;

uniform stencil_params {
    mat4 camera_matrix;
};

void main() {
    gl_Position = camera_matrix * vec4(position, 0.0, 1.0);
}
@end

@fs stencil_fs
void main() {
    // No color output, stencil only
}
@end

@program stencil stencil_vs stencil_fs
```

### 6B: Fill Pass Shader

```glsl
@vs fill_vs
in vec2 position;

uniform fill_vs_params {
    mat4 camera_matrix;
};

void main() {
    gl_Position = camera_matrix * vec4(position, 0.0, 1.0);
}
@end

@fs fill_fs
uniform fill_fs_params {
    vec4 fill_color;
};

out vec4 frag_color;

void main() {
    frag_color = fill_color;
}
@end

@program fill fill_vs fill_fs
```

### 6C: Loop-Blinn Curve Shader

**Option 1: Quadratic Loop-Blinn (simpler)**
```glsl
@vs curve_vs
in vec2 position;
in vec2 uv;

out vec2 tex_coord;

uniform curve_vs_params {
    mat4 camera_matrix;
};

void main() {
    gl_Position = camera_matrix * vec4(position, 0.0, 1.0);
    tex_coord = uv;
}
@end

@fs curve_fs
in vec2 tex_coord;
out vec4 frag_color;

uniform curve_fs_params {
    vec4 fill_color;
};

void main() {
    // Loop-Blinn implicit equation for quadratic: u^2 - v = 0
    float u = tex_coord.x;
    float v = tex_coord.y;
    float f = u * u - v;

    // Discard pixels outside curve
    // Use smooth discard for antialiasing
    float alpha = 1.0 - smoothstep(-0.01, 0.01, f);
    if (alpha < 0.01) discard;

    frag_color = vec4(fill_color.rgb, fill_color.a * alpha);
}
@end

@program curve curve_vs curve_fs
```

**Option 2: Cubic Loop-Blinn (more complex, but no approximation needed)**
```glsl
// This requires classifying cubic curve type and computing
// appropriate texture coordinates. See Loop & Blinn 2005 paper.
// Can implement later if quadratic approximation isn't sufficient.
```

---

## Phase 7: Integration

**In `main.odin`:**

Add fill geometry and renderer to main state:
```odin
fill_geom: FillGeometry,
fill_renderer: FillRenderer,
```

Initialize in startup:
```odin
fill_renderer = fill_renderer_init()
```

Update geometry generation:
```odin
if editor.should_rerender {
    generate_handle_geometry(&editor, &handle_geom)
    generate_path_geometry(&editor, &path_geom)
    generate_fill_geometry(&editor, &fill_geom)  // NEW

    render_update_geometry(&point_renderer, &handle_geom)
    render_update_geometry(&line_renderer, &path_geom)
    fill_renderer_update(&fill_renderer, &fill_geom)  // NEW
}
```

Update render order:
```odin
render_frame :: proc() {
    // Pass action: clear color AND stencil
    pass_action := sg.Pass_Action{
        colors = {0 = {load_action = .CLEAR, clear_value = {0.1, 0.1, 0.1, 1.0}}},
        stencil = {load_action = .CLEAR, clear_value = 0},
    }

    sg.begin_default_pass(pass_action, sapp.width(), sapp.height())

    // Render fills FIRST (underneath everything)
    fill_renderer_render(&fill_renderer, editor.camera, &fill_geom)

    // Then edges and points on top
    line_renderer_render(&line_renderer, &path_geom, editor.camera)
    point_renderer_render(&point_renderer, &handle_geom, editor.camera)

    sg.end_pass()
    sg.commit()
}
```

---

## Phase 8: User Commands

**In `commands.odin`:**

Add fill toggle command:
```odin
ToggleFill :: struct {
    path_id: int,
}

toggle_fill_execute :: proc(cmd: ^ToggleFill, es: ^EditorState) {
    for &path in es.paths {
        if path.id == cmd.path_id {
            path.has_fill = !path.has_fill
            es.should_rerender = true
            break
        }
    }
}

toggle_fill_undo :: proc(cmd: ^ToggleFill, es: ^EditorState) {
    // Just toggle again
    toggle_fill_execute(cmd, es)
}

SetFillColor :: struct {
    path_id:   int,
    old_color: [4]f32,
    new_color: [4]f32,
}

set_fill_color_execute :: proc(cmd: ^SetFillColor, es: ^EditorState) {
    for &path in es.paths {
        if path.id == cmd.path_id {
            path.fill_color = cmd.new_color
            es.should_rerender = true
            break
        }
    }
}

set_fill_color_undo :: proc(cmd: ^SetFillColor, es: ^EditorState) {
    for &path in es.paths {
        if path.id == cmd.path_id {
            path.fill_color = cmd.old_color
            es.should_rerender = true
            break
        }
    }
}
```

Add keyboard bindings (in `editor.odin`):
```odin
// In editor input handling:
if sapp.get_key_state(.F) == .PRESSED {
    // Toggle fill for currently selected path
    if selected_path, ok := get_selected_path(es); ok {
        cmd := ToggleFill{path_id = selected_path.id}
        history_execute(&es.history, cmd, es)
    }
}

if sapp.get_key_state(.C) == .PRESSED {
    // Cycle through preset colors
    if selected_path, ok := get_selected_path(es); ok {
        colors := [][4]f32{
            {1.0, 0.0, 0.0, 0.5},  // Red
            {0.0, 1.0, 0.0, 0.5},  // Green
            {0.0, 0.0, 1.0, 0.5},  // Blue
            {1.0, 1.0, 0.0, 0.5},  // Yellow
            {1.0, 0.0, 1.0, 0.5},  // Magenta
            {0.0, 1.0, 1.0, 0.5},  // Cyan
        }
        // Cycle to next color
        // ... implementation ...
    }
}
```

---

## Implementation Order (Revised)

### Step 1: Stencil Pass (Basic Test)
**Goal:** Get stencil buffer working with simple test
- Implement Phase 1-2: Data structures + stencil fan generation
- Implement Phase 5A: Stencil pass renderer only
- Implement Phase 6A: Stencil shader
- **Test:** Render stencil buffer as grayscale to verify winding

### Step 2: Cover Pass (Solid Fill)
**Goal:** Fill polygons with solid colors
- Implement Phase 3B: Fill box generation
- Implement Phase 5B: Fill pass renderer
- Implement Phase 6B: Fill shader
- **Deliverable:** Can fill simple closed paths with solid colors

### Step 3: Straight-Edge Testing
**Goal:** Verify stencil-and-cover works for various polygon types
- Test convex polygons (triangle, square, pentagon)
- Test concave polygons (star, L-shape)
- Test self-intersecting polygons (figure-eight)
- **Deliverable:** Robust filling for all straight-edge cases

### Step 4: Curved Edges (Loop-Blinn)
**Goal:** Handle bezier curve boundaries
- Implement Phase 3A: Curve quad generation
- Implement Phase 4: Cubic to quadratic approximation (if using quadratic)
- Implement Phase 5C: Curve pass renderer
- Implement Phase 6C: Loop-Blinn shader
- **Deliverable:** Smooth curved boundaries

### Step 5: Integration & Polish
**Goal:** Full user experience
- Implement Phase 7: Integration into main loop
- Implement Phase 8: User commands and keybindings
- Add visual feedback for fill toggle
- **Deliverable:** Fully interactive fill system

---

## Key Design Decisions

### Rendering Strategy: True Stencil-and-Cover
- **Stencil pass:** Triangle fan with winding rule → determines "inside"
- **Cover pass:** Render quads where stencil test passes
- **Advantage:** O(n) geometry, scales to landmasses, GPU does heavy lifting
- **Trade-off:** Two passes instead of one (negligible performance impact)

### Winding Rule
- **Non-zero winding:** Increment for CCW triangles, decrement for CW
  - Handles self-intersecting paths correctly
  - Supports "holes" in paths (future work)
- **Alternative:** Even-odd (simpler, but doesn't handle complex cases)

### Loop-Blinn: Quadratic vs Cubic
- **Start with quadratic:** Simpler shader, well-documented, project 05 reference
- **Approximate cubic:** Use subdivision or least-squares fitting
- **Future:** Implement cubic Loop-Blinn for perfect accuracy

### Stencil Buffer Setup
- **Clear to 0** at start of frame
- **Non-zero test:** Draw only where stencil != 0
- **No manual clearing:** Let GPU handle it via pass action

---

## Performance Characteristics

### CPU Work: O(n)
- Stencil fan: n vertices → n triangles
- Fill box: 4 vertices (constant)
- Curve quads: k curved segments → k quads (k typically << n)
- **Total:** Linear in number of path points

### GPU Work: Proportional to Fill Area
- Stencil pass: ~n triangles (cheap, no color writes)
- Fill pass: Fill pixels * stencil test
- Curve pass: Curve pixels * stencil test * Loop-Blinn equation
- **Scaling:** Independent of path complexity, only depends on screen coverage

### Example: Landmass with 10,000 Points
- **CPU:** 10,000 vertices → trivial
- **GPU stencil:** 10,000 triangles → 1-2ms (typical)
- **GPU cover:** Depends on zoom level, not point count
- **Result:** Real-time performance even for complex maps

---

## Code Style Guidelines

### Naming Conventions
- Types: `PascalCase` (e.g., `FillRenderer`, `StencilVertex`)
- Procedures: `snake_case` (e.g., `fill_renderer_init`, `generate_stencil_fan`)
- Constants: `SCREAMING_SNAKE_CASE` (e.g., `DEFAULT_FILL_COLOR`)
- Module prefixes: File-based (e.g., `fill_renderer_*` in render.odin)

### Structural Patterns
- Use `distinct` for type safety: `WorldVec2 :: distinct [2]f32`
- Separate geometry types: `StencilVertex` vs `CurveVertex`
- Maybe types for optionals: `Maybe(PathRef)` instead of pointers
- Horizontal separation: One concern per file
- Vertical dataflow: Domain → Geometry → Render → Display

### Resource Management
- Dynamic arrays for collections: `[dynamic]StencilVertex`
- Use `clear()` to reuse allocations (not `delete()`)
- Context allocator by default
- GPU buffers: Dynamic, updated only on `should_rerender`

---

## Testing Strategy

### Phase 1: Stencil Buffer Verification
1. Render stencil buffer as grayscale image
2. Create simple triangle → verify winding increments correctly
3. Create self-intersecting path → verify non-zero rule

### Phase 2: Solid Fill
1. Square path → verify solid fill
2. Concave polygon → verify fill respects shape
3. Multiple paths → verify separate stencil regions

### Phase 3: Edge Cases
1. Very small path (< 1 pixel) → verify doesn't crash
2. Very large path (> screen) → verify clipping
3. Path with 2 points → verify no fill (not closed)

### Phase 4: Curved Boundaries
1. Path with one curved segment → verify Loop-Blinn
2. Path with all curved segments → verify complete boundary
3. Tight curves (high curvature) → verify approximation quality

### Phase 5: Interactivity
1. Toggle fill → verify immediate update
2. Change color → verify color updates
3. Undo/redo → verify state restoration

---

## Known Issues & Future Work

### Current Limitations
- Only convex quadratic curves (Loop-Blinn quadratic)
- No gradient/pattern fills
- No stroke rendering on top of fill
- Single winding rule (non-zero)

### Future Enhancements
- **Cubic Loop-Blinn:** Eliminate quadratic approximation
- **Gradient fills:** Linear, radial, conical
- **Pattern fills:** Textures, hatch patterns, dots
- **Holes in paths:** Use multiple paths with opposite winding
- **Stroke + fill:** Render both with proper compositing
- **Dashed outlines:** Shader-based dash pattern
- **GPU tessellation:** Use geometry shader for adaptive subdivision

### Alternative Approaches
- **SDF-based rendering:** Distance fields instead of Loop-Blinn
- **Multi-sample stencil:** Higher quality antialiasing
- **Hybrid rasterization:** CPU tessellation + GPU fill for very large maps

---

## References

### Papers
- **Loop & Blinn 2005:** "Resolution Independent Curve Rendering using Programmable Graphics Hardware"
- **Nehab & Hoppe 2008:** "Random-Access Rendering of General Vector Graphics"
- **Kilgard & Bolz 2012:** "GPU-accelerated Path Rendering" (NV_path_rendering)

### Existing Code
- `05_loop_blinn/` - Loop-Blinn quadratic Bezier reference
- `06_vector_path_editor/bezier.odin:113-114` - TODO comment about sampling
- `06_vector_path_editor/render.odin` - Existing renderer patterns

### Resources
- **Sokol GFX stencil:** https://github.com/floooh/sokol/blob/master/sokol_gfx.h
- **OpenGL stencil tutorial:** https://learnopengl.com/Advanced-OpenGL/Stencil-testing
- **Skia path rendering:** https://skia.org/ (reference implementation)

### Algorithms
- **Non-zero winding rule:** Standard vector graphics fill algorithm
- **Cubic to quadratic fitting:** Least-squares approximation
- **Bezier bounding box:** Solve derivative = 0 for extrema

### Coordinate Transforms
- `world_to_screen()` - World → Screen (for UI)
- `screen_to_world()` - Screen → World (for tolerance, input)
- `camera_matrix()` - Combined transform for vertex shader
