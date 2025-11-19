This is the first meaty project of the projects I'm doing here. As such, I need to think about how to tackle it.

First, it's probably a good time to make some organisational decisions. It might still be ok to put all of the code for this project into a single file, but for the next project it probably won't be (as it's going to include almost all of the code from this project, as well as code from other ones) so it might be good to start thinking about organisation now.

Another question I need to answer now is how to actually tackle the triangulation part. The Loop-Blinn paper kinda mentions triangulation as if it's trivial. From the GPU's side, dealing with triangles is trivial, but actually generating them for a curve isn't necessarily.

Options:
- libtess2 - A tesselation library written in C. I would have to try my hand at building bindings for Odin to call into that code, might be a good learning opportunity
- my own algorithm - I'll probably do this eventually, just to get a feel for the principles behind it, but I'm leaning away from this in favour of the library approach
