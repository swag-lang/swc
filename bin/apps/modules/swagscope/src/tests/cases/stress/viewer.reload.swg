#global if #command == Swag.CompilerCommand.Test
#global private
using Core, Gui, Viewers

#[Swag.TestTag("stress")]
#test
{
    let previous = MarkdownText.g_ViewerSettings
    defer MarkdownText.g_ViewerSettings = previous
    MarkdownText.g_ViewerSettings = {}
    var source: String
    for 12_000 do
        source += "A paragraph of the manuscript remains at the same reading position.\n\n"
    let fileName = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope-reload-%.md", Guid64.random()))
    writeReloadFile(fileName, source)
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    window.searchBox.setText("manuscript")
    for 64 where window.searchTimer != null do
        host.fireTimer(window.searchTimer)
    let zoom = assume cast(*MarkdownText.ZoomButton, window.currentInfo!.children[0])
    zoom.applyZoom(150)
    let view = assume cast(*Markdown.View, window.currentView)
    for 64 where view.isLoading() do
        host.fireTimers()
    assume cast(*ScrollWnd, view.children[0]).setScrollPos(0, 700)
    for 64 where view.isLoading() do
        host.fireTimers()
    let position = assume cast(*ScrollWnd, view.children[0]).scrollPosition()
    Swag.assert(position.y > 0)

    source += "The file now contains another paragraph.\n"
    writeReloadFile(fileName, source)
    pollFileWatch(&host, window)
    Swag.assert(window.pendingFile.isEmpty())
    for 8 where window.pendingFile.isEmpty() do
        pollFileWatch(&host, window)
    Swag.assert(not window.pendingFile.isEmpty())
    completeQueuedViewerFile(&host, window)
    for 64 where window.readingState.restoring
    {
        host.fireTimers()
        host.fireTimer(window.fileWatchTimer)
    }

    Swag.assert(not window.readingState.restoring)
    Swag.assert(window.choices[window.activeChoiceIndex].key == "markdown")
    Swag.assert(window.searchBox.text() == "manuscript")
    Swag.assert(assume cast(*MarkdownText.ZoomButton, window.currentInfo.children[0]).zoomPercent == 150)
    Swag.assert(assume cast(*ScrollWnd, window.currentView!.children[0]).scrollPosition() == position)
    pollFileWatch(&host, window)
    Swag.assert(window.pendingFile.isEmpty())

    // A temporarily missing path leaves the current viewer readable; its return is observed.
    discard expect File.delete(fileName)
    pollFileWatch(&host, window)
    Swag.assert(window.currentView != null and window.pendingFile.isEmpty())
    writeReloadFile(fileName, "Short document.\n")
    for 8 where window.pendingFile.isEmpty() do
        pollFileWatch(&host, window)
    completeQueuedViewerFile(&host, window)
    host.fireTimer(window.fileWatchTimer)
    Swag.assert(assume cast(*ScrollWnd, window.currentView.children[0]).scrollPosition().y == 0)
}
