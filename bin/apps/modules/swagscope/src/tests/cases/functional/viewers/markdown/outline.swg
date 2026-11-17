#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

const SectionCount = 24'u64

// Writes a document of numbered sections long enough to scroll, and returns where each begins.
func writeSections(fileName: string)->Array'u64
{
    var offsets: Array'u64
    var source:  String
    for index in SectionCount
    {
        offsets.add(source.length)
        source += Format.toString("# Section %\n\n", index)
        for 6 do
            source += "A paragraph of ordinary prose that gives the section some height on the page.\n\n"
    }

    discard expect File.writeAllBytes(fileName, source.toString())
    return offsets
}

struct OutlinedDocument
{
    window:  *ViewerWindow
    zoom:    *MarkdownText.ZoomButton
    view:    *Markdown.View
    outline: *DocumentOutline
}

// Opens `fileName` in a viewer window and waits for its headings. An outline that is `open`
// follows the reading as the document moves; a closed one keeps its full width to the document.
func openOutlined(host: *HeadlessHost, fileName: string, open = true)->OutlinedDocument
{
    host.setup(880, 560)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(host, window)

    let zoom    = assume cast(*MarkdownText.ZoomButton, window.currentInfo!.children[0])
    let outline = unwrap zoom.outline
    if open
    {
        outline.toggle.setChecked(true)
        outline.toggle.sigCheckedChanged.call(outline.toggle)
    }

    completeViewerBackgroundLoad(host, &outline.load)
    window.applyLayout()
    return {window, zoom, assume cast(*Markdown.View, window.currentView), outline}
}

func settle(host: *HeadlessHost, view: *Markdown.View)
{
    for 256 where view.isLoading() do
        host.fireTimers()
    discard host.render()
}

// The full outline marks the heading being read as the document moves, without asking the
// document to move again, and marks nothing it does not list.
#test
{
    let fileName = Testing.tempFilePath("scope-markdown-follow-", ".md")
    defer discard catch File.delete(fileName)
    let offsets = writeSections(fileName)

    var host: HeadlessHost
    let document = openOutlined(&host, fileName)
    let outline  = document.outline
    Swag.require(outline.rows.count == SectionCount)

    var chosen = 0
    outline.sigSelected += func|&chosen|(_, _) { chosen += 1 }

    // Reading the top of the document marks its first heading.
    settle(&host, document.view)
    outline.markReading(document.view.readingOffset())
    Swag.require(outline.markedTarget() == offsets[0])

    // The document moved by itself: the outline follows and emits no choice.
    Swag.require(document.view.revealHeading(offsets[5]))
    settle(&host, document.view)
    Swag.require(outline.markedTarget() == offsets[5])
    Swag.require(chosen == 0)

    // A filter that hides the heading being read marks the nearest one listed before it.
    outline.setFilter("Section 1")
    Swag.require(outline.rows.count == 11 and outline.markedTarget() == offsets[1])
    outline.setFilter("Section 2")
    Swag.require(outline.markedTarget() == offsets[2])
    outline.setFilter("Section 9")
    Swag.require(outline.rows.count == 1 and outline.markedTarget() == Swag.U64.Max)
    outline.setFilter("")
    Swag.require(outline.markedTarget() == offsets[5] and chosen == 0)

    // Marking is a no-op before any block is laid out.
    outline.markReading(Swag.U64.Max)
    Swag.require(outline.markedTarget() == offsets[5])
}

// At the end of the document a later heading cannot rise to the top: the one the reader chose
// stays marked instead of the one that happens to stand there.
#test
{
    let fileName = Testing.tempFilePath("scope-markdown-end-", ".md")
    defer discard catch File.delete(fileName)
    let offsets = writeSections(fileName)

    // The last section ends the document within one screen only at the full width.
    var host: HeadlessHost
    let document = openOutlined(&host, fileName, open: false)
    let outline  = document.outline
    let last     = cast(u32, SectionCount - 1)

    outline.list.selectLine(last)
    settle(&host, document.view)
    Swag.require(outline.markedTarget() == offsets[last])
    Swag.require(document.view.readingProgress() >= 1)

    // The same reading position, reached without a choice, marks the heading at the top.
    outline.list.unselectAll()
    outline.markReading(document.view.readingOffset(), atEnd: true)
    Swag.require(outline.markedTarget() <= offsets[last] and outline.markedTarget() != Swag.U64.Max)
}

