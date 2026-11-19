#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Pixel

// Paints frames until the window presents the GPU target and returns those pixels.
func settledPresentation(app: *Application, surface: *Surface)->Array'u8
{
    var watch: Time.Stopwatch
    watch.start()
    while watch.elapsedMilliseconds() < 10000
    {
        app.paintSurfaces()
        if expect Testing.verifyNativePresentation(surface)
        {
            let image = app.renderer.readRenderTarget(&surface.rt, 0, 0, surface.rc.width, surface.rc.height)
            return image.pixels
        }

        Threading.Thread.sleep(5'ms)
    }

    Swag.require(false, "the presentation never matched the GPU target")
    return {}
}

// A window comes back after a device reset with its theme, text and frame intact.
//
// This resets the graphics device for real. Run it on its own: displays driven through a USB
// graphics adapter can go dark for a few seconds while the driver recovers.
#[Swag.TestTag("integration.renderer.reset")]
#test
{
    var app: Application
    let surface = expect app.createSurface(40, 40, 360, 240, surfaceId: "gui-device-reset-test")
    discard PushButton.create(surface.wnd.view, "Probe", {32, 32, 84, 32})
    surface.show()
    let before = settledPresentation(&app, surface)

    surface.invalidate()
    Pixel.Testing.submitDeviceHang()

    var watch: Time.Stopwatch
    watch.start()
    while app.rendererOgl.deviceResets == 0 and watch.elapsedMilliseconds() < 30000
    {
        app.paintSurfaces()
        Threading.Thread.sleep(50'ms)
    }

    Swag.require(app.rendererOgl.deviceResets == 1, "the device reset was never reported")
    Swag.require(app.theme.res.imgWidgets.isValid(), "the theme atlas was not uploaded again")
    let after = settledPresentation(&app, surface)
    Swag.require(Slice.equals(after.toSlice(), before.toSlice()), "the window came back with different pixels")
}
