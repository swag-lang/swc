#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

internal func saveViewerState(window: *ViewerWindow)->String
{
    var result:     ConcatBuffer
    var encoder:    Serialization.Encoder'Serialization.Write.TagBin
    var serializer: Serialization.Serializer
    expect serializer.startWrite(&encoder, &result)
    expect serializer.beginSection(.Unordered)
    expect window.serializeState(&serializer)
    expect serializer.endSection()
    expect serializer.end()
    return result.toString()
}

// Reports whether the lens of `window` shows an entry titled `title`.
internal func lensHasEntry(window: *ViewerWindow, title: string)->bool
{
    for section in window.lens.results.sections
    {
        for &entry in section!.entries where entry.title == title do
            return true
    }

    return false
}

internal func loadViewerState(window: *ViewerWindow, bytes: const [..] u8)
{
    var decoder:    Serialization.Decoder'Serialization.Read.TagBin
    var serializer: Serialization.Serializer
    expect serializer.startRead(&decoder, bytes)
    expect serializer.beginSection(.Unordered)
    expect window.serializeState(&serializer)
    expect serializer.endSection()
    expect serializer.end()
}

// The Markdown scale round-trips with the window preferences and rejects out-of-range state.
#test
{
    let previous = MarkdownText.g_ViewerSettings
    defer MarkdownText.g_ViewerSettings = previous
    var host: Testing.HeadlessHost
    host.setup(880, 560)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    for percent in [150'u32, 0, 400]
    {
        MarkdownText.g_ViewerSettings.zoomPercent = percent
        let saved = saveViewerState(window)
        MarkdownText.g_ViewerSettings = {}
        loadViewerState(window, saved.toSlice())
        Swag.require(MarkdownText.g_ViewerSettings.zoomPercent == Viewer.clampZoom(percent))
    }
}

// MIDI label and keyboard-width choices round-trip with the main window and sanitize old state.
#test
{
    let previous = Midi.g_ViewerSettings
    defer Midi.g_ViewerSettings = previous
    var host: Testing.HeadlessHost
    host.setup(880, 560)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())

    Midi.g_ViewerSettings = {pitchLabelMode: .MidiNumber, keyboardWidthMode: 2}
    let saved = saveViewerState(window)
    Midi.g_ViewerSettings = {}
    loadViewerState(window, saved.toSlice())
    Swag.require(Midi.g_ViewerSettings.pitchLabelMode == .MidiNumber and Midi.g_ViewerSettings.keyboardWidthMode == 2)

    Midi.g_ViewerSettings.keyboardWidthMode = Swag.U32.Max
    let damaged = saveViewerState(window)
    Midi.g_ViewerSettings = {}
    loadViewerState(window, damaged.toSlice())
    Swag.require(Midi.g_ViewerSettings.pitchLabelMode == .MidiNumber and Midi.g_ViewerSettings.keyboardWidthMode == 2)
}

