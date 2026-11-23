#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

#[Swag.TestTag("stress")]
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-lens-line-after-prefix-", ".txt")
    defer discard catch File.delete(fileName)

    var source: String
    for line in 80_000
    {
        source += Format.toString("Line % - ", line + 1)
        source += "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n"
    }
    let target = source.indexOf("Line 50000")
    Swag.require(target > 8 * 1024 * 1024 and source.length < 64 * 1024 * 1024)
    discard expect File.writeAllBytes(fileName, source)

    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, fileName, true, 800, 560)
    window.lens.open(":50000")
    host.finishAnimations()
    let section = unwrap window.lens.results.sections[0]
    Swag.require(section.entries[0].title == Format.toString(appStrings().lens_GoToLine, 50_000))
    section.entries[0].run!()
    window.lens.close()

    let view = assume cast(*PlainText.Panel, window.currentView)
    completeTextReads(&host, view)
    let position = Format.toString("start %, target %, bytes %, line %",
                                   view.residentStart,
                                   target,
                                   view.bytesRead,
                                   view.currentLine())
    Swag.require(view.residentStart <= target and target < view.bytesRead and view.currentLine() == 50_000,
                 position)
    view.windowLine = 0
    Swag.require(view.currentByteOffset() == target)
    Swag.require(view.canBookmarkCurrentPosition())
    Swag.require(view.addCurrentPositionBookmark("Distant"))
    Swag.require(view.bookmarks[0].line == 0 and view.bookmarks[0].offset == target)
}

#[Swag.TestTag("stress")]
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-lens-estimated-line-", ".txt")
    defer discard catch File.delete(fileName)

    var file = expect File.openWrite(fileName)
    for batch in 500
    {
        var lines: String
        for line in 1_000
        {
            let number = batch * 1_000 + line + 1
            lines += Format.toString("Line % - ", number)
            lines += "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n"
        }
        expect file.writeAll(lines)
    }
    let fileSize = expect file.size()
    file.close()
    Swag.require(fileSize > 64 * 1024 * 1024)

    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, fileName, true, 800, 560)
    window.lens.open(":500000")
    host.finishAnimations()
    let section = unwrap window.lens.results.sections[0]
    let estimatedTitle = Format.toString("% · %",
                                         Format.toString(appStrings().lens_GoToLine, 500_000),
                                         PlainText.texts().ui_Estimated)
    Swag.require(section.entries[0].title == estimatedTitle)
    section.entries[0].run!()
    window.lens.close()

    let view = assume cast(*PlainText.Panel, window.currentView)
    completeTextReads(&host, view)
    Swag.require(view.hasEstimatedLine and view.estimatedLine == 500_000)
    Swag.require(Utf8.contains(view.detailsText().toSlice(), Format.toString(PlainText.texts().ui_EstimatedLine, 500_000).toSlice()))
}