// Choosing a heading can be undone and redone; a heading reached by scrolling is not a jump.
#test
{
    let fileName = Testing.tempFilePath("scope-markdown-history-", ".md")
    defer discard catch File.delete(fileName)
    let offsets = writeSections(fileName)

    var host: HeadlessHost
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    let document = openOutlined(&host, fileName)
    let zoom     = document.zoom
    let view     = document.view
    settle(&host, view)
    Swag.require(not zoom.history.canGoBack() and not zoom.history.canGoForward())

    Swag.require(view.revealHeading(offsets[3]))
    settle(&host, view)
    Swag.require(not zoom.history.canGoBack())

    document.outline.list.selectLine(12)
    settle(&host, view)
    Swag.require(view.readingOffset() == offsets[12])
    Swag.require(zoom.history.canGoBack() and zoom.history.backVisits.back() == offsets[3])

    zoom.goBack()
    settle(&host, view)
    Swag.require(view.readingOffset() == offsets[3])
    Swag.require(not zoom.history.canGoBack() and zoom.history.canGoForward())
    Swag.require(document.outline.markedTarget() == offsets[3])

    // Alt and the arrows walk the same history from the document.
    view.setFocus()
    host.keyPress(.Right, .Alt)
    settle(&host, view)
    Swag.require(view.readingOffset() == offsets[12] and not zoom.history.canGoForward())
    host.keyPress(.Left, .Alt)
    settle(&host, view)
    Swag.require(view.readingOffset() == offsets[3])

    expect host.app.setLanguage("fr")
    Swag.require(MarkdownText.texts().ui_Back == "Retour dans le document")
    Swag.require(MarkdownText.texts().ui_Forward == "Avancer dans le document")
}

// A press on the heading already marked still returns to it, and a press on another one goes
// there: following the reading never makes the outline deaf to the reader.
#test
{
    let fileName = Testing.tempFilePath("scope-markdown-press-", ".md")
    defer discard catch File.delete(fileName)
    let offsets = writeSections(fileName)

    var host: HeadlessHost
    let document = openOutlined(&host, fileName)
    let outline  = document.outline

    Swag.require(document.view.revealHeading(offsets[5]))
    settle(&host, document.view)
    Swag.require(outline.markedTarget() == offsets[5])

    var chosen = 0
    outline.sigSelected += func|&chosen|(_, _) { chosen += 1 }
    let list   = outline.list
    let rowTop = func|list|(row: f32)->Math.Point => list.listView.localToSurface(Math.Point{24, list.lineHeight() * (row + 0.5) - list.scrollWnd.scrollPosition().y})

    host.click(rowTop(5))
    settle(&host, document.view)
    Swag.require(chosen == 1 and outline.markedTarget() == offsets[5])
    Swag.require(document.zoom.history.canGoBack())

    host.click(rowTop(7))
    settle(&host, document.view)
    Swag.require(chosen == 2 and document.view.readingOffset() == offsets[7])
    Swag.require(outline.markedTarget() == offsets[7])
}

// Returns the section heading at or before `reading`, the one a reader there is in.
func sectionAt(offsets: const [..] u64, reading: u64)->u64
{
    var result = Swag.U64.Max
    for offset in offsets where offset <= reading do
        result = offset
    return result
}

// An outline opened over a document marks the heading in view at once, before any scroll, and
// whether its headings or the document's layout came first. Opening the panel narrows the
// document, so the heading in view is read again rather than assumed.
#test
{
    let fileName = Testing.tempFilePath("scope-markdown-open-", ".md")
    defer discard catch File.delete(fileName)
    let offsets = writeSections(fileName)

    var host: HeadlessHost
    host.setup(880, 560)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    window.applyLayout()
    let view = assume cast(*Markdown.View, window.currentView)
    settle(&host, view)
    Swag.require(view.revealHeading(offsets[4]))
    settle(&host, view)

    let zoom    = assume cast(*MarkdownText.ZoomButton, window.currentInfo!.children[0])
    let outline = unwrap zoom.outline
    outline.toggle.setChecked(true)
    outline.toggle.sigCheckedChanged.call(outline.toggle)
    completeViewerBackgroundLoad(&host, &outline.load)
    Swag.require(outline.rows.count == SectionCount)
    let reading = sectionAt(offsets.toSlice(), view.readingOffset())
    Swag.require(reading >= offsets[3] and outline.markedTarget() == reading)

    // Closed and opened again, it marks where the document has moved meanwhile.
    outline.toggle.setChecked(false)
    outline.toggle.sigCheckedChanged.call(outline.toggle)
    outline.list.unselectAll()
    Swag.require(view.revealHeading(offsets[9]))
    settle(&host, view)
    outline.toggle.setChecked(true)
    outline.toggle.sigCheckedChanged.call(outline.toggle)
    Swag.require(outline.markedTarget() == sectionAt(offsets.toSlice(), view.readingOffset()))
    Swag.require(outline.markedTarget() >= offsets[8])
}