// The window canonicalizes what it opens, so the fixture is spelled the way it will be read
// back: `#curlocation` gives its directory with the host separator, which no comparison
// against `currentFile` would survive.
internal func viewerFixturePath()->String
{
    var result: #returntype
    result = Path.combine(testSourceRoot(#curlocation), "datas/comprehensive.txt")
    Path.normalize(&result)
    return result
}

func hexViewerFixturePath()->String
{
    var result: #returntype
    result = Path.combine(testSourceRoot(#curlocation), "datas/viewer.hex")
    Path.normalize(&result)
    return result
}

func markTestViewerRetired(wnd: *Wnd)->bool
{
    let retired = cast(*bool, unwrap wnd.userData)
    retired[] = true
    return true
}

func delayTestViewerRetirement(wnd: *Wnd)->bool
{
    let calls = cast(*u32, unwrap wnd.userData)
    calls[] += 1
    return calls[] >= 2
}

// Waits for the summary the text viewer publishes once its background analysis lands.
//
// `isLoading` above answers for the document, not for the line and word totals: those arrive on
// their own worker, and the information band shows the encoding alone until they do. A golden of
// that band therefore has two possible answers unless it waits here.
internal func completeViewerStatistics(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    let view = assume cast(*PlainText.Panel, window.currentView)
    completeTextStatistics(host, view)
}

// Runs a search to its end: every streamed chunk, and every poll of a viewer that reads its
// document in the background.
internal func completeViewerSearch(host: *Testing.HeadlessHost, window: *ViewerWindow)
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
    if window.currentView and
       window.activeChoiceIndex < window.choices.count and
       window.choices[window.activeChoiceIndex].key == PlainText.ViewerKey do
        completeTextReads(host, assume cast(*PlainText.Panel, window.currentView))
}

func createSidePanelFixture(host: Viewer.Host)
{
    let panel = host.createSidePanel(220, host.icon(), "Details")
    let label = Label.create(panel.content, "Viewer details")
    label.dockStyle = .Center

    with let view = Wnd.create'Wnd(host.contentParent())
    {
        .dockStyle       = .Center
        .backgroundStyle = .View
    }

    host.attachView(view)
}

// The optional viewer lane is host composition, not a private rectangle each decoder invents.
// It is a card in the shape of the sheet, the floating inset away from the window edges, and
// closing it returns every pixel to the document.
#test
{
    var host: Testing.HeadlessHost
    host.setup(720, 460)

    let infoParent = Wnd.create'Wnd(&host.root, {0, 0, 720, 40})
    var session    = openTestViewer(testViewerPlugin(&createSidePanelFixture), &host.root, "fixture.panel", infoParent: infoParent)
    host.root.applyLayout()

    Swag.require(session.view != null and
                 session.sidePanelHost != null and
                 session.sidePanel != null and
                 session.sidePanelButton != null)
    Swag.require(session.sidePanelHost.parent == &host.root and session.sidePanel.parent == session.sidePanelHost)
    Swag.require(session.sidePanelButton.parent == infoParent)
    let gutter = host.root.themeMetrics().floating_Inset
    Swag.require(session.sidePanelHost.backgroundStyle == .Transparent and session.sidePanel.backgroundStyle == .Transparent)
    Swag.require(session.sidePanelHost.padding.x == 0 and session.sidePanelHost.padding.z == gutter)
    Swag.require(session.sidePanelHost.padding.y == 0 and session.sidePanelHost.padding.w == gutter)
    Swag.require(session.sidePanelHost.position.width == 220 + gutter)
    Swag.require(not session.sidePanelHost.isLocallyVisible() and not session.sidePanelButton.isLocallyVisible())

    session.sidePanelButton.show()
    let closedWidth = session.view.position.width
    session.sidePanelButton.setChecked(true)
    session.sidePanelButton.sigCheckedChanged.call(session.sidePanelButton)
    host.root.applyLayout()
    Swag.require(session.sidePanelHost.isLocallyVisible())
    Swag.require(session.view.position.width == closedWidth - session.sidePanelHost.position.width)

    session.sidePanelButton.setChecked(false)
    session.sidePanelButton.sigCheckedChanged.call(session.sidePanelButton)
    host.root.applyLayout()
    Swag.require(not session.sidePanelHost.isLocallyVisible() and session.view.position.width == closedWidth)
}

#test
{
    const Source = "Cat catalog cat catapult\ncat"
    var matches: Array'Viewer.SearchMatch
    Viewer.collectTextMatches(Source, "cat", {}, 0, 0, 0, &matches)
    Swag.require(matches.count == 5)

    matches.clear()
    Viewer.collectTextMatches(Source, "cat", {wholeWord: true}, 0, 0, 0, &matches)
    Swag.require(matches.count == 3 and
                 matches[0].offset == 0 and
                 matches[1].offset == 12 and
                 matches[2].offset == 25)

    matches.clear()
    Viewer.collectTextMatches(Source, "cat", {matchCase: true, wholeWord: true}, 0, 0, 0, &matches)
    Swag.require(matches.count == 2 and matches[0].offset == 12 and matches[1].offset == 25)

    matches.clear()
    Viewer.collectTextMatches(Source, #raw "c.t(a)?", {regularExpression: true}, 0, 0, 0, &matches)
    Swag.require(matches.count == 5 and matches[0].length == 3 and matches[1].length == 4)
    Swag.require(Viewer.patternIsValid(#raw "c.t(a)?", {regularExpression: true}))
    Swag.require(not Viewer.patternIsValid("(", {regularExpression: true}))
}

#test
{
    let executable         = Env.executablePath()
    let direct: [1] string = [executable]
    Swag.require(viewerStartupFile(direct).isEmpty())

    let withFile: [2] string = [executable, executable]
    Swag.require(viewerStartupFile(withFile) == executable)
}

#test
{
    let fileName = Gui.Testing.tempFilePath("scope-text-stream-", ".txt")
    defer discard catch File.delete(fileName)

    let fixture = Path.combine(testSourceRoot(#curlocation), "datas/comprehensive.txt")
    var source  = expect File.readAllText(fixture)
    for 2_000 do
        source += "A source line that stays readable while the rest remains on disk.\n"
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

    let loaded = view.editor.text()
    Swag.require(loaded.count <= 16 * 1024)
    Swag.require(view.bytesRead < view.fileSize)

    var image = host.render(view)
    view.updateEstimatedHeight()
    let loadedHeight = view.editor.loadedDocumentHeight()
    Swag.require(image.isValid() and loadedHeight > 0)
    Swag.require(view.editor.scrollableClientRect().height > loadedHeight)

    view.editor.setScrollPosition(Math.Point{0, loadedHeight * 2})
    let position = view.editor.scrollPosition()
    Swag.require(position.y > loadedHeight)
    view.loadNextChunk()
    Swag.require(view.editor.scrollPosition() == position)

    view.editor.setScrollPosition({0, 0})
    let beforeEnd = view.editor.scrollPosition()
    var end       = KeyEvent{kind: .Pressed, key: .End, modifiers: .Control}
    let handled   = view.hookOnChildEvent!(view.editor, &end)
    Swag.require(handled)
    completeTextReads(&host, view)
    discard host.render(view)
    Swag.require(view.editor.scrollPosition().y > beforeEnd.y)
}

// Line and word totals are computed independently of the resident streaming window and become
// available in the information summary without forcing the whole document into the editor.
#test
{
    let fileName = writeTempFile("statistics.txt", "one two\nthree\n")
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 420)
    let commands      = Wnd.create'Wnd(&host.root, {0, 0, 240, 36})
    var viewerSession = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName, commandParent: commands)
    let view          = assume cast(*PlainText.Panel, viewerSession.view)
    completeTextStatistics(&host, view)

    Swag.require(view.statistics.lines == 2 and view.statistics.words == 3)
    let details = view.detailsText()
    Swag.require(Utf8.contains(details.toSlice(), "2 lines") and Utf8.contains(details.toSlice(), "3 words"))
}

internal func writeTempFile(suffix: string, bytes: const [..] u8)->String
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory, Format.toString("scope_%_%", Guid64.random(), suffix))
    discard expect File.writeAllBytes(fileName, bytes)
    return fileName
}

func assertFolderFiles(window: *ViewerWindow, names: const [..] String)
{
    Swag.require(window.folderFiles.count == names.count and
                 window.siblings.count == names.count and
                 window.folderList.lineCount() == names.count)
    for name, index in names
    {
        Swag.require(window.folderFiles[index] == name[] and window.siblings[index] == name[])
        Swag.require(window.folderList.lineAt(cast(u32, index))!.itemAt(0).name.raw == (Path.fileName(name[]) orelse name[]))
    }
}

// Selecting another file cancels the previous file's scan immediately, before asynchronous
// classification has had a chance to replace the viewer.
#test
{
    let first  = writeTempFile("search-first.txt", "needle in the first file\n")
    let second = writeTempFile("search-second.txt", "second file\n")
    defer discard catch File.delete(first)
    defer discard catch File.delete(second)

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(first, remember: false)
    completeQueuedViewerFile(&host, window)
    window.searchBox.setText("needle")
    Swag.require(window.searchTimer != null)

    window.openFile(second, remember: false)
    Swag.require(window.searchTimer == null)
    Swag.require(not (window.searchBox.text()).count and window.searchMatches.isEmpty())
}

// A file that is not UTF-8 is read as text rather than sent to the hexadecimal view: the mark
// names the encoding, the mark itself never reaches the document, and the reader sees characters.
#test
{
    var utf16: Array'u8
    utf16.add(0xFF)
    utf16.add(0xFE)
    for c in "Hello, wide world"
    {
        utf16.add(cast(u8, c))
        utf16.add(0)
    }

    let wideFile = writeTempFile("utf16.txt", utf16.toSlice())
    defer discard catch File.delete(wideFile)

    Swag.require(PlainText.Panel.supports(wideFile))
    let probed = PlainText.Panel.probe(wideFile)
    Swag.require(probed.encoding == .Utf16Le and probed.contentStart == 2 and probed.accepted)

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    let commands      = Wnd.create'Wnd(&host.root, {0, 0, 240, 36})
    var viewerSession = openTestViewer(PlainText.viewerPlugin(), &host.root, wideFile, commandParent: commands)

    with let view = assume cast(*PlainText.Panel, viewerSession.view)
    {
        .resize(800, 520)
        .applyLayout()
    }

    Swag.require(view.encoding == .Utf16Le)
    Swag.require(view.encodingName() == "UTF-16 LE")
    Swag.require(view.editor.text() == "Hello, wide world")

    var options: OptionSheet.Page
    view.describeOptions(&options)
    Swag.require(options.rows[2].value == "UTF-16 LE")
}

// A single-byte page has no mark to announce it, and every byte decodes, so the accented byte is
// what the reader is shown rather than a fallback to bytes.
#test
{
    let latin: [11] u8 = ['c', 'a', 'f', 0xE9, ' ', 'n', 'a', 0xEF, 'v', 'e', '\n']
    let file = writeTempFile("cp1252.txt", latin)
    defer discard catch File.delete(file)

    Swag.require(PlainText.Panel.probe(file).encoding == .Windows1252)

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    let commands      = Wnd.create'Wnd(&host.root, {0, 0, 240, 36})
    var viewerSession = openTestViewer(PlainText.viewerPlugin(), &host.root, file, commandParent: commands)

    with let view = assume cast(*PlainText.Panel, viewerSession.view)
    {
        .resize(800, 520)
        .applyLayout()
    }

    Swag.require(view.editor.text() == "café naïve\n")

    // A reader who disagrees with the detection corrects it, and the same bytes read differently.
    view.applyEncoding(.Utf16Le)
    completeTextReads(&host, view)
    Swag.require(view.encoding == .Utf16Le)
    Swag.require(view.editor.text() != "café naïve\n")
}

// An unmarked legacy file can keep an ASCII-only head and reveal its first code-page byte after
// streaming has begun. That late byte changes the tentative encoding; it does not reject the file.
#test
{
    var bytes: Array'u8
    for 16 * 1024 do
        bytes.add('a')
    bytes.add(0xE9)
    bytes.add('\n')

    let file = writeTempFile("late-cp1252.txt", bytes.toSlice())
    defer discard catch File.delete(file)

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    let commands      = Wnd.create'Wnd(&host.root, {0, 0, 240, 36})
    var viewerSession = openTestViewer(PlainText.viewerPlugin(), &host.root, file, commandParent: commands)

    with let view = assume cast(*PlainText.Panel, viewerSession.view)
    {
        .resize(800, 520)
        .applyLayout()
    }

    Swag.require(view.encoding == .Utf8 and view.isStreaming())
    completeTextReads(&host, view)
    Swag.require(view.encoding == .Windows1252)
    Swag.require(Utf8.endsWith(view.editor.text(), "é\n"))
    Swag.require(not Utf8.contains(view.editor.text(), PlainText.texts().ui_NotText))
}

// Deciding an encoding is not accepting the file: code page 1252 gives every byte a meaning, so
// what keeps a binary out of the text view is the content it decodes to.
#test
{
    var binary: Array'u8
    for i in 512'u32 do
        binary.add(cast(u8, ((i * 7) & 0xFF)))
    let file = writeTempFile("binary.bin", binary.toSlice())
    defer discard catch File.delete(file)
    Swag.require(not PlainText.Panel.supports(file))
}

// The panel lists what is beside the current file and what was read before it, and a row opens
// its file without the window being rebuilt.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory, Format.toString("scope_panel_%", Guid64.random()))
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)

    var names: Array'String
    for i in 3'u32
    {
        let one = Path.combine(folder, Format.toString("file%.txt", i))
        discard expect File.writeAllText(one, "a readable line\n")
        names.add(one)
    }

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    var index = createViewerPluginRegistry()

    with let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    {
        .resize(960, 680)
        .openFile(names[0])
    }

    completeQueuedViewerFile(&host, window)

    Swag.require(not window.panelVisible and not window.filePanelHost.isLocallyVisible())
    window.toggleFilePanel()
    Swag.require(window.panelVisible and window.filePanelHost.isLocallyVisible())
    Swag.require(window.sendComputeCommandStateEvent(ViewerCommands.Files).checked)
    Swag.require(window.mainSplitter.items[0]!.minimumSize == ViewerWindow.PanelMinWidth + window.themeMetrics().floating_Inset)
    Swag.require(window.mainSplitter.items[0]!.maximumSize == ViewerWindow.PanelMaxWidth + window.themeMetrics().floating_Inset)
    window.mainSplitter.setPaneSize(0, 1)
    Swag.require(window.mainSplitter.items[0]!.size == window.mainSplitter.items[0]!.minimumSize)
    window.mainSplitter.setPaneSize(0, 2_000)
    Swag.require(window.mainSplitter.items[0]!.size == window.mainSplitter.items[0]!.maximumSize)
    window.mainSplitter.setPaneSize(0, 340)
    Swag.require(window.filePanelHost.position.width == 340)
    Swag.require(window.filePanel.isVertical() and window.filePanel.items.count == 2)
    Swag.require(window.filePanel.items[0]!.minimumSize == ViewerWindow.PaneMinSize)
    Swag.require(window.recentList.listFlags.has(.Ellipsis) and window.folderList.listFlags.has(.Ellipsis))
    Swag.require(window.recentList.scrollWnd.flags.has(.DisableHorizontal) and window.folderList.scrollWnd.flags.has(.DisableHorizontal))
    Swag.require(window.folderHistoryButton.isEnabled() and not window.folderHistoryButton.isLocallyVisible())
    Swag.require(not window.kindButton.isLocallyVisible() and not window.folderLabel.text.isEmpty())
    Swag.require(window.folderHistory.count == 1 and window.folderHistory[0].folder == folder)
    assertFolderFiles(window, names.toSlice())
    Swag.require(window.recentList.lineCount() == 1)
    for i in window.folderList.lineCount()
    {
        let icon = window.folderList.lineAt(i)!.itemAt(0).icon
        Swag.require(icon.isValid() and icon.index == cast(s32, ViewerIcons.Text))
    }

    let recentIcon = window.recentList.lineAt(0)!.itemAt(0).icon
    Swag.require(recentIcon.isValid() and recentIcon.index == cast(s32, ViewerIcons.Text))

    // Choosing a sibling opens it, and the recent list grows by exactly that file.
    window.folderList.selectLine(2)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.currentFile == names[2])
    Swag.require(window.recent.count == 2 and window.recent[0] == names[2])
    assertFolderFiles(window, names.toSlice())

    // A recent row keeps the list under the pointer stable while it opens its file.
    window.recentList.selectLine(1)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.currentFile == names[0])
    Swag.require(window.recent.count == 2 and window.recent[0] == names[2] and window.recent[1] == names[0])
    assertFolderFiles(window, names.toSlice())

    window.setFilePanelVisible(false)
    Swag.require(not window.sendComputeCommandStateEvent(ViewerCommands.Files).checked)
    window.setFilePanelVisible(true)

    window.filePanel.setPaneSize(0, 120)
    let panelWidth = window.mainSplitter.items[0]!.size
    let state      = saveViewerState(window)
    window.recent.clear()
    window.filePanel.setPaneSize(0, 180)
    window.setFilePanelVisible(false)
    loadViewerState(window, state.toSlice())
    Swag.require(window.recent.count == 2 and window.panelVisible)
    Swag.require(window.leftPanelWidth == panelWidth - window.themeMetrics().floating_Inset)
    Swag.require(window.mainSplitter.items[0]!.size == panelWidth)
    window.setFilePanelVisible(window.panelVisible)
    Swag.require(window.folderHistory.count == 1 and window.folderHistory[0].folder == folder)
    Swag.require(window.recentPaneSize == 120 and window.filePanel.items[0]!.size == 120)
}

// The folder header keeps a bounded history and returns directly to the last file viewed in the
// chosen folder.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let root = Path.combine(tempDirectory, Format.toString("scope_folder_history_%", Guid64.random()))
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)

    var files: Array'String
    for i in ViewerWindow.FolderHistoryCount + 2
    {
        let folder = Path.combine(root, Format.toString("folder%", i))
        expect Directory.create(folder)
        let fileName = Path.combine(folder, "document.txt")
        discard expect File.writeAllText(fileName, "a readable line\n")
        files.add(fileName)
    }

    var selectedFolder: String
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    for one in files
    {
        window.openFile(one[])
        completeQueuedViewerFile(&host, window)
    }

    Swag.require(window.folderHistory.count == ViewerWindow.FolderHistoryCount)
    Swag.require(window.folderHistory[0].file == files.back())
    selectedFolder = window.folderHistory.back().folder.toString()
    let selectedFile = String.from(window.folderHistory.back().file)
    host.clickPopupMenuItemWhenShown(selectedFolder)
    window.showFolderHistory()
    host.pump()
    completeQueuedViewerFile(&host, window)
    Swag.require(host.autoHandled and window.currentFile == selectedFile)
    Swag.require(window.folderHistory[0].folder == selectedFolder)
}

// Rebuilding the lists after a recent-file choice keeps the viewport under the pointer, and the
// folder pane continues to own file names rather than borrowing document text.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory, Format.toString("scope_recent_scroll_%", Guid64.random()))
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)

    var names: Array'String
    for i in ViewerWindow.RecentCount
    {
        let fileName = Path.combine(folder, Format.toString("file%.txt", i))
        let content  = Format.toString("document text %\n", i)
        discard expect File.writeAllBytes(fileName, content)
        names.add(fileName)
    }

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    var index = createViewerPluginRegistry()

    with let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    {
        .resize(960, 680)
        .openFile(names[0])
    }

    completeQueuedViewerFile(&host, window)
    window.recent.clear()
    for name in names do
        window.recent.add(name[])
    window.setFilePanelVisible(true)
    window.applyLayout()

    window.recentList.scrollWnd.setScrollPos(0, 80)
    let before = window.recentList.scrollWnd.scrollPosition()
    Swag.require(before.y > 0)
    window.recentList.selectLine(8)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.currentFile == names[8])
    Swag.require(window.recentList.scrollWnd.scrollPosition() == before)

    for i in window.folderList.lineCount()
    {
        let label = window.folderList.lineAt(i)!.itemAt(0).name.raw
        Swag.require(Utf8.startsWith(label, "file") and Utf8.endsWith(label, ".txt"))
        Swag.require(not Utf8.contains(label, "document text"))
    }
}

