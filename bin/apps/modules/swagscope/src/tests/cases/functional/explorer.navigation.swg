#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Every filesystem ancestor and every archive folder can be selected independently.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 640)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let explorer = Explorer.create(window.documentPanel, window)
    explorer.setMode(.Names)
    let archive = Path.combine(testSourceRoot(#curlocation), "datas", "viewer.archive.zip")
    explorer.listing = expect ExplorerListing.load(archive)
    explorer.folder  = "docs/"
    explorer.updateBreadcrumb()
    let breadcrumb = explorer.address.breadcrumb

    // The breadcrumb includes the current archive folder above the page title.
    Swag.require(breadcrumb.items.count > 2)
    let count = breadcrumb.items.count
    Swag.require(breadcrumb.items.back().name == "docs")
    Swag.require(not breadcrumb.quiet and explorer.title.text() == "docs")
    let menu = MenuCtrl.createPopup(breadcrumb)
    defer menu.destroy()
    explorer.fillBreadcrumbMenu(count - 2, menu)
    Swag.require(menu.items.count == 2)
    let item = unwrap menu.items[1]
    Swag.require(item.name.raw == "docs")
    Swag.require(item.icon.isValid() and item.icon.color == host.theme.colors.arc)
    let folderTarget = String.from(unwrap item.id)
    Swag.require(folderTarget == Format.toString("%\n%", explorer.listing.path, "docs/"))
    explorer.navigateBreadcrumb(folderTarget)
    Swag.require(explorer.requested == explorer.listing.path and explorer.requestedFolder == "docs/")
    explorer.load.wait()
    host.pump()

    let parent = count - 3
    explorer.fillBreadcrumbMenu(parent, menu)
    for entry in menu.items do
        Swag.require(entry!.icon.color == host.theme.colors.arc)
    for &target in explorer.menuPaths do
        Swag.require(not Utf8.endsWith(target[], "viewer.archive.zip\n"))

    // Typing starts on the whole location, selected, and the focus leaving gives the path back.
    explorer.folder = ""
    explorer.updateBreadcrumb()
    Swag.require(explorer.locationText() == explorer.listing.path)
    let address = explorer.address
    address.beginEdit()
    Swag.require(address.edit.isLocallyVisible() and not address.pathScroll.isLocallyVisible())
    Swag.require(explorer.locationText() == address.edit.text())
    explorer.focusContent()
    Swag.require(not address.edit.isLocallyVisible() and address.pathScroll.isLocallyVisible())

    // A location typed in the address reaches a folder inside the archive as well as the archive's
    // own folder, with or without the quotes a copied path comes between.
    explorer.navigateTyped(Format.toString("\"%/data\"", explorer.listing.path))
    Swag.require(explorer.requested == explorer.listing.path and explorer.requestedFolder == "data/")
    explorer.load.wait()
    host.pump()
    let folder = unwrap Path.directoryName(archive)
    explorer.navigateTyped(Format.toString("  %  ", folder))
    Swag.require(explorer.requested == folder and explorer.requestedFolder.isEmpty())
    explorer.load.wait()
    host.pump()
    explorer.navigateTyped(Path.combine(folder, "no such folder"))
    Swag.require(explorer.status.text() == appStrings().explore_NotFound)
}

// Opening folder history reads saved entries without probing their volumes or last files.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 640)
    let window  = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    var missing = Path.combine(Env.getSpecialDirectory(.Temp), Guid64.random().toString())
    window.folderHistory.add({folder: missing, file: Path.combine(missing, "missing.txt")})
    var opened: bool
    host.app.sigFrame += func|host = &host, &opened, &missing|(_)
    {
        if opened do
            return
        let menu = unwrap host.capturedPopupMenu()
        Swag.require(menu.items.count == 1)
        Swag.require(menu.items[0]!.id == missing.toString())
        Swag.require(menu.items[0]!.icon.color == host.theme.colors.arc)
        opened = true
        Swag.require(host.dismissPopupMenu())
    }

    window.showFolderHistory()
    Swag.require(opened and window.currentFile.isEmpty())
}

// A short absolute path stays visible at minimum width without a redundant centered title, and
// its current segment opens editing.
#test
{
    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        host.setup(ViewerWindow.MinWidth, 680)
        if light do
            host.theme.setLight()
        host.notify(.ThemeChanged)
        let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
        let explorer = Explorer.create(window.documentPanel, window)
        explorer.listing.path = "Z:/Films"
        explorer.updateBreadcrumb()
        explorer.layoutTools()
        window.applyLayout()
        let address = explorer.address
        Swag.require(address.breadcrumb.items.count == 2)
        Swag.require(address.breadcrumb.items[0].name == "Z:/")
        Swag.require(address.breadcrumb.items[1].name == "Films")
        Swag.require(address.breadcrumb.scrollPos.x == 0)
        Swag.require(address.isLocallyVisible())
        Swag.require(not explorer.title.isLocallyVisible())
        let information = window.informationCaptionButton.surfaceRect()
        Swag.require(information.x > window.clientRect().width / 2)
        Swag.require(window.backCaptionButton.surfaceRect().right() < information.x)
        var point = address.breadcrumb.localToSurface(address.breadcrumb.items.back().bodyRect.center())
        host.surface.surfaceToScreen(&point)
        host.click(point)
        Swag.require(address.edit.isLocallyVisible() and address.edit.text() == "Z:/Films")
        host.keyPress(.Escape)
        Swag.require(not address.edit.isLocallyVisible())
    }
}
