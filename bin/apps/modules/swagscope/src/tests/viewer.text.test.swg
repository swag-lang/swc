#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

func textViewerFixturePath()->String
{
    return Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), "comprehensive.txt")
}

func finishTextStatistics(host: *Testing.HeadlessHost, view: *TextView)
{
    for 8
    {
        if view.statisticsThread.isValid() do
            view.statisticsThread.wait()
        if view.statisticsTimer do
            host.fireTimer(view.statisticsTimer)
        if Atomic.get(&view.statisticsState) == 1 and view.statisticsEncoding == view.encoding and view.statisticsStart == view.contentStart do
            return
    }

    Swag.assert(false, "text statistics did not settle")
}

// The viewer-owned controls route their documented shortcuts, update the document, and follow a
// live language change.  Statistics are only shown for the encoding that computed them.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 520)
    defer
    {
        discard catch host.app.setLanguage(ReferenceLanguage)
        host.shutdown()
    }

    let fileName = textViewerFixturePath()
    var result   = openTestViewer(textViewerPlugin(), &host.root, fileName.toString(), commandParent: &host.root, infoParent: &host.root)
    Swag.assert(result.view != null and result.commands != null and result.info != null)
    Swag.assert(result.revealMatch != null and result.searchBounds != null and result.clearSearch != null and result.isLoading != null and result.retire != null)

    let view = cast(*TextView) result.view
    assertViewerInfoButton(view.zoomLabel)
    Swag.assert(result.info.preferredSize.x == ViewerZoomSlotWidth)
    finishTextStatistics(&host, view)
    let lineDetails = Format.toString(textStrings().ui_Lines, view.statistics.lines)
    Swag.assert(Utf8.contains(view.detailsText().toSlice(), lineDetails.toSlice()))

    var toggleWrap = KeyEvent{kind: .Pressed, key: .W, modifiers: .Control}
    Swag.assert(view.hookOnChildEvent!(view.editor, &toggleWrap) and not view.wrapping)
    var zoomIn = KeyEvent{kind: .Pressed, key: .OemPlus, modifiers: .Control}
    Swag.assert(view.hookOnChildEvent!(view.editor, &zoomIn) and view.zoomPercent == 125)
    var resetZoom = KeyEvent{kind: .Pressed, key: .D0, modifiers: .Control}
    Swag.assert(view.hookOnChildEvent!(view.editor, &resetZoom) and view.zoomPercent == 100)

    view.applyEncoding(.Utf16Le)
    let changedDetails = view.detailsText()
    Swag.assert(changedDetails == Format.toString(textStrings().ui_Details, "UTF-16 LE"))

    let oldEncodingTip = String.from(view.encodingCombo.toolTip)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.assert(view.wrapButton.toolTip == textStrings().ui_WrapOff)
    Swag.assert(view.encodingCombo.toolTip == textStrings().ui_Encoding and view.encodingCombo.toolTip != oldEncodingTip)
    Swag.assert(view.zoomLabel.toolTip == textStrings().ui_ZoomMenu)
}

// Basic text owns a focused visual contract just like every format-specific document surface.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(820, 540)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let commandBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 52})
    commandBar.dockStyle       = .Bottom
    commandBar.backgroundStyle = .Window
    commandBar.padding         = {16, 8, 16, 8}
    let infoBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 40})
    infoBar.dockStyle       = .Top
    infoBar.backgroundStyle = .InformationBar
    infoBar.padding         = {16, 4, 16, 4}

    var result = openTestViewer(textViewerPlugin(), &host.root, textViewerFixturePath().toString(), commandParent: commandBar, infoParent: infoBar)
    Swag.assert(result.view != null and result.commands != null and result.info != null)
    commandBar.centerGroup = result.commands
    infoBar.centerGroup    = result.info
    let view = cast(*TextView) result.view
    finishTextStatistics(&host, view)
    view.dockStyle          = .Center
    view.commands.dockStyle = .None
    view.info.dockStyle     = .None

    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(&host.root)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.text.document")
}

// Encoding changes are requests, even if an earlier worker already finished. Only the last
// interpretation reaches the document; neither the selector nor paint publishes stale text.
#test
{
    let fileName = Testing.tempFilePath("scope-text-encoding-", ".txt")
    defer discard catch File.delete(fileName)
    var source: String
    for 40_000 do
        source += "Plain text stays responsive while changing its encoding.\n"
    discard expect File.writeAllBytes(fileName, cast(const [..] u8) source.toString())
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    var session = openTestViewer(textViewerPlugin(), &host.root, fileName, waitForText: false)
    let view    = cast(*TextView) session.view!
    view.resize(640, 360)
    view.applyLayout()
    Swag.assert(view.read.started and view.editor.text().isEmpty())
    view.applyEncoding(.Windows1252)
    view.applyEncoding(.Utf8)
    completeTextReads(&host, view)
    finishTextStatistics(&host, view)
    Swag.assert(view.statistics.lines == 40_000)
    let previousText = String.from(view.editor.text())

    view.applyEncoding(.Utf16Le)
    Swag.assert(view.pendingSeek and view.editor.text() == previousText)
    view.loadNextChunk()
    Swag.assert(view.read.started)
    view.read.task.wait()
    view.applyEncoding(.Utf32Be)
    view.applyEncoding(.Windows1252)
    Swag.assert(Atomic.get(&view.read.cancelled))
    discard host.render(view)
    Swag.assert(view.editor.text() == previousText)
    completeTextReads(&host, view)
    Swag.assert(view.encoding == .Windows1252 and view.read.encoding == .Windows1252)
    Swag.assert(Utf8.startsWith(view.editor.text(), "Plain text stays responsive"))
    finishTextStatistics(&host, view)
    Swag.assert(view.statistics.lines == 40_000)
    Swag.assert(view.bytesRead - view.residentStart <= 256 * 1024)

    // Retirement cancels a queued read without waiting or publishing its result.
    discard view.revealOffset(source.length / 2, "")
    view.loadNextChunk()
    Swag.assert(view.read.started)
    discard view.retire()
    Swag.assert(Atomic.get(&view.read.cancelled))
    view.read.task.wait()
}

// Resident search offsets still refer to file bytes, including CRLF discarded by the editor.
#test
{
    let fileName = Testing.tempFilePath("scope-text-crlf-", ".txt")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, "first\r\nsecond\r\nneedle")
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    var session = openTestViewer(textViewerPlugin(), &host.root, fileName)
    let view    = cast(*TextView) session.view!
    Swag.assert(view.revealOffset(15, "needle"))
    Swag.assert(not view.read.started and not view.pendingSeek)
    Swag.assert(view.editor.selectedText() == "needle")
}
