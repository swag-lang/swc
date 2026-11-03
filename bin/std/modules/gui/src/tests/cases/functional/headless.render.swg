#global if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core, Pixel
    using wnd: Wnd

#test
{
    for animated in [false, true]
    {
        var host: Testing.HeadlessHost
        host.setup(48, 32)
        host.setReducedMotion(false)
        let view = Wnd.create'SettledPaintWnd(&host.root, {0, 0, 48, 32})

        // The first paint resolves style and can invalidate layout. Measure an idle tree
        // after that initialization, rather than requiring initialization to be paint-free.
        discard host.render()
        view.paints  = 0
        view.animate = animated
        let image = host.renderSettled()
        Swag.assert(image.pixelColor(20, 16) == (animated ? Argb.White : Argb.Black))
        Swag.assert(view.paints == (animated ? 2 : 1), Format.toString("animated=% paints=% dirty=%", animated, view.paints, host.surface.isDirty).toString())
        Swag.assert(host.app.animator.activeCount() == 0)

        // A later explicit render still repaints: callers may be testing repaint/cache behavior.
        discard host.render()
        Swag.assert(view.paints == (animated ? 3 : 2))
    }
}
#test
{
    var cpu: RenderCpu
    var app: Application
    app.setRenderer(&cpu)

    let surface = expect app.createSurface(0, 0, 160, 96)
    Swag.assert(not app.renderer.needsNativeWindow())
    Swag.assert(surface.nativeRenderHandle() == null)

    surface.show()
    let image = app.renderer.readRenderTarget(&surface.rt, 0, 0, surface.rc.width, surface.rc.height)
    Swag.assert(image.isValid() and image.width == surface.rc.width and image.height == surface.rc.height)
}
#test
{
    const Columns = 8's32
    const Rows    = 8's32

    var host: Testing.HeadlessHost
    host.setup(640, 400)

    for row in Rows
    {
        for column in Columns do
            discard PushButton.create(&host.root, "grid", Math.Rectangle{cast(f32, (column * 78 + 4)), cast(f32, (row * 46 + 4)), 70, 38})
    }

    host.pump()
    host.root.applyLayout()

    // The whole surface: every button is painted.
    host.surface.invalidate()
    host.surface.paintWnd(&host.root)
    Swag.assert(host.surface.paintedWnds == Columns * Rows)
    Swag.assert(host.surface.skippedWnds == 0)

    // One button's rectangle, from a surface that is not already dirty: a widget that asks for
    // its own repaint while painting would otherwise widen the region this measures. The other
    // buttons are outside it by more than the margin a window is allowed to paint into, so they
    // never reach the painter at all.
    host.surface.isDirty = false
    host.surface.invalidateRect({4, 4, 70, 38})
    host.surface.paintWnd(&host.root)
    Swag.assert(host.surface.paintedWnds + host.surface.skippedWnds == Columns * Rows)
    Swag.assert(host.surface.paintedWnds < 12)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)

    let button = PushButton.create(&host.root, "edge", {200, 120, 80, 40})
    host.pump()
    host.root.applyLayout()

    host.surface.isDirty = false
    host.surface.invalidateRect(button.paintExtent(button.surfaceRect()))
    host.surface.paintWnd(&host.root)
    Swag.assert(host.surface.paintedWnds == 1 and host.surface.skippedWnds == 0)

    host.surface.isDirty = false
    host.surface.invalidateRect({0, 0, 8, 8})
    host.surface.paintWnd(&host.root)
    Swag.assert(host.surface.paintedWnds == 0 and host.surface.skippedWnds == 1)
}
