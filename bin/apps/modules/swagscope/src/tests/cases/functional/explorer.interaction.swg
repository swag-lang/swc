#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

func assertExplorerRenderStable(host: *Testing.HeadlessHost, window: *ViewerWindow, explorer: *Explorer)
{
    let before = host.renderSettled(window)
    let after  = host.render(window)
    let rect   = explorer.surfaceRect()
    var changed: u32
    for y in cast(s32, rect.height)
    {
        for x in cast(s32, rect.width)
        {
            let px = cast(s32, rect.x) + x
            let py = cast(s32, rect.y) + y
            if before.pixelColor(px, py) != after.pixelColor(px, py) do
                changed += 1
        }
    }

    Swag.require(changed == 0)
}

// Closing the information sheet returns its reserved width to the explorer page.
#[Swag.TestTag("explorer-info-close")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 640)

    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let data   = Path.combine(testSourceRoot(#curlocation), "datas")
    window.openExplorer(data)
    let explorer = unwrap window.explorer
    for 16
    {
        if not explorer.load.started do
            break
        explorer.load.task.wait()
        host.pump()
    }

    Swag.require(not explorer.load.started)
    window.applyLayout()

    let pageWidth     = explorer.grid.position.width
    let scrollWidth   = explorer.scroll.position.width
    let explorerWidth = explorer.position.width
    explorer.showInformation()
    Swag.require(explorer.padding.z == window.themeMetrics().infoSheet_Width + window.themeMetrics().floating_Inset)
    Swag.require(explorer.grid.position.width < pageWidth)

    let sheet  = window.infoSheet.surfaceRect()
    let metric = window.themeMetrics()
    var point  = Math.Point{sheet.right() - metric.infoSheet_Padding - metric.embInfo_CloseSize * 0.5,
                            sheet.y + metric.infoSheet_Padding - metric.embInfo_CloseMargin + metric.embInfo_CloseSize * 0.5}
    window.infoSheet.surface!.surfaceToScreen(&point)
    host.click(point)

    Swag.require(not window.infoSheet.isLocallyVisible())
    Swag.require(explorer.padding.z == 0)
    Swag.require(Math.abs(explorer.grid.position.width - pageWidth) < 0.5,
                 Format.toString("grid % / %, scroll % / %, explorer % / %",
                                 pageWidth,
                                 explorer.grid.position.width,
                                 scrollWidth,
                                 explorer.scroll.position.width,
                                 explorerWidth,
                                 explorer.position.width).toString())
}

// Filtering ignores case, narrows the shown indices, and restores the full listing when cleared.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let explorer = Explorer.create(window.documentPanel, window)
    explorer.setMode(.Names)
    for name in ["Alpha.txt", "Beta.md", "Alpine.png"] do
        explorer.entries.add({name: name, attempted: true})
    explorer.fill()

    explorer.filter.setText("AL")
    Swag.require(explorer.shown.count == 2)
    Swag.require(explorer.entries[explorer.shown[0]].name == "Alpha.txt")
    Swag.require(explorer.entries[explorer.shown[1]].name == "Alpine.png")

    explorer.filter.setText("bEtA.MD")
    Swag.require(explorer.shown.count == 1 and explorer.entries[explorer.shown[0]].name == "Beta.md")
    explorer.filter.setText("missing")
    Swag.require(explorer.shown.isEmpty())
    explorer.filter.setText("")
    Swag.require(explorer.shown.count == explorer.entries.count)
}

// Sorting uses the selected field, keeps folders first, and reverses file order when descending.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    let dataDirectory = Path.combine(testSourceRoot(), "datas")
    var listing: ExplorerListing
    var load:    ExplorerListingLoad
    load.start(dataDirectory, "", 0, false, &host.surfaceWnd)
    Swag.require(load.finish(&listing).isEmpty())

    for index in 1 until listing.entries.count do
        Swag.require(Latin1.compareNatural(listing.entries[index - 1].name, listing.entries[index].name) <= 0)

    load.start(dataDirectory, "", 2, false, &host.surfaceWnd)
    Swag.require(load.finish(&listing).isEmpty())
    for index in 1 until listing.entries.count
    {
        let previous = &listing.entries[index - 1]
        let current  = &listing.entries[index]
        Swag.require(previous.directory or not current.directory)
        if not previous.directory and not current.directory do
            Swag.require(previous.size <= current.size)
    }

    load.start(dataDirectory, "", 2, true, &host.surfaceWnd)
    Swag.require(load.finish(&listing).isEmpty())
    for index in 1 until listing.entries.count
    {
        let previous = &listing.entries[index - 1]
        let current  = &listing.entries[index]
        Swag.require(previous.directory or not current.directory)
        if not previous.directory and not current.directory do
            Swag.require(previous.size >= current.size)
    }
}

