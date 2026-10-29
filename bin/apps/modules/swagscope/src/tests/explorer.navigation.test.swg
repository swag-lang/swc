#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

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

    // The breadcrumb names the levels above the page; the folder shown is the title.
    Swag.assert(breadcrumb.items.count > 2)
    let count = breadcrumb.items.count + 1
    Swag.assert(breadcrumb.items.back().name == "viewer.archive.zip")
    Swag.assert(breadcrumb.quiet and explorer.title.text() == "docs")
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
