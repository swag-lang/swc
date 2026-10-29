#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// Long selected names animate inside their tile, while short names leave no timer running.
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

    // The beginning of the name occupies the same pixels before the marquee moves. The tile
    // background changes on selection, so compare text masks against each frame's own ground.
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
    host.fireTimer(explorer.grid.nameTimer)
    Swag.assert(explorer.grid.nameTick == 1)
    explorer.grid.select(1)
    Swag.assert(explorer.grid.nameTimer == null)
}
