#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// The complete surface pipeline owns the premultiplied shadow and the rounded body together.
// Fractional scales pin the boundaries where the shadow's rectangular scissors meet.
#[Swag.TestTag("golden")]
#test
{
    for scale, index in [1.0'f32, 1.25'f32, 1.5'f32, 2.0'f32]
    {
        var host: Testing.HeadlessHost
        host.setup(180, 120, scale)
        defer host.shutdown()
        host.surface.flags = SurfaceFlags.StandardWindow
        host.theme.metrics.surfaceWnd_ShadowSize   = 18
        host.theme.metrics.surfaceWnd_CornerRadius = 12
        host.surface.setPosition({0, 0, 180 * scale, 120 * scale})
        host.root.setPosition(host.surfaceWnd.position)
        let image = host.render()
        Pixel.Testing.assertImageGolden(&image, Format.toString("surface.shadow.%", index).toString())

        // A partial repaint can end inside any band or entirely inside the opaque body. Its
        // scissors must leave exactly the same pixels as the original complete frame.
        let clips: [4] Math.Rectangle = [{0, 0, 45, 120}, {45, 0, 90, 40}, {45, 80, 135, 40}, {50, 50, 10, 10}]
        for clip in clips
        {
            host.surface.invalidateRect(clip)
            host.surface.paintWnd(&host.root)
            let partial = host.app.renderer.readRenderTarget(&host.surface.rt, 0, 0, host.surface.rc.width, host.surface.rc.height)
            Pixel.Testing.assertImagesNear(&image, &partial, "surface.shadow.partial")
        }
    }
}
