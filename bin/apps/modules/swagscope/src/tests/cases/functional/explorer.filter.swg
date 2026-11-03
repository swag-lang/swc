#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// The caption filter owns Escape; dismissing an edit must not dismiss its explorer page.
#test
{
    var host: Testing.HeadlessHost
    let window   = boardWindow(&host, false, films: false, width: 960, height: 640)
    let explorer = unwrap window.explorer
    for name in ["Alpha.txt", "Beta.md", "Alpine.png"] do
        explorer.entries.add({name: name, attempted: true})
    showBoard(&host, window, "Documents", "Notes")

    var point = window.findCaptionButton.surfaceRect().center()
    host.surface.surfaceToScreen(&point)
    host.click(point)
    Swag.require(explorer.filter.hasFocus())
    Swag.require(explorer.filterPanel.isLocallyVisible())
    let anchor = window.findCaptionButton.surfaceRect()
    let panel  = explorer.filterPanel.surfaceRect()
    Swag.require(Math.abs(panel.x - anchor.x) < 1)
    Swag.require(panel.y >= anchor.bottom() and panel.y - anchor.bottom() < Explorer.ToolHeight)
    Swag.require(explorer.filter.position.width == ViewerWindow.SearchNoOptionsFieldWidth)
    explorer.filter.setText("Alpha")
    Swag.require(explorer.shown.count == 1)
    host.keyPress(.Escape)
    Swag.require(window.isExploring(), "Escape in the filter must stay in Explorer")
    Swag.require(not explorer.filter.isLocallyVisible())
    Swag.require(not explorer.filterPanel.isLocallyVisible())
    Swag.require(not explorer.filter.text().count and explorer.shown.count == 3)
    Swag.require(explorer.grid.hasFocus())

    // Keyboard entry points use the same edit, including an empty query.
    host.keyPress(.F, .Control)
    Swag.require(explorer.filter.hasFocus())
    host.keyPress(.Escape)
    Swag.require(window.isExploring() and explorer.grid.hasFocus())
    host.keyPress(.Oem2)
    Swag.require(explorer.filter.hasFocus())
    explorer.filter.setText("Beta")
    host.keyPress(.Return)
    Swag.require(window.isExploring() and explorer.grid.hasFocus())
    Swag.require(explorer.shown.count == 1)
    host.keyPress(.F, .Control)
    host.keyPress(.Escape)
    Swag.require(not explorer.filter.text().count and explorer.shown.count == 3)
    Swag.require(window.isExploring())

    // Address editing also keeps Escape before the window shortcut is considered.
    host.keyPress(.L, .Control)
    Swag.require(explorer.address.edit.hasFocus())
    host.keyPress(.Escape)
    Swag.require(window.isExploring() and not explorer.address.edit.isLocallyVisible())

    // The window command dismisses only the current layer.
    Swag.require(window.keyShortcut(.None, .Escape) == ViewerCommands.Dismiss)
    window.toggleInformation()
    Swag.require(window.infoSheet.isLocallyVisible())
    explorer.focusContent()
    host.keyPress(.Escape)
    Swag.require(window.isExploring() and not window.infoSheet.isLocallyVisible())
    window.setFullScreen(true)
    host.keyPress(.Escape)
    Swag.require(window.isExploring() and not window.fullScreen)

    // Once the edit is over, the page's own Escape command is available again.
    host.keyPress(.Escape)
    Swag.require(not window.isExploring())
    Swag.require(window.sendComputeCommandStateEvent(ViewerCommands.Dismiss).disabled)
}

// Resizing and showing the folder pane keep a useful edit inside its explorer, at high DPI too.
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

    let panel = explorer.filterPanel.surfaceRect()
    let area  = explorer.surfaceRect()
    Swag.require(panel.x >= area.x and panel.right() <= area.right())
    Swag.require(panel.y >= area.y and panel.bottom() <= area.bottom())
    Swag.require(explorer.filter.position.width > 100 and explorer.filter.hasFocus())
    explorer.focusContent()
    Swag.require(not explorer.filterPanel.isLocallyVisible())
}
