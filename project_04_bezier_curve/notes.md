For cubic Bezier curves, a naive first approach:

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
