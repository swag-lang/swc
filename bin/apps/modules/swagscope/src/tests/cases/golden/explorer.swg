#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window   = archivePage(&host, false)
    let explorer = unwrap window.explorer
    Swag.require(explorer.extractAll.isLocallyVisible() and explorer.extractAll.name.raw == appStrings().cmd_ExtractAll)
    for &entry in explorer.entries do
        Swag.require(entry.directory and entry.modified.length == 16)

    // The chosen member, its picture not asked for so the page holds still.
    explorer.navigate(explorer.listing.path, "docs/")
    completeExplorer(&host, explorer)
    explorer.address.breadcrumb.clear()
    explorer.address.breadcrumb.addItem("viewer.archive.zip")
    explorer.address.breadcrumb.addItem("docs")
    explorer.address.refreshPath()
    for &entry in explorer.entries do
        entry.attempted = true
    explorer.selected = 0
    explorer.fill()
    explorer.showInformation()
    Swag.require(not explorer.title.isLocallyVisible())
    let sheet = window.infoSheet.text()
    Swag.require(Utf8.contains(sheet, appStrings().cmd_OpenChosen) and Utf8.contains(sheet, appStrings().cmd_Extract))
    Swag.require(Utf8.contains(sheet, "CRC-32"))
    window.applyLayout()
    var image = host.renderSettled(window)
    Pixel.Testing.assertImageGolden(&image, "explorer.archive")
    var frame = host.render(&host.surfaceWnd)
    Pixel.Testing.assertImageGolden(&frame, "explorer.frame.encre")
}

// A listing failure uses the page's readable center instead of the narrow status line.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 640)
    host.surface.updateFlags(SurfaceFlags.StandardWindow | SurfaceFlags.NoShadow)
    host.theme.setLight()
    host.notify(.ThemeChanged)

    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openExplorer(Path.combine(testSourceRoot(#curlocation), "datas"))
    let explorer = unwrap window.explorer
    completeExplorer(&host, explorer)
    explorer.setStatus("")
    explorer.failure.setText("The folder could not be read.\nThe filename, directory name, or volume label syntax is incorrect.")
    explorer.list.hide()
    explorer.scroll.hide()
    explorer.failure.show()
    explorer.applyLayout()
    window.applyLayout()

    var image = host.renderSettled(window)
    Pixel.Testing.assertImageGolden(&image, "explorer.failure.paper")
}
