#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Pixel

// Paints frames until the presented bitmap holds exactly the GPU target, and returns it.
func settledPresentation(app: *Application, surface: *Surface)->Array'u8
{
    var watch: Time.Stopwatch
    watch.start()
    while watch.elapsedMilliseconds() < 10000
    {
        app.paintSurfaces()
        if expect Testing.verifyNativePresentation(surface)
        {
            var result: #returntype
            let bytes = cast(u64, surface.presentationWidth) * cast(u64, surface.presentationHeight) * 4
            result.add(Swag.makeSlice(cast(const [*] u8, unwrap surface.presentationPixels), bytes))
            return result
        }

        Threading.Thread.sleep(5'ms)
    }

    Swag.require(false, "the presentation never matched the GPU target")
    return {}
}

// A device reset while a presentation is still in flight never publishes what the lost device
// left behind: the window comes back on a new context with its theme, text and frame intact.
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

    // A pending transfer is what published sheared, stale rows once its device was gone.
    surface.invalidate()
    surface.paint()
    Swag.require(surface.readback.isPending())
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