// The panel opens before any file has been read: there is no folder to name, so the section keeps
// its own title and both lists stay empty.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)

    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    Swag.require(window.currentFile.isEmpty())
    window.setFilePanelVisible(true)
    Swag.require(window.panelVisible and window.filePanelHost.isLocallyVisible())
    Swag.require(window.folderList.lineCount() == 0 and window.recentList.lineCount() == 0)
    Swag.require(not window.filePanel.isPaneVisible(0) and not window.recentPane.isLocallyVisible())
    Swag.require(window.folderLabel.text == appStrings().ui_Folder)
}

// The history is a list the reader owns: one file leaves it, or all of them do, and the section
// closes itself once it has nothing left to offer.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory, Format.toString("scope_history_%", Guid64.random()))
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)

    var names: Array'String
    for i in 3'u32
    {
        let one = Path.combine(folder, Format.toString("file%.txt", i))
        discard expect File.writeAllText(one, "a readable line\n")
        names.add(one)
    }

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    for one in names
    {
        window.openFile(one[])
        completeQueuedViewerFile(&host, window)
    }

    window.setFilePanelVisible(true)
    Swag.require(window.recent.count == 3 and window.recentList.lineCount() == 3)

    // The most recent file is at the head, and forgetting one leaves the others in their order.
    window.forgetRecent(names[2])
    Swag.require(window.recent.count == 2 and window.recentList.lineCount() == 2)
    Swag.require(window.recent[0] == names[1] and window.recent[1] == names[0])

    // Forgetting what the history does not hold changes nothing, and the file stays open.
    window.forgetRecent(Path.combine(folder, "absent.txt"))
    Swag.require(window.recent.count == 2 and window.currentFile == names[2])

    Swag.require(window.recentClearButton.parent == window.recentLabel.parent and not window.recentClearButton.isLocallyVisible())
    Swag.require(not Utf8.contains(appStrings().ui_ConfirmClearHistory, "?"))

    host.clickModalButtonWhenShown(Dialog.BtnNo)
    window.confirmClearRecent()
    host.pump()
    Swag.require(host.autoHandled and window.recent.count == 2)

    host.clickModalButtonWhenShown(Dialog.BtnYes)
    window.confirmClearRecent()
    host.pump()
    Swag.require(host.autoHandled)
    Swag.require(window.recent.isEmpty() and window.recentList.lineCount() == 0)
    Swag.require(not window.filePanel.isPaneVisible(0) and not window.recentPane.isLocallyVisible())
    Swag.require(window.currentFile == names[2] and window.folderList.lineCount() == 3)
}

// The history row menu offers what that file can do, and its own entry removes one file.
//
// The folder list is not a list the reader owns, so the same menu there stops at the actions that
// do not touch the history.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory, Format.toString("scope_menu_%", Guid64.random()))
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)

    var names: Array'String
    for i in 3'u32
    {
        let one = Path.combine(folder, Format.toString("file%.txt", i))
        discard expect File.writeAllText(one, "a readable line\n")
        names.add(one)
    }

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    for one in names
    {
        window.openFile(one[])
        completeQueuedViewerFile(&host, window)
    }

    window.setFilePanelVisible(true)
    window.applyLayout()

    let list = window.recentList
    Swag.require(list.lineCount() == 3)

    // The row naming the file read before the one that is open, which the panel opens on its own
    // when it is picked: what the menu acts on is the row, not the document.
    list.selectLine(1)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.currentFile == names[1])

    var clipboardImage = Image.create(2, 2, .BGRA8)
    clipboardImage.clear()
    Clipboard.addImage(clipboardImage)
    host.clickPopupMenuItemWhenShown("scope.file.copyPath")
    window.showFileMenu(list, window.recent.toSlice(), {120, 120})
    host.pump()
    Swag.require(host.autoHandled and Clipboard.getString() == names[1])
    Swag.require(not Clipboard.hasImage())

    Clipboard.addImage(clipboardImage)
    host.clickPopupMenuItemWhenShown("scope.file.copyName")
    window.showFileMenu(list, window.recent.toSlice(), {120, 120})
    host.pump()
    Swag.require(host.autoHandled and Clipboard.getString() == "file1.txt")
    Swag.require(not Clipboard.hasImage())

    host.clickPopupMenuItemWhenShown("scope.file.forget")
    window.showFileMenu(list, window.recent.toSlice(), {120, 120})
    host.pump()
    Swag.require(host.autoHandled)
    Swag.require(window.recent.count == 2 and window.recent[0] == names[2] and window.recent[1] == names[0])
    Swag.require(list.lineCount() == 2 and window.currentFile == names[1])

    // A folder row names a file the folder holds, and nothing offers to take it out of a list it
    // was never in.
    window.folderList.selectLine(0)
    completeQueuedViewerFile(&host, window)
    let folderMenu = window.createFileActionsMenu(false)
    defer folderMenu.destroy()
    for item in folderMenu.items do
        Swag.require(item!.id != "scope.file.forget")
    host.pump()
}

// The viewer a reader picks for one file becomes the viewer that kind of file opens in, and
// choosing the ordinary one back is the removal of that decision rather than one more.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory, Format.toString("scope_preferred_%", Guid64.random()))
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)

    let first  = Path.combine(folder, "notes.txt")
    let second = Path.combine(folder, "other.txt")
    for one in [first, second] do
        discard expect File.writeAllText(one[], "a readable line\n")

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    window.openFile(first)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.choices.count == 3 and window.choices[0].key == PlainText.ViewerKey)
    Swag.require(window.activeChoiceIndex == 0 and window.preferences.isEmpty())

    // Every viewer the file can open in is a segment of one row of the lens, the one in use
    // checked; the keys land on it.
    window.lens.open(appStrings().lens_ViewAs)
    let viewAs = unwrap window.lens.results.sections[0]
    Swag.require(viewAs.label == appStrings().lens_ViewAs and
                 viewAs.inline and
                 viewAs.entries.count == window.choices.count)
    Swag.require(window.lens.chosenEntry()!.title == viewAs.entries[0].title)
    Swag.require(viewAs.entries[0].checked and not viewAs.entries[1].checked)
    window.lens.close()

    window.selectViewer(2)
    Swag.require(window.choices[window.activeChoiceIndex].key == "hex")
    Swag.require(window.preferences.count == 1 and
                 window.preferences[0].kind == PlainText.ViewerKey and
                 window.preferences[0].viewer == "hex")

    // The next file of the same kind opens where the reader left the previous one.
    window.openFile(second)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.choices[window.activeChoiceIndex].key == "hex")

    // The decision crosses a session with the other panel choices.
    let state = saveViewerState(window)
    window.preferences.clear()
    loadViewerState(window, state.toSlice())
    Swag.require(window.preferences.count == 1 and window.preferences[0].viewer == "hex")

    window.selectViewer(0)
    Swag.require(window.preferences.isEmpty())
    window.openFile(first)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.choices[window.activeChoiceIndex].key == PlainText.ViewerKey)
}

// Keeps the virtual document extent monotonic while several large-file chunks arrive between
// paints, and exercises complete keyboard navigation through the real focused editor.

// Rapid scrollbar scrubbing coalesces to the latest byte window and remains stable when the
// direction changes repeatedly. Each completed seek keeps the requested viewport instead of
// snapping back to the resident window it replaced.

// Every appearance crosses the same state boundary as the surface placement.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)

    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    Swag.require(window.appearanceButton.appearanceTheme == .Dark)

    window.applyTheme(cast(u32, AppearanceTheme.Dark))
    host.notify(.ThemeChanged)
    Swag.require(window.themeIndex == cast(u32, AppearanceTheme.Dark))
    Swag.require(host.app.theme.colors.view_Bk == ThemeColors.encrePalette().ground)

    window.applyTheme(cast(u32, AppearanceTheme.Light))
    host.notify(.ThemeChanged)
    Swag.require(window.themeIndex == cast(u32, AppearanceTheme.Light))
    Swag.require(host.app.theme.colors.view_Bk == ThemeColors.papierPalette().ground)
    Swag.require(window.themeColors().view_Bk == ThemeColors.papierPalette().ground)

    let state = saveViewerState(window)
    window.applyTheme(0)
    loadViewerState(window, state.toSlice())
    window.applyTheme(window.themeIndex)
    host.notify(.ThemeChanged)
    Swag.require(window.themeIndex == cast(u32, AppearanceTheme.Light) and host.app.theme.colors.view_Bk == ThemeColors.papierPalette().ground)
    Swag.require(window.themeColors().view_Bk == ThemeColors.papierPalette().ground)
}

// The caption appearance action reaches the standard application about dialog.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)

    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    Swag.require(not window.appearanceButton.sigAboutRequested.isEmpty())
    let capabilities = window.aboutViewerList()
    Swag.require(Utf8.contains(capabilities.toSlice(), "<b>Archive</b>"))
    Swag.require(not Utf8.contains(capabilities.toSlice(), "\n") and not Utf8.contains(capabilities.toSlice(), ".zip"))
    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    window.showAbout()
    host.pump()

    Swag.require(host.autoHandled)
    Swag.require(host.openedSurfaceCount() == 0)
}

// Choosing a language in the lens switches the complete application tree to French, the commands
// of the lens and the hint teaching it included.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    registerAppStrings(&host.app.resources)
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    Swag.require(window.sendComputeCommandStateEvent(ViewerCommands.Open).name == "Open…")
    Swag.require(window.sendComputeCommandStateEvent(ViewerCommands.Close).name == "Close File")

    window.lens.open("Français")
    Swag.require(window.lens.chosenEntry()!.title == "Français")
    window.lens.runChosen()
    host.pump()

    Swag.require(host.app.language() == "fr")
    Swag.require(window.language == "fr")

    // Headless surfaces stay outside Application.surfaces, so deliver the broadcast they would
    // receive from setLanguage in a native window.
    host.notify(.LanguageChanged)
    Swag.require(window.surface!.wnd.name.raw == ProductName)
    Swag.require(window.sendComputeCommandStateEvent(ViewerCommands.Open).name == "Ouvrir…")
    Swag.require(window.sendComputeCommandStateEvent(ViewerCommands.Close).name == "Fermer le fichier")
    Swag.require(window.hintLine.hints[0].text == "tout le reste")
    Swag.require(window.dropHighlight.prompt.text() == "Déposez un fichier pour l'afficher")
    Swag.require(host.openedSurfaceCount() == 0)
}

// Finds a match split across scanner chunks in a multi-megabyte file and materializes it in the
// resident text window without losing the virtual scroll range.

