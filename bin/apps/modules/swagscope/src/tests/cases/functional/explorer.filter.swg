#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// Explorer and file viewers share one centered search control. Escape clears the folder filter
// and leaves the page open, while the information sheet remains visible.
#test
{
    var host: Testing.HeadlessHost
    let window   = boardWindow(&host, false, films: false, width: 960, height: 640)
    let explorer = unwrap window.explorer
    for name in ["Alpha.txt", "Beta.md", "Alpine.png"] do
        explorer.entries.add({name: name, attempted: true})
    showBoard(&host, window, "Documents", "Notes")

    host.clickWnd(&window.findCaptionButton.button)
    Swag.require(window.searchShown and window.searchBox.hasFocus())
    Swag.require(window.searchBar.isLocallyVisible())
    let area = window.documentArea()
    let bar  = window.searchBar.position
    Swag.require(Math.abs(bar.horzCenter() - area.horzCenter()) < 1)
    window.searchBox.setText("Alpha")
    Swag.require(explorer.shown.count == 1)
    window.toggleInformation()
    host.keyPress(.Escape)
    Swag.require(window.isExploring() and not window.searchShown)
    Swag.require(window.infoSheet.isLocallyVisible())
    Swag.require(not explorer.filter.text().count and explorer.shown.count == 3)
    Swag.require(explorer.grid.hasFocus())

    host.keyPress(.F, .Control)
    Swag.require(window.searchBox.hasFocus())
    window.searchBox.setText("Beta")
    host.keyPress(.Return)
    Swag.require(explorer.shown.count == 1)
    host.keyPress(.Escape)
    Swag.require(not explorer.filter.text().count and explorer.shown.count == 3)
    Swag.require(window.infoSheet.isLocallyVisible())
    window.closeInformation()

    host.keyPress(.L, .Control)
    Swag.require(explorer.address.edit.hasFocus())
    host.keyPress(.Escape)
    Swag.require(window.isExploring() and not explorer.address.edit.isLocallyVisible())

    window.setFullScreen(true)
    host.keyPress(.Escape)
    Swag.require(window.isExploring() and not window.fullScreen)
    host.keyPress(.Escape)
    Swag.require(window.isExploring())
}

// Resizing and opening the folder pane keep the same search bar centered on the document.
#test
{
    var host: Testing.HeadlessHost
    let window   = boardWindow(&host, true, films: false, scale: 1.5, width: 960, height: 640)
    let explorer = unwrap window.explorer
    showBoard(&host, window, "Documents", "Notes")
    explorer.revealFilter()
    window.resize(ViewerWindow.MinWidth, 640)
    window.setFilePanelVisible(true)
    window.applyLayout()

    let area = window.documentArea()
    let bar  = window.searchBar.position
    Swag.require(Math.abs(bar.horzCenter() - area.horzCenter()) < 1)
    Swag.require(bar.x >= area.x and bar.right() <= area.right())
    Swag.require(window.searchBox.hasFocus())
}
