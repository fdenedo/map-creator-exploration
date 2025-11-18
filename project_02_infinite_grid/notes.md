In 2D, a camera can be described simply using a position (offset) and a zoom amount.

Then pass the values as a uniform to the shader.

```glsl
layout(binding=0) uniform vs_params {
    float u_aspect_ratio;
    float u_camera_x;
    float u_camera_y;
   	float u_camera_zoom;
};

void main() {
    float x = (position.x - u_camera_x) * u_camera_zoom;
    float y = (position.y * u_aspect_ratio - u_camera_y) * u_camera_zoom;

    gl_Position = vec4(x, y, 0.0, 1.0);
}
```

It's important to think about WORLD SPACE and SCREEN SPACE

```glsl
// This represents transforming in World Space (zoom is preformed before taking camera offset into consideration)
float x = (position.x * u_camera_zoom) - u_camera_x;
float y = (position.y * u_camera_zoom * u_aspect_ratio) - u_camera_y * u_aspect_ratio;
```

```glsl
// This represents transforming in Screen Space (zoom happens after calculating pan position)
float x = (position.x - u_camera_x) * u_camera_zoom;
float y = (position.y * u_aspect_ratio - u_camera_y) * u_camera_zoom;
```

For a mapping application, we want the MOUSE POSITION to be the centre of the zoom

I think it might be useful to think of screen space as what you see. It's essentially what is rendered to the window.
World space is the underlying representation. Maybe I can be more accurate about that.


## From AI
The Position vs. Delta Mental Model
The Core Confusion:
You were mixing up absolute positions ("where something is") with relative offsets ("how far something moved").
The Aha Moment
Positions need a reference frame:

"The mouse is at pixel (400, 300)" → needs to know where (0,0) is
Converting screen position → world position requires knowing where the camera is looking
Formula: world_pos = (screen_pos - center) / zoom + camera_pos

Deltas are reference-free:

"The mouse moved 50 pixels right" → doesn't matter where it started
Converting screen delta → world delta only needs the scale factor
Formula: world_delta = screen_delta / zoom

The Trick That Got You
Your screen_to_world() function had + state.camera.x in it. That's the telltale sign: "This converts positions, not deltas!"
When you fed it a delta, you were essentially saying: "Take this offset of 50 pixels, pretend it's a position, and add the camera location to it." Nonsense! The camera's position has nothing to do with how far you dragged.
Quick Mental Check for the Future
When you're about to convert something:
Ask yourself: "Is this value telling me WHERE something is, or HOW FAR something moved?"

WHERE (position) → needs camera position in the formula
HOW FAR (delta/offset) → only needs zoom/scale

Bonus tip: Deltas never have - 1.0 when converting from pixels to NDC, because they're measuring a distance, not a location. You don't center a distance!

This is exactly the kind of thing that makes matrices nice - they let you clearly separate "transform a position" from "transform a direction/delta" (using w=1 vs w=0). But you've now earned that understanding the hard way, which means it'll stick! 🎉

The Calculus Lens
Think about what you're really doing when you drag the mouse:
You're computing the derivative!
When you calculate mouse_delta = current_mouse - previous_mouse, you're approximating:
dx/dt ≈ Δx/Δt
The mouse position is a function of time: mouse(t). You're not interested in the absolute value mouse(t) - you want the rate of change dmouse/dt.
Here's the key insight:

Position is like f(x) - the actual value of the function
Delta/velocity is like f'(x) - the derivative

And here's the beautiful part: Derivatives don't care about constant offsets!
If f(x) = x + C, then f'(x) = 1 regardless of what C is.
That's why camera position doesn't appear in your delta formula - it's a constant offset that vanishes when you take the derivative!
The Chain Rule Connection
When you do world_delta = screen_delta / zoom, you're actually applying the chain rule:
d(world)/dt = d(world)/d(screen) × d(screen)/dt
Where d(world)/d(screen) = 1/zoom (the Jacobian!)

## The Algorithm
So, first we started by drawing lines at an arbitrary distance apart from each other (0.1 world unit). We didn't really care how far apart they were from a pixel perspective. Zooming in leaves lines very close together, and the whole grid becomes small and is clearly not infinite. Zooming out leaves only a portion of a few lines visible in the window, even though data for all the non-visible ones are still being sent to the GPU.

So we can start by defining the minimum distance between lines. Let's say 10px. That is a screen space distance. We can calculate how much that represents in world units by dividing the total number of pixels in one direction of the window (x or y) by the number of world units that are visible in that direction (using camera zoom).

e.g. 
  If 1000px = 800 world units, then 1px = 0.8 world units.
  Then the minimum world spacing is `minimum pixel spacing / world units per pixel`
  => `10 / 0.8 = 12.5`
  
In this case, then, each line needs to be at least 12.5 world units apart. If we draw lines every 10 pixels, that's how far apart they'll be. But 12.5 is maybe not a value I want to represent. It's not too bad, but let's say we only want to represent multiples of 10 for now (we could also say integer exponents of 10, or `10^x` where `x` is an integer, so 0.1, 0.01 are fine as `10^-1`, `10^-2` etc.)

So here we can use logarithms. Essentially, start by asking "what number do I need to raise 10 to the power of to get 12.5?". In this case, it's roughly 1.097. We can then round up to the nearest whole number (`ceil(1.097) = 2`), and then raise 10 to the power of that value (10^2 = 100). So now, we know that these lines will be 100px apart.


Finally got it working! I also replaced the uniforms with a single camera matrix (which matches what I will end up doing in the 3D case).

Things left to think about:

- Camera-relative rendering: My current float coordinates will break down at very large values. Remember that, if the range is the same, the GPU doesn't necessarily care if im looking at points near the origin or 1 million units away from it. Perhaps try it here - see if it breaks when going really far away (move the camera programattically)
- Projection, View, Model matrices: right now my 2D camera matrix handles aspect ratio. This goes away with a proper MVP matrix strategy :)
- Maybe think about adding minor/major grid lines
- Right now it's not really infinite zoom - I probably need to think about camera-relative rendering in order to make it work