// A viewer that reads its document in the background is polled from the search timer: the
// query is answered a page at a time, the count settles once the last page is in, and the match
// is shown on its page.
#test
{
    let fileName = Testing.tempFilePath("scope-search-pdf-", ".pdf")
    defer discard catch File.delete(fileName)
    var document = Pdf.Document.create()
    var first    = Pdf.Page.create(320, 220)
    first.addText("PDF viewer", 32, 28, 24, Color.fromArgb(Argb.Black))
    document.addPage(#move first)
    var second = Pdf.Page.create(320, 220)
    second.addText("Second page", 32, 28, 24, Color.fromArgb(Argb.Black))
    document.addPage(#move second)
    expect document.save(fileName)

    var host: Testing.HeadlessHost
    host.setup(880, 560)
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(fileName)
    completeQueuedViewerFile(&host, window)
    let view = assume cast(*PdfDocument.Panel, window.currentView)
    Swag.require(not view.load.isPending() and view.pdfView.pageCount() == 2)

    window.searchBox.setFocus()
    window.searchBox.setText("second")
    completeViewerSearch(&host, window)
    Swag.require(window.searchComplete and window.searchMatches.count == 1 and window.searchIndex == 0)
    Swag.require(window.searchCountLabel.text() == "1/1")
    Swag.require(window.searchNext.isEnabled() and window.searchPrevious.isEnabled())
    Swag.require(view.pdfView.pageIndex == 1 and view.pdfView.selectedText() == "Second")
    Swag.require(window.searchBox.hasFocus())

    window.searchBox.setText("absent")
    completeViewerSearch(&host, window)
    Swag.require(window.searchComplete and window.searchMatches.isEmpty())
    Swag.require(window.searchCountLabel.text() == "0/0")
}

// The shared result set drives counts, wraparound navigation, case matching and whole-word
// boundaries without changing what the viewer marks.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-search-", ".txt")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "Cat catalog cat catapult\ncat")

    var host: Testing.HeadlessHost
    host.setup(880, 560)
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(fileName)
    completeQueuedViewerFile(&host, window)
    window.searchBox.setFocus()
    window.searchBox.setText("cat")
    completeViewerSearch(&host, window)

    Swag.require(window.searchMatches.count == 5 and window.searchIndex == 0 and window.searchMatch == 0)
    Swag.require(window.searchCountLabel.text() == "1/5")
    Swag.require(window.searchBox.hasFocus())
    discard host.render(window)
    host.fireTimers()
    Swag.require(window.searchOverlay.isLocallyVisible())
    let basic = assume cast(*PlainText.Panel, window.currentView)
    Swag.require(basic.editor.selectedText() == "Cat")
    var matchBounds: Math.Rectangle
    Swag.require(basic.searchBounds(&matchBounds))
    Swag.require(window.searchOverlay.position.width == Math.round(matchBounds.width + ViewerSearchOverlay.InsetX * 2))
    Swag.require(window.searchOverlay.position.height >= ViewerSearchOverlay.MarkMinHeight and
                 window.searchOverlay.position.height < Math.round(matchBounds.height))
    let firstMark = host.render(window)
    for 8 do
        host.fireTimer(window.searchBoundsTimer)
    window.searchOverlay.invalidate()
    let repeatedMark = host.render(window)
    Swag.require(Hash.hashBytes32(firstMark.pixels.toSlice()) == Hash.hashBytes32(repeatedMark.pixels.toSlice()))

    window.findPrevious()
    Swag.require(window.searchIndex == 4 and window.searchMatch == 25 and window.searchCountLabel.text() == "5/5")
    window.findNext()
    Swag.require(window.searchIndex == 0 and window.searchMatch == 0)

    window.searchWholeWordOption = true
    window.restartSearch()
    completeViewerSearch(&host, window)
    Swag.require(window.searchMatches.count == 3 and window.searchCountLabel.text() == "1/3")

    window.searchMatchCaseOption = true
    window.restartSearch()
    completeViewerSearch(&host, window)
    Swag.require(window.searchMatches.count == 2 and
                 window.searchMatch == 12 and
                 window.searchCountLabel.text() == "1/2")

    window.searchRegexOption     = true
    window.searchMatchCaseOption = false
    discard window.searchBox.revalidate()
    window.searchBox.setText(#raw "c.t(a)?")
    completeViewerSearch(&host, window)
    Swag.require(window.searchBox.isValid() and window.searchMatches.count == 3)

    window.searchBox.setText("(")
    Swag.require(not window.searchBox.isValid() and window.searchTimer == null)
    Swag.require(window.searchCountLabel.text() == "0/0" and window.searchCountLabel.toolTip == appStrings().ui_SearchInvalidRegularExpression)

    window.searchRegexOption = false
    discard window.searchBox.revalidate()

    window.searchBox.setText("absent")
    completeViewerSearch(&host, window)
    Swag.require(window.searchMatches.isEmpty() and window.searchCountLabel.text() == "0/0")
    Swag.require(window.searchBox.hasFocus() and not window.searchOverlay.isLocallyVisible())

    window.searchBox.setText("cat")
    completeViewerSearch(&host, window)
    Swag.require(not window.searchBox.children.isEmpty())
    window.searchBox.setText(null)
    Swag.require(not (window.searchBox.text()).count)
    Swag.require(not (window.searchCountLabel.text()).count and not window.searchOverlay.isLocallyVisible())
    Swag.require(assume cast(*PlainText.Panel, window.currentView).editor.isSelectionEmpty())
}

// Search navigation over a streamed Markdown file materializes every distant occurrence in both
// directions, and clearing the query removes the viewer-owned mark as well as the shared halo.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-search-markdown-", ".md")
    defer discard catch File.delete(fileName)

    const Query = "streamed-search-anchor"
    var source = String.from("# Search fixture\n\n")
    var offsets: Array'u64
    for occurrence in 3
    {
        offsets.add(source.length)
        source += Query
        source += Format.toString(" occurrence %\n\n", occurrence + 1)
        for 600 do
            source += "A long Markdown paragraph separates this result from the next page.\n\n"
    }

    expect File.writeAllBytes(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(fileName)
    completeQueuedViewerFile(&host, window)

    var markdownIndex = Swag.U32.Max
    for choice, choiceIndex in window.choices where choice.key == "markdown" do
        markdownIndex = cast(u32, choiceIndex)
    Swag.require(markdownIndex != Swag.U32.Max)
    window.selectViewer(markdownIndex)
    window.searchBox.setFocus()
    window.searchBox.setText(Query)
    completeViewerSearch(&host, window)
    Swag.require(window.searchMatches.count == 3 and window.searchMatch == offsets[0])

    for 2_048 where not window.searchOverlay.isLocallyVisible() do
        host.fireTimers()
    Swag.require(window.searchOverlay.isLocallyVisible())

    window.findNext()
    Swag.require(window.searchIndex == 1 and window.searchMatch == offsets[1])
    window.searchOverlay.hide()
    for 2_048 where not window.searchOverlay.isLocallyVisible() do
        host.fireTimers()
    Swag.require(window.searchOverlay.isLocallyVisible())

    window.findNext()
    Swag.require(window.searchIndex == 2 and window.searchMatch == offsets[2])
    window.searchOverlay.hide()
    for 2_048 where not window.searchOverlay.isLocallyVisible() do
        host.fireTimers()
    Swag.require(window.searchOverlay.isLocallyVisible())

    window.findPrevious()
    Swag.require(window.searchIndex == 1 and window.searchMatch == offsets[1])
    window.searchOverlay.hide()
    for 2_048 where not window.searchOverlay.isLocallyVisible() do
        host.fireTimers()
    Swag.require(window.searchOverlay.isLocallyVisible())

    let markdown = assume cast(*Markdown.View, window.currentView)
    var bounds: Math.Rectangle
    Swag.require(markdown.searchMatchRect(&bounds))

    let beforeSearchPage = bounds.y
    host.keyPress(.PageDown)
    for 2_048 where bounds.y >= beforeSearchPage
    {
        host.fireTimers()
        discard markdown.searchMatchRect(&bounds)
    }

    Swag.require(markdown.searchMatchRect(&bounds))
    let afterSearchPage = bounds.y
    Swag.require(afterSearchPage < beforeSearchPage)
    Swag.require(window.searchBox.hasFocus())

    markdown.setFocus()
    host.keyPress(.PageUp)
    Swag.require(markdown.searchMatchRect(&bounds))
    Swag.require(bounds.y > afterSearchPage)
    Swag.require(markdown.hasFocus())

    window.searchBox.setText(null)
    Swag.require(not markdown.searchMatchRect(&bounds))
    Swag.require(not window.searchOverlay.isLocallyVisible())
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    host.app.theme.setDark()
    host.app.notifyThemeChanged()

    var index = createViewerPluginRegistry()

    with let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    {
        .resize(960, 680)
        .applyLayout()
    }

    // Nothing but the work: no band, no menu, no toolbar. What floats over the document waits
    // until it is asked for.
    let gutter = window.themeMetrics().floating_Inset
    Swag.require(window.backgroundStyle == .Application and window.padding.y == 0)
    Swag.require(window.mainSplitter.dockStyle == .Center)
    Swag.require(window.appearanceButton.parent == &host.surfaceWnd and not window.appearanceButton.isLocallyVisible())
    Swag.require(window.searchBar.parent == window and not window.searchBar.isLocallyVisible())
    Swag.require(window.searchGroup.parent == window.searchBar)
    Swag.require(window.searchBox.parent == window.searchGroup and window.searchNavigation.parent == window.searchGroup)
    Swag.require(window.searchPrevious.icon.isValid() and window.searchNext.icon.isValid())
    Swag.require(not window.searchPrevious.isEnabled() and not window.searchNext.isEnabled())
    Swag.require(window.viewerBar.parent == window and not window.viewerBar.isLocallyVisible())
    Swag.require(window.infoSheet.dockStyle == .Float and not window.infoSheet.isLocallyVisible())
    Swag.require(window.hintLine.isLocallyVisible() and window.hintLine.hints.count == 1)
    Swag.require(window.hintLine.hints[0].key == Input.formatKeyShortcut(.Control, .Space) and window.hintLine.hints[0].text == appStrings().ui_HintLens)
    Swag.require(not window.lens.isOpen())
    Swag.require(window.readingLine.parent == window.documentHost and not window.readingLine.isLocallyVisible())
    Swag.require(window.filePanelHost.backgroundStyle == .Transparent and window.filePanel.backgroundStyle == .Transparent)
    Swag.require(window.filePanelHost.padding.x == gutter and window.filePanelHost.padding.w == gutter)
    Swag.require(window.documentHost.backgroundStyle == .Transparent and window.documentPanel.backgroundStyle == .View)
    Swag.require(window.documentHost.padding.y == window.stripInset())
    Swag.require(window.documentPanel.parent == window.documentHost and window.home.parent == window.documentPanel)
    Swag.require(window.recentPane.backgroundStyle == .Transparent and window.folderPane.backgroundStyle == .Transparent)
    Swag.require(window.recentLabel.parent!.backgroundStyle == .Transparent and
                 window.folderLabel.parent!.backgroundStyle == .Transparent)
    Swag.require(window.recentClearButton.parent == window.recentLabel.parent)

    // Nothing frames the work: the bands an application once drew are the ground it sits on.
    let colors = window.themeColors()
    Swag.require(colors.view_Bk == colors.ground and colors.wnd_Bk == colors.ground)
    Swag.require(colors.informationBar_Bk == colors.ground and
                 colors.commandBar_Bk == colors.ground and
                 colors.toolBar_Bk == colors.ground)
    Swag.require(window.surface!.minSize.x == ViewerWindow.MinWidth)
    Swag.require(window.home.message.isEmpty() and window.home.rows.isEmpty())

    // The window without a file is its home.
    Swag.require(window.home.isLocallyVisible())
    Swag.require(not window.lensLauncher.captionButton.isLocallyVisible())
    Swag.require(not window.informationCaptionButton.isLocallyVisible())
    Swag.require(window.currentView == null and window.currentCommands == null)
    Swag.require(window.currentActions == null and window.currentInfo == null)
    Swag.require(not window.loadingOverlay.isLocallyVisible())
    Testing.assertContentFits(window)

    // Every command of the window is an entry of the lens; what does not apply to an empty
    // window stays out, and the key of a command is written beside it.
    window.lens.open(">")
    Swag.require(lensHasEntry(window, appStrings().cmd_Open) and lensHasEntry(window, appStrings().cmd_Explore))
    Swag.require(lensHasEntry(window, appStrings().cmd_FullScreen) and lensHasEntry(window, appStrings().ui_Files))
    Swag.require(lensHasEntry(window, appStrings().ui_PlayOnce) and lensHasEntry(window, appStrings().cmd_ClearHistory))
    Swag.require(not lensHasEntry(window, appStrings().ui_CloseFile) and not lensHasEntry(window, appStrings().cmd_Reload))
    window.lens.close()
    Swag.require(window.sendComputeCommandStateEvent(ViewerCommands.Open).shortcut == Input.formatKeyShortcut(.Control, .O))
    Swag.require(window.sendComputeCommandStateEvent(ViewerCommands.Lens).shortcut == Input.formatKeyShortcut(.Control, .Space))

    // The door opens on its command and closes on Escape.
    window.sendCommandEvent(ViewerCommands.Lens)
    Swag.require(window.lens.isOpen())
    host.keyPress(.Escape)
    Swag.require(not window.lens.isOpen())

    // The viewer's commands float centred at the foot of the document, as wide as they ask and
    // never wider than the document, and leave once the pointer rests.
    window.resize(ViewerWindow.MinWidth, 680)
    let widestCommands = Wnd.create'Wnd(window.viewerBar, {0, 0, 2_000, 36})
    widestCommands.preferredSize.x = 2_000
    window.currentCommands         = widestCommands
    window.notePointer({20, 20})
    Swag.require(window.viewerBar.isLocallyVisible() and window.viewerBar.position.height == ViewerWindow.BarHeight)
    let area = window.documentArea()
    Swag.require(window.viewerBar.position.x >= area.x + gutter - 1 and window.viewerBar.position.right() <= area.right() - gutter + 1)
    Swag.require(widestCommands.position.y >= 0 and widestCommands.position.bottom() <= window.viewerBar.position.height)
    window.notePointer(window.viewerBar.surfaceRect().center())
    host.fireTimer(window.viewerBarTimer)
    Swag.require(window.viewerBar.isLocallyVisible())
    window.notePointer({20, 20})
    host.fireTimer(window.viewerBarTimer)
    Swag.require(not window.viewerBar.isLocallyVisible() and window.app().isCursorHidden())
    window.notePointer({21, 20})
    Swag.require(not window.app().isCursorHidden())
    window.currentCommands = null
    widestCommands.destroy()
    window.updateViewerBar()
}

// Search floats over the document only when the selected viewer exposes it and the reader asked
// for it. Switching to a viewer without that contract puts the bar away and never leaves keyboard
// focus in an invisible field.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)

    var index = createViewerPluginRegistry()

    with let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    {
        .resize(960, 680)
        .openFile(viewerFixturePath())
    }

    completeQueuedViewerFile(&host, window)
    window.applyLayout()

    // The find bar waits for its command, then floats at the horizontal centre of the document.
    Swag.require(not window.searchBar.isLocallyVisible() and window.searchBox.isEnabled())
    window.sendCommandEvent(ViewerCommands.Find)
    Swag.require(window.searchBar.isLocallyVisible() and window.searchBox.hasFocus())
    let area = window.documentArea()
    Swag.require(Math.abs(window.searchBar.position.horzCenter() - area.horzCenter()) <= 1)
    Swag.require(window.searchBar.position.x >= area.x and window.searchBar.position.right() <= area.right())
    Swag.require(window.searchBar.position.y >= area.y)
    let actionSize = themeActionButtonSize(window.themeMetrics())
    Swag.require(window.searchOptionsButton.isVisible() and window.searchOptionsButton.icon.sizeX == themeActionIconSize(window.themeMetrics()))
    Swag.require(window.searchOptionsButton.position.height == actionSize)
    Swag.require(window.searchPrevious.icon.sizeX == themeActionIconSize(window.themeMetrics()) and window.searchNext.icon.sizeX == themeActionIconSize(window.themeMetrics()))
    Swag.require(window.searchPrevious.position.height == actionSize and window.searchNext.position.height == actionSize)
    Swag.require(window.searchGroup.children.count == 3)
    Swag.require(window.searchGroup.children[0] == window.searchOptionsButton)
    Swag.require(window.searchGroup.children[1] == window.searchBox)
    Swag.require(window.searchGroup.children[2] == window.searchNavigation)
    Swag.require(window.searchNavigation.children.count == 3)
    Swag.require(window.searchNavigation.children[0] == window.searchPrevious)
    Swag.require(window.searchNavigation.children[1] == window.searchNext)
    Swag.require(window.searchNavigation.children[2] == window.searchCountLabel)
    Swag.require(window.searchCountLabel.textHorizontalAlignment == .Left)

    // A viewer without search puts the bar away and the keyboard back.
    let midiFile = Path.combine(Path.combine(testSourceRoot(#curlocation), "datas"), "viewer.mid")
    window.openFile(midiFile)
    completeQueuedViewerFile(&host, window)
    Swag.require(not window.searchBar.isLocallyVisible() and not window.searchBox.isEnabled())
    Swag.require(not window.searchBox.hasFocus())
    Swag.require(window.sendComputeCommandStateEvent(ViewerCommands.Find).hidden)

    // The bar the reader asked for comes back with a viewer that searches, until it is put away.
    window.openFile(viewerFixturePath())
    completeQueuedViewerFile(&host, window)
    Swag.require(window.searchBar.isLocallyVisible() and window.searchBox.isEnabled())
    window.hideSearch()
    Swag.require(not window.searchBar.isLocallyVisible() and not window.searchShown)
}

// File metadata can arrive after the first frame. Publishing it lays out the line of readings
// immediately, without waiting for a resize, theme change, or another outer layout pass.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)

    var index = createViewerPluginRegistry()

    with let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    {
        .resize(ViewerWindow.MinWidth, 680)
        .applyLayout()
    }

    Swag.require(not window.readingLine.isLocallyVisible())

    window.currentFile     = viewerFixturePath()
    window.currentFileSize = "1.2 KiB"
    window.choices.add(ViewerPluginChoice{pluginIndex: 0, key: "html"})
    window.activeChoiceIndex = 0
    window.updateFileInfo("UTF-8 · streamed")

    // The readings and the size share the faint line; the name is the title of the window.
    Swag.require(window.readingLine.isLocallyVisible())
    Swag.require(window.readingLine.details.text() == "UTF-8 · streamed · 1.2 KiB")
    Swag.require(window.readingLine.details.position.width >= Math.ceil(window.readingLine.details.itf.measureContent({}).x))
    Swag.require(window.surface!.wnd.name.raw == (Path.fileName(viewerFixturePath()) orelse ""))

    // A long line keeps its start and ends in an ellipsis at the narrowest window.
    let wideDetails = "3840 × 2160 · 120000 frames · 59.94 fps · 01:02:03 · AAC-LC · 48000 Hz · 6 channels · 24 bit · Swag CPU decoder · 3840 × 2160 · 120000 frames · 59.94 fps"
    window.resize(1600, 680)
    window.updateFileInfo(wideDetails)
    let wideWidth = Math.ceil(window.readingLine.details.itf.measureContent({}).x)
    Swag.require(window.readingLine.details.position.width >= wideWidth)

    window.resize(ViewerWindow.MinWidth, 680)
    window.updateFileInfo(wideDetails)
    Swag.require(window.readingLine.details.position.width < wideWidth)
    Swag.require(window.readingLine.details.position.right() <= window.readingLine.clientRect().right())
}

// Full screen preserves the exact window state around a content-only presentation. Moving the
// pointer brings the viewer's commands over the content without shrinking it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)

    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(scopeTestDataPath("segoeui.ttf"), remember: false)
    completeQueuedViewerFile(&host, window)
    window.setFilePanelVisible(true)
    let position = host.surface.position
    let flags    = host.surface.flags

    window.sendCommandEvent(ViewerCommands.FullScreen)
    Swag.require(window.fullScreen and window.sendComputeCommandStateEvent(ViewerCommands.FullScreen).checked)
    Swag.require(host.surface.flags.has(.NoShadow) and host.surface.flags.has(.TopMost))
    Swag.require(not host.surface.flags.has(.LargeCaption) and not host.surface.flags.has(.Border))
    Swag.require(not window.readingLine.isLocallyVisible() and not window.filePanelHost.isLocallyVisible())
    Swag.require(not window.viewerBar.isLocallyVisible())

    // Moving the pointer brings the viewer's commands over the content without shrinking it;
    // resting lets them go.
    let bounds = window.currentView!.surfaceRect()
    window.notePointer({10, 1})
    Swag.require(window.viewerBar.isLocallyVisible() and window.currentView.surfaceRect() == bounds)
    host.fireTimer(window.viewerBarTimer)
    Swag.require(not window.viewerBar.isLocallyVisible())

    window.setFullScreen(false)
    Swag.require(not window.fullScreen and not window.sendComputeCommandStateEvent(ViewerCommands.FullScreen).checked)
    Swag.require(host.surface.flags == flags and host.surface.position == position)
    Swag.require(window.readingLine.isLocallyVisible() and window.filePanelHost.isLocallyVisible())
}

// A decoder error discovered after creation replaces the active viewer and its commands in place.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 420)

    var index    = createViewerPluginRegistry()
    let window   = ViewerWindow.create(&host.surfaceWnd, #move index)
    let failed   = Wnd.create'Wnd(window)
    let commands = Wnd.create'Wnd(window.viewerBar)
    var retired: bool
    failed.userData = &retired
    window.choices.add(ViewerPluginChoice{pluginIndex: 0, key: "html"})
    window.instances.add(ViewerSession{view: failed, commands: commands, retire: func|failed|()->bool => markTestViewerRetired(failed)})
    window.currentView       = failed
    window.currentCommands   = commands
    window.activeChoiceIndex = 0
    window.currentFile       = "sample.bin"

    reportViewerFailure(failed, "payload ends before its declared length")

    Swag.require(retired and failed.isPendingDestroy and commands.isPendingDestroy)
    Swag.require(window.currentCommands == null)
    Swag.require(window.currentView != null and window.currentView != failed)
    Swag.require(window.instances[0].failureReason == "payload ends before its declared length")
    let errorView = assume cast(*ViewerErrorView, window.currentView)
    Swag.require(errorView.reasonLabel.text() == window.instances[0].failureReason.toString())
}

// Counts the buttons under `wnd` whose arrow points down.
func downwardArrows(wnd: *Wnd)->u64
{
    var result = 0'u64
    if wnd is IconButton as button
    {
        if button.arrowPosition == .RightDownward do
            result += 1
    }
    for child in wnd.children do
        result += downwardArrows(child[])
    return result
}

// The line of readings stands at the foot of the window, so every menu it opens opens upward and
// every arrow on it says so: no viewer mixes an arrow pointing down among them.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    for name in ["comprehensive.txt", "sample.cpp", "viewer.hex", "viewer.groove.mid", "viewer.pdf", "title.png", "viewer.page.html"]
    {
        window.openFile(scopeTestDataPath(name), remember: false)
        completeQueuedViewerFile(&host, window)
        Swag.require(window.readingLine.isLocallyVisible())
        Swag.require(downwardArrows(window.readingLine) == 0)
    }
}

// A picture whose decoder refuses it is not a dead end: the failure offers the other viewers of
// the file and its own application, and an offer opens the file in that viewer.
#test
{
    var bytes = expect File.readAllBytes(scopeTestDataPath("title.png"))
    bytes[29] ^= 0xFF     // Breaks the checksum of the IHDR chunk.
    let fileName = writeTempFile("broken.png", bytes.toSlice())
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.resize(800, 560)
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.choices[window.activeChoiceIndex].key == "image")
    let errorView = assume cast(*ViewerErrorView, window.currentView)
    Swag.require(errorView.actions.isLocallyVisible() and errorView.actions.children.count >= 2)
    Swag.require(assume cast(*PushButton, errorView.actions.children.back()).text() == appStrings().ui_MenuOpenDefault)

    var hex = Swag.U64.Max
    for child, i in errorView.actions.children
    {
        let button = assume cast(*PushButton, child[])
        for choice in window.choices where choice.key == "hex" and
                                           Format.toString(appStrings().ui_ViewAsChoice, window.index.plugins[choice.pluginIndex].displayName()) == button.text() do
            hex = i
    }

    Swag.require(hex != Swag.U64.Max)
    window.applyLayout()
    host.click(errorView.actions.children[hex].surfaceRect().center())
    completeQueuedViewerFile(&host, window)
    Swag.require(window.choices[window.activeChoiceIndex].key == "hex")
    Swag.require(not (window.currentView is ViewerErrorView))
}

