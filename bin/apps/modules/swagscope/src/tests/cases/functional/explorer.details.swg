#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Opening a ZIP shows sortable column headings over its detail rows.
#test
{
    var host: Testing.HeadlessHost
    host.setup(720, 500)
    host.theme.setLight()
    host.notify(.ThemeChanged)

    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(Path.combine(testSourceRoot(#curlocation), "datas", "viewer.archive.zip"))
    completeViewerWindowClassification(&host, window)
    Swag.require(window.explorer != null)
    let explorer = window.explorer
    completeExplorer(&host, explorer)
    window.applyLayout()

    let header = explorer.archiveHeader
    Swag.require(explorer.mode == .Details and header.isVisible())
    Swag.require(header.itemAt(0).name.text == appStrings().explore_Name)
    Swag.require(header.itemAt(1).name.text == appStrings().explore_Compression and not header.itemAt(1).isClickable)
    Swag.require(header.itemAt(2).name.text == appStrings().explore_Size)
    Swag.require(header.itemAt(3).name.text == appStrings().explore_Modified)
    Swag.require(header.surfaceRect().x == explorer.grid.surfaceRect().x)
    let lastColumnRight = header.itemPositionAt(3) + header.itemWidthAt(3)
    Swag.require(lastColumnRight == explorer.grid.clientRect().width - ExplorerGrid.CellInset)

    header.sigColumnClicked.call(cast(*Wnd, header), 2'u32)
    completeExplorer(&host, explorer)
    Swag.require(header.sortColumn == 2 and header.sortDirection == .Ascending)
    header.sigColumnClicked.call(cast(*Wnd, header), 2'u32)
    completeExplorer(&host, explorer)
    Swag.require(header.sortColumn == 2 and header.sortDirection == .Descending)

    explorer.setMode(.Names)
    Swag.require(not header.isVisible() and explorer.list.isVisible())
    explorer.setMode(.Details)
    Swag.require(header.isVisible() and not explorer.list.isVisible())
}

// Local audio inspection can provide a track duration without a network lookup or sample decode.
#test
{
    let file = Path.combine(testSourceRoot(#curlocation), "datas", "pacman_beginning.wav")
    Swag.require(localSoundDuration(file) >= 4)
}
