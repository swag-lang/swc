#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// An application can select the CPU backend before its first surface; creation then follows the
// normal GUI lifecycle without allocating a native window or replacing that backend with OpenGL.
#test
{
    var cpu: RenderCpu
    var app: Application
    app.setRenderer(&cpu)

    let surface = (expect app.createSurface(0, 0, 160, 96))!
    @assert(!app.renderer.needsNativeWindow())
    @assert(!surface.hWnd)

    surface.show()
    let image = app.renderer.readRenderTarget(&surface.rt, 0, 0, surface.rc.width, surface.rc.height)
    @assert(image.isValid() and image.width == surface.rc.width and image.height == surface.rc.height)
}

// The headless host must exercise the complete GUI paint path, not only record commands.
#test
{
    var host: Testing.HeadlessHost
    host.setup(96, 64)
    defer host.shutdown()
    let background = host.render()
    @assert(background.isValid())
    @assert(background.width == 96 and background.height == 64)
    @assert(background.pixelFormat == .BGRA8)

    let button  = PushButton.create(&host.root, "", {20, 16, 56, 32})
    let enabled = host.render()
    @assert(Memory.compare(enabled.pixels.buffer, background.pixels.buffer, enabled.byteCount) != 0)
    Pixel.Testing.assertImageGolden(&enabled, "widget.cpu.pushbutton")

    button.disable()
    let disabled = host.render()
    @assert(Memory.compare(disabled.pixels.buffer, enabled.pixels.buffer, disabled.byteCount) != 0)
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
    defer host.shutdown()

    for row in Rows
    {
        for column in Columns do
            discard PushButton.create(&host.root, "grid", {cast(f32) (column * 78 + 4), cast(f32) (row * 46 + 4), 70, 38})
    }

    host.pump()
    host.root.applyLayout()

    // The whole surface: every button is painted.
    host.surface.invalidate()
    host.surface.paintWnd(&host.root)
    @assert(host.surface.paintedWnds == Columns * Rows)
    @assert(host.surface.skippedWnds == 0)

    // One button's rectangle, from a surface that is not already dirty: a widget that asks for
    // its own repaint while painting would otherwise widen the region this measures. The other
    // buttons are outside it by more than the margin a window is allowed to paint into, so they
    // never reach the painter at all.
    host.surface.isDirty = false
    host.surface.invalidateRect({4, 4, 70, 38})
    host.surface.paintWnd(&host.root)
    @assert(host.surface.paintedWnds + host.surface.skippedWnds == Columns * Rows)
    @assert(host.surface.paintedWnds < 12)
}

// Rejecting a window on a tighter rectangle than the one it dirties would leave the difference
// stale, so the region `invalidate` marks for a window is always enough to repaint it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()

    let button = PushButton.create(&host.root, "edge", {200, 120, 80, 40})
    host.pump()
    host.root.applyLayout()

    host.surface.isDirty = false
    host.surface.invalidateRect(button.paintExtent(button.surfaceRect()))
    host.surface.paintWnd(&host.root)
    @assert(host.surface.paintedWnds == 1 and host.surface.skippedWnds == 0)

    host.surface.isDirty = false
    host.surface.invalidateRect({0, 0, 8, 8})
    host.surface.paintWnd(&host.root)
    @assert(host.surface.paintedWnds == 0 and host.surface.skippedWnds == 1)
}