#[Swag.TestTag("stress")]
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-large-scroll-", ".txt")
    defer discard catch File.delete(fileName)

    var source: String
    for 70_000 do
        source += "A large source line keeps the virtual scrollbar stable between frames.\n"
    Swag.require(source.length >= 2 * 1024 * 1024)
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

    host.paint(view)
    view.updateEstimatedHeight()

    view.setInitialFocus(view.editor)
    Swag.require(view.editor.hasFocus())
    host.keyPress(Input.Key.Down)
    Swag.require(view.editor.selectionEnd().lineIndex == 1)
    host.keyPress(Input.Key.Up)
    Swag.require(view.editor.selectionEnd().lineIndex == 0)
    host.keyPress(Input.Key.PageDown)
    let pageLine = view.editor.selectionEnd().lineIndex
    Swag.require(pageLine > 1)
    host.keyPress(Input.Key.PageUp)
    Swag.require(view.editor.selectionEnd().lineIndex < pageLine)

    let firstVirtualHeight = view.virtualHeight
    Swag.require(firstVirtualHeight > view.editor.paddedClientRect().height)
    for 64
    {
        view.loadNextChunk()
        Swag.require(view.virtualHeight >= firstVirtualHeight)
        Swag.require(view.editor.scrollableClientRect().height >= firstVirtualHeight)
    }

    Swag.require(view.bytesRead - view.residentStart <= 256 * 1024 + 16 * 1024)
    Swag.require((view.editor.text()).count <= 256 * 1024 + 16 * 1024)
    Swag.require(view.bytesRead < view.fileSize)

    let firstStart = view.residentStart
    view.editor.setScrollPosition(Math.Point{0, view.virtualHeight * 0.5})
    Swag.require(view.pendingSeek)
    host.fireTimers()
    completeTextReads(&host, view)
    Swag.require(view.residentStart > firstStart)
    Swag.require(view.bytesRead - view.residentStart <= 256 * 1024 + 16 * 1024)

    host.keyPress(Input.Key.End)
    completeTextReads(&host, view)
    host.paint(view)
    Swag.require(view.residentStart > 0)
    Swag.require(view.editor.scrollPosition().y > 0)
    host.keyPress(Input.Key.Home)
    completeTextReads(&host, view)
    host.paint(view)
    Swag.require(view.residentStart == 0 and not view.pendingSeek)
    Swag.require(view.editor.selectionEnd().lineIndex == 0)
    Swag.require(view.editor.scrollPosition().y == 0)
    host.fireTimers()
    Swag.require(view.residentStart == 0 and view.editor.scrollPosition().y == 0)
}

#[Swag.TestTag("stress")]
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-text-scrub-", ".txt")
    defer discard catch File.delete(fileName)

    var source: String
    for index in 70_000 do
        source += Format.toString("Distinct streamed line % keeps scrollbar seeks observable.\n", index)
    Swag.require(source.length >= 2 * 1024 * 1024)
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

    host.paint(view)
    view.updateEstimatedHeight()

    view.editor.setScrollPosition(Math.Point{0, view.virtualHeight * 0.85})
    Swag.require(view.pendingSeek)
    view.editor.setScrollPosition({0, 0})
    Swag.require(not view.pendingSeek)

    view.editor.setScrollPosition(Math.Point{0, view.virtualHeight * 0.85})
    view.editor.setScrollPosition(Math.Point{0, view.virtualHeight * 0.2})
    Swag.require(view.pendingSeek and view.isStreaming())
    completeTextReads(&host, view)
    let lowOffset = cast(u64, (0.2 * cast(f32, view.fileSize)))
    Swag.require(view.residentStart <= lowOffset and view.bytesRead >= lowOffset)

    let ratios = [0.8'f32, 0.1'f32, 0.65'f32, 0.3'f32, 0.9'f32, 0.05'f32]
    for ratio in ratios
    {
        let requestedY = view.virtualHeight * ratio
        view.editor.setScrollPosition(Math.Point{0, requestedY})
        Swag.require(view.pendingSeek and view.isStreaming())
        completeTextReads(&host, view)
        let offset = cast(u64, (ratio * cast(f32, view.fileSize)))
        Swag.require(view.residentStart <= offset and view.bytesRead >= offset)
        Swag.require(Math.abs(view.editor.scrollPosition().y - requestedY) <= 1)
        Swag.require(not view.editor.text().isEmpty())
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
    Swag.require(source.length >= 2 * 1024 * 1024)
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
    Swag.require(window.searchMatch == target)
    Swag.require(window.searchMatches.count == 1 and window.searchIndex == 0)
    Swag.require(window.searchCountLabel.text() == "1/1")
    let textView = assume cast(*PlainText.Panel, window.currentView)
    Swag.require(textView.editor.selectedText() == query)
    Swag.require(textView.bytesRead < textView.fileSize)
    host.paint(textView)
    textView.updateEstimatedHeight()
    Swag.require(textView.editor.scrollableClientRect().height > textView.editor.paddedClientRect().height)
}
