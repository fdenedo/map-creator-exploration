# Challenges

Up to this point, I've been deferring the problem of filling polygons and drawing great-arcs in the projection. I really need to solve these problems now, before going too much further.

## Clipping

The first issue becomes clear with Orthographic projection. Right now, features on the occluded hemisphere of the projection are still visible (where the difference between A - a vector from the centre of the sphere to that feature's points - and B - a vector from the centre of the sphere to the centre of the projection - exceeds 90°).

I need to make points on the other side invisible. A first attempt could be to just calculate the dot product between vectors A and B and if that exceeds 0, not project that point. To see the issue with this, imagine a polygon that is described by a ring of points, where half of those points are on the visible hemisphere, and half are occluded. If we set up the projection to not project the occluded points, those points will correctly be invisible. But what of the polygon? The polygon will end up being an incomplete line.

We need to consider the polygon's intersection with the clip boundary - the boundary between the visible hemisphere and the cooluded hemisphere. The visible part of the polygon should be closed along the clip boundary to keep a complete polygon on the visible hemisphere.

## Straight Edges on a Globe

The next issue I want to think about is the fact that, right now (at least when drawing GeoJSON polygons) I am representing the lines between points as just that - straight lines. This is fine for GeoJSON technically, at least according to the specification, but it means that points on the lines between points described are actually inside the globe, not on its surface.

In order to represent this properly (and allow for splitting lines etc.) I probably need to represent the lines between points as geodesics - that is the line connecting two points should represent an arc of the circle whose radius and centre point are the same as the globes - a great circle.

---

# Solution: Spherical Clipping Pipeline

## Core Idea

- Work in 3D unit sphere space, not in geographic or projected 2D space
- Points are unit vectors: `(x, y, z)` where `x² + y² + z² = 1`
- Rotate the sphere so the projection centre is at `(0, 0, 1)`, making the clip boundary simply `z = 0`
- Visibility becomes a simple check: `z > 0`
- Great circle arcs are interpolated via spherical lerp (slerp)

## Pipeline Steps

1. **Convert to Unit Sphere**
   - `x = cos(lat) * cos(lon)`
   - `y = cos(lat) * sin(lon)`
   - `z = sin(lat)`

2. **Rotate to View Space**
   - Build a rotation matrix that takes the projection centre to `(0, 0, 1)`
   - Fixed cost per frame; each point is then just a matrix multiply

3. **Clip to Hemisphere**
   - Use Sutherland-Hodgman algorithm against the `z = 0` plane
   - For edges crossing the boundary, find intersection along the great circle arc (solvable analytically)
   - Add arc segments along the horizon circle to close clipped polygons

4. **Adaptive Subdivision**
   - For each edge, check angular distance between endpoints
   - If above threshold, subdivide at midpoint via slerp
   - Recurse until edges are short enough
   - Use screen-space error metric: subdivide more when zoomed in

5. **Project to 2D**
   - After rotation, orthographic is trivial: `(x, y, z) → (x, y)`
   - Other projections apply their formula here

6. **Tessellate & Render**
   - Clipped, subdivided polygon is now simple 2D
   - Use ear clipping or similar for triangulation

## Performance Considerations

- Rotation matrix computed once per frame
- Early cull: bounding sphere check to skip entirely occluded polygons
- Small polygons entirely visible: skip clipping
- Cap subdivision recursion depth
- Cache 3D sphere representation of source geometry; redo steps 2-6 on view change

## Design Decisions

- Edges are great circle arcs (geodesics), not straight lines in lat/lon space
- View is dynamic (user rotates, adds/moves points frequently), so cache at sphere level, recompute projection pipeline per frame
- Horizon arc segments use adaptive subdivision based on zoom level for smooth appearance
