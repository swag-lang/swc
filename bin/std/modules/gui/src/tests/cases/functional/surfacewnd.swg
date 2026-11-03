#global if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core, Pixel

#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    buildChromeWindow(&host)
    let applicationInk = host.theme.colors.wnd_BtnIcon
    var paper = ThemeColors.papierPalette()
    host.surfaceWnd.setChromePalette(&paper)
    Swag.assert(host.surfaceWnd.themeColors().wnd_Bk == paper.ground)
    Swag.assert(host.surfaceWnd.minimizeBtn!.themeColors().btnIcon_Icon == paper.faintText)
    Swag.assert(host.theme.colors.wnd_BtnIcon == applicationInk)
    Swag.assert(host.root.themeColors().wnd_Bk == host.theme.colors.wnd_Bk)

    host.surface.updateFlags(remove: .MinimizeButton | .MaximizeButton | .CloseButton)
    host.surface.updateFlags(add: .MinimizeButton | .MaximizeButton | .CloseButton)
    Swag.assert(host.surfaceWnd.minimizeBtn.themeColors().btnIcon_Icon == paper.faintText)
    Swag.assert(host.surfaceWnd.closeBtn!.themeColors().btnIcon_HotIcon == host.surfaceWnd.themeColors().wnd_BtnCloseHotIcon)
    host.surfaceWnd.setChromePalette(null)
    Swag.assert(host.surfaceWnd.minimizeBtn.themeColors().btnIcon_Icon == applicationInk)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(64, 64)
    host.app.setAppIcon(chromeTestMark())

    let glyph  = host.app.appGlyph(18)
    let pixels = host.app.renderer.readTexturePixels(glyph.imageList!.texture, .RGBA8)

    func at(pixels: const [..] u8, x, y: s32)->u32
    {
        let offset = cast(u64, (y * 32 + x) * 4)
        return Math.make32(pixels[offset + 3], pixels[offset], pixels[offset + 1], pixels[offset + 2])
    }

    Swag.assert(glyph.sizeX == 18 and glyph.color.a == 0)
    Swag.assert(at(pixels.toSlice(), 8, 8) == 0xFFFFFFFF)
    Swag.assert(at(pixels.toSlice(), 2, 2) >> 24 == 0)
    Swag.assert(at(pixels.toSlice(), 16, 16) >> 24 == 0)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 120)
    buildChromeWindow(&host)

    let strip = host.theme.metrics.wnd_StripHeight
    Swag.assert(host.surfaceWnd.stripHeight() == strip)
    Swag.assert(host.surfaceWnd.hitTestCaption({240, strip * 0.5}))
    Swag.assert(host.surfaceWnd.hitTestCaption({10, strip * 0.5}))
    Swag.assert(not host.surfaceWnd.hitTestCaption({240, strip + 10}))

    let close = unwrap host.surfaceWnd.closeBtn
    Swag.assert(not host.surfaceWnd.hitTestCaption(close.surfaceRect().center()))
    Swag.assert(close.position.right() <= host.surfaceWnd.clientRect().right())

    var image  = host.render(&host.surfaceWnd)
    let ground = host.theme.colors.wnd_Bk
    Swag.assert(image.pixelColor(240, 4).argb == ground.argb)
    Swag.assert(image.pixelColor(240, cast(s32, strip) + 8).argb == ground.argb)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 200)
    buildChromeWindow(&host)

    let strip = host.theme.metrics.wnd_StripHeight
    Swag.assert(host.root.position.y == 1 and host.root.position.height == 198)
    Swag.assert(host.root.stripInset() == strip - 1)

    // A document continuing below the strip is content: the strip drags over it.
    with let document = Wnd.create'Wnd(&host.root, {0, 0, 478, 198})
    {
        .focusPolicy = .Tab
    }

    Swag.assert(host.surfaceWnd.hitTestCaption({240, 20}))
    Swag.assert(not host.surfaceWnd.hitTestCaption({240, strip + 10}))
    Swag.assert(document.stripInset() == strip - 1)

    // A button set in the strip is a control: it keeps its clicks, and the strip around it drags.
    let share = PushButton.create(&host.root, "Share", {100, 10, 80, 32})
    Swag.assert(not host.surfaceWnd.hitTestCaption({140, 26}))
    Swag.assert(host.surfaceWnd.hitTestCaption({240, 26}))

    // A band laid below the strip has nothing to keep clear of.
    let band = Wnd.create'Wnd(&host.root, {0, strip, 478, 40})
    Swag.assert(band.stripInset() == 0)

    // The window buttons stay above the view, and over them nothing drags.
    let close = unwrap host.surfaceWnd.closeBtn
    Swag.assert(host.surfaceWnd.windowAt(close.position.horzCenter(), close.position.vertCenter(), true) == close)

    share.destroy()
    band.destroy()
    host.pump()
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 200)
    buildChromeWindow(&host)

    let strip = host.theme.metrics.wnd_StripHeight
    Swag.assert(not host.surfaceWnd.hitTestCaption({40, strip + 40}))

    host.surfaceWnd.groundHitTest = func(pos: Math.Point)->bool => pos.x < 100
    Swag.assert(host.surfaceWnd.hitTestCaption({40, strip + 40}))
    Swag.assert(not host.surfaceWnd.hitTestCaption({240, strip + 40}))
    Swag.assert(host.surfaceWnd.hitTestCaption({240, strip * 0.5}))

    // The window buttons never drag, whatever the view answers.
    host.surfaceWnd.groundHitTest = func(_: Math.Point)->bool => true
    let close = unwrap host.surfaceWnd.closeBtn
    Swag.assert(not host.surfaceWnd.hitTestCaption(close.surfaceRect().center()))
}
#test
{
    var resizes = 0
    var host: Testing.HeadlessHost
    host.setup(480, 200)
    buildChromeWindow(&host)
    host.surface.updateFlags(remove: .Border)

    host.root.hookOnEvent = func|resizes = &resizes|(_, evt)->bool
    {
        if evt is ResizeEvent do
            resizes[] += 1
        return false
    }

    host.surface.updateFlags(remove: .LargeCaption)
    Swag.assert(host.surfaceWnd.stripHeight() == 0)
    Swag.assert(host.root.stripInset() == 0)
    Swag.assert(resizes > 0)
    Swag.assert(not host.surfaceWnd.hitTestCaption({240, 20}))

    host.surface.updateFlags(add: .LargeCaption)
    Swag.assert(host.root.stripInset() == host.theme.metrics.wnd_StripHeight)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 120)
    buildChromeWindow(&host)
    let title = String.from(host.surfaceWnd.name.raw)
    host.surfaceWnd.showTitle(false)
    Swag.assert(host.surfaceWnd.titleHidden and host.surfaceWnd.name.raw == title)
    host.surfaceWnd.showTitle(true)
    Swag.assert(not host.surfaceWnd.titleHidden)
}
