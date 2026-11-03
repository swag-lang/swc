#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// A small invalidation reconstructs the same backdrop as a full paint, without cumulative blur.
#test
{
    var host: Testing.HeadlessHost
    let lens = backdropLens(&host, false, 1.5, compact: true)
    lens.open()
    let expected = host.renderSettled()
    for count in 3
    {
        discard count
        host.surface.invalidateRect({40, 40, 12, 12})
        host.surface.paintWnd(&host.root)
        let actual = host.app.renderer.readRenderTarget(&host.surface.rt, 0, 0, expected.width, expected.height)
        Pixel.Testing.assertImagesNear(&expected, &actual, "backdrop.partial", {maxChannelDelta: 0})
    }

    lens.close()
    host.settleAnimations()
    Swag.assert(not host.root.hasBackdrop())
}

// The material samples the parent before the lens's own opacity layer is recorded.
#test
{
    var host: Testing.HeadlessHost
    let lens  = backdropLens(&host, true, compact: true)
    let clear = host.render()
    lens.open()
    let blurred = host.renderSettled()
    lens.setPresentationOpacity(0.5)
    let halfway = host.render()
    let x       = 46
    let y       = 34
    let before  = clear.pixelColor(x, y)
    let after   = blurred.pixelColor(x, y)
    let middle  = halfway.pixelColor(x, y)
    Swag.assert(before != after)
    Swag.assert(Math.abs(cast(s32, middle.r) * 2 - before.r - after.r) <= 4)
}
