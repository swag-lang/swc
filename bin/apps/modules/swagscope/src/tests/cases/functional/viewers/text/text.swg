#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

func textViewerFixturePath()->String => Path.combine(scopeTestDataDirectory(), "comprehensive.txt")

// A generated UTF-8 field report retains realistic line structure and searchable prose.
#test
{
    let fileName = scopeTestDataPath("viewer.field-notes.txt")
    let source   = expect File.readAllText(fileName)
    let phrase   = "sample labels were replaced after calibration"
    let offset   = source.indexOf(phrase)
    Swag.require(offset != Swag.U64.Max)

    var host: Testing.HeadlessHost
    host.setup(800, 520)
    var result = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName)
    let view   = assume cast(*PlainText.Panel, result.view)
    completeTextReads(&host, view)
    Swag.require(view.encoding == .Utf8)
    Swag.require(Utf8.contains(view.editor.text(), "Résumé de tournée"))

    let match = Viewer.SearchMatch{offset: offset, length: phrase.count}
    Swag.require(result.revealMatch!(match, phrase))
    Swag.require(view.editor.selectedText() == phrase)
}

func finishTextStatistics(host: *Testing.HeadlessHost, view: *PlainText.Panel)
{
    for 8
    {
        view.statisticsTask.wait()
        host.pump()
        if view.hasStatistics and
           view.statisticsEncoding == view.encoding and
           view.statisticsStart == view.contentStart do
            return
    }

    Swag.require(false, "text statistics did not settle")
}

// Lines are counted in the units of their encoding: a byte 0x0A inside a wider character is not a
// line feed, and a byte-order mark is not part of the first line.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-text-lines-", ".txt")
    defer discard catch File.delete(fileName)

    // UTF-16 LE with its mark: "a", U+0A00, U+010A, line feed, "b", line feed, "c".
    let bytes = [0xFF'u8, 0xFE'u8, 0x61'u8, 0x00'u8, 0x00'u8, 0x0A'u8, 0x0A'u8, 0x01'u8, 0x0A'u8, 0x00'u8, 0x62'u8, 0x00'u8, 0x0A'u8, 0x00'u8, 0x63'u8, 0x00'u8]
    expect File.writeAllBytes(fileName, bytes)

    var lines: Viewer.LineCounter
    Swag.require(lines.lineAt(fileName, 0, .Utf16Le, 2) == 1)
    Swag.require(lines.lineAt(fileName, 10, .Utf16Le, 2) == 2)
    Swag.require(lines.lineAt(fileName, 14, .Utf16Le, 2) == 3)
    Swag.require(lines.lineAt(fileName, 6, .Utf16Le, 2) == 1)

    // Read as UTF-32 BE from the start, the same bytes hold no line feed at all.
    lines.reset()
    Swag.require(lines.lineAt(fileName, 16, .Utf32Be) == 1)

    // A line is found where the previous one ended, from the closest line already numbered or
    // from the start; a line past the last one answers the start of the last line.
    lines.reset()
    Swag.require(lines.offsetOfLine(fileName, 0, .Utf16Le, 2) == Swag.U64.Max)
    Swag.require(lines.offsetOfLine(fileName, 1, .Utf16Le, 2) == 2)
    Swag.require(lines.offsetOfLine(fileName, 3, .Utf16Le, 2) == 14)
    Swag.require(lines.lineAt(fileName, 14, .Utf16Le, 2) == 3)
    Swag.require(lines.offsetOfLine(fileName, 2, .Utf16Le, 2) == 10)
    Swag.require(lines.offsetOfLine(fileName, 9, .Utf16Le, 2) == 14)

    // Counting an offset inside a line caches its real line start, not the requested byte.
    lines.reset()
    Swag.require(lines.lineAt(fileName, 12, .Utf16Le, 2) == 2)
    Swag.require(lines.offsetOfLine(fileName, 2, .Utf16Le, 2) == 10)

    let anchorOffset = lines.numberedOffset
    let anchorLine = lines.numberedLine
    Swag.require(lines.estimateOffsetOfLine(fileName, 3, .Utf16Le, 2) == 14)
    Swag.require(lines.estimateOffsetOfLine(fileName, 100, .Utf16Le, 2) == Swag.U64.Max)
    Swag.require(lines.numberedOffset == anchorOffset and lines.numberedLine == anchorLine)
}

