#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

#[Swag.TestTag("golden")]
#test
{
    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        let window   = archivePage(&host, light)
        let explorer = unwrap window.explorer
        Swag.assert(explorer.extractAll.isLocallyVisible() and explorer.extractAll.name.raw == appStrings().cmd_ExtractAll)
        for &entry in explorer.entries do
            Swag.assert(entry.directory and entry.modified.length == 16)

        // The chosen member, its picture not asked for so the page holds still.
        explorer.navigate(explorer.listing.path, "docs/")
        completeExplorer(&host, explorer)
        explorer.address.breadcrumb.clear()
        explorer.address.breadcrumb.addItem("viewer.archive.zip")
        explorer.address.refreshPath()
        for &entry in explorer.entries do
            entry.attempted = true
        explorer.selected = 0
        explorer.fill()
        explorer.showInformation()
        let sheet = window.infoSheet.text()
        Swag.assert(Utf8.contains(sheet, appStrings().cmd_OpenChosen) and Utf8.contains(sheet, appStrings().cmd_Extract))
        Swag.assert(Utf8.contains(sheet, "CRC-32"))
        window.applyLayout()
        host.settleAnimations(window)
        var image = host.render(window)
        Pixel.Testing.assertImageGolden(&image, light ? "explorer.archive.paper" : "explorer.archive")
        var frame = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&frame, light ? "explorer.frame.paper" : "explorer.frame.encre")
    }
}
