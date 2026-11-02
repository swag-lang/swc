#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

struct SettledPaintWnd
{
    using wnd: Wnd
    paints:    u32
    animate:   bool
    value:     f32
}

impl IWnd for SettledPaintWnd
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        if evt.kind != .Content do
            return
        .paints += 1
        if .animate and .paints == 1
        {
            discard .app().animator.animateF32(me,
                                                AnimationChannel.from("test.settled.paint"),
                                                0,
                                                1,
                                                func(wnd, value)
                                                {
                                                    let target = assume cast(*SettledPaintWnd, wnd)
                                                    target.value = value
                                                },
                                                {duration: 100'ms})
        }

        evt.paintContext.painter.fillRect(.clientRect(), .value == 1 ? Argb.White : Argb.Black)
    }
}

// Capturing an idle tree paints it once; a paint-started track reaches its endpoint before capture.
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
        view.paints = 0
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

// An application can select the CPU backend before its first surface; creation then follows the
// normal GUI lifecycle without allocating a native window or replacing that backend with OpenGL.
#test
{
    var cpu: RenderCpu
    var app: Application
    app.setRenderer(&cpu)

    let surface = expect app.createSurface(0, 0, 160, 96)
    Swag.assert(not app.renderer.needsNativeWindow())
    Swag.assert(not surface.hWnd)

    surface.show()
    let image = app.renderer.readRenderTarget(&surface.rt, 0, 0, surface.rc.width, surface.rc.height)
    Swag.assert(image.isValid() and image.width == surface.rc.width and image.height == surface.rc.height)
}

// The headless host must exercise the complete GUI paint path, not only record commands.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(96, 64)

    let background = host.render()
    Swag.assert(background.isValid())
    Swag.assert(background.width == 96 and background.height == 64)
    Swag.assert(background.pixelFormat == .BGRA8)

    let button  = PushButton.create(&host.root, "", {20, 16, 56, 32})
    let enabled = host.render()
    Swag.assert(not Slice.equals(enabled.pixels.toSlice(), background.pixels.toSlice()))
    Pixel.Testing.assertImageGolden(&enabled, "widget.cpu.pushbutton")

    button.disable()
    let disabled = host.render()
    Swag.assert(not Slice.equals(disabled.pixels.toSlice(), enabled.pixels.toSlice()))
}

// A repaint is normally one control wide, and the tree it sits in is a whole window. A window
// that cannot reach the region being repainted records nothing at all, instead of recording
// commands for the painter to clip away afterwards.
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

// Rejecting a window on a tighter rectangle than the one it dirties would leave the difference
// stale, so the region `invalidate` marks for a window is always enough to repaint it.
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