// Whole-file line navigation treats CR, LF, and CRLF as one line ending each.
#test
{
    let fileName = Testing.tempFilePath("scope-text-line-endings-", ".txt")
    defer discard catch File.delete(fileName)
    let bytes = ['a'u8, '\r'u8, 'b'u8, '\r'u8, '\n'u8, 'c'u8, '\n'u8, 'd'u8, '\r'u8, 'e'u8]
    discard expect File.writeAllBytes(fileName, bytes)

    var lines: Viewer.LineCounter
    Swag.require(lines.offsetOfLine(fileName, 1) == 0)
    Swag.require(lines.offsetOfLine(fileName, 2) == 2)
    Swag.require(lines.offsetOfLine(fileName, 3) == 5)
    Swag.require(lines.offsetOfLine(fileName, 4) == 7)
    Swag.require(lines.offsetOfLine(fileName, 5) == 9)
    Swag.require(lines.lineAt(fileName, 1) == 1)
    Swag.require(lines.lineAt(fileName, 2) == 2)
    Swag.require(lines.lineAt(fileName, 4) == 2)
    Swag.require(lines.lineAt(fileName, 5) == 3)
    Swag.require(lines.lineAt(fileName, 8) == 4)
    Swag.require(lines.lineAt(fileName, 9) == 5)

    // A CR at the exact scan limit needs one more unit of lookahead to distinguish CR from CRLF.
    lines.reset()
    Swag.require(lines.lineAt(fileName, 2, .Utf8, 0, 2) == 0)
    lines.reset()
    Swag.require(lines.lineAt(fileName, 2, .Utf8, 0, 3) == 2)

    let utf16File = Testing.tempFilePath("scope-text-line-endings-utf16-", ".txt")
    defer discard catch File.delete(utf16File)
    // UTF-16 LE: U+0D00, CR, U+0A00, CRLF, U+000A.
    let utf16Bytes = [0x00'u8, 0x0D, 0x0D, 0, 0x00, 0x0A, 0x0D, 0, 0x0A, 0, 0x0A, 0]
    discard expect File.writeAllBytes(utf16File, utf16Bytes)
    lines.reset()
    Swag.require(lines.offsetOfLine(utf16File, 2, .Utf16Le) == 4)
    Swag.require(lines.offsetOfLine(utf16File, 3, .Utf16Le) == 10)
    Swag.require(lines.lineAt(utf16File, 2, .Utf16Le) == 1)
    Swag.require(lines.lineAt(utf16File, 4, .Utf16Le) == 2)
    Swag.require(lines.lineAt(utf16File, 10, .Utf16Le) == 3)

    // A final CR starts an empty last line, including for requests beyond EOF.
    let trailingCrFile = Testing.tempFilePath("scope-text-trailing-cr-", ".txt")
    defer discard catch File.delete(trailingCrFile)
    discard expect File.writeAllBytes(trailingCrFile, ['x'u8, '\r'u8])
    lines.reset()
    Swag.require(lines.offsetOfLine(trailingCrFile, 2) == 2)
    Swag.require(lines.offsetOfLine(trailingCrFile, 8) == 2)
    Swag.require(lines.lineAt(trailingCrFile, 2) == 2)
}

// CRLF remains one ending when its two encoded units straddle a read chunk.
#test
{
    let fileName = Testing.tempFilePath("scope-text-split-crlf-", ".txt")
    defer discard catch File.delete(fileName)
    var bytes: Array'u8
    bytes.resize(65_538)
    for i in 65_535 do
        bytes[i] = 'x'
    bytes[65_535] = '\r'
    bytes[65_536] = '\n'
    bytes[65_537] = 'z'
    discard expect File.writeAllBytes(fileName, bytes.toSlice())

    var lines: Viewer.LineCounter
    Swag.require(lines.lineAt(fileName, 65_537) == 2)
    Swag.require(lines.offsetOfLine(fileName, 2) == 65_537)

    // UTF-16 LE has its CR unit at the end of the same read chunk.
    let wideFile = Testing.tempFilePath("scope-text-split-crlf-utf16-", ".txt")
    defer discard catch File.delete(wideFile)
    var wideBytes: Array'u8
    wideBytes.resize(65_540)
    for i in 32_767
    {
        wideBytes[i * 2] = 'x'
        wideBytes[i * 2 + 1] = 0
    }
    wideBytes[65_534] = 0x0D
    wideBytes[65_535] = 0
    wideBytes[65_536] = 0x0A
    wideBytes[65_537] = 0
    wideBytes[65_538] = 'z'
    wideBytes[65_539] = 0
    discard expect File.writeAllBytes(wideFile, wideBytes.toSlice())

    lines.reset()
    Swag.require(lines.lineAt(wideFile, 65_538, .Utf16Le) == 2)
    Swag.require(lines.offsetOfLine(wideFile, 2, .Utf16Le) == 65_538)
}

// The line under the cursor is a line of the whole file, wherever the resident window starts. A
// window whose preceding lines would take a pause to count names no line rather than one of its
// own, until the reader numbers the lines.
#test
{
    let fileName = Testing.tempFilePath("scope-text-line-readout-", ".txt")
    defer discard catch File.delete(fileName)
    var source: String
    for i in 120_000 do
        source += Format.toString("Line % of a file longer than the resident window.\n", i + 1)
    discard expect File.writeAllBytes(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName)
    let view    = assume cast(*PlainText.Panel, session.view)
    defer if view.lineNumbers do
        view.toggleLineNumbers()
    Swag.require(view.currentLine() == 1)

    // A window a short count away is numbered without the gutter.
    var lines: Viewer.LineCounter
    let near = lines.offsetOfLine(fileName, 30_000)
    Swag.require(Utf8.startsWith(source.toSlice()[near to], "Line 30000 of"))
    Swag.require(view.revealOffset(near, "Line 30000"))
    completeTextReads(&host, view)
    Swag.require(view.residentStart > 0 and view.currentLine() == 30_000)
    Swag.require(Utf8.contains(view.detailsText().toSlice(), Format.toString(PlainText.texts().ui_CurrentLine, 30_000).toSlice()))

    // A window more than a few megabytes from the last count waits for the gutter.
    let far = lines.offsetOfLine(fileName, 110_000)
    Swag.require(Utf8.startsWith(source.toSlice()[far to], "Line 110000 of"))
    view.lines.reset()
    Swag.require(view.revealOffset(far, "Line 110000"))
    completeTextReads(&host, view)
    Swag.require(view.currentLine() == 0)
    Swag.require(not Utf8.contains(view.detailsText().toSlice(), Format.toString(PlainText.texts().ui_CurrentLine, "").toSlice()))

    view.toggleLineNumbers()
    Swag.require(view.currentLine() == 110_000)
}

// Typed byte positions and columns stay on source-character boundaries in UTF-8 and UTF-32.
#test
{
    let utf8File = Testing.tempFilePath("scope-text-offset-utf8-", ".txt")
    defer discard catch File.delete(utf8File)
    discard expect File.writeAllBytes(utf8File, ['a'u8, 0xC3, 0xA9, 'z'u8])

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(PlainText.viewerPlugin(), &host.root, utf8File)
    let utf8View = assume cast(*PlainText.Panel, session.view)
    completeTextReads(&host, utf8View)
    Swag.require(utf8View.encoding == .Utf8)
    Swag.require(utf8View.alignOffset(2) == 1)
    Swag.require(utf8View.offsetOfColumn(0, 3).offset == 3)

    let utf32File = Testing.tempFilePath("scope-text-offset-utf32-", ".txt")
    defer discard catch File.delete(utf32File)
    discard expect File.writeAllBytes(utf32File, [0'u8, 0, 0xFE, 0xFF, 0, 0, 0, 'A'u8, 0, 0, 0, 'B'u8])

    var utf32Session = openTestViewer(PlainText.viewerPlugin(), &host.root, utf32File)
    let utf32View = assume cast(*PlainText.Panel, utf32Session.view)
    completeTextReads(&host, utf32View)
    Swag.require(utf32View.encoding == .Utf32Be)
    Swag.require(utf32View.alignOffset(7) == 4)
    let second = utf32View.offsetOfColumn(4, 2)
    Swag.require(second.offset == 8 and second.column == 2)

    utf32View.fileSize = 0
    Swag.require(utf32View.alignOffset(0) == utf32View.contentStart)
}

// Basic text numbers its lines on demand, and the choice follows the reader to the next file.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 520)
    var result = openTestViewer(PlainText.viewerPlugin(), &host.root, textViewerFixturePath(), commandParent: &host.root)
    let view   = assume cast(*PlainText.Panel, result.view)
    Swag.require(not view.editor.flags.has(.LineNumbers))

    view.toggleLineNumbers()
    defer if view.lineNumbers do
        view.toggleLineNumbers()
    Swag.require(view.editor.flags.has(.LineNumbers))

    // The options show both switches in the state the panel is in.
    var options: OptionSheet.Page
    view.describeOptions(&options)
    Swag.require(options.rows[0].kind == .Toggle and options.rows[0].checked == view.wrapping)
    Swag.require(options.rows[1].label == PlainText.texts().ui_Numbers and options.rows[1].checked)

    // Marking the blanks is one more flag of the same editor; numbering stays as it was.
    Swag.require(options.rows[2].label == PlainText.texts().ui_Blanks and not options.rows[2].checked)
    view.toggleBlanks()
    defer if view.blanks do
        view.toggleBlanks()
    Swag.require(view.editor.flags.has(.DrawBlanks) and view.editor.flags.has(.LineNumbers))

    // The tab stops are a choice of the same sheet, carried by the editor and to the next file.
    Swag.require(options.rows[3].label == PlainText.texts().ui_TabWidth and options.rows[3].value == "4")
    view.setTabWidth(2)
    defer view.setTabWidth(4)
    Swag.require(view.editor.tabSize == 2 and view.editor.flags.has(.DrawBlanks))
    var next = openTestViewer(PlainText.viewerPlugin(), &host.root, textViewerFixturePath(), commandParent: &host.root)
    Swag.require(assume cast(*PlainText.Panel, next.view).editor.tabSize == 2)
    view.toggleWrap()
    Swag.require(view.editor.flags.has(.LineNumbers) and not view.editor.flags.has(.WordWrap))
    view.toggleWrap()
}

// The viewer-owned controls route their documented shortcuts, update the document, and follow a
// live language change.  Statistics are only shown for the encoding that computed them.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 520)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    let fileName = textViewerFixturePath()
    var result   = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName, commandParent: &host.root, infoParent: &host.root)
    Swag.require(result.view != null and result.commands == null and result.info != null)
    Swag.require(result.revealMatch != null and
                 result.searchBounds != null and
                 result.clearSearch != null and
                 result.isLoading != null and
                 result.retire != null)

    let view = assume cast(*PlainText.Panel, result.view)
    assertViewerInfoButton(view.zoomLabel)
    Swag.require(result.info.preferredSize.x == Viewer.InfoOptionsWidth + Viewer.ZoomSlotWidth)
    finishTextStatistics(&host, view)
    let lineDetails = Format.toString(PlainText.texts().ui_Lines, view.statistics.lines)
    Swag.require(Utf8.contains(view.detailsText().toSlice(), lineDetails.toSlice()))

    var toggleWrap = KeyEvent{kind: .Pressed, key: .W, modifiers: .CtrlShift}
    Swag.require(view.hookOnChildEvent!(view.editor, &toggleWrap) and not view.wrapping)

    // Ctrl+W is not the wrap shortcut, whether the editor or the panel receives it.
    var closeChild = KeyEvent{kind: .Pressed, key: .W, modifiers: .Control}
    Swag.require(not view.hookOnChildEvent(view.editor, &closeChild) and not view.wrapping)
    var closePanel = KeyEvent{kind: .Pressed, key: .W, modifiers: .Control}
    view.sendEvent(&closePanel)
    Swag.require(not closePanel.accepted and not view.wrapping)
    var panelWrap = KeyEvent{kind: .Pressed, key: .W, modifiers: .CtrlShift}
    view.sendEvent(&panelWrap)
    Swag.require(panelWrap.accepted and view.wrapping)
    view.sendEvent(&panelWrap)
    Swag.require(not view.wrapping)

    var zoomIn = KeyEvent{kind: .Pressed, key: .OemPlus, modifiers: .Control}
    Swag.require(view.hookOnChildEvent(view.editor, &zoomIn) and view.zoomPercent == 125)
    var resetZoom = KeyEvent{kind: .Pressed, key: .D0, modifiers: .Control}
    Swag.require(view.hookOnChildEvent(view.editor, &resetZoom) and view.zoomPercent == 100)
    view.applyEncoding(.Utf16Le)
    completeTextReads(&host, view)
    let changedDetails = view.detailsText()
    Swag.require(Utf8.startsWith(changedDetails.toSlice(), "UTF-16 LE"))
    let columnReadout = Format.toString(PlainText.texts().ui_CurrentColumn, view.editor.cursorLogicalCharPos() + 1)
    let byteReadout = Format.toString(PlainText.texts().ui_CurrentByte, Format.toString("%{X}", view.currentByteOffset()))
    Swag.require(Utf8.contains(changedDetails.toSlice(), columnReadout.toSlice()))
    Swag.require(Utf8.contains(changedDetails.toSlice(), byteReadout.toSlice()))

    // The encoding is chosen among the options, from a page that checks the one in force.
    host.activateOptionRowWhenShown(PlainText.texts().ui_Encoding)
    host.thenActivateOptionRow("UTF-8")
    view.showOptions()
    Swag.require(host.autoHandled and view.encoding == .Utf8)
    host.activateOptionRowWhenShown(PlainText.texts().ui_Wrap)
    view.showOptions()
    Swag.require(view.wrapping)
    view.toggleWrap()

    let oldEncoding = String.from(PlainText.texts().ui_Encoding)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.require(view.optionsButton.toolTip == "Options")
    Swag.require(oldEncoding != PlainText.texts().ui_Encoding)
    Swag.require(view.zoomLabel.toolTip == PlainText.texts().ui_ZoomMenu)
}