// File selection never waits for a viewer that needs another event-loop turn to retire. The
// generic host keeps the previous content visible, then opens the queued file once a task below
// the window reports that the viewer's work ended.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 560)

    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    let old    = Wnd.create'Wnd(window)
    old.setPosition({19, 73, 617, 389})
    var retireCalls: u32
    old.userData = &retireCalls
    window.instances.add(ViewerSession{view: old, retire: func|old|()->bool => delayTestViewerRetirement(old)})
    window.currentView       = old
    window.activeChoiceIndex = 0

    let fileName = viewerFixturePath()
    window.openFile(fileName, remember: false)
    Swag.require(window.currentView == old and retireCalls == 0)
    Swag.require(window.pendingFile == fileName and window.startupTimer != null)
    Swag.require(not window.loadingOverlay.isLocallyVisible() and window.loadingWantedSince != 0)
    expireViewerLoadingDelay(window)
    Swag.require(window.loadingOverlay.isLocallyVisible() and window.loadingOverlay.position == old.position)

    host.fireTimer(window.startupTimer)
    window.choiceLoad.task.wait()
    host.pump()
    Swag.require(window.currentView == old and retireCalls == 1)
    Swag.require(window.pendingFile == fileName and window.awaitingRetirement and window.startupTimer == null)

    // The viewer's work ends the way every viewer's does, with a task event to one of its windows.
    var ended: Swag.Task
    ended.submit(func() {}, old.taskNotifier(&ended))
    ended.wait()
    host.pump()
    Swag.require(retireCalls == 1 and window.startupTimer != null)

    host.fireTimer(window.startupTimer)
    Swag.require(retireCalls == 2 and old.isPendingDestroy)
    Swag.require(window.currentView != null and window.currentView != old)
    Swag.require(window.pendingFile.isEmpty() and window.startupTimer == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 560)

    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.currentView     = Wnd.create'Wnd(window)
    window.currentCommands = Wnd.create'Wnd(window.viewerBar)
    window.instances.resize(1)
    window.instances[0].view     = window.currentView
    window.instances[0].commands = window.currentCommands
    window.currentFile           = "sample.cpp"
    window.showEmpty(appStrings().ui_Unsupported)
    Swag.require(window.currentView == null)
    Swag.require(window.currentCommands == null)
    Swag.require(window.instances.isEmpty())
    Swag.require(window.currentFile.isEmpty())
    Swag.require(window.readingLine.details.name.raw.isEmpty() and not window.readingLine.isLocallyVisible())
    Swag.require(window.home.isLocallyVisible() and window.hintLine.isLocallyVisible())
    Swag.require(window.surface!.wnd.name.raw == ProductName)
}

