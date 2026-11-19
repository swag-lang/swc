#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// An interior repaint preserves the outline and shadow without recording them.
#test
{
    for scale in [1.0'f32, 1.5'f32, 2.0'f32]
    {
        for radius in [0.0'f32, 12.0'f32]
        {
            var host: Testing.HeadlessHost
            host.setup(180, 120, scale)
            host.surface.flags = .StandardWindow
            host.theme.metrics.surfaceWnd_ShadowSize   = 18
            host.theme.metrics.surfaceWnd_CornerRadius = radius
            host.surface.setPosition(Math.Rectangle{0, 0, 180 * scale, 120 * scale})
            host.root.setPosition(host.surfaceWnd.position)
            let full = host.render()

            host.app.frameTrace.enabled = true
            host.surface.isDirty        = false
            host.surface.invalidateRect({50, 50, 20, 20})
            host.surface.paintWnd(&host.root)
            let withChrome = host.app.frameTrace.batches
            let partial    = host.app.renderer.readRenderTarget(&host.surface.rt, 0, 0, host.surface.rc.width, host.surface.rc.height)
            Pixel.Testing.assertImagesNear(&full, &partial, "surface.interior.chrome")

            // Repainting through the rounded corner must reconstruct its alpha and shadow.
            host.surface.invalidateRect({12, 12, 28, 28})
            host.surface.paintWnd(&host.root)
            let corner = host.app.renderer.readRenderTarget(&host.surface.rt, 0, 0, host.surface.rc.width, host.surface.rc.height)
            Pixel.Testing.assertImagesNear(&full, &corner, "surface.corner.partial")

            host.surface.flags.remove(.Border)
            host.theme.metrics.surfaceWnd_ShadowSize = 0
            host.app.frameTrace.batches = 0
            host.surface.invalidateRect({50, 50, 20, 20})
            host.surface.paintWnd(&host.root)
            Swag.require(withChrome != 0 and host.app.frameTrace.batches == withChrome)
        }
    }
}

// A maximized body stays opaque without the shadow or the rectangular premultiplication pass.
#test
{
    for scale in [1.0'f32, 1.5'f32]
    {
        var host: Testing.HeadlessHost
        host.setup(180, 120, scale)
        host.surface.flags = .StandardWindow
        host.theme.metrics.surfaceWnd_ShadowSize   = 18
        host.theme.metrics.surfaceWnd_CornerRadius = 0
        host.surface.setPosition(Math.Rectangle{0, 0, 180 * scale, 120 * scale})
        host.root.setPosition(host.surfaceWnd.position)
        let restored = host.render()
        host.surface.isMaximized = true
        let maximized = host.render()
        let body      = host.surfaceWnd.surfaceRect()
        for y in cast(s32, (body.height * scale))
        {
            for x in cast(s32, (body.width * scale))
            {
                let px = x + cast(s32, (body.x * scale))
                let py = y + cast(s32, (body.y * scale))
                Swag.require(maximized.pixelColor(px, py).argb == restored.pixelColor(px, py).argb)
                Swag.require(maximized.pixelColor(px, py).a == 255)
            }
        }

        Swag.require(maximized.pixelColor(0, 0).argb == 0)
        host.surface.invalidateRect({50, 50, 10, 10})
        host.surface.paintWnd(&host.root)
        let partial = host.app.renderer.readRenderTarget(&host.surface.rt, 0, 0, host.surface.rc.width, host.surface.rc.height)
        Pixel.Testing.assertImagesNear(&maximized, &partial, "surface.maximized.partial")
    }
}
