#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// The application About box: the tile, the name and its mono identity line, then the provenance.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    host.setup(900, 700)

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
    let surface = unwrap dialog.surface
    var image   = host.renderSurface(surface)
    Pixel.Testing.assertImageGolden(&image, "about")
    surface.destroy()
}