// The active viewer's right pane shares bounded splitter geometry and saves its current width.
#test
{
    var host: Testing.HeadlessHost
    host.setup(1000, 720)

    with let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    {
        .resize(1000, 720)
        .openFile(hexViewerFixturePath())
    }

    completeQueuedViewerFile(&host, window)
    var hexChoice = Swag.U32.Max
    for choice, index in window.choices where choice.key == "hex" do
        hexChoice = cast(u32, index)
    Swag.require(hexChoice != Swag.U32.Max)
    window.selectViewer(hexChoice)
    completeQueuedViewerFile(&host, window)

    // The panel is turned on from the lens, its toggle staying off the window.
    let button = assume cast(*IconButton, window.currentSidePanelButton)
    window.sendCommandEvent(ViewerCommands.SidePanel)
    Swag.require(button.isChecked and not button.isLocallyVisible())
    Swag.require(window.mainSplitter.items[2]!.view == window.currentSidePanelHost)
    Swag.require(window.mainSplitter.items[2]!.minimumSize == ViewerWindow.RightPanelMinWidth + window.themeMetrics().floating_Inset)
    Swag.require(window.mainSplitter.items[2]!.maximumSize == ViewerWindow.RightPanelMaxWidth + window.themeMetrics().floating_Inset)
    window.mainSplitter.setPaneSize(2, 1)
    Swag.require(window.mainSplitter.items[2]!.size == window.mainSplitter.items[2]!.minimumSize)
    window.mainSplitter.setPaneSize(2, 2_000)
    Swag.require(window.mainSplitter.items[2]!.size == window.mainSplitter.items[2]!.maximumSize)

    window.mainSplitter.setPaneSize(2, 500)
    let panelSize = window.mainSplitter.items[2]!.size
    let state     = saveViewerState(window)
    window.mainSplitter.setPaneSize(2, 560)
    loadViewerState(window, state.toSlice())
    Swag.require(window.rightPanelWidth == panelSize - window.themeMetrics().floating_Inset)
    Swag.require(window.mainSplitter.items[2]!.size == panelSize)

    window.setFullScreen(true)
    Swag.require(not window.mainSplitter.isPaneVisible(2))
    window.setFullScreen(false)
    Swag.require(window.mainSplitter.isPaneVisible(2) and button.isChecked)
    Swag.require(window.mainSplitter.items[2]!.size == panelSize,
                 Format.toString("right pane width changed from % to % after full screen (splitter: %)",
                                 panelSize,
                                 window.mainSplitter.items[2]!.size,
                                 window.mainSplitter.position.width))
    Swag.require(Math.abs(window.currentSidePanelHost!.position.right() - window.mainSplitter.paddedClientRect().right()) <= 1)
    let divider = window.themeMetrics().splitView_BarSize
    Swag.require(Math.abs(window.currentSidePanelHost.surfaceRect().x - window.documentPanel.surfaceRect().right() - divider) <= 1)
    window.setFilePanelVisible(true)
    Swag.require(Math.abs(window.documentPanel.surfaceRect().x - window.filePanelHost.surfaceRect().right() - divider) <= 1)
    Swag.require(Math.abs(window.currentSidePanelHost.surfaceRect().x - window.documentPanel.surfaceRect().right() - divider) <= 1)
}

#test
{
    let fileName = Gui.Testing.tempFilePath("scope-cached-view-", ".txt")
    defer discard catch File.delete(fileName)
    let source = "cached text"
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(800, 560)

    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(fileName)
    completeQueuedViewerFile(&host, window)

    // The lens takes the keyboard while it is open and gives it back to the document.
    let textView = assume cast(*PlainText.Panel, window.currentView)
    textView.setInitialFocus(textView.editor)
    Swag.require(textView.editor.hasFocus())
    window.sendCommandEvent(ViewerCommands.Lens)
    Swag.require(window.lens.isOpen() and not textView.editor.hasFocus())
    host.keyPress(Input.Key.Escape)
    Swag.require(not window.lens.isOpen() and textView.editor.hasFocus())

    let cachedView     = window.currentView
    let cachedCommands = window.currentCommands
    let childCount     = window.children.count
    let commandCount   = window.viewerBar.children.count
    window.activeChoiceIndex = 1
    Swag.require(window.activateChoice(0))
    Swag.require(window.currentView == cachedView)
    Swag.require(window.currentCommands == cachedCommands)
    Swag.require(window.children.count == childCount)
    Swag.require(window.viewerBar.children.count == commandCount)
    Swag.require(window.surface!.wnd.name.raw == (Path.fileName(fileName) orelse ""))
}

// Replacing a streaming document retires its short-period loader before deferred destruction.
// This is the path exercised by quickly moving from one file to the next in the sibling browser.
#test
{
    let firstFile  = Gui.Testing.tempFilePath("scope-switch-first-", ".txt")
    let secondFile = Gui.Testing.tempFilePath("scope-switch-second-", ".txt")
    defer discard catch File.delete(firstFile)
    defer discard catch File.delete(secondFile)

    var source: String
    for 2_000 do
        source += "A streamed document keeps loading while another file is selected.\n"
    let bytes = source.bytes()
    discard expect File.writeAllBytes(firstFile, bytes)
    discard expect File.writeAllBytes(secondFile, bytes)

    var host: Testing.HeadlessHost
    host.setup(800, 560)

    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(firstFile)
    host.fireTimer(window.startupTimer)
    window.choiceLoad.task.wait()
    host.pump()

    let discardedView  = assume cast(*PlainText.Panel, window.currentView)
    let discardedTimer = discardedView.addTimer(Viewer.BackgroundPollInterval)

    // The replacement keeps the outgoing view on screen until its own first chunk is published,
    // so the swap is observed once that chunk is in rather than as soon as the file is chosen.
    window.openFile(secondFile)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.currentView != discardedView)

    // A test can keep the timer's address for identity after the host has reclaimed it. Firing
    // that stale address must be a no-op and, in particular, must never dereference its target.
    host.fireTimer(discardedTimer)
}

