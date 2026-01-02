# Projeciton-Aware Editor

## Notes from previous projects

The idea of using layers is a pretty good idea, but it's a bit heavyhanded for this project, as we only have 2 layers: the UI layer and the Map/Editor Layer. Defining these at the app level is perfectly acceptable, as it means we can directly and easily orchestrate exactly how they are supposed to work together.

Think about adding a debug layer, even though most of the things I would want to show in a debug layer are probably useful for the end user to see

Note that this is likely going to be the base of the main application

- [X] Define high-level architecture
- [X] Copy relevant project code from project 07
- [ ] Determine code that is relevant to use from project 06
- [ ] Copy code from project 06
- [ ] Build editor tools
- [ ] Implement keybinds
- [ ] Implement event system
- [ ] Build UI to switch between tools
- [ ] Implement GPU-side projection code
- [ ] Implement true separation between canvas space and screen space
- [ ] Implement code to create projection-aware graticules (inspiration from project 02 and [this Endless Grid YouTube video](https://www.youtube.com/watch?v=RqrkVmj-ntM) )
- [ ] Implement other projections (Equal-Earth, Mollyweide, Mercator)
- [ ] [MAYBE] Build custom UI features (minimal)
- [ ] [MAYBE] Add save/load
- [ ] [MAYBE] Add brush tool to paint pixels directly (raster graphics)
