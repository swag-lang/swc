#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// The application About box keeps its product mark and provenance in separate bands.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    host.setup(900, 700)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let appIcon = expect Image.decode(".png", AppIcon)
    host.app.setAppIcon(appIcon)
    let dlg = Gui.AboutDlg.createApplication(&host.surface, {
        productName: ProductName,
        version: "1.2.3",
        buildDate: {year: 2026, month: 9, day: 1},
        sourceUrl: "https://github.com/swag-lang/swc/tree/master/bin/apps/modules/swagcapture",
        copyrightHolder: "Christophe Beaudet"})

    dlg.applyLayout()
    Swag.assert(dlg.labelMessage.dockStyle == .None)
    let surface  = dlg.surface!
    let rendered = host.render(dlg)

    // The window's bottom border belongs below the action bar, outside this crop.
    let contentBottom = cast(s32, dlg.buttonBar.surfaceRect().y)
    var image         = rendered.cropped(25, 60, cast(s32, surface.position.width) - 50, contentBottom - 60)
    Pixel.Testing.assertImageGolden(&image, "about")
    surface.destroy()
}