// The encodings answer a query in the lens, the one in force checked, rather than fill the empty
// lens: the options list them too.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 520)
    var result = openTestViewer(PlainText.viewerPlugin(), &host.root, textViewerFixturePath(), commandParent: &host.root, infoParent: &host.root)
    let view   = assume cast(*PlainText.Panel, result.view)

    var empty: Lens.Results
    var emptyEntries = Viewer.LensEntries.create(&empty, "Text", host.theme)
    view.describeLens(&emptyEntries)
    for &entry in empty.sections[0]!.entries do
        Swag.require(not Utf8.startsWith(entry.title, PlainText.texts().ui_Encoding), "an empty lens lists no encodings")

    var asked        = Testing.lensResults("encoding")
    var askedEntries = Viewer.LensEntries.create(&asked, "Text", host.theme)
    view.describeLens(&askedEntries)
    var encodings = 0
    var checked   = 0
    for &entry in asked.sections[0]!.entries where Utf8.startsWith(entry.title, PlainText.texts().ui_Encoding)
    {
        encodings += 1
        if entry.checked do
            checked += 1
    }

    Swag.require(encodings == 6 and checked == 1)
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
    discard expect File.writeAllBytes(fileName, source)
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName, waitForText: false)

    with let view = assume cast(*PlainText.Panel, session.view)
    {
        .resize(640, 360)
        .applyLayout()
    }

    Swag.require(view.read.started and view.editor.text().isEmpty())
    view.applyEncoding(.Windows1252)
    view.applyEncoding(.Utf8)
    completeTextReads(&host, view)
    finishTextStatistics(&host, view)
    Swag.require(view.statistics.lines == 40_000)
    let previousText = String.from(view.editor.text())

    view.applyEncoding(.Utf16Le)
    Swag.require(view.pendingSeek and view.editor.text() == previousText)
    view.loadNextChunk()
    Swag.require(view.read.started)
    view.read.task.wait()
    view.applyEncoding(.Utf32Be)
    view.applyEncoding(.Windows1252)
    Swag.require(view.read.wasCancelled())
    discard host.render(view)
    Swag.require(view.editor.text() == previousText)
    completeTextReads(&host, view)
    Swag.require(view.encoding == .Windows1252 and view.read.encoding == .Windows1252)
    Swag.require(Utf8.startsWith(view.editor.text(), "Plain text stays responsive"))
    finishTextStatistics(&host, view)
    Swag.require(view.statistics.lines == 40_000)
    Swag.require(view.bytesRead - view.residentStart <= 256 * 1024)

    // Retirement cancels a queued read without waiting or publishing its result.
    discard view.revealOffset(source.length / 2, "")
    view.loadNextChunk()
    Swag.require(view.read.started)
    discard view.retire()
    Swag.require(view.read.wasCancelled())
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
    var session = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName)
    let view    = assume cast(*PlainText.Panel, session.view)
    Swag.require(view.revealOffset(15, "needle"))
    Swag.require(not view.read.started and not view.pendingSeek)
    Swag.require(view.editor.selectedText() == "needle")
}

// An untrusted search offset cannot wrap into the resident window and produce an invalid highlight.
#test
{
    let fileName = Testing.tempFilePath("scope-text-offset-overflow-", ".txt")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, "needle")

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName)
    let view    = assume cast(*PlainText.Panel, session.view)
    Swag.require(view.bytesRead == view.fileSize)

    let revealed = view.revealOffset(Swag.U64.Max, "needle")
    Swag.require(revealed)
    Swag.require(view.pendingSeek and view.pendingSeekOffset == view.fileSize)
    view.stopLoading()
    discard view.retire()
}