// Closing through the lens retires the reader and leaves its history available.
#test
{
    var host: Testing.HeadlessHost
    host.setup(880, 560)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    Swag.require(window.sendComputeCommandStateEvent(ViewerCommands.Close).hidden)

    window.openFile(viewerFixturePath())
    completeQueuedViewerFile(&host, window)
    completeViewerStatistics(&host, window)
    window.setFilePanelVisible(true)
    window.searchBox.setText("verification marker")
    let recentCount = window.recent.count
    window.sendCommandEvent(ViewerCommands.Close)
    for 4_096
    {
        if window.pendingEmpty.isEmpty() do
            break
        Threading.Thread.sleep(1'ms)
        host.fireTimers()
    }

    Swag.require(window.pendingEmpty.isEmpty() and window.currentFile.isEmpty())
    Swag.require(window.instances.isEmpty() and window.currentView == null)
    Swag.require(window.home.isLocallyVisible() and window.sendComputeCommandStateEvent(ViewerCommands.Close).hidden)
    Swag.require(window.sendComputeCommandStateEvent(ViewerCommands.OpenDefault).hidden)
    Swag.require(window.searchBox.text().count == 0 and window.searchTimer == null)
    Swag.require(window.fileWatchTimer == null and window.slideTimer == null)
    Swag.require(window.folderFiles.isEmpty() and window.siblings.isEmpty())
    Swag.require(window.recent.count == recentCount)

    window.openFile(viewerFixturePath())
    completeQueuedViewerFile(&host, window)
    Swag.require(not window.currentFile.isEmpty() and not window.sendComputeCommandStateEvent(ViewerCommands.Close).hidden)
}

// The file panel can close itself and keeps the command of the lens in step.
#test
{
    var host: Testing.HeadlessHost
    host.setup(880, 560)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.sendCommandEvent(ViewerCommands.Files)
    Swag.require(window.sendComputeCommandStateEvent(ViewerCommands.Files).checked and window.filePanelHost.isLocallyVisible())
    window.closeFilesButton.sigPressed.call(window.closeFilesButton)
    Swag.require(not window.sendComputeCommandStateEvent(ViewerCommands.Files).checked and not window.filePanelHost.isLocallyVisible())
}

// Closing a queued opening discards its classification, including a worker already in flight.
#test
{
    for started in [false, true]
    {
        var host: Testing.HeadlessHost
        host.setup(880, 560)
        let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
        window.openFile(viewerFixturePath(), remember: false)
        if started do
            host.fireTimer(window.startupTimer)
        window.sendCommandEvent(ViewerCommands.Close)
        Swag.drainWork()
        host.pump()
        if window.startupTimer do
            host.fireTimer(window.startupTimer)
        Swag.require(window.pendingFile.isEmpty() and window.pendingEmpty.isEmpty())
        Swag.require(not window.choiceLoad.started and window.currentFile.isEmpty())
        Swag.require(window.instances.isEmpty() and window.home.isLocallyVisible())
    }
}

// A desktop file lights the document target before it is released, then uses the usual queued
// opening path without keeping an acknowledgement on screen.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)

    host.theme.setDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    let file   = viewerFixturePath()
    window.resize(960, 680)
    window.applyLayout()

    var point = window.documentPanel.surfaceRect().center()
    window.surface!.surfaceToScreen(&point)
    Swag.require(host.dragFilesOver(point, [file.toString()]) == DropEffect.Copy)
    Swag.require(window.dropHighlight.isLocallyVisible())
    Swag.require(window.dropHighlight.parent == window.documentPanel)
    Swag.require(window.dropHighlight.prompt.text() == appStrings().ui_DropTitle)
    Swag.require(not window.dropHighlight.prompt.isLocallyVisible())
    Swag.require(window.dropHighlight.wndFlags.has(.Disabled))
    Swag.require(window.dropHighlight.clientRect().width == window.documentPanel.clientRect().width)
    Swag.require(window.dropHighlight.clientRect().height == window.documentPanel.clientRect().height)
    Swag.require(window.pendingFile.isEmpty() and window.startupTimer == null)

    host.cancelDrag()
    Swag.require(not window.dropHighlight.isLocallyVisible())
    Swag.require(window.pendingFile.isEmpty() and window.startupTimer == null)

    Swag.require(host.dragFilesOver(point, [file.toString()]) == DropEffect.Copy)
    Swag.require(window.dropHighlight.isLocallyVisible())

    window.applyLayout()
    Testing.assertContentFits(window)

    Swag.require(host.dropFiles(point, [file.toString()]) == DropEffect.Copy)
    Swag.require(not window.dropHighlight.isLocallyVisible())
    Swag.require(window.pendingFile == file and window.startupTimer != null)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.currentFile == file)

    Swag.require(host.dragFilesOver(point, [file.toString()]) == DropEffect.Copy)
    Swag.require(window.dropHighlight.prompt.isLocallyVisible())
    host.cancelDrag()
}

// The folder filter walks only the neighbours of the current file's kind: registered viewers
// group their extensions, and an unregistered kind groups by its extension alone.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory, Format.toString("scope_kind_%", Guid64.random()))
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)

    let names: [5] string = ["pic1.png", "pic2.jpg", "notes.txt", "more.txt", "readme.md"]
    for one in names do
        discard expect File.writeAllBytes(Path.combine(folder, one), "a readable line\n")

    var host: Testing.HeadlessHost
    host.setup(960, 680)

    var index = createViewerPluginRegistry()

    with let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    {
        .resize(960, 680)
        .openFile(Path.combine(folder, "pic1.png"))
    }

    completeQueuedViewerFile(&host, window)

    window.rebuildSiblings()
    Swag.require(window.siblings.count == 5)

    // Pictures walk pictures: both image extensions belong to one registered viewer.
    window.setFolderSameKind(true)
    window.rebuildSiblings()
    Swag.require(window.siblings.count == 2)
    window.navigate(1)
    completeQueuedViewerFile(&host, window)
    Swag.require(Path.fileName(window.currentFile) == "pic2.jpg")
    window.navigate(1)
    completeQueuedViewerFile(&host, window)
    Swag.require(Path.fileName(window.currentFile) == "pic1.png")

    // A kind nothing registers falls back to the extension.
    window.openFile(Path.combine(folder, "notes.txt"))
    completeQueuedViewerFile(&host, window)
    window.rebuildSiblings()
    Swag.require(window.siblings.count == 2)

    window.setFolderSameKind(false)
    window.rebuildSiblings()
    Swag.require(window.siblings.count == 5)

    // The choice survives a session like the other panel decisions.
    window.setFolderSameKind(true)
    window.searchMatchCaseOption = true
    window.searchWholeWordOption = true
    window.searchRegexOption     = true
    let state = saveViewerState(window)
    window.setFolderSameKind(false)
    window.searchMatchCaseOption = false
    window.searchWholeWordOption = false
    window.searchRegexOption     = false
    loadViewerState(window, state)
    Swag.require(window.folderSameKind and
                 window.searchMatchCaseOption and
                 window.searchWholeWordOption and
                 window.searchRegexOption)
}

