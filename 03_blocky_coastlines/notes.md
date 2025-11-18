Couldn't get RAD Debugger to work, but I think doing something like the following might work:

1. build the project using `odin build . -debug -o:none`
2. Launch the debugger and point to the created .exe file

It seems like the major learning points for this mini-project are around orchestrating draw calls (one draw call per "feature") and orchestrating user interaction.
I'm quite used to having rather long and messy switch cases and if statements, but it feels right to start getting into types of code here that are a lot easier to reason about, especially as I start supporting richer user interaction.

I won't do it as a part of this project (yet) but I need to think about it for sure, as it will become much easier to abstract and reason about in the future.
