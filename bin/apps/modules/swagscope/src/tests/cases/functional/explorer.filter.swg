#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// The permanent folder filter keeps its place through focus changes, resizing and the sheet.
// Escape returns to the listing while the field and its query stay visible.
#test
{
    var host: Testing.HeadlessHost
    let window   = boardWindow(&host, false, films: false, width: 960, height: 640)
    let explorer = unwrap window.explorer
    for name in ["Alpha.txt", "Beta.md", "Alpine.png"] do
        explorer.entries.add({name: name, attempted: true})
    showBoard(&host, window, "Documents", "Notes")

    host.keyPress(.F, .Control)
    Swag.require(window.searchBox.hasFocus())
    Swag.require(not window.searchBar.isLocallyVisible() and window.searchGroup.isVisible())
    let bar = window.searchGroup.surfaceRect()
    let tools = explorer.tools.surfaceRect()
    Swag.require(bar.right() < tools.x)
    window.searchBox.setText("Alpha")
    Swag.require(explorer.shown.count == 1)
    window.toggleInformation()
    Swag.require(window.searchGroup.surfaceRect() == bar and explorer.tools.surfaceRect() == tools)
    Swag.require(window.infoSheet.surfaceRect().y >= tools.bottom())
    host.keyPress(.Escape)
    Swag.require(window.isExploring() and not window.searchShown)
    Swag.require(window.searchGroup.isVisible())
    Swag.require(window.infoSheet.isLocallyVisible())
    Swag.require(explorer.filter.text() == "Alpha" and explorer.shown.count == 1)
    Swag.require(explorer.grid.hasFocus())

    host.keyPress(.F, .Control)
    Swag.require(window.searchBox.hasFocus())
    window.searchBox.setText("Beta")
    host.keyPress(.Return)
    Swag.require(explorer.shown.count == 1)
    host.keyPress(.Escape)
    Swag.require(explorer.filter.text() == "Beta" and explorer.shown.count == 1)
    Swag.require(not window.infoSheet.isLocallyVisible() and explorer.grid.hasFocus())
    window.searchBox.setText("")
    Swag.require(not explorer.filter.text().count and explorer.shown.count == 3)

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

// The folder filter uses the same case, word and expression rules as document search.
#test
{
    var host: Testing.HeadlessHost
    let window   = boardWindow(&host, false, films: false, width: 960, height: 640)
    let explorer = unwrap window.explorer
    for name in ["Alpha.txt", "alpha.md", "Alphabet.png", "Beta.txt"] do
        explorer.entries.add({name: name, attempted: true})
    showBoard(&host, window, "Documents", "Notes")
    window.sendCommandEvent(ViewerCommands.Find)
    Swag.require(window.searchOptionsButton.isLocallyVisible())
    let menu = window.createSearchOptionsMenu()
    Swag.require(menu.items.count == 3)
    menu.destroy()

    window.searchBox.setText("alpha")
    Swag.require(explorer.shown.count == 3)
    window.setSearchOption(ViewerCommands.MatchCase)
    Swag.require(explorer.shown.count == 1)
    window.setSearchOption(ViewerCommands.MatchCase)
    window.setSearchOption(ViewerCommands.WholeWord)
    Swag.require(explorer.shown.count == 2)
    window.setSearchOption(ViewerCommands.RegularExpression)
    window.searchBox.setText("^Alpha.*\\.txt$")
    Swag.require(explorer.shown.count == 1)
    window.searchBox.setText("(")
    Swag.require(not window.searchBox.isValid() and explorer.shown.isEmpty())
}

// Resizing keeps the permanent filter and listing tools on one line.
#test
{
    var host: Testing.HeadlessHost
    let window   = boardWindow(&host, true, films: false, scale: 1.5, width: 960, height: 640)
    let explorer = unwrap window.explorer
    showBoard(&host, window, "Documents", "Notes")
    explorer.revealFilter()
    window.resize(ViewerWindow.MinWidth, 640)

    window.applyLayout()

    let bar   = window.searchGroup.surfaceRect()
    let tools = explorer.tools.surfaceRect()
    Swag.require(bar.right() < tools.x)
    Swag.require(Math.abs(bar.vertCenter() - tools.vertCenter()) < 1)
    Swag.require(window.searchBox.hasFocus())
}
