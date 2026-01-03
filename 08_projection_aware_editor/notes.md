# Challenges

Up to this point, I've been deferring the problem of filling polygons and drawing great-arcs in the projection. I really need to solve these problems now, before going too much further.

## Clipping

The first issue becomes clear with Orthographic projection. Right now, features on the occluded hemisphere of the projection are still visible (where the difference between A - a vector from the centre of the sphere to that feature's points - and B - a vector from the centre of the sphere to the centre of the projection - exceeds 90°).

I need to make points on the other side invisible. A first attempt could be to just calculate the dot product between vectors A and B and if that exceeds 0, not project that point. To see the issue with this, imagine a polygon that is described by a ring of points, where half of those points are on the visible hemisphere, and half are occluded. If we set up the projection to not project the occluded points, those points will correctly be invisible. But what of the polygon? The polygon will end up being an incomplete line.

We need to consider the polygon's intersection with the clip boundary - the boundary between the visible hemisphere and the cooluded hemisphere. The visible part of the polygon should be closed along the clip boundary to keep a complete polygon on the visible hemisphere.

## Straight Edges on a Globe

The next issue I want to think about is the fact that, right now (at least when drawing GeoJSON polygons) I am representing the lines between points as just that - straight lines. This is fine for GeoJSON technically, at least according to the specification, but it means that points on the lines between points described are actually inside the globe, not on its surface.

In order to represent this properly (and allow for splitting lines etc.) I probably need to represent the lines between points as geodesics - that is the line connecting two points should represent an arc of the circle whose radius and centre point are the same as the globes - a great circle.
