#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

#[Swag.TestTag("stress")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 640)
    let window   = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    let explorer = Explorer.create(window.documentPanel, window)
    explorer.setMode(.Names)
    for index in 20_000
    {
        with var entry: ExplorerEntry
        {
            .name      = Format.toString("File %.txt", index)
            .attempted = true
        }

        explorer.entries.add(#move entry)
    }

    explorer.fill()
    explorer.selected = 1234
    explorer.setMode(.Small)
    window.applyLayout()
    let visible = explorer.grid.visibleRange()
    Swag.require(visible.end - visible.first < 100 and explorer.shown.count == 20_000)
    explorer.setMode(.Details)
    Swag.require(explorer.selected == 1234 and explorer.list.focusIndex == 1234)
    explorer.filter.setText("File 1234.txt")
    Swag.require(explorer.shown.count == 1 and explorer.shown[0] == 1234)
}
