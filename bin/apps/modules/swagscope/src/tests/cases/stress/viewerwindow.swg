#global if #command == Swag.CompilerCommand.Test
#global private
using Core, Pixel, Gui, Viewers

#[Swag.TestTag("stress")]
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-large-scroll-", ".txt")
    defer discard catch File.delete(fileName)

    var source: String
    for 70_000 do
        source += "A large source line keeps the virtual scrollbar stable between frames.\n"
    Swag.assert(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    let commands      = Wnd.create'Wnd(&host.root, {0, 0, 200, 36})
    var viewerSession = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName, commandParent: commands)

    with let view = assume cast(*PlainText.Panel, viewerSession.view)
    {
        .resize(800, 520)
        .applyLayout()
    }

    discard host.render(view)
    view.updateEstimatedHeight()

    view.setInitialFocus(view.editor)
    Swag.assert(view.editor.hasFocus())
    host.keyPress(Input.Key.Down)
    Swag.assert(view.editor.selectionEnd().lineIndex == 1)
    host.keyPress(Input.Key.Up)
    Swag.assert(view.editor.selectionEnd().lineIndex == 0)
    host.keyPress(Input.Key.PageDown)
    let pageLine = view.editor.selectionEnd().lineIndex
    Swag.assert(pageLine > 1)
    host.keyPress(Input.Key.PageUp)
    Swag.assert(view.editor.selectionEnd().lineIndex < pageLine)

    let firstVirtualHeight = view.virtualHeight
    Swag.assert(firstVirtualHeight > view.editor.paddedClientRect().height)
    for 64
    {
        view.loadNextChunk()
        Swag.assert(view.virtualHeight >= firstVirtualHeight)
        Swag.assert(view.editor.scrollableClientRect().height >= firstVirtualHeight)
    }

    Swag.assert(view.bytesRead - view.residentStart <= 256 * 1024 + 16 * 1024)
    Swag.assert((view.editor.text()).count <= 256 * 1024 + 16 * 1024)
    Swag.assert(view.bytesRead < view.fileSize)

    let firstStart = view.residentStart
    view.editor.setScrollPosition(Math.Point{0, view.virtualHeight * 0.5})
    Swag.assert(view.pendingSeek)
    host.fireTimers()
    completeTextReads(&host, view)
    Swag.assert(view.residentStart > firstStart)
    Swag.assert(view.bytesRead - view.residentStart <= 256 * 1024 + 16 * 1024)

    host.keyPress(Input.Key.End)
    completeTextReads(&host, view)
    discard host.render(view)
    Swag.assert(view.residentStart > 0)
    Swag.assert(view.editor.scrollPosition().y > 0)
    host.keyPress(Input.Key.Home)
    completeTextReads(&host, view)
    discard host.render(view)
    Swag.assert(view.residentStart == 0 and not view.pendingSeek)
    Swag.assert(view.editor.selectionEnd().lineIndex == 0)
    Swag.assert(view.editor.scrollPosition().y == 0)
    host.fireTimers()
    Swag.assert(view.residentStart == 0 and view.editor.scrollPosition().y == 0)
}
#[Swag.TestTag("stress")]
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-text-scrub-", ".txt")
    defer discard catch File.delete(fileName)

    var source: String
    for index in 70_000 do
        source += Format.toString("Distinct streamed line % keeps scrollbar seeks observable.\n", index)
    Swag.assert(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    let commands      = Wnd.create'Wnd(&host.root, {0, 0, 200, 36})
    var viewerSession = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName, commandParent: commands)

    with let view = assume cast(*PlainText.Panel, viewerSession.view)
    {
        .resize(800, 520)
        .applyLayout()
    }

    discard host.render(view)
    view.updateEstimatedHeight()

    view.editor.setScrollPosition(Math.Point{0, view.virtualHeight * 0.85})
    Swag.assert(view.pendingSeek)
    view.editor.setScrollPosition({0, 0})
    Swag.assert(not view.pendingSeek)

    view.editor.setScrollPosition(Math.Point{0, view.virtualHeight * 0.85})
    view.editor.setScrollPosition(Math.Point{0, view.virtualHeight * 0.2})
    Swag.assert(view.pendingSeek and view.isStreaming())
    completeTextReads(&host, view)
    let lowOffset = cast(u64, (0.2 * cast(f32, view.fileSize)))
    Swag.assert(view.residentStart <= lowOffset and view.bytesRead >= lowOffset)

    let ratios = [0.8'f32, 0.1'f32, 0.65'f32, 0.3'f32, 0.9'f32, 0.05'f32]
    for ratio in ratios
    {
        let requestedY = view.virtualHeight * ratio
        view.editor.setScrollPosition(Math.Point{0, requestedY})
        Swag.assert(view.pendingSeek and view.isStreaming())
        completeTextReads(&host, view)
        let offset = cast(u64, (ratio * cast(f32, view.fileSize)))
        Swag.assert(view.residentStart <= offset and view.bytesRead >= offset)
        Swag.assert(Math.abs(view.editor.scrollPosition().y - requestedY) <= 1)
        Swag.assert(not view.editor.text().isEmpty())
    }
}
#[Swag.TestTag("stress")]
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-large-search-", ".txt")
    defer discard catch File.delete(fileName)

    let query  = "marker across boundary"
    let target = ViewerWindow.SearchChunkSize * 10 - 7
    var source: String
    for target / 64 do
        source += "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n"
    for target - source.length do
        source += "x"
    source += query
    for 32_000 do
        source += "\nThe rest of the large document stays searchable."
    Swag.assert(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(fileName)
    completeQueuedViewerFile(&host, window)
    window.searchBox.setText(query)
    window.findNext()

    completeViewerSearch(&host, window)
    Swag.assert(window.searchMatch == target)
    Swag.assert(window.searchMatches.count == 1 and window.searchIndex == 0)
    Swag.assert(window.searchCountLabel.text() == "1/1")
    let textView = assume cast(*PlainText.Panel, window.currentView)
    Swag.assert(textView.editor.selectedText() == query)
    Swag.assert(textView.bytesRead < textView.fileSize)
    discard host.render(textView)
    textView.updateEstimatedHeight()
    Swag.assert(textView.editor.scrollableClientRect().height > textView.editor.paddedClientRect().height)
}
