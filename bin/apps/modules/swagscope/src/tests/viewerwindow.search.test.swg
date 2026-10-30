#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

func completeFind(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    var steps = 0'u32
    while window.searchTimer and steps < 4_096
    {
        host.fireTimer(window.searchTimer)
        if window.searchTimer and not window.searchStream.isOpen() do
            Threading.Thread.sleep(1'ms)
        steps += 1
    }

    Swag.assert(window.searchTimer == null)
}

// Markdown paints under the caption strip; the shared find bar stays below it and its arrows act.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)

    let fileName = Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas/comprehensive.md")
    var index    = createViewerPluginRegistry()
    let window   = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.openFile(fileName)
    completeQueuedViewerFile(&host, window)
    window.applyLayout()

    window.showSearch()
    let area = window.documentArea()
    let top  = Math.max(area.y, window.stripInset()) + window.themeMetrics().floating_Inset * 0.5
    Swag.assert(window.searchBar.position.y >= top - 1)
    Swag.assert(window.searchBar.radius() == window.themeMetrics().corner_Floating)

    window.searchBox.setText("Heading")
    completeFind(&host, window)
    Swag.assert(window.searchMatches.count > 1 and
                window.searchNext.isEnabled() and
                window.searchPrevious.isEnabled())
    host.click(window.searchNext.surfaceRect().center())
    Swag.assert(window.searchIndex == 1)
    host.click(window.searchPrevious.surfaceRect().center())
    Swag.assert(window.searchIndex == 0)

    // A changed option must appear checked in the next search menu.
    Swag.assert(window.searchOptionsButton.isVisible() and window.searchOptionsButton.isEnabled())
    window.setSearchOption(ViewerCommands.MatchCase)
    Swag.assert(window.searchMatchCaseOption)
    completeFind(&host, window)

    let menu = window.createSearchOptionsMenu()
    var matchCaseChecked = false
    for maybeItem in menu.items
    {
        let item = unwrap maybeItem
        if item.id != ViewerCommands.MatchCase do
            continue
        Swag.assert(item.checked)
        matchCaseChecked = true
    }
    Swag.assert(matchCaseChecked)
}
