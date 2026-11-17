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

    Swag.require(window.searchTimer == null)
}

// Markdown and the other viewers reserve a strip for find; its arrows act on the document.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)

    let fileName = Path.combine(testSourceRoot(#curlocation), "datas/comprehensive.md")
    var index    = createViewerPluginRegistry()
    let window   = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.openFile(fileName)
    completeQueuedViewerFile(&host, window)
    window.applyLayout()

    window.showSearch()
    let area = window.documentArea()
    let top  = window.stripInset() + window.themeMetrics().floating_Inset * 0.5
    Swag.require(window.searchBar.position.bottom() <= area.y + window.currentView!.padding.y)
    Swag.require(window.searchBar.position.y >= top - 1)
    Swag.require(window.searchBar.backgroundStyle == .Transparent)
    Swag.require(window.searchCloseButton.isVisible())

    window.searchBox.setText("Heading")
    completeFind(&host, window)
    Swag.require(window.searchMatches.count > 1 and
                 window.searchNext.isEnabled() and
                 window.searchPrevious.isEnabled())
    host.click(window.searchNext.surfaceRect().center())
    Swag.require(window.searchIndex == 1)
    host.click(window.searchPrevious.surfaceRect().center())
    Swag.require(window.searchIndex == 0)

    // A changed option must appear checked in the next search menu.
    Swag.require(window.searchOptionsButton.isVisible() and window.searchOptionsButton.isEnabled())
    window.setSearchOption(ViewerCommands.MatchCase)
    Swag.require(window.searchMatchCaseOption)
    completeFind(&host, window)

    let menu = window.createSearchOptionsMenu()
    var matchCaseChecked = false
    for maybeItem in menu.items
    {
        let item = unwrap maybeItem
        if item.id != ViewerCommands.MatchCase do
            continue
        Swag.require(item.checked)
        matchCaseChecked = true
    }

    Swag.require(matchCaseChecked)
}

// A colon and a number in the lens move a text or a code reader to that line: the caret stands
// at its start and the line is in view, however far down the file it is.
#test
{
    for extension in [".txt", ".swg"]
    {
        let fileName = Testing.tempFilePath("scope-lens-line-", extension)
        defer discard catch File.delete(fileName)
        var source: String
        for i in 600 do
            source += Format.toString("// Line % of a file longer than the view.\n", i + 1)
        discard expect File.writeAllText(fileName, source)

        var host: HeadlessHost
        let window = framedViewerWindow(&host, fileName, extension == ".txt")
        window.lens.open(":450")
        host.finishAnimations()
        let section = unwrap window.lens.results.sections[0]
        Swag.require(section.entries[0].title == Format.toString(appStrings().lens_GoToLine, 450))
        section.entries[0].run!()
        window.lens.close()
        host.finishAnimations()

        let view = window.instances[window.activeChoiceIndex].view
        var editor: *RichEditCtrl
        if extension == ".txt"
        {
            let text = assume cast(*PlainText.Panel, view)
            completeTextReads(&host, text)
            Swag.require(text.currentLine() == 450, Format.toString("line %", text.currentLine()))
            editor = text.editor
        }
        else
        {
            let code = assume cast(*Code.Panel, view)
            discard host.render(code)
            Swag.require(code.editor.cursorLogicalLineIndex() == 449, Format.toString("line %", code.editor.cursorLogicalLineIndex() + 1))
            editor = code.editor
        }

        Swag.require(editor.cursorLogicalCharPos() == 0)
        let caret = editor.cursorDisplayPosition(editor.selectionStart())
        let top   = editor.scrollPosition().y
        Swag.require(caret.y > top and caret.y <= top + editor.paddedClientRect().height, "the line is out of view")

        // A column after a second colon places the caret on that character of the line; one past
        // its end stops at the end, and the row says so.
        for typed, index in [":451:4", ":452:999"]
        {
            window.lens.open(typed)
            host.finishAnimations()
            let columns = unwrap window.lens.results.sections[0]
            let column  = index == 0 ? 4'u64 : 44
            Swag.require(columns.entries[0].title == Format.toString(appStrings().lens_GoToLineColumn, 451 + index, column), columns.entries[0].title)
            columns.entries[0].run!()
            window.lens.close()
            host.finishAnimations()
            if extension == ".txt" do
                completeTextReads(&host, assume cast(*PlainText.Panel, view))
            else do
                discard host.render(unwrap view)
            Swag.require(editor.cursorLogicalLineIndex() == 450 + index or extension == ".txt")
            Swag.require(editor.cursorLogicalCharPos() == column - 1, Format.toString("column %", editor.cursorLogicalCharPos() + 1))
        }
    }
}

// A search that found nothing in a document of pictures of pages says why: there are no words to
// find, not none that match. A document with text keeps the plain answer.
#test
{
    for name, index in ["viewer.jpeg.pdf", "viewer.pdf"]
    {
        var host: HeadlessHost
        host.setup(960, 680)
        let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
        window.resize(960, 680)
        window.openFile(scopeTestDataPath(name))
        completeQueuedViewerFile(&host, window)
        window.applyLayout()

        window.showSearch()
        window.searchBox.setText("qqzzxx")
        completeFind(&host, window)
        Swag.require(window.searchComplete and window.searchMatches.isEmpty())
        let toolTip = window.searchCountLabel.toolTip.toString()
        if index == 0 do
            Swag.require(Utf8.contains(toolTip, PdfDocument.texts().ui_NoTextLayer), toolTip)
        else do
            Swag.require(toolTip == appStrings().ui_NoMatch, toolTip)
    }
}

// A count of matches over a document some pages of which hold no text says what it leaves out.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-partly-scanned-", ".pdf")
    defer discard catch File.delete(fileName)
    var document = Pdf.Document.create()
    var written  = Pdf.Page.create(320, 220)
    written.addText("alpha words", 32, 28, 24, Color.fromArgb(Argb.Black))
    document.addPage(#move written)
    document.addPage(Pdf.Page.create(320, 220))
    expect document.save(fileName)

    var host: HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.resize(960, 680)
    window.openFile(fileName)
    completeQueuedViewerFile(&host, window)
    window.applyLayout()

    window.showSearch()
    window.searchBox.setText("alpha")
    completeFind(&host, window)
    Swag.require(window.searchComplete and window.searchMatches.count == 1)
    let toolTip = window.searchCountLabel.toolTip.toString()
    Swag.require(Utf8.contains(toolTip, Format.toString(PdfDocument.texts().ui_SomeNoText, 1, 2).toString()), toolTip)
}
