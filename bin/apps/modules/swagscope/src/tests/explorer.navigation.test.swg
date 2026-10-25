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
    Swag.assert(explorer.breadcrumb.items.count > 3)
    let count = explorer.breadcrumb.items.count
    Swag.assert(explorer.breadcrumb.items[count - 2].name == "viewer.archive.zip")
    Swag.assert(explorer.breadcrumb.items.back().name == "docs")
    let menu = MenuCtrl.createPopup(explorer.breadcrumb)
    defer menu.destroy()
    explorer.fillBreadcrumbMenu(count - 2, menu)
    Swag.assert(menu.items.count == 2)
    let item = unwrap menu.items[1]
    Swag.assert(item.name.raw == "docs")
    let folderTarget = String.from(unwrap item.id)
    Swag.assert(folderTarget == explorer.breadcrumb.items.back().tag)
    explorer.navigateBreadcrumb(folderTarget)
    Swag.assert(explorer.requested == explorer.listing.path and explorer.requestedFolder == "docs/")
    explorer.load.wait()
    host.pump()

    let parent = count - 3
    explorer.fillBreadcrumbMenu(parent, menu)
    for &target in explorer.menuPaths do
        Swag.assert(not Utf8.endsWith(target[], "viewer.archive.zip\n"))
}
