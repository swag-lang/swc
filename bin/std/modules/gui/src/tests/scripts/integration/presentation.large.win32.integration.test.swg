#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Pixel

struct PresentationPatternWnd
{
    using wnd:  Wnd
    generation: u32
}

impl IWnd for PresentationPatternWnd
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        for row in 96'u32
        {
            let color = Color.fromRgb(cast(u8, (row * 17 + .generation * 31) % 256),
                                      cast(u8, (row * 43 + .generation * 7) % 256),
                                      cast(u8, (row * 11 + .generation * 53) % 256))
            painter.fillRect({0, cast(f32, row) * 32, 4096, 32}, color)
            painter.fillRect({cast(f32, row) * 23, cast(f32, row) * 32, 7, 32}, Argb.White)
        }
    }
}

// Large odd-sized frames alternate full and narrow transfers on every connected monitor.
// Compare the complete bitmap, including rows untouched by each partial presentation.
#[Swag.TestTag("integration.host.windows.stress")]
#test
{
    var app: Application
    let monitors = Env.getMonitors()
    Swag.assert(not monitors.isEmpty())
    for monitor in monitors
    {
        let bounds  = monitor.physicalBounds
        let surface = expect app.createSurface(cast(s32, bounds.x) + 20,
                                               cast(s32, bounds.y) + 20,
                                               2751,
                                               1891,
                                               surfaceId: "gui-large-presentation-test")
        defer surface.destroy()
        let view = Wnd.create'PresentationPatternWnd(surface.wnd)
        surface.setView(view)
        surface.setPosition({bounds.x + 20, bounds.y + 20, 2751, 1891})
        surface.show()

        for frame in 12'u32
        {
            view.generation = frame
            if frame % 3 == 0
            {
                surface.invalidate()
            }
            else
            {
                surface.invalidateRect({31 + cast(f32, frame) * 17, 47, 257, 701})
            }

            surface.paint()
            Swag.assert(surface.readback.isPending())

            var watch: Time.Stopwatch
            watch.start()
            while surface.readback.isPending() and watch.elapsedMilliseconds() < 2000
            {
                discard surface.advanceNativePresentation()
                Threading.Thread.sleep(1'ms)
            }

            Swag.assert(not surface.readback.isPending())
            let verified = expect Testing.verifyNativePresentation(surface)
            Swag.assert(verified)
        }
    }
}
