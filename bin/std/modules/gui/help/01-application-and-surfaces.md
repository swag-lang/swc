# Application and surfaces

[[Gui.Application]] owns the renderer, theme, input state, surfaces, timers, and
event queue. A typical program creates one application value, creates its main
[[Gui.Surface]], populates the surface's root view, then enters
[[Gui.Application.run]].

```swag
using Core, Gui

var app: Application

#main
{
    let surface = notnull (try app.createSurface(
        100, 100, 640, 420, SurfaceFlags.OverlappedWindow))
    surface.setTitle("Tasks")

    let view = surface.getView()
    PushButton.create(view, "Add task")

    surface.show()
    return app.run()
}
```

The first surface initializes the shared Pixel renderer and default theme.
Additional surfaces belong to the same application and participate in the same
event loop.

Use [[Gui.Application.postEvent]] to enqueue work for the UI loop.
[[Gui.Application.sendEvent]] dispatches immediately and should only be used when
the caller is already on the UI thread and understands event propagation.
