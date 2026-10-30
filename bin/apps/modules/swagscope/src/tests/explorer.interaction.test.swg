#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

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
    Swag.assert(explorer.shown.count == 2)
    Swag.assert(explorer.entries[explorer.shown[0]].name == "Alpha.txt")
    Swag.assert(explorer.entries[explorer.shown[1]].name == "Alpine.png")

    explorer.filter.setText("bEtA.MD")
    Swag.assert(explorer.shown.count == 1 and explorer.entries[explorer.shown[0]].name == "Beta.md")
    explorer.filter.setText("missing")
    Swag.assert(explorer.shown.isEmpty())
    explorer.filter.setText("")
    Swag.assert(explorer.shown.count == explorer.entries.count)
}

// Sorting uses the selected field, keeps folders first, and reverses file order when descending.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    let testDirectory = unwrap Path.directoryName(#curlocation.fileName)
    let dataDirectory = Path.combine(testDirectory, "datas")
    var listing: ExplorerListing
    var load: ExplorerListingLoad
    load.start(dataDirectory, "", 0, false, &host.surfaceWnd)
    Swag.assert(load.finish(&listing).isEmpty())

    for index in 1 until listing.entries.count do
        Swag.assert(Latin1.compareNatural(listing.entries[index - 1].name, listing.entries[index].name) <= 0)

    load.start(dataDirectory, "", 2, false, &host.surfaceWnd)
    Swag.assert(load.finish(&listing).isEmpty())
    for index in 1 until listing.entries.count
    {
        let previous = &listing.entries[index - 1]
        let current  = &listing.entries[index]
        Swag.assert(previous.directory or not current.directory)
        if not previous.directory and not current.directory do
            Swag.assert(previous.size <= current.size)
    }

    load.start(dataDirectory, "", 2, true, &host.surfaceWnd)
    Swag.assert(load.finish(&listing).isEmpty())
    for index in 1 until listing.entries.count
    {
        let previous = &listing.entries[index - 1]
        let current  = &listing.entries[index]
        Swag.assert(previous.directory or not current.directory)
        if not previous.directory and not current.directory do
            Swag.assert(previous.size >= current.size)
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
                Swag.assert(previous.directory or not current.directory)
                if previous.directory or current.directory do
                    continue

                var order: s32
                switch column
                {
                case 1:
                    order = Latin1.compareNatural(Path.extension(previous.name) orelse "",
                                                  Path.extension(current.name) orelse "")
                case 2:
                    order = previous.size == current.size ? 0 : (previous.size < current.size ? -1 : 1)
                case 3:
                    order = Latin1.compareNatural(previous.modified, current.modified)
                default: order = Latin1.compareNatural(previous.name, current.name)
                }

                if order == 0 do
                    order = Latin1.compareNatural(previous.name, current.name)
                Swag.assert(descending ? order >= 0 : order <= 0)
            }
        }
    }
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
        Swag.assert(explorer.grid.hovered == 0)

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

        Swag.assert(changed > 0)
    }
}