// Every sort field has a deterministic order in both directions, including ties and folders.
#test
{
    for column in 4
    {
        for descending in [false, true]
        {
            var load: ExplorerListingLoad
            load.sortColumn = cast(u32, column)
            load.descending = descending
            load.result.entries.add({name: "track10.txt", size: 10, modified: "2026-02-01 00:00"})
            load.result.entries.add({name: "Folder", directory: true})
            load.result.entries.add({name: "track2.md", size: 20, modified: "2026-01-01 00:00"})
            load.result.entries.add({name: "readme.txt", size: 5, modified: "2026-03-01 00:00"})
            load.result.entries.add({name: "a.md", size: 20, modified: "2026-01-01 00:00"})
            load.sortEntries()

            for index in 1 until load.result.entries.count
            {
                let previous = &load.result.entries[index - 1]
                let current  = &load.result.entries[index]
                Swag.require(previous.directory or not current.directory)
                if previous.directory or current.directory do
                    continue

                var order: s32
                switch column
                {
                case 1: order = Latin1.compareNatural(Path.extension(previous.name) orelse "",
                                                      Path.extension(current.name) orelse "")

                case 2:  order = previous.size == current.size ? 0 : (previous.size < current.size ? -1 : 1)
                case 3:  order = Latin1.compareNatural(previous.modified, current.modified)
                default: order = Latin1.compareNatural(previous.name, current.name)
                }

                if order == 0 do
                    order = Latin1.compareNatural(previous.name, current.name)
                Swag.require(descending ? order >= 0 : order <= 0)
            }
        }
    }
}

// Double-clicking a folder and a file works through the list; closing the viewer restores the
// folder, mode, and selection, and Return opens the selected file through the keyboard path.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 640)
    let root   = Gui.Testing.tempFilePath("scope-explorer-flow-", "")
    let nested = Path.combine(root, "Nested")
    expect Directory.create(root)
    expect Directory.create(nested)
    let file = Path.combine(nested, "readme.txt")
    discard expect File.writeAllText(file, "Explorer round trip")
    defer discard catch Directory.delete(root, recurse: true)

    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openExplorer(root)
    let explorer = unwrap window.explorer
    for 16
    {
        if not explorer.load.started do
            break
        explorer.load.task.wait()
        host.pump()
    }

    Swag.require(not explorer.load.started and explorer.entries.count == 1)
    explorer.suspend()
    for &preview in explorer.previews where preview.started
    {
        preview.task.wait()
        host.pump()
    }

    explorer.setMode(.Names)
    window.applyLayout()
    var listRect = explorer.list.listView.surfaceRect()
    var rowPoint = Math.Point{listRect.x + 32, listRect.y + explorer.list.lineHeight() * 0.5}
    host.click(rowPoint)
    Swag.require(explorer.selected == 0)
    host.doubleClick(rowPoint)
    for 16
    {
        if not explorer.load.started do
            break
        explorer.load.task.wait()
        host.pump()
    }

    Swag.require(explorer.listing.path == (expect Path.absolute(nested)) and explorer.entries.count == 1)
    explorer.setMode(.Details)
    Swag.require(explorer.mode == .Details and explorer.list.lineCount() == 1)
    window.applyLayout()
    listRect = explorer.list.listView.surfaceRect()
    rowPoint = Math.Point{listRect.x + 32, listRect.y + explorer.list.lineHeight() * 0.5}
    host.click(rowPoint)
    Swag.require(explorer.selected == 0)
    host.doubleClick(rowPoint)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.currentView != null and window.currentFile == (expect Path.absolute(file)))
    Swag.require(not explorer.isLocallyVisible())

    window.closeFile()
    host.pump()
    Swag.require(explorer.isLocallyVisible() and explorer.folder.isEmpty())
    Swag.require(explorer.listing.path == (expect Path.absolute(nested)))
    Swag.require(explorer.mode == .Details and explorer.selected == 0)
    assertExplorerRenderStable(&host, window, explorer)

    explorer.setMode(.Names)
    window.applyLayout()
    host.focus(explorer.list.listView)
    host.keyPress(.Return)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.currentView != null and window.currentFile == (expect Path.absolute(file)))
    window.closeFile()
    host.pump()
    Swag.require(explorer.mode == .Names and explorer.selected == 0)
    assertExplorerRenderStable(&host, window, explorer)

    window.closeFile()
    host.pump()
    Swag.require(not window.explorerActive and window.home.isLocallyVisible())
}

// Hover marks a thumbnail with the theme's stronger edge in both palettes.
#test
{
    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        host.setup(960, 640)
        if light do
            host.theme.setLight()
        else do
            host.theme.setDark()
        host.notify(.ThemeChanged)

        let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
        let explorer = Explorer.create(window.documentPanel, window)
        window.explorer       = explorer
        window.explorerActive = true
        explorer.entries.add({name: "Hover target.txt", attempted: true})
        explorer.setMode(.Medium)
        explorer.show()
        window.applyLayout()

        let tile      = explorer.grid.tileRect(0)
        let before    = host.render(window)
        let tilePoint = explorer.grid.localToSurface(Math.Point{tile.x, tile.y})
        let point     = explorer.grid.localToSurface(Math.Point{tile.horzCenter(), tile.y + 1})
        host.moveMouse(point)
        Swag.require(explorer.grid.hovered == 0)

        let after = host.render(window)
        var changed: u32
        for y in cast(s32, tile.height)
        {
            for x in cast(s32, tile.width)
            {
                let px = cast(s32, tilePoint.x) + x
                let py = cast(s32, tilePoint.y) + y
                if before.pixelColor(px, py) != after.pixelColor(px, py) do
                    changed += 1
            }
        }

        Swag.require(changed > 0)
    }
}
