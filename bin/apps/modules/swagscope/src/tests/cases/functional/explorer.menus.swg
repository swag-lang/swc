#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Opens the test data folder in a real explorer and waits for its listing.
func openMenuExplorer(host: *Testing.HeadlessHost, width = 1280'f32)->*ViewerWindow
{
    host.setup(width, 720)
    host.surface.updateFlags(SurfaceFlags.StandardWindow | SurfaceFlags.NoShadow)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.onlineMovies = false
    window.onlineMusic  = false
    window.openExplorer(scopeTestDataDirectory())
    // Menu tests do not need thumbnails; names mode keeps media preview workers out of the host.
    let explorer = unwrap window.explorer
    explorer.setMode(.Names)
    waitMenuExplorer(host, window)
    window.applyLayout()
    return window
}

func waitMenuExplorer(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    let explorer = unwrap window.explorer
    for 64
    {
        host.pump()
        if not explorer.load.started do
            break
        explorer.load.task.wait()
    }

    host.pump()
    Swag.require(not explorer.load.started)
}

// Context actions follow the clicked breadcrumb or entry in both listing presentations.
#test
{
    let scratch = Testing.tempFilePath("scope-explorer-path-", "")
    let root = Path.combine(scratch, "Parent")
    let folder = Path.combine(root, "Folder")
    let file = Path.combine(folder, "File.txt")
    expect Directory.create(scratch)
    defer discard catch Directory.delete(scratch, recurse: true)
    expect Directory.create(root)
    expect Directory.create(folder)
    expect File.writeAllText(file, "A file to locate")

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    shipFrame(&host)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openExplorer(folder)
    let explorer = unwrap window.explorer
    explorer.setMode(.Names)
    waitMenuExplorer(&host, window)
    window.applyLayout()

    var postedActions: u32
    window.hookOnEvent = func|&postedActions|(_, evt)
    {
        if evt is CommandEvent as command where command.id == ViewerCommands.CopyLocation or command.id == ViewerCommands.CopyPath do
            postedActions += 1
        return false
    }
    defer window.hookOnEvent = null

    let breadcrumb = explorer.address.breadcrumb
    for index in breadcrumb.items.count - 2 until breadcrumb.items.count
    {
        var point = breadcrumb.localToSurface(breadcrumb.items[index].bodyRect.center())
        host.surface.surfaceToScreen(&point)
        Swag.require(host.mouseTargetAt(point) == breadcrumb)
        host.clickPopupMenuItemWhenShown(ViewerCommands.CopyLocation)
        host.click(point, .Right)
        let intended = index + 1 == breadcrumb.items.count ? folder : root
        Swag.require(host.autoHandled)
        Swag.require(Path.equals(Clipboard.getString(), intended), Format.toString("copied %, expected %", Clipboard.getString(), intended))
    }

    for mode in [ExplorerMode.Details, .Medium]
    {
        explorer.setMode(mode)
        window.applyLayout()
        var point = mode == .Details ? explorer.list.listView.localToSurface(Math.Point{50, explorer.list.lineHeight() * 0.5}) :
                                       explorer.grid.localToSurface(explorer.grid.tileRect(0).center())
        host.surface.surfaceToScreen(&point)
        host.clickPopupMenuItemWhenShown(ViewerCommands.CopyPath)
        host.click(point, .Right)
        Swag.require(host.autoHandled and Path.equals(Clipboard.getString(), file))
        Swag.require(window.currentFile.isEmpty())
    }
    Swag.require(postedActions == 0)

    window.sendCommandEvent(ViewerCommands.CopyLocation)
    Swag.require(Path.equals(Clipboard.getString(), folder))
    window.sendCommandEvent(ViewerCommands.CopyPath)
    Swag.require(Path.equals(Clipboard.getString(), file))
    Swag.require(postedActions == 2)
}

// Chooses `id` in the popup that `button` opens, through the shipped opener and modal path.
func chooseInQuietMenu(host: *Testing.HeadlessHost, window: *ViewerWindow, button: *IconButton, id: WndId)
{
    host.clickPopupMenuItemWhenShown(id)
    button.sigPressed.call(cast(*Button, button))
    waitMenuExplorer(host, window)
}

// Checks that the sort button names the column in force, then its direction.
func requireSortLabel(explorer: *Explorer, column, direction: string)
{
    let label = Format.toString("% %", column, direction)
    Swag.require(explorer.sortMenu.text() == label.toString())
}

// A choice made in the sort menu takes effect once, whatever the order already was: choosing the
// descending order really reverses the listing, and the button names the order in force.
#test
{
    var host: Testing.HeadlessHost
    let window   = openMenuExplorer(&host)
    let explorer = unwrap window.explorer
    Swag.require(explorer.sortColumn == 0 and not explorer.descending)
    requireSortLabel(explorer, appStrings().sort_Name, "↑")

    chooseInQuietMenu(&host, window, explorer.sortMenu, ViewerCommands.SortDescending)
    Swag.require(explorer.descending)
    requireSortLabel(explorer, appStrings().sort_Name, "↓")
    Swag.require(window.sendComputeCommandStateEvent(ViewerCommands.SortDescending).checked)
    var files: Array'String
    for index in explorer.shown where not explorer.entries[index].directory do
        files.add(explorer.entries[index].name)
    Swag.require(files.count > 2)
    for index in 1 until files.count do
        Swag.require(Latin1.compareNatural(files[index - 1], files[index]) >= 0)

    chooseInQuietMenu(&host, window, explorer.sortMenu, ViewerCommands.SortSize)
    Swag.require(explorer.sortColumn == 2 and explorer.descending)
    requireSortLabel(explorer, appStrings().sort_Size, "↓")

    chooseInQuietMenu(&host, window, explorer.sortMenu, ViewerCommands.SortAscending)
    Swag.require(explorer.sortColumn == 2 and not explorer.descending)
    requireSortLabel(explorer, appStrings().sort_Size, "↑")
}

// The kind menu holds "All items" apart from the kinds it narrows to, and its button names the
// kind in force.
#test
{
    var host:    Testing.HeadlessHost
    let window   = openMenuExplorer(&host)
    let explorer = unwrap window.explorer
    var checked: bool
    host.app.sigFrame += func|host = &host, checked = &checked|(_)
    {
        if checked[] do
            return
        let menu = unwrap host.capturedPopupMenu()
        Swag.require(menu.items.count > 2)
        Swag.require(menu.items[0]!.id == ViewerCommands.FilterAll)
        Swag.require(menu.items[1]!.separator)
        checked[] = true
        Swag.require(host.dismissPopupMenu())
    }

    explorer.kindMenu.sigPressed.call(cast(*Button, explorer.kindMenu))
    host.app.sigFrame.clear()
    Swag.require(checked)

    chooseInQuietMenu(&host, window, explorer.kindMenu, ViewerCommands.FilterImages)
    Swag.require(explorer.kindFilter == .Images)
    Swag.require(explorer.kindMenu.text() == appStrings().explore_FilterImages)
    chooseInQuietMenu(&host, window, explorer.kindMenu, ViewerCommands.FilterAll)
    Swag.require(explorer.kindFilter == .All)
}

// The view menu changes the view once, and its button names what the page shows.
#test
{
    var host: Testing.HeadlessHost
    let window   = openMenuExplorer(&host)
    let explorer = unwrap window.explorer
    chooseInQuietMenu(&host, window, explorer.modeMenu, ViewerCommands.Modes[1])
    Swag.require(explorer.mode == .Details)
    Swag.require(explorer.modeMenu.text() == appStrings().explore_Details)
    chooseInQuietMenu(&host, window, explorer.modeMenu, ViewerCommands.Modes[3])
    Swag.require(explorer.mode == .Medium)
    chooseInQuietMenu(&host, window, explorer.modeMenu, ViewerCommands.Boards[1])
    Swag.require(explorer.forced and explorer.forcedBoard == .Grid and explorer.grid.board == .Grid)
    Swag.require(explorer.modeMenu.text() == appStrings().board_Grid)
}

// A folder of films keeps its choice of online artwork or local previews in the view menu when
// the tiles are forced into a grid: the choice still decides what the grid shows.
#test
{
    var host: Testing.HeadlessHost
    let window   = boardWindow(&host, false, films: true)
    let explorer = unwrap window.explorer
    for name in ["One.mkv", "Two.mkv", "Three.mkv"] do
        explorer.entries.add({name: name, path: name, attempted: true})
    explorer.fill()
    Swag.require(explorer.grid.board == .Posters and explorer.showsMedia())
    explorer.forceBoard(true, .Grid)
    Swag.require(explorer.grid.board == .Grid and explorer.showsMedia())
    for command in ViewerCommands.Artwork do
        Swag.require(not window.sendComputeCommandStateEvent(command).hidden)

    explorer.entries.clear()
    explorer.entries.add({name: "notes.txt", path: "notes.txt", attempted: true})
    explorer.fill()
    Swag.require(not explorer.showsMedia())
    for command in ViewerCommands.Artwork do
        Swag.require(window.sendComputeCommandStateEvent(command).hidden)
}

// The path has air after the navigation; the permanent query and tools share the line below.
#test
{
    for width in [ViewerWindow.MinWidth, 1280'f32]
    {
        var host: Testing.HeadlessHost
        let window   = openMenuExplorer(&host, width)
        let explorer = unwrap window.explorer
        let address  = explorer.address.surfaceRect()
        let tools    = explorer.tools.surfaceRect()
        let header   = explorer.header.surfaceRect()
        Swag.require(address.bottom() <= tools.y)
        let frame = window.surface!.wnd
        Swag.require(frame.titleHidden)
        let navigation = window.refreshCaptionButton.surfaceRect()
        Swag.require(address.x - navigation.right() >= window.themeMetrics().wnd_CaptionPathGap - 0.5)
        Swag.require(address.width <= window.themeMetrics().wnd_CaptionPathWidth)
        Swag.require(address.right() + window.themeMetrics().wnd_CaptionPathGap < frame.captionRoomRect().right())
        Swag.require(window.searchGroup.surfaceRect().right() < tools.x)
        Swag.require(header.height <= Explorer.ToolHeight + Explorer.HeaderGap + 0.5)
        Swag.require(explorer.scroll.surfaceRect().y >= header.bottom())
        Swag.require(explorer.sortMenu.isVisible() and
                     explorer.kindMenu.isVisible() and
                     explorer.modeMenu.isVisible())
    }
}
