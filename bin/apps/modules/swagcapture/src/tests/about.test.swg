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

    host.app.setAppIcon(expect Image.decode(".png", AppIcon))

    with var about: Gui.ApplicationAboutDlgParams
    {
        .productName     = ProductName
        .version         = "1.2.3"
        .buildDate       = {year: 2026, month: 9, day: 1}
        .sourceUrl       = "https://github.com/swag-lang/swc/tree/master/bin/apps/modules/swagcapture"
        .copyrightHolder = "Christophe Beaudet"
    }

    let dialog = Gui.AboutDlg.createApplication(&host.surface, about)

    dialog.applyLayout()
    Swag.assert(dialog.labelMessage.dockStyle == .None)
    let surface  = dialog.surface!
    let rendered = host.render(dialog)

    // The window's bottom border belongs below the action bar, outside this crop.
    let contentBottom = cast(s32, dialog.buttonBar.surfaceRect().y)
    var image         = rendered.cropped(25, 60, cast(s32, surface.position.width) - 50, contentBottom - 60)
    Pixel.Testing.assertImageGolden(&image, "about")
    surface.destroy()
}
