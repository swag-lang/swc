#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Pixel

// Dismissing a modal restores the entire frame when a child has already dirtied one region.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var app: Application
    let surface = expect app.createSurface(40, 40, 360, 240, surfaceId: "gui-dim-presentation-test")
    let button  = PushButton.create(surface.wnd.view, "Probe", {32, 32, 84, 32})
    surface.show()
    let width  = surface.rc.width
    let height = surface.rc.height
    let normal = app.renderer.readRenderTarget(&surface.rt, 0, 0, width, height)
    Swag.require(expect Testing.verifyNativePresentation(surface))

    surface.disable()
    surface.paint()
    let dimmed = app.renderer.readRenderTarget(&surface.presentationTarget, 0, 0, width, height)
    Swag.require(dimmed.isValid() and not Slice.equals(normal.pixels.toSlice(), dimmed.pixels.toSlice()))
    Swag.require(expect Testing.verifyNativePresentation(surface))

    button.invalidate()
    surface.enable()
    surface.paint()
    let restored = app.renderer.readRenderTarget(&surface.rt, 0, 0, width, height)
    Swag.require(Slice.equals(normal.pixels.toSlice(), restored.pixels.toSlice()))
    Swag.require(expect Testing.verifyNativePresentation(surface))

    surface.setOpacity(0.5)
    surface.paint()
    let faded = app.renderer.readRenderTarget(&surface.presentationTarget, 0, 0, width, height)
    let alpha = faded.pixelColor(width / 2, height / 2).a
    Swag.require(alpha == 127 or alpha == 128)
    Swag.require(expect Testing.verifyNativePresentation(surface))
}
