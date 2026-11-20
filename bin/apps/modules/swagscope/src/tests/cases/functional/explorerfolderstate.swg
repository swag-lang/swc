#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// Turning privacy off does not serialize a private visit; a later public visit may be saved.
#test
{
    let root  = Testing.tempFilePath("scope-private-visit-", "")
    let other = Path.combine(root, "other")
    expect Directory.create(other, recurse: true)
    defer catch Directory.delete(root, recurse: true)
    var publisher: File.MountPrivacyPublisher
    expect publisher.open(root, true)
    var host: Testing.HeadlessHost
    host.setup(880, 560)
    defer host.shutdown()
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openExplorer(root)
    let explorer = unwrap window.explorer
    completeExplorer(&host, explorer)
    explorer.filter.setText("private-visit-filter")
    publisher.setPrivateMode(false)
    let privateSave = saveViewerState(window)
    Swag.require(window.folderViews.isEmpty() and explorer.privateView)
    Swag.require(not Utf8.contains(privateSave.toString(), "private-visit-filter"))

    explorer.navigate(other)
    completeExplorer(&host, explorer)
    explorer.navigate(root)
    completeExplorer(&host, explorer)
    let publicSave = saveViewerState(window)
    Swag.require(not explorer.privateView and window.folderViews.count == 2)
    Swag.require(window.privacy.folderView(other, "")!.query.isEmpty())
    Swag.require(Utf8.contains(publicSave.toString(), "private-visit-filter"))
}

// Returning to a folder restores its complete presentation and the surviving selection.
#test
{
    let root   = Testing.tempFilePath("scope-folder-view-", "")
    let first  = Path.combine(root, "first")
    let second = Path.combine(root, "second")
    expect Directory.create(first, recurse: true)
    expect Directory.create(second)
    defer catch Directory.delete(root, recurse: true)
    for index in 24 do
        discard expect File.writeAllText(Path.combine(first, Format.toString("item-%{02}.txt", index)), "text")

    var host: Testing.HeadlessHost
    host.setup(880, 560)
    defer host.shutdown()
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.onlineMovies = false
    window.openExplorer(first)
    let explorer = unwrap window.explorer
    completeExplorer(&host, explorer)
    explorer.setMode(.Large)
    explorer.forceBoard(true, .Grid)
    explorer.setArtworkSource(.Local)
    explorer.setThumbnailCrop(.None)
    explorer.setKindFilter(.Documents)
    explorer.filter.setText("item")
    explorer.sortBy(2, true)
    completeExplorer(&host, explorer)
    explorer.grid.select(8)
    explorer.scroll.setScrollPos(0, 100)
    let selected = explorer.entries[explorer.selected].path
    let scroll   = explorer.scroll.scrollPosition()

    explorer.navigate(second)
    completeExplorer(&host, explorer)
    explorer.setMode(.Names)
    explorer.setThumbnailCrop(.Entropy)
    explorer.setKindFilter(.All)
    explorer.filter.setText("")
    explorer.sortBy(0, false)
    completeExplorer(&host, explorer)
    explorer.navigate(first)
    completeExplorer(&host, explorer)
    Swag.require(explorer.mode == .Large and explorer.forced and explorer.forcedBoard == .Grid)
    Swag.require(explorer.artworkSource == .Local and explorer.kindFilter == .Documents)
    Swag.require(explorer.thumbnailCrop == .None)
    Swag.require(explorer.sortColumn == 2 and explorer.descending and explorer.filter.text() == "item")
    Swag.require(explorer.selected < explorer.entries.count and explorer.entries[explorer.selected].path == selected)
    Swag.require(explorer.scroll.scrollPosition() == scroll)

    let saved = saveViewerState(window)
    window.folderViews.clear()
    loadViewerState(window, cast(const [..] u8, saved))
    let state = unwrap window.privacy.folderView(first, "")
    Swag.require(state.mode == .Large and state.crop == .None and state.descending and state.query == "item")
}

// A public-to-private switch redacts saved views while keeping them usable until exit.
#test
{
    let root = Testing.tempFilePath("scope-private-folder-view-", "")
    expect Directory.create(root)
    defer catch Directory.delete(root)
    var publisher: File.MountPrivacyPublisher
    expect publisher.open(root, false)
    var host: Testing.HeadlessHost
    host.setup(880, 560)
    defer host.shutdown()
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.privacy.rememberFolderView({path: root, mode: .Small, query: "private-filter", descending: true})
    window.privacy.rememberFolderView({path: root, folder: "inside/", mode: .Details})
    Swag.require(window.folderViews.count == 2)
    publisher.setPrivateMode(true)
    let saved = saveViewerState(window)
    Swag.require(window.folderViews.isEmpty() and window.privacy.folderViews.count == 2)
    Swag.require(not Utf8.contains(saved.toString(), root.toString()) and
                 not Utf8.contains(saved.toString(), "private-filter"))
    Swag.require(window.privacy.folderView(root, "")!.mode == .Small)
    Swag.require(window.privacy.folderView(root, "inside/")!.mode == .Details)
    publisher.close()
    Swag.require(window.privacy.folderView(root, "")!.query == "private-filter")
}
