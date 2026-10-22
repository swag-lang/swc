#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Pixel, Win32

// Ordinary frames yield to input while readback is pending, coalesce dirty content, and never
// let an older asynchronous frame replace a synchronously prepared resize.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var app: Application
    let surface = expect app.createSurface(40, 40, 360, 240, surfaceId: "gui-async-presentation-test")
    let button  = PushButton.create(surface.wnd.view, "Probe", {32, 32, 84, 32})
    surface.show()
    Swag.assert(surface.presentationWidth == surface.rc.width)
    Swag.assert(not surface.readback.isPending())
    Swag.assert(not surface.presentationTarget.colorBuffer.isValid())

    app.rendererOgl.resetScratchCounters()
    surface.invalidate()
    surface.paint()
    Swag.assert(surface.readback.isPending())

    // Border scratch stays on the perimeter, even when the whole window is repainted.
    Swag.assert(app.rendererOgl.scratchClearedPixels < cast(u64, surface.rc.width) * cast(u64, surface.rc.height) / 2)
    surface.invalidate()
    var dispatched: bool
    surface.wnd.view.hookOnEvent = func|&dispatched|(_, evt)->bool
    {
        if evt is CommandEvent as command where command.id == "presentation.probe"
        {
            dispatched = true
            return true
        }

        return false
    }

    surface.wnd.view.postCommandEvent("presentation.probe")
    app.sendPostedEvents()
    Swag.assert(dispatched and surface.isDirty and surface.readback.isPending())

    var watch: Time.Stopwatch
    watch.start()
    while surface.readback.isPending() and watch.elapsedMilliseconds() < 2000
    {
        discard surface.advanceNativePresentation()
        Threading.Thread.sleep(1'ms)
    }

    Swag.assert(not surface.readback.isPending() and not surface.asynchronousPresentationFailed)
    Swag.assert(surface.isDirty)
    surface.paint()
    Swag.assert(surface.readback.isPending())
    surface.setPosition({60, 50, 420, 280})
    Swag.assert(not surface.readback.isPending())
    Swag.assert(surface.presentationWidth == surface.rc.width and surface.presentationHeight == surface.rc.height)
    Swag.assert(surface.position == Math.Rectangle{60, 50, 420, 280})

    let expected = app.renderer.readRenderTarget(&surface.rt, 0, 0, surface.rc.width, surface.rc.height)
    let pixels   = Swag.makeSlice(cast(const [*] u8, surface.presentationPixels!), expected.byteCount)
    Swag.assert(Slice.equals(pixels, expected.pixels.toSlice()))

    button.disable()
    surface.paint()
    Swag.assert(surface.readback.isPending())
    Swag.assert(surface.presentationDirtyRect.width < cast(f32, surface.rc.width))
    Swag.assert(surface.presentationDirtyRect.height < cast(f32, surface.rc.height))
    watch.restart()
    while surface.readback.isPending() and watch.elapsedMilliseconds() < 2000
    {
        discard surface.advanceNativePresentation()
        Threading.Thread.sleep(1'ms)
    }

    Swag.assert(not surface.readback.isPending() and not surface.asynchronousPresentationFailed)
    let partial = app.renderer.readRenderTarget(&surface.rt, 0, 0, surface.rc.width, surface.rc.height)
    Swag.assert(Slice.equals(pixels, partial.pixels.toSlice()))
    Swag.assert(not surface.isDirty)
    var bounds: RECT
    let positioned = GetWindowRect(surface.win32Handle(), &bounds)
    Swag.assert(positioned)
    Swag.assert(bounds.left == 60 and bounds.top == 50 and bounds.right == 480 and bounds.bottom == 330)

    button.enable()
    surface.paint()
    Swag.assert(surface.readback.isPending())
    surface.showNormalAt(#copy surface.position)
    Swag.assert(not surface.readback.isPending())
    let placed = app.renderer.readRenderTarget(&surface.rt, 0, 0, surface.rc.width, surface.rc.height)
    Swag.assert(Slice.equals(pixels, placed.pixels.toSlice()))
}
