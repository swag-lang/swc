#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// The selected title scrolls only when the title actually shown in its tile is too long.
#test
{
    var host: Testing.HeadlessHost
    host.setup(880, 420)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let explorer = Explorer.create(window.documentPanel, window)
    explorer.entries.add({name: "A very long file name that cannot fit inside a small thumbnail tile.txt", attempted: true})
    explorer.entries.add({name: "short.txt", attempted: true})
    explorer.fill()
    explorer.show()
    window.applyLayout()
    let resting = host.render(window)
    explorer.grid.select(0)
    let selected = host.render(window)

    // Selecting the tile draws a ring around the picture; its text stays on the page ground.
    let rect           = explorer.grid.surfaceRect()
    let left           = cast(s32, rect.x + 16)
    let top            = cast(s32, rect.y + explorer.grid.cell.y - 24 - ExplorerGrid.ReadingHeight)
    let restingGround  = resting.pixelColor(left + 2, top + 22).argb
    let selectedGround = selected.pixelColor(left + 2, top + 22).argb
    var ink: u64
    for y in 20
    {
        for x in 60
        {
            let before = resting.pixelColor(left + cast(s32, x), top + cast(s32, y)).argb != restingGround
            let after  = selected.pixelColor(left + cast(s32, x), top + cast(s32, y)).argb != selectedGround
            Swag.assert(before == after)
            if before do
                ink += 1
        }
    }

    Swag.assert(ink > 0)
    Swag.assert(explorer.grid.nameTimer != null)
    explorer.grid.select(1)
    Swag.assert(explorer.grid.nameTimer == null)
}

// Catalogue titles can be much shorter than their file names, and should not keep an idle timer.
#test
{
    var host: Testing.HeadlessHost
    host.setup(880, 420)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let explorer = Explorer.create(window.documentPanel, window)
    explorer.entries.add({name: "A very long source filename that does not appear on a poster.mkv", attempted: true})
    explorer.entries.add({name: "short.mkv", attempted: true})
    explorer.fill()
    explorer.show()
    window.applyLayout()

    let grid = explorer.grid
    Swag.assert(grid.nameTimer == null)
    grid.board = .Posters
    grid.posters = true
    explorer.entries[0].movie.title = "Short title"
    grid.select(0)
    Swag.assert(grid.nameTimer == null)

    explorer.entries[0].movie.title = "A catalogue title that is far too long to fit inside this poster tile"
    grid.select(0)
    Swag.assert(grid.nameTimer != null)

    grid.rows = true
    grid.select(1)
    Swag.assert(grid.nameTimer == null)
}
