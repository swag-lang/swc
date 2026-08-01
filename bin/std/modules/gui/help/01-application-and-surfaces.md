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
        100, 100, 640, 420, SurfaceFlags.StandardWindow))
    surface.setTitle("Tasks")

    let view = surface.view()
    PushButton.create(view, "Add task")

    surface.show()
    return app.run()
}
```

The first surface initializes the selected [[Pixel.IRenderer]] and default theme.
OpenGL is selected by default. To use the CPU renderer or a third-party backend,
select it before creating the first surface; the concrete renderer must outlive
the application:

```swag
var cpu: Pixel.RenderCpu
var app: Application
app.setRenderer(&cpu)
let surface = notnull (try app.createSurface(0, 0, 640, 420))
```

Additional surfaces use the same renderer and participate in the same event loop.
Their painters are bound automatically; paint handlers use the renderer exposed
by [[Gui.PaintContext]].

Use [[Gui.Application.postEvent]] to enqueue work for the UI loop.
[[Gui.Application.sendEvent]] dispatches immediately and should only be used when
the caller is already on the UI thread and understands event propagation.
