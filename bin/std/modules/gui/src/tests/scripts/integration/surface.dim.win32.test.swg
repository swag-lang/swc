#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Pixel, Win32

// Dismissing a modal restores the entire native bitmap, even when a control has
// already queued a smaller repaint. Prepare pixels without ever showing a window.
#[Swag.TestTag("integration.host.hidden")]
#test
{
    var app: Application
    let surface = expect app.createSurface(0, 0, 360, 240, surfaceId: "gui-dim-presentation-test")
    let button  = PushButton.create(surface.wnd.view, "Probe", {32, 32, 84, 32})
    Swag.assert(not IsWindowVisible(surface.win32Handle()))
    let prepared = surface.prepareResizeFrame(surface.wnd)
    Swag.assert(prepared)
    let expected = app.renderer.readRenderTarget(&surface.rt, 0, 0, surface.rc.width, surface.rc.height)

    surface.disable()
    let dimmedFrame = surface.prepareResizeFrame(surface.wnd)
    Swag.assert(dimmedFrame)
    let dimmed = Swag.makeSlice(cast(const [*] u8, unwrap surface.presentationPixels), expected.byteCount)
    Swag.assert(not Slice.equals(dimmed, expected.pixels.toSlice()))

    button.invalidate()
    surface.enable()
    let restoredFrame = surface.prepareResizeFrame(surface.wnd)
    Swag.assert(restoredFrame)
    let restored = Swag.makeSlice(cast(const [*] u8, surface.presentationPixels), expected.byteCount)
    Swag.assert(Slice.equals(restored, expected.pixels.toSlice()))
    Swag.assert(not IsWindowVisible(surface.win32Handle()))
}
