This is the first meaty project of the projects I'm doing here. As such, I need to think about how to tackle it.

First, it's probably a good time to make some organisational decisions. It might still be ok to put all of the code for this project into a single file, but for the next project it probably won't be (as it's going to include almost all of the code from this project, as well as code from other ones) so it might be good to start thinking about organisation now.

Another question I need to answer now is how to actually tackle the triangulation part. The Loop-Blinn paper kinda mentions triangulation as if it's trivial. From the GPU's side, dealing with triangles is trivial, but actually generating them for a curve isn't necessarily.

Options:
- libtess2 - A tesselation library written in C. I would have to try my hand at building bindings for Odin to call into that code, might be a good learning opportunity
- my own algorithm - I'll probably do this eventually, just to get a feel for the principles behind it, but I'm leaning away from this in favour of the library approach

I think for this project right now, I'll focus on making the code a bit more modular, as there is a lot of code I will want to reuse going forward, and starting with a simple toy project that demonstrated Loop-Blinn working, so I can easily port that and get it working with the more sophisticated spline drawing I want to get involved with in the next project. I'll also want to bring the code that closes "coastlines" from project 2.

This is also my first attempt at implementing a paper.

So I added code to allow me to switch between a quadratic curve and a cubic curve, as the quadratic case is much easier to work with. It was almost magical. All I had to do was send a bit more data with each control point, corresponding to texture coordinates. The first gets [0, 0], the second, [0, 0.5] and the third, [1, 1]. It turns out (that Loop and Blinn proved) that for any quadratic parametric curve, evaluating the implicit function u^2 - v = < 0 (where each of those coordiantes above are [u,v]) can be evaluated against each pixel, and correctly coloured depending on what the sign of the result is.
