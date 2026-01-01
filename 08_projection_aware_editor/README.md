# Main Architecture

We can imagine the architecture of the main part of the application (the Editor) as having 3 layers:
- **Document:** this is the layer that holds all of the data the user interacts with and edits (raster data, vector splines, polygons, points of interest etc.)
- **Viewport:** this is the layer that determines how the Document data is rendered on the screen. Looking at project 6, the viewport will own the Camera, the Projection etc. The user can set values to determine how the Viewport renders the Document, but the Viewport is ultimately controlled by the application
- **UI:** this is the layer the user interacts with to change settings to influence the Editor and Viewport. For now, we can mainly think of this layer as allowing the user to click buttons to change the tools

The user will interact with and manipulate the Document through the Editor API. The Editor API provides the user with a set of tools that allow them to determine how they wish to manipulate the data.

- Basic support for vector spline manipulation (Pen tool)
- Basic support for raster drawing (Brush tool)

The Command Pattern (see project 06) will be necessary to allow users to Undo/Redo editor actions. The API for the commands needs to be clear, and all actions that it is reasonable to undo/redo need to go through the Command History Controller.

Application
├── Document (contains data - e.g. domain layers, shapes, raster data, GeoJSON, Shapefile)
├── Viewport (camera, rendering document)
└── UI (tools, panels, controls viewport and document)
