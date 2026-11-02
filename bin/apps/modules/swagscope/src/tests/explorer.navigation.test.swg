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
    let archive = Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas", "viewer.archive.zip")
    explorer.listing = expect ExplorerListing.load(archive)
    explorer.folder  = "docs/"
    explorer.updateBreadcrumb()
    let breadcrumb = explorer.address.breadcrumb

    // The breadcrumb includes the current archive folder above the page title.
    Swag.assert(breadcrumb.items.count > 2)
    let count = breadcrumb.items.count
    Swag.assert(breadcrumb.items.back().name == "docs")
    Swag.assert(not breadcrumb.quiet and explorer.title.text() == "docs")
    let menu = MenuCtrl.createPopup(breadcrumb)
    defer menu.destroy()
    explorer.fillBreadcrumbMenu(count - 2, menu)
    Swag.assert(menu.items.count == 2)
    let item = unwrap menu.items[1]
    Swag.assert(item.name.raw == "docs")
    let folderTarget = String.from(unwrap item.id)
    Swag.assert(folderTarget == Format.toString("%\n%", explorer.listing.path, "docs/"))
    explorer.navigateBreadcrumb(folderTarget)
    Swag.assert(explorer.requested == explorer.listing.path and explorer.requestedFolder == "docs/")
    explorer.load.wait()
    host.pump()

    let parent = count - 3
    explorer.fillBreadcrumbMenu(parent, menu)
    for &target in explorer.menuPaths do
        Swag.assert(not Utf8.endsWith(target[], "viewer.archive.zip\n"))

    // Typing starts on the whole location, selected, and the focus leaving gives the path back.
    explorer.folder = ""
    explorer.updateBreadcrumb()
    Swag.assert(explorer.locationText() == explorer.listing.path)
    let address = explorer.address
    address.beginEdit()
    Swag.assert(address.edit.isLocallyVisible() and not address.pathScroll.isLocallyVisible())
    Swag.assert(explorer.locationText() == address.edit.text())
    explorer.focusContent()
    Swag.assert(not address.edit.isLocallyVisible() and address.pathScroll.isLocallyVisible())

    // A location typed in the address reaches a folder inside the archive as well as the archive's
    // own folder, with or without the quotes a copied path comes between.
    explorer.navigateTyped(Format.toString("\"%/data\"", explorer.listing.path))
    Swag.assert(explorer.requested == explorer.listing.path and explorer.requestedFolder == "data/")
    explorer.load.wait()
    host.pump()
    let folder = unwrap Path.directoryName(archive)
    explorer.navigateTyped(Format.toString("  %  ", folder))
    Swag.assert(explorer.requested == folder and explorer.requestedFolder.isEmpty())
    explorer.load.wait()
    host.pump()
    explorer.navigateTyped(Path.combine(folder, "no such folder"))
    Swag.assert(explorer.status.text() == appStrings().explore_NotFound)
}

// A short absolute path stays visible at minimum width, and its current segment opens editing.
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
        Swag.assert(address.breadcrumb.items.count == 2)
        Swag.assert(address.breadcrumb.items[0].name == "Z:/")
        Swag.assert(address.breadcrumb.items[1].name == "Films")
        Swag.assert(address.breadcrumb.scrollPos.x == 0)
        Swag.assert(address.surfaceRect().bottom() <= explorer.title.surfaceRect().y)
        Swag.assert(explorer.title.position.width >= explorer.title.itf.measureContent({}).x)
        let information = window.informationCaptionButton.surfaceRect()
        Swag.assert(information.x > window.clientRect().width / 2)
        Swag.assert(window.backCaptionButton.surfaceRect().right() < information.x)
        var point = address.breadcrumb.localToSurface(address.breadcrumb.items.back().bodyRect.center())
        host.surface.surfaceToScreen(&point)
        host.click(point)
        Swag.assert(address.edit.isLocallyVisible() and address.edit.text() == "Z:/Films")
        host.keyPress(.Escape)
        Swag.assert(not address.edit.isLocallyVisible())
    }
}