// Bare arrows never navigate files globally. The image viewer is the one document type that
// deliberately owns that gesture and asks the host for its neighboring image.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory, Format.toString("scope_arrows_%", Guid64.random()))
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)

    discard expect File.writeAllBytes(Path.combine(folder, "t1.txt"), "a readable line\n")
    discard expect File.writeAllBytes(Path.combine(folder, "t2.txt"), "a readable line\n")
    discard expect File.writeAllBytes(Path.combine(folder, "bundle.zip"), "not an image")
    let imageSource = expect File.readAllText(Path.combine(testSourceRoot(#curlocation), "datas/sample.svg"))
    let imageBytes  = imageSource.bytes()
    discard expect File.writeAllBytes(Path.combine(folder, "pic1.svg"), imageBytes)
    discard expect File.writeAllBytes(Path.combine(folder, "pic2.svg"), imageBytes)

    var host: Testing.HeadlessHost
    host.setup(960, 680)

    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    // The text editor owns the caret keys: with the keyboard parked on a toolbar button, the
    // arrow reaches the editor instead of walking the folder, and the keyboard follows it.
    window.openFile(Path.combine(folder, "t1.txt"))
    completeQueuedViewerFile(&host, window)
    let textView = assume cast(*PlainText.Panel, window.currentView)
    let outside  = IconButton.create(window, {}, {0, 0, 32, 32})
    outside.focusPolicy = .Tab
    outside.setFocus()
    Swag.require(not textView.editor.hasFocus())
    host.keyPress(Input.Key.Right)
    Swag.require(Path.fileName(window.currentFile) == "t1.txt")
    Swag.require(textView.editor.hasFocus())

    // Image gestures stay with images even when the folder panel's kind filter is off.
    window.openFile(Path.combine(folder, "pic1.svg"))
    completeQueuedViewerFile(&host, window)
    Swag.require(not window.folderSameKind)
    outside.setFocus()
    host.keyPress(Input.Key.Right)
    completeQueuedViewerFile(&host, window)
    Swag.require(Path.fileName(window.currentFile) == "pic2.svg")
    host.keyPress(Input.Key.Right)
    completeQueuedViewerFile(&host, window)
    Swag.require(Path.fileName(window.currentFile) == "pic1.svg")

    let imageView = assume cast(*Picture.Panel, window.currentView)
    imageView.previousButton.sigPressed.call(imageView.previousButton)
    completeQueuedViewerFile(&host, window)
    Swag.require(Path.fileName(window.currentFile) == "pic2.svg")
}

// Writes `names` as copies of the sample vector picture into a fresh folder, and returns that folder.
func createPictureFolder(stem: string, names: const [..] string)->String
{
    let folder = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("%_%", stem, Guid64.random()))
    expect Directory.create(folder)
    let imageSource = expect File.readAllText(Path.combine(testSourceRoot(#curlocation), "datas/sample.svg"))
    let imageBytes  = imageSource.bytes()
    for name in names do
        discard expect File.writeAllBytes(Path.combine(folder, name), imageBytes)
    return folder
}

// A folder round follows the current file in the panel, keeps it visible, and softens only the
// files already read in that round. Leaving the folder modes restores ordinary row rendering.
#test
{
    let folder = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("scope_folder_progress_%", Guid64.random()))
    expect Directory.create(folder)
    defer discard catch Directory.delete(folder, recurse: true)

    let imageSource = expect File.readAllText(Path.combine(testSourceRoot(#curlocation), "datas/sample.svg"))
    let imageBytes  = imageSource.bytes()
    for i in 24 do
        discard expect File.writeAllBytes(Path.combine(folder, Format.toString("pic%.svg", i)), imageBytes)

    var host: Testing.HeadlessHost
    host.setup(960, 680)

    var index = createViewerPluginRegistry()

    with let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    {
        .resize(960, 680)
        .openFile(Path.combine(folder, "pic0.svg"))
    }

    completeQueuedViewerFile(&host, window)
    window.openFile(window.folderFiles[20], remember: false)
    completeQueuedViewerFile(&host, window)
    window.setFilePanelVisible(true)
    window.applyLayout()

    let firstIndex = window.siblingIndex
    window.folderList.scrollWnd.setScrollPos(0, 0)
    Swag.require(firstIndex > window.folderList.lastVisibleLineIndex())

    window.setPlayMode(.Folder)
    Swag.require(window.folderList.isLineSelected(cast(u32, firstIndex)))
    Swag.require(window.folderList.firstVisibleLineIndex() <= firstIndex and firstIndex <= window.folderList.lastVisibleLineIndex())
    Swag.require(window.folderList.lineAt(cast(u32, firstIndex))!.colorFg == window.themeColors().label_TextLight)
    Swag.require(window.folderList.lineAt(cast(u32, firstIndex) - 1)!.colorFg.a == 0)

    Swag.require(window.continueFile(.Folder))
    completeQueuedViewerFile(&host, window)
    let secondIndex = window.siblingIndex
    Swag.require(secondIndex == firstIndex + 1 and window.folderList.isLineSelected(cast(u32, secondIndex)))
    Swag.require(window.folderList.firstVisibleLineIndex() <= secondIndex and secondIndex <= window.folderList.lastVisibleLineIndex())
    Swag.require(window.folderList.lineAt(cast(u32, firstIndex))!.colorFg == window.themeColors().label_TextLight)
    Swag.require(window.folderList.lineAt(cast(u32, secondIndex) + 1)!.colorFg.a == 0)

    window.setPlayMode(.Once)
    Swag.require(window.folderReadingFiles.isEmpty())
    for i in window.folderList.lineCount() do
        Swag.require(window.folderList.lineAt(i)!.colorFg.a == 0)
}

// A folder play mode walks the files the current viewer opens, in folder order and around again
// past the last one, whatever the panel filter says; a file alone of its kind has no successor.
// The file it brings up is not one the reader chose, so the history does not grow with it.
#test
{
    let folder = createPictureFolder("scope_play", ["pic1.svg", "pic2.svg", "pic3.svg"])
    defer discard catch Directory.delete(folder, recurse: true)
    discard expect File.writeAllBytes(Path.combine(folder, "notes.txt"), "a readable line\n")

    var host: Testing.HeadlessHost
    host.setup(960, 680)

    var index = createViewerPluginRegistry()

    with let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    {
        .resize(960, 680)
        .openFile(Path.combine(folder, "pic1.svg"))
    }

    completeQueuedViewerFile(&host, window)
    window.setFolderSameKind(false)
    window.setPlayMode(.Folder)
    let recentCount = window.recent.count

    Swag.require(window.continueFile(.Folder))
    Swag.require(Path.fileName(window.pendingFile) == "pic2.svg")
    completeQueuedViewerFile(&host, window)
    Swag.require(window.continueFile(.Folder))
    completeQueuedViewerFile(&host, window)
    Swag.require(Path.fileName(window.currentFile) == "pic3.svg")
    Swag.require(window.continueFile(.Folder))
    completeQueuedViewerFile(&host, window)
    Swag.require(Path.fileName(window.currentFile) == "pic1.svg")
    Swag.require(window.folderReadingFiles.count == 1 and window.folderReadingFiles[0] == window.currentFile)
    Swag.require(window.recent.count == recentCount)

    // The one text file has nothing of its kind to go on with, in either folder mode.
    window.openFile(Path.combine(folder, "notes.txt"))
    completeQueuedViewerFile(&host, window)
    Swag.require(not window.continueFile(.Folder) and not window.continueFile(.Shuffle))
    Swag.require(window.pendingFile.isEmpty())
}

// The shuffle reaches every file of the kind once before any comes again, and never brings
// straight back the one that has just ended.
#test
{
    let folder = createPictureFolder("scope_shuffle", ["pic1.svg", "pic2.svg", "pic3.svg", "pic4.svg"])
    defer discard catch Directory.delete(folder, recurse: true)

    var host: Testing.HeadlessHost
    host.setup(960, 680)

    var index = createViewerPluginRegistry()

    with let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    {
        .resize(960, 680)
        .openFile(Path.combine(folder, "pic1.svg"))
    }

    completeQueuedViewerFile(&host, window)
    window.setPlayMode(.Shuffle)

    // Three continuations from the first picture reach the three others, whatever their order.
    var seen: Array'String
    for step in 3
    {
        Swag.require(seen.count == step)
        Swag.require(window.continueFile(.Shuffle))
        let picked = Path.fileName(window.pendingFile) orelse ""
        Swag.require(picked != "pic1.svg" and not seen.contains(String.from(picked)))
        seen.add(picked)
        completeQueuedViewerFile(&host, window)
    }

    // Every file has had its turn: a new round starts, and not with the one that just ended.
    let last = String.from(Path.fileName(window.currentFile) orelse "")
    Swag.require(window.continueFile(.Shuffle))
    Swag.require(window.folderReadingFiles.count == 1)
    Swag.require(Path.fileName(window.pendingFile.toString()) != last.toString())
    completeQueuedViewerFile(&host, window)
}

// A viewer that has finished its file is answered by the play mode: stay, present it again, or
// stay as it is while the next file of the folder comes up. A still picture has no end of its
// own, so the folder modes count the slideshow pace on it, and only while it is the picture on
// screen; a file alone of its kind is the whole playlist.
#test
{
    let folder = createPictureFolder("scope_finish", ["pic1.svg", "pic2.svg"])
    defer discard catch Directory.delete(folder, recurse: true)
    discard expect File.writeAllBytes(Path.combine(folder, "notes.txt"), "a readable line\n")

    var host: Testing.HeadlessHost
    host.setup(960, 680)

    var index = createViewerPluginRegistry()

    with let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    {
        .resize(960, 680)
        .openFile(Path.combine(folder, "pic1.svg"))
    }

    completeQueuedViewerFile(&host, window)
    let view = unwrap window.currentView

    Swag.require(window.playMode == .Once)
    Swag.require(reportViewerFinished(view) == .Stop and window.pendingFile.isEmpty())
    window.setPlayMode(.Repeat)
    Swag.require(reportViewerFinished(view) == .Replay and window.pendingFile.isEmpty())

    // The image viewer reported its still picture on arrival: a folder mode starts counting
    // on it as soon as it is chosen, and stops the moment the mode leaves the folder.
    Swag.require(window.stillView == view and window.slideTimer == null)
    window.setPlayMode(.Folder)
    Swag.require(window.slideTimer != null)
    window.setPlayMode(.Once)
    Swag.require(window.slideTimer == null)
    window.setPlayMode(.Folder)

    // A view that is not the one on screen has no say.
    Swag.require(reportViewerFinished(window.documentPanel) == .Stop and window.pendingFile.isEmpty())

    Swag.require(reportViewerFinished(view) == .Next)
    Swag.require(Path.fileName(window.pendingFile) == "pic2.svg" and window.slideTimer == null)
    completeQueuedViewerFile(&host, window)
    Swag.require(window.stillView == window.currentView and window.slideTimer != null)
    host.fireTimer(window.slideTimer)
    Swag.require(window.slideTimer == null and Path.fileName(window.pendingFile) == "pic1.svg")
    completeQueuedViewerFile(&host, window)

    window.openFile(Path.combine(folder, "notes.txt"))
    completeQueuedViewerFile(&host, window)
    Swag.require(window.stillView == null and window.slideTimer == null)
    Swag.require(reportViewerFinished(window.currentView) == .Replay and window.pendingFile.isEmpty())
}

// The image viewer builds its playback control in its own command group and shares the host policy.
#test
{
    let folder = createPictureFolder("scope_play_menu", ["picture.svg"])
    defer discard catch Directory.delete(folder, recurse: true)

    var host: Testing.HeadlessHost
    host.setup(960, 680)

    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    Swag.require(window.playMode == .Once)
    window.openFile(Path.combine(folder, "picture.svg"))
    completeQueuedViewerFile(&host, window)
    let imageView = assume cast(*Picture.Panel, window.currentView)
    let button    = imageView.playModeButton
    Swag.require(button.parent == window.currentCommands)
    window.revealViewerBar()
    Swag.require(button.isVisible())
    window.pointerPosition = {0, 0}
    window.concealViewerBar()
    Swag.require(window.viewerBar.isLocallyVisible())

    host.activateOptionRowWhenShown(appStrings().ui_PlayMode)
    host.thenActivateOptionRow(appStrings().ui_PlayShuffle)
    button.showOptions()
    Swag.require(window.playMode == .Shuffle and button.icon.index == cast(s32, ThemeIcons.Shuffle))
    Swag.require(not window.viewerBar.isLocallyVisible())
    window.revealViewerBar()

    host.activateOptionRowWhenShown(appStrings().ui_PlayMode)
    host.thenActivateOptionRow(appStrings().ui_PlayFolder)
    host.thenActivateOptionRow(appStrings().ui_PlaySlide)
    host.thenActivateOptionRow("10 s")
    button.showOptions()
    Swag.require(window.playMode == .Folder and button.icon.index == cast(s32, ThemeIcons.RepeatAll))
    Swag.require(window.slideSeconds == 10)

    // The modes are one choice and the paces another: each page checks exactly the value in
    // force, and each mode carries the glyph the button shows for it.
    var options: OptionSheet.Page
    button.playback.addOptionRows(&options, button.view, showSlideDuration: true)
    Swag.require(options.rows.count == 2)
    Swag.require(options.rows[0].value == appStrings().ui_PlayFolder and options.rows[1].value == "10 s")

    var modes: OptionSheet.Page
    options.rows[0].buildLink(&modes)
    let icons = [ThemeIcons.PlayOnce, .RepeatOne, .RepeatAll, .Shuffle]
    for entry in 4
    {
        Swag.require(modes.rows[entry].kind == .Choice and modes.rows[entry].checked == (entry == 2))
        Swag.require(modes.rows[entry].icon.index == cast(s32, icons[entry]))
    }

    var paces: OptionSheet.Page
    options.rows[1].buildLink(&paces)
    for entry in Viewer.SlideChoices.count do
        Swag.require(paces.rows[entry].checked == (entry == 2))

    // The same picture can be inspected as bytes; presentation follows the selected viewer.
    for choice, index in window.choices where choice.key == "hex"
    {
        window.selectViewer(cast(u32, index))
        break
    }

    completeQueuedViewerFile(&host, window)
    Swag.require(not button.isVisible())
    window.selectViewer(0)
    completeQueuedViewerFile(&host, window)
    window.revealViewerBar()
    Swag.require(button.isVisible())
    window.showEmpty(appStrings().ui_Unsupported)
}

// What a viewer can do is a row of the lens too, under the viewer's name, and choosing a row
// runs it as the viewer's own control does.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(viewerFixturePath(), remember: false)
    completeQueuedViewerFile(&host, window)

    let view = assume cast(*PlainText.Panel, window.currentView)
    window.sendCommandEvent(ViewerCommands.Lens)

    // Plain text keeps its options on the line of readings: no floating group comes with the lens.
    Swag.require(window.lens.isOpen() and window.currentCommands == null and not window.viewerBar.isLocallyVisible())
    window.lens.setQuery(">")
    Swag.require(lensHasEntry(window, PlainText.texts().ui_Wrap) and lensHasEntry(window, appStrings().cmd_ZoomIn))
    Swag.require(lensHasEntry(window, appStrings().cmd_Options))

    let wrapping = view.wrapping
    window.lens.setQuery(PlainText.texts().ui_Wrap)
    Swag.require(window.lens.chosenEntry()!.title == PlainText.texts().ui_Wrap)
    Swag.require(window.lens.chosenEntry()!.checked == wrapping)
    window.lens.runChosen()
    Swag.require(not window.lens.isOpen() and view.wrapping != wrapping)
    completeTextReads(&host, view)
}

// Common task vocabulary reaches the real command in either shipped language.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    registerAppStrings(&host.app.resources)
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    for french in [false, true]
    {
        expect host.app.setLanguage(french ? "fr" : ReferenceLanguage)
        host.notify(.LanguageChanged)
        window.lens.open(french ? "ouvrir film" : "open movie")
        Swag.require(window.lens.chosenEntry()!.id == ViewerCommands.Open)
        window.lens.close()
        window.lens.open(french ? "mediatheque" : "media library")
        Swag.require(window.lens.chosenEntry()!.id == ViewerCommands.Explore)
        window.lens.close()
        window.lens.open(french ? "cinema" : "cinema")
        Swag.require(window.lens.chosenEntry()!.id == ViewerCommands.FullScreen)
        window.lens.close()
    }
}
