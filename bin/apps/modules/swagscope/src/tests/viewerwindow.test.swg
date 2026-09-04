#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

func saveViewerState(window: *ViewerWindow)->String
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

func loadViewerState(window: *ViewerWindow, bytes: const [..] u8)
{
    var decoder:    Serialization.Decoder'Serialization.Read.TagBin
    var serializer: Serialization.Serializer
    expect serializer.startRead(&decoder, bytes)
    expect serializer.beginSection(.Unordered)
    expect window.serializeState(&serializer)
    expect serializer.endSection()
    expect serializer.end()
}

// The window canonicalizes what it opens, so the fixture is spelled the way it will be read
// back: `#curlocation` gives its directory with the host separator, which no comparison
// against `currentFile` would survive.
func viewerFixturePath()->String
{
    var result: retval
    result = Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/comprehensive.txt")
    Path.normalize(&result)
    return result
}

// A golden can look plausibly rounded at fit-to-window scale while a square child has actually
// repainted its corner. Pin the document panel's own antialiased transition as well as its image.
func assertViewerPanelCorner(image: const *Image, panel: *Wnd)
{
    let rect    = panel.surfaceRect()
    let radius  = cast(s32) panel.themeRects().panel_Bk.radius
    let outside = panel.parent!.themeColors().toolBar_Bk.argb
    let inside  = panel.themeColors().view_Bk.argb
    let left    = cast(s32) rect.x
    let top     = cast(s32) rect.y

    Swag.assert(image.pixelColor(left, top).argb == outside)
    Swag.assert(image.pixelColor(left + radius, top + radius).argb == inside)

    var antialiasedCorner: bool
    for y in 0 until radius
    {
        for x in 0 until radius
        {
            let pixel = image.pixelColor(left + x, top + y).argb
            if pixel != outside and pixel != inside do
                antialiasedCorner = true
        }
    }

    Swag.assert(antialiasedCorner)
}

func markTestViewerRetired(wnd: *Wnd)->bool
{
    let retired = cast(*bool) wnd.userData!
    retired[] = true
    return true
}

func delayTestViewerRetirement(wnd: *Wnd)->bool
{
    let calls = cast(*u32) wnd.userData!
    calls[] += 1
    return calls[] >= 2
}

func completeQueuedViewerFile(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    completeViewerWindowClassification(host, window)

    var steps = 0'u32
    while window.activeChoiceIndex < window.instances.count and steps < 4_096
    {
        let instance = &window.instances[window.activeChoiceIndex]
        if !instance.view or !instance.isLoading or !instance.isLoading!(instance.view!) do
            break
        Threading.Thread.sleep(1'ms)
        host.fireTimers()
        steps += 1
    }
}

// Runs a search to its end: every streamed chunk, and every poll of a viewer that reads its
// document in the background.
func completeViewerSearch(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    var steps = 0'u32
    while window.searchTimer and steps < 4_096
    {
        host.fireTimer(window.searchTimer)
        if window.searchTimer and !window.searchStream.isOpen() do
            Threading.Thread.sleep(1'ms)
        steps += 1
    }

    Swag.assert(window.searchTimer == null)
}

func createSidePanelFixture(host: Viewer.Host)
{
    let panel = host.createSidePanel(220, host.icon(), "Details")
    let label = Label.create(panel.content, "Viewer details")
    label.dockStyle = .Center

    let view = Wnd.create'Wnd(host.contentParent())
    view.dockStyle       = .Center
    view.backgroundStyle = .View
    host.attachView(view)
}

// The optional viewer lane is host composition, not a private rectangle each decoder invents.
// Its outer seam has the splitter width, its content has panel geometry, and closing it returns
// every pixel to the document.
#test
{
    var host: Testing.HeadlessHost
    host.setup(720, 460)
    defer host.shutdown()

    let infoParent = Wnd.create'Wnd(&host.root, {0, 0, 720, 40})
    var session    = openTestViewer(testViewerPlugin(&createSidePanelFixture), &host.root, "fixture.panel", infoParent: infoParent)
    host.root.applyLayout()

    Swag.assert(session.view != null and session.sidePanelHost != null and session.sidePanel != null and session.sidePanelButton != null)
    Swag.assert(session.sidePanelHost!.parent == &host.root and session.sidePanel!.parent == session.sidePanelHost)
    Swag.assert(session.sidePanelButton!.parent == infoParent)
    Swag.assert(session.sidePanelHost!.backgroundStyle == .ToolBar and session.sidePanel!.backgroundStyle == .Panel)
    Swag.assert(session.sidePanelHost!.padding.x == 0 and session.sidePanelHost!.padding.z == host.root.themeMetrics().panel_GutterSize)
    Swag.assert(session.sidePanelHost!.padding.y == 0 and session.sidePanelHost!.padding.w == 0)
    Swag.assert(session.sidePanelHost!.position.width == 220 + host.root.themeMetrics().panel_GutterSize)
    Swag.assert(!session.sidePanelHost!.isLocallyVisible() and !session.sidePanelButton!.isLocallyVisible())

    session.sidePanelButton!.show()
    let closedWidth = session.view!.position.width
    session.sidePanelButton!.setChecked(true)
    session.sidePanelButton!.sigCheckedChanged.call(session.sidePanelButton!)
    host.root.applyLayout()
    Swag.assert(session.sidePanelHost!.isLocallyVisible())
    Swag.assert(session.view!.position.width == closedWidth - session.sidePanelHost!.position.width)

    session.sidePanelButton!.setChecked(false)
    session.sidePanelButton!.sigCheckedChanged.call(session.sidePanelButton!)
    host.root.applyLayout()
    Swag.assert(!session.sidePanelHost!.isLocallyVisible() and session.view!.position.width == closedWidth)
}

#test
{
    const Source = "Cat catalog cat catapult\ncat"
    var matches: Array'Viewer.SearchMatch
    Viewer.collectTextMatches(Source, "cat", {}, 0, 0, 0, &matches)
    Swag.assert(matches.count == 5)

    matches.clear()
    Viewer.collectTextMatches(Source, "cat", {wholeWord: true}, 0, 0, 0, &matches)
    Swag.assert(matches.count == 3 and matches[0].offset == 0 and matches[1].offset == 12 and matches[2].offset == 25)

    matches.clear()
    Viewer.collectTextMatches(Source, "cat", {matchCase: true, wholeWord: true}, 0, 0, 0, &matches)
    Swag.assert(matches.count == 2 and matches[0].offset == 12 and matches[1].offset == 25)

    matches.clear()
    Viewer.collectTextMatches(Source, #raw "c.t(a)?", {regularExpression: true}, 0, 0, 0, &matches)
    Swag.assert(matches.count == 5 and matches[0].length == 3 and matches[1].length == 4)
    Swag.assert(Viewer.patternIsValid(#raw "c.t(a)?", {regularExpression: true}))
    Swag.assert(!Viewer.patternIsValid("(", {regularExpression: true}))
}

#test
{
    let executable         = Env.executablePath()
    let direct: [1] string = [executable]
    Swag.assert(viewerStartupFile(direct).isEmpty())

    let withFile: [2] string = [executable, executable]
    Swag.assert(viewerStartupFile(withFile) == executable)
}

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("scope_text_stream_%.txt", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    let fixture = Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/comprehensive.txt")
    var source  = expect File.readAllText(fixture)
    for 2_000 do
        source += "A source line that stays readable while the rest remains on disk.\n"
    discard expect File.writeAllBytes(fileName, Swag.makeSlice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()
    let commands      = Wnd.create'Wnd(&host.root, {0, 0, 200, 36})
    var viewerSession = openTestViewer(textViewerPlugin(), &host.root, fileName, commandParent: commands)
    let view          = cast(*TextView) viewerSession.view!
    view.resize(800, 520)
    view.applyLayout()

    let loaded = view.editor.text()
    Swag.assert(loaded.count <= 16 * 1024)
    Swag.assert(view.stream.isOpen())
    Swag.assert(expect view.stream.position() < view.fileSize)

    var image = host.render(view)
    view.updateEstimatedHeight()
    let loadedHeight = view.editor.loadedDocumentHeight()
    Swag.assert(image.isValid() and loadedHeight > 0)
    Swag.assert(view.editor.scrollableClientRect().height > loadedHeight)

    view.editor.setScrollPosition({0, loadedHeight * 2})
    let position = view.editor.scrollPosition()
    Swag.assert(position.y > loadedHeight)
    view.loadNextChunk()
    Swag.assert(view.editor.scrollPosition() == position)

    view.editor.setScrollPosition({0, 0})
    let beforeEnd = view.editor.scrollPosition()
    var end       = KeyEvent{kind: .Pressed, key: .End, modifiers: .Control}
    Swag.assert(view.hookOnChildEvent!(view.editor, &end))
    discard host.render(view)
    Swag.assert(view.editor.scrollPosition().y > beforeEnd.y)
}

// Line and word totals are computed independently of the resident streaming window and become
// available in the information summary without forcing the whole document into the editor.
#test
{
    let fileName = writeTempFile("statistics.txt", cast(const [..] u8) "one two\nthree\n")
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
    host.setup(640, 420)
    defer host.shutdown()
    let commands      = Wnd.create'Wnd(&host.root, {0, 0, 240, 36})
    var viewerSession = openTestViewer(textViewerPlugin(), &host.root, fileName.toString(), commandParent: commands)
    let view          = cast(*TextView) viewerSession.view!
    while !Atomic.get(&view.statisticsState) do
        host.pump()
    if view.statisticsTimer do
        host.fireTimer(view.statisticsTimer)

    Swag.assert(view.statistics.lines == 2 and view.statistics.words == 3)
    let details = view.detailsText()
    Swag.assert(Utf8.contains(details.toSlice(), "2 lines") and Utf8.contains(details.toSlice(), "3 words"))
}

func writeTempFile(suffix: string, bytes: const [..] u8)->String
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("scope_%_%", Guid64.random(), suffix).toString())
    discard expect File.writeAllBytes(fileName.toString(), bytes)
    return fileName
}

func assertFolderFiles(window: *ViewerWindow, names: const [..] String)
{
    Swag.assert(window.folderFiles.count == names.count and window.siblings.count == names.count and window.folderList.lineCount() == names.count)
    for name, index in names
    {
        Swag.assert(window.folderFiles[index] == name[] and window.siblings[index] == name[])
        Swag.assert(window.folderList.lineAt(cast(u32) index)!.itemAt(0).name.raw == (Path.fileName(name[].toString()) orelse name[].toString()))
    }
}

// Selecting another file cancels the previous file's scan immediately, before asynchronous
// classification has had a chance to replace the viewer.
#test
{
    let first  = writeTempFile("search-first.txt", cast(const [..] u8) "needle in the first file\n")
    let second = writeTempFile("search-second.txt", cast(const [..] u8) "second file\n")
    defer discard catch File.delete(first.toString())
    defer discard catch File.delete(second.toString())

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()
    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(first.toString(), remember: false)
    completeQueuedViewerFile(&host, window)
    window.searchBox.setText("needle")
    Swag.assert(window.searchTimer != null)

    window.openFile(second.toString(), remember: false)
    Swag.assert(window.searchTimer == null)
    Swag.assert(!(window.searchBox.text()).count and window.searchMatches.isEmpty())
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
        utf16.add(cast(u8) c)
        utf16.add(0)
    }

    let wideFile = writeTempFile("utf16.txt", utf16.toSlice())
    defer discard catch File.delete(wideFile.toString())

    Swag.assert(TextView.supports(wideFile.toString()))
    let probed = TextView.probe(wideFile.toString())
    Swag.assert(probed.encoding == .Utf16Le and probed.contentStart == 2 and probed.accepted)

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()
    let commands      = Wnd.create'Wnd(&host.root, {0, 0, 240, 36})
    var viewerSession = openTestViewer(textViewerPlugin(), &host.root, wideFile.toString(), commandParent: commands)
    let view          = cast(*TextView) viewerSession.view!
    view.resize(800, 520)
    view.applyLayout()

    Swag.assert(view.encoding == .Utf16Le)
    Swag.assert(view.encodingName() == "UTF-16 LE")
    Swag.assert(view.editor.text() == "Hello, wide world")
    Swag.assert(view.encodingCombo.selectedIndex == 1)
}

// A single-byte page has no mark to announce it, and every byte decodes, so the accented byte is
// what the reader is shown rather than a fallback to bytes.
#test
{
    let latin: [11] u8 = ['c', 'a', 'f', 0xE9, ' ', 'n', 'a', 0xEF, 'v', 'e', '\n']
    let file           = writeTempFile("cp1252.txt", latin)
    defer discard catch File.delete(file.toString())

    Swag.assert(TextView.probe(file.toString()).encoding == .Windows1252)

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()
    let commands      = Wnd.create'Wnd(&host.root, {0, 0, 240, 36})
    var viewerSession = openTestViewer(textViewerPlugin(), &host.root, file.toString(), commandParent: commands)
    let view          = cast(*TextView) viewerSession.view!
    view.resize(800, 520)
    view.applyLayout()
    Swag.assert(view.editor.text() == "café naïve\n")

    // A reader who disagrees with the detection corrects it, and the same bytes read differently.
    view.applyEncoding(.Utf16Le)
    Swag.assert(view.encoding == .Utf16Le)
    Swag.assert(view.editor.text() != "café naïve\n")
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
    defer discard catch File.delete(file.toString())

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()
    let commands      = Wnd.create'Wnd(&host.root, {0, 0, 240, 36})
    var viewerSession = openTestViewer(textViewerPlugin(), &host.root, file.toString(), commandParent: commands)
    let view          = cast(*TextView) viewerSession.view!
    view.resize(800, 520)
    view.applyLayout()

    Swag.assert(view.encoding == .Utf8 and view.loadTimer != null)
    host.fireTimer(view.loadTimer)
    Swag.assert(view.encoding == .Windows1252)
    Swag.assert(Utf8.endsWith(view.editor.text(), "é\n"))
    Swag.assert(!Utf8.contains(view.editor.text(), textStrings().ui_NotText))
}

// Deciding an encoding is not accepting the file: code page 1252 gives every byte a meaning, so
// what keeps a binary out of the text view is the content it decodes to.
#test
{
    var binary: Array'u8
    for i in 512'u32 do
        binary.add(cast(u8) ((i * 7) & 0xFF))
    let file = writeTempFile("binary.bin", binary.toSlice())
    defer discard catch File.delete(file.toString())
    Swag.assert(!TextView.supports(file.toString()))
}

// The panel lists what is beside the current file and what was read before it, and a row opens
// its file without the window being rebuilt.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory.toString(), Format.toString("scope_panel_%", Guid64.random()).toString())
    expect Directory.create(folder.toString())
    defer discard catch Directory.delete(folder.toString(), recurse: true)

    var names: Array'String
    for i in 3'u32
    {
        let one = Path.combine(folder.toString(), Format.toString("file%.txt", i).toString())
        discard expect File.writeAllBytes(one.toString(), cast(const [..] u8) "a readable line\n")
        names.add(one)
    }

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.openFile(names[0].toString())
    completeQueuedViewerFile(&host, window)

    Swag.assert(!window.panelVisible and !window.filePanelHost.isLocallyVisible())
    window.toggleFilePanel()
    Swag.assert(window.panelVisible and window.filePanelHost.isLocallyVisible())
    Swag.assert(window.filesButton.isChecked)
    Swag.assert(window.filePanel.position.width == ViewerPanelWidth)
    Swag.assert(window.filePanel.minSize.x == ViewerPanelWidth and window.filePanel.maxSize.x == ViewerPanelWidth)
    Swag.assert(window.filePanel.isVertical() and window.filePanel.items.count == 2)
    Swag.assert(window.filePanel.items[0]!.minimumSize == ViewerPaneMinSize)
    Swag.assert(window.recentList.listFlags.has(.Ellipsis) and window.folderList.listFlags.has(.Ellipsis))
    Swag.assert(window.recentList.scrollWnd.flags.has(.DisableHorizontal) and window.folderList.scrollWnd.flags.has(.DisableHorizontal))
    Swag.assert(window.folderHistoryButton.parent == window.folderLabel.parent and window.folderHistoryButton.isEnabled())
    Swag.assert(window.kindButton.position.x - window.folderHistoryButton.position.right() == 8)
    Swag.assert(window.folderHistory.count == 1 and window.folderHistory[0].folder == folder)
    assertFolderFiles(window, names.toSlice())
    Swag.assert(window.recentList.lineCount() == 1)
    for i in window.folderList.lineCount()
    {
        let icon = window.folderList.lineAt(i)!.itemAt(0).icon
        Swag.assert(icon.isValid() and icon.index == cast(s32) ViewerIcons.Text)
    }

    let recentIcon = window.recentList.lineAt(0)!.itemAt(0).icon
    Swag.assert(recentIcon.isValid() and recentIcon.index == cast(s32) ViewerIcons.Text)

    // Choosing a sibling opens it, and the recent list grows by exactly that file.
    window.folderList.selectLine(2)
    completeQueuedViewerFile(&host, window)
    Swag.assert(window.currentFile == names[2])
    Swag.assert(window.recent.count == 2 and window.recent[0] == names[2])
    assertFolderFiles(window, names.toSlice())

    // A recent row keeps the list under the pointer stable while it opens its file.
    window.recentList.selectLine(1)
    completeQueuedViewerFile(&host, window)
    Swag.assert(window.currentFile == names[0])
    Swag.assert(window.recent.count == 2 and window.recent[0] == names[2] and window.recent[1] == names[0])
    assertFolderFiles(window, names.toSlice())

    window.setFilePanelVisible(false)
    Swag.assert(!window.filesButton.isChecked)
    window.setFilePanelVisible(true)

    window.filePanel.setPaneSize(0, 120)
    let state = saveViewerState(window)
    window.recent.clear()
    window.filePanel.setPaneSize(0, 180)
    window.setFilePanelVisible(false)
    loadViewerState(window, state.toSlice())
    Swag.assert(window.recent.count == 2 and window.panelVisible)
    Swag.assert(window.folderHistory.count == 1 and window.folderHistory[0].folder == folder)
    Swag.assert(window.recentPaneSize == 120 and window.filePanel.items[0]!.size == 120)
}

// The folder header keeps a bounded history and returns directly to the last file viewed in the
// chosen folder.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let root          = Path.combine(tempDirectory.toString(), Format.toString("scope_folder_history_%", Guid64.random()).toString())
    expect Directory.create(root.toString())
    defer discard catch Directory.delete(root.toString(), recurse: true)

    var files: Array'String
    for i in ViewerFolderHistoryCount + 2
    {
        let folder = Path.combine(root.toString(), Format.toString("folder%", i).toString())
        expect Directory.create(folder.toString())
        let fileName = Path.combine(folder.toString(), "document.txt")
        discard expect File.writeAllBytes(fileName.toString(), cast(const [..] u8) "a readable line\n")
        files.add(fileName)
    }

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    for one in files
    {
        window.openFile(one[].toString())
        completeQueuedViewerFile(&host, window)
    }

    Swag.assert(window.folderHistory.count == ViewerFolderHistoryCount)
    Swag.assert(window.folderHistory[0].file == files.back())
    let selectedFolder = String.from(window.folderHistory.back().folder.toString())
    let selectedFile   = String.from(window.folderHistory.back().file.toString())
    host.clickPopupMenuItemWhenShown(selectedFolder.toString())
    window.showFolderHistory()
    host.pump()
    completeQueuedViewerFile(&host, window)
    Swag.assert(host.autoHandled and window.currentFile == selectedFile)
    Swag.assert(window.folderHistory[0].folder == selectedFolder)
}

// Rebuilding the lists after a recent-file choice keeps the viewport under the pointer, and the
// folder pane continues to own file names rather than borrowing document text.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory.toString(), Format.toString("scope_recent_scroll_%", Guid64.random()).toString())
    expect Directory.create(folder.toString())
    defer discard catch Directory.delete(folder.toString(), recurse: true)

    var names: Array'String
    for i in ViewerRecentCount
    {
        let fileName = Path.combine(folder.toString(), Format.toString("file%.txt", i).toString())
        let content  = Format.toString("document text %\n", i)
        discard expect File.writeAllBytes(fileName.toString(), cast(const [..] u8) content.toString())
        names.add(fileName)
    }

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.openFile(names[0].toString())
    completeQueuedViewerFile(&host, window)
    window.recent.clear()
    for name in names do
        window.recent.add(name[])
    window.setFilePanelVisible(true)
    window.applyLayout()

    window.recentList.scrollWnd.setScrollPos(0, 80)
    let before = window.recentList.scrollWnd.scrollPosition()
    Swag.assert(before.y > 0)
    window.recentList.selectLine(8)
    completeQueuedViewerFile(&host, window)
    Swag.assert(window.currentFile == names[8])
    Swag.assert(window.recentList.scrollWnd.scrollPosition() == before)

    for i in window.folderList.lineCount()
    {
        let label = window.folderList.lineAt(i)!.itemAt(0).name.raw
        Swag.assert(Utf8.startsWith(label, "file") and Utf8.endsWith(label, ".txt"))
        Swag.assert(!Utf8.contains(label, "document text"))
    }
}

// The panel opens before any file has been read: there is no folder to name, so the section keeps
// its own title and both lists stay empty.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    Swag.assert(window.currentFile.isEmpty())
    window.setFilePanelVisible(true)
    Swag.assert(window.panelVisible and window.filePanelHost.isLocallyVisible())
    Swag.assert(window.folderList.lineCount() == 0 and window.recentList.lineCount() == 0)
    Swag.assert(!window.filePanel.isPaneVisible(0) and !window.recentPane.isLocallyVisible())
    Swag.assert(window.folderLabel.text() == appStrings().ui_Folder)
}

// The history is a list the reader owns: one file leaves it, or all of them do, and the section
// closes itself once it has nothing left to offer.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory.toString(), Format.toString("scope_history_%", Guid64.random()).toString())
    expect Directory.create(folder.toString())
    defer discard catch Directory.delete(folder.toString(), recurse: true)

    var names: Array'String
    for i in 3'u32
    {
        let one = Path.combine(folder.toString(), Format.toString("file%.txt", i).toString())
        discard expect File.writeAllBytes(one.toString(), cast(const [..] u8) "a readable line\n")
        names.add(one)
    }

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    for one in names
    {
        window.openFile(one[].toString())
        completeQueuedViewerFile(&host, window)
    }

    window.setFilePanelVisible(true)
    Swag.assert(window.recent.count == 3 and window.recentList.lineCount() == 3)

    // The most recent file is at the head, and forgetting one leaves the others in their order.
    window.forgetRecent(names[2].toString())
    Swag.assert(window.recent.count == 2 and window.recentList.lineCount() == 2)
    Swag.assert(window.recent[0] == names[1] and window.recent[1] == names[0])

    // Forgetting what the history does not hold changes nothing, and the file stays open.
    window.forgetRecent(Path.combine(folder.toString(), "absent.txt").toString())
    Swag.assert(window.recent.count == 2 and window.currentFile == names[2])

    Swag.assert(window.recentClearButton.parent == window.recentLabel.parent)
    Swag.assert(window.recentClearButton.icon.isValid())
    Swag.assert(!Utf8.contains(appStrings().ui_ConfirmClearHistory, "?"))

    host.clickModalButtonWhenShown(Dialog.BtnNo)
    window.confirmClearRecent()
    host.pump()
    Swag.assert(host.autoHandled and window.recent.count == 2)

    host.clickModalButtonWhenShown(Dialog.BtnYes)
    window.confirmClearRecent()
    host.pump()
    Swag.assert(host.autoHandled)
    Swag.assert(window.recent.isEmpty() and window.recentList.lineCount() == 0)
    Swag.assert(!window.filePanel.isPaneVisible(0) and !window.recentPane.isLocallyVisible())
    Swag.assert(window.currentFile == names[2] and window.folderList.lineCount() == 3)
}

// The history row menu offers what that file can do, and its own entry removes one file.
//
// The folder list is not a list the reader owns, so the same menu there stops at the actions that
// do not touch the history.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory.toString(), Format.toString("scope_menu_%", Guid64.random()).toString())
    expect Directory.create(folder.toString())
    defer discard catch Directory.delete(folder.toString(), recurse: true)

    var names: Array'String
    for i in 3'u32
    {
        let one = Path.combine(folder.toString(), Format.toString("file%.txt", i).toString())
        discard expect File.writeAllBytes(one.toString(), cast(const [..] u8) "a readable line\n")
        names.add(one)
    }

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    for one in names
    {
        window.openFile(one[].toString())
        completeQueuedViewerFile(&host, window)
    }

    window.setFilePanelVisible(true)
    window.applyLayout()

    let list = window.recentList
    Swag.assert(list.lineCount() == 3)

    // The row naming the file read before the one that is open, which the panel opens on its own
    // when it is picked: what the menu acts on is the row, not the document.
    list.selectLine(1)
    completeQueuedViewerFile(&host, window)
    Swag.assert(window.currentFile == names[1])

    host.clickPopupMenuItemWhenShown("scope.file.copyPath")
    window.showFileMenu(list, window.recent.toSlice(), {120, 120})
    host.pump()
    Swag.assert(host.autoHandled and Clipboard.getString() == names[1])

    host.clickPopupMenuItemWhenShown("scope.file.copyName")
    window.showFileMenu(list, window.recent.toSlice(), {120, 120})
    host.pump()
    Swag.assert(host.autoHandled and Clipboard.getString() == "file1.txt")

    host.clickPopupMenuItemWhenShown("scope.file.forget")
    window.showFileMenu(list, window.recent.toSlice(), {120, 120})
    host.pump()
    Swag.assert(host.autoHandled)
    Swag.assert(window.recent.count == 2 and window.recent[0] == names[2] and window.recent[1] == names[0])
    Swag.assert(list.lineCount() == 2 and window.currentFile == names[1])

    // A folder row names a file the folder holds, and nothing offers to take it out of a list it
    // was never in: the armed step finds no such entry and dismisses the menu instead.
    window.folderList.selectLine(0)
    completeQueuedViewerFile(&host, window)
    host.clickPopupMenuItemWhenShown("scope.file.forget", maxFrames: 4)
    window.showFileMenu(window.folderList, window.siblings.toSlice(), {120, 120})
    host.pump()
    Swag.assert(!host.autoHandled)
}

// The viewer a reader picks for one file becomes the viewer that kind of file opens in, and
// choosing the ordinary one back is the removal of that decision rather than one more.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory.toString(), Format.toString("scope_preferred_%", Guid64.random()).toString())
    expect Directory.create(folder.toString())
    defer discard catch Directory.delete(folder.toString(), recurse: true)

    let first  = Path.combine(folder.toString(), "notes.txt")
    let second = Path.combine(folder.toString(), "other.txt")
    for one in [first, second] do
        discard expect File.writeAllBytes(one[].toString(), cast(const [..] u8) "a readable line\n")

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    window.openFile(first.toString())
    completeQueuedViewerFile(&host, window)
    Swag.assert(window.choices.count == 3 and window.choices[0].key == TextViewerKey)
    Swag.assert(window.activeChoiceIndex == 0 and window.preferences.isEmpty())

    // Every entry of the selector says which viewer it is before its name is read.
    Swag.assert(window.viewerCombo.items.count == window.choices.count)
    for item in window.viewerCombo.items do
        Swag.assert(item!.icon.isValid())

    window.selectViewer(2)
    Swag.assert(window.choices[window.activeChoiceIndex].key == "hex")
    Swag.assert(window.preferences.count == 1 and window.preferences[0].kind == TextViewerKey and window.preferences[0].viewer == "hex")

    // The next file of the same kind opens where the reader left the previous one.
    window.openFile(second.toString())
    completeQueuedViewerFile(&host, window)
    Swag.assert(window.choices[window.activeChoiceIndex].key == "hex")

    // The decision crosses a session with the other panel choices.
    let state = saveViewerState(window)
    window.preferences.clear()
    loadViewerState(window, state.toSlice())
    Swag.assert(window.preferences.count == 1 and window.preferences[0].viewer == "hex")

    window.selectViewer(0)
    Swag.assert(window.preferences.isEmpty())
    window.openFile(first.toString())
    completeQueuedViewerFile(&host, window)
    Swag.assert(window.choices[window.activeChoiceIndex].key == TextViewerKey)
}

// Pins the file panel: two named sections share the left edge, the row naming the open file is
// the selected one, and the document keeps the rest of the surface.
#[Swag.TestTag("golden")]
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory.toString(), "scope_panel_golden")
    discard catch Directory.delete(folder.toString(), recurse: true)
    expect Directory.create(folder.toString())
    defer discard catch Directory.delete(folder.toString(), recurse: true)

    let names: [4] string = ["changelog.md", "notes.txt", "report-with-a-name-too-long-for-the-fixed-history-panel.txt", "sample.json"]
    for one in names do
        discard expect File.writeAllBytes(Path.combine(folder.toString(), one).toString(), cast(const [..] u8) "a readable line\n")

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.openFile(Path.combine(folder.toString(), "notes.txt").toString())
    completeQueuedViewerFile(&host, window)
    window.toggleFilePanel()
    window.applyLayout()
    host.settleAnimations(window, 4)

    Swag.assert(window.folderList.lineCount() == 4)
    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "panel")
    Testing.assertContentFits(window)
}

// Keeps the virtual document extent monotonic while several large-file chunks arrive between
// paints, and exercises complete keyboard navigation through the real focused editor.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("scope_large_scroll_%.txt", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String
    for 70_000 do
        source += "A large source line keeps the virtual scrollbar stable between frames.\n"
    Swag.assert(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllBytes(fileName, Swag.makeSlice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()
    let commands      = Wnd.create'Wnd(&host.root, {0, 0, 200, 36})
    var viewerSession = openTestViewer(textViewerPlugin(), &host.root, fileName, commandParent: commands)
    let view          = cast(*TextView) viewerSession.view!
    view.resize(800, 520)
    view.applyLayout()
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
    view.editor.setScrollPosition({0, view.virtualHeight * 0.5})
    Swag.assert(view.pendingSeek)
    host.fireTimers()
    Swag.assert(view.residentStart > firstStart)
    Swag.assert(view.bytesRead - view.residentStart <= 256 * 1024 + 16 * 1024)

    host.keyPress(Input.Key.End)
    discard host.render(view)
    Swag.assert(view.residentStart > 0)
    Swag.assert(view.editor.scrollPosition().y > 0)
    host.keyPress(Input.Key.Home)
    discard host.render(view)
    Swag.assert(view.residentStart == 0)
    Swag.assert(view.editor.selectionEnd().lineIndex == 0)
    Swag.assert(view.editor.scrollPosition().y == 0)
}

// Rapid scrollbar scrubbing coalesces to the latest byte window and remains stable when the
// direction changes repeatedly. Each completed seek keeps the requested viewport instead of
// snapping back to the resident window it replaced.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("scope_text_scrub_%.txt", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String
    for index in 70_000 do
        source += Format.toString("Distinct streamed line % keeps scrollbar seeks observable.\n", index)
    Swag.assert(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllBytes(fileName, Swag.makeSlice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()
    let commands      = Wnd.create'Wnd(&host.root, {0, 0, 200, 36})
    var viewerSession = openTestViewer(textViewerPlugin(), &host.root, fileName, commandParent: commands)
    let view          = cast(*TextView) viewerSession.view!
    view.resize(800, 520)
    view.applyLayout()
    discard host.render(view)
    view.updateEstimatedHeight()

    view.editor.setScrollPosition({0, view.virtualHeight * 0.85})
    Swag.assert(view.pendingSeek)
    view.editor.setScrollPosition({0, 0})
    Swag.assert(!view.pendingSeek)

    view.editor.setScrollPosition({0, view.virtualHeight * 0.85})
    view.editor.setScrollPosition({0, view.virtualHeight * 0.2})
    Swag.assert(view.pendingSeek and view.loadTimer != null)
    host.fireTimer(view.loadTimer)
    let lowOffset = cast(u64) (0.2 * cast(f32) view.fileSize)
    Swag.assert(view.residentStart <= lowOffset and view.bytesRead >= lowOffset)

    let ratios = [0.8'f32, 0.1'f32, 0.65'f32, 0.3'f32, 0.9'f32, 0.05'f32]
    for ratio in ratios
    {
        let requestedY = view.virtualHeight * ratio
        view.editor.setScrollPosition({0, requestedY})
        Swag.assert(view.pendingSeek and view.loadTimer != null)
        host.fireTimer(view.loadTimer)
        let offset = cast(u64) (ratio * cast(f32) view.fileSize)
        Swag.assert(view.residentStart <= offset and view.bytesRead >= offset)
        Swag.assert(Math.abs(view.editor.scrollPosition().y - requestedY) <= 1)
        Swag.assert(!view.editor.text().isEmpty())
    }
}

// All three application palettes cross the same state boundary as the surface placement.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    Swag.assert(window.appearanceButton.appearanceTheme == .SwagDark)

    window.applyTheme(cast(u32) AppearanceTheme.Dark)
    host.notify(.ThemeChanged)
    Swag.assert(window.themeIndex == cast(u32) AppearanceTheme.Dark)
    Swag.assert(host.app.theme.colors.view_Bk == ThemeColors.darkPalette().view)

    window.applyTheme(cast(u32) AppearanceTheme.Light)
    host.notify(.ThemeChanged)
    Swag.assert(window.themeIndex == cast(u32) AppearanceTheme.Light)
    Swag.assert(host.app.theme.colors.view_Bk == 0xFFFFFFFF)
    Swag.assert(window.themeColors().view_Bk == 0xFFFFFFFF)

    let state = saveViewerState(window)
    window.applyTheme(0)
    loadViewerState(window, state.toSlice())
    window.applyTheme(window.themeIndex)
    host.notify(.ThemeChanged)
    Swag.assert(window.themeIndex == cast(u32) AppearanceTheme.Light and host.app.theme.colors.view_Bk == 0xFFFFFFFF)
    Swag.assert(window.themeColors().view_Bk == 0xFFFFFFFF)
}

// The caption appearance action reaches the standard application about dialog.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    Swag.assert(!window.appearanceButton.sigAboutRequested.isEmpty())
    let capabilities = window.aboutViewerList()
    Swag.assert(Utf8.contains(capabilities.toSlice(), "<b>Archive</b>"))
    Swag.assert(!Utf8.contains(capabilities.toSlice(), "\n") and !Utf8.contains(capabilities.toSlice(), ".zip"))
    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    window.showAbout()
    host.pump()

    Swag.assert(host.autoHandled)
    Swag.assert(host.openedSurfaceCount() == 0)
}

// The application About box presents supported content as one compact capability line instead of
// a scrolling extension inventory.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 700)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let appIcon = expect Image.decode(".png", AppIcon)
    host.app.setAppIcon(appIcon)
    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    let dlg    = window.createAboutDialog({year: 2026, month: 9, day: 1}, version: "1.2.3")
    dlg.applyLayout()

    let surface  = dlg.surface!
    let rendered = host.render(dlg)
    var image    = rendered.cropped(0, 0, cast(s32) surface.position.width, cast(s32) surface.position.height)
    Pixel.Testing.assertImageGolden(&image, "about")
    surface.destroy()
}

// The live appearance menu switches the complete application tree to French and closes its
// transient popup before the translated controls are used again.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer
    {
        discard catch host.app.setLanguage(ReferenceLanguage)
        host.shutdown()
    }

    registerAppStrings(&host.app.resources)
    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.surface!.setTitle(appStrings().ui_WindowTitle)
    Swag.assert(window.openButton.toolTip == "Open (Ctrl+O)")

    host.openPopupSubMenuWhenShown("Language")
    host.thenClickPopupMenuItem("fr")
    window.appearanceButton.sigPressed.call(window.appearanceButton)
    host.pump()

    Swag.assert(host.app.language() == "fr")
    Swag.assert(window.language == "fr")

    // Headless surfaces stay outside Application.surfaces, so deliver the broadcast they would
    // receive from setLanguage in a native window.
    host.notify(.LanguageChanged)
    Swag.assert(window.surface!.wnd.name.raw == appStrings().ui_WindowTitle)
    Swag.assert(window.openButton.toolTip == "Ouvrir (Ctrl+O)")
    Swag.assert(window.dropHighlight.prompt.text() == "Déposez un fichier pour l'afficher")
    Swag.assert(host.openedSurfaceCount() == 0)
}

// Finds a match split across scanner chunks in a multi-megabyte file and materializes it in the
// resident text window without losing the virtual scroll range.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("scope_large_search_%.txt", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    let query  = "marker across boundary"
    let target = ViewerSearchChunkSize * 10 - 7
    var source: String
    for target / 64 do
        source += "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\n"
    for target - source.length do
        source += "x"
    source += query
    for 32_000 do
        source += "\nThe rest of the large document stays searchable."
    Swag.assert(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllBytes(fileName, Swag.makeSlice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()
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
    let textView = cast(*TextView) window.currentView!
    Swag.assert(textView.editor.selectedText() == query)
    Swag.assert(textView.bytesRead < textView.fileSize)
    discard host.render(textView)
    textView.updateEstimatedHeight()
    Swag.assert(textView.editor.scrollableClientRect().height > textView.editor.paddedClientRect().height)
}

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
    defer host.shutdown()
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(fileName)
    completeQueuedViewerFile(&host, window)
    let view = cast(*PdfViewer) window.currentView!
    Swag.assert(view.loadTimer == null and view.pdfView.pageCount() == 2)

    window.searchBox.setFocus()
    window.searchBox.setText("second")
    completeViewerSearch(&host, window)
    Swag.assert(window.searchComplete and window.searchMatches.count == 1 and window.searchIndex == 0)
    Swag.assert(window.searchCountLabel.text() == "1/1")
    Swag.assert(window.searchNext.isEnabled() and window.searchPrevious.isEnabled())
    Swag.assert(view.pdfView.pageIndex == 1 and view.pdfView.selectedText() == "Second")
    Swag.assert(window.searchBox.hasFocus())

    window.searchBox.setText("absent")
    completeViewerSearch(&host, window)
    Swag.assert(window.searchComplete and window.searchMatches.isEmpty())
    Swag.assert(window.searchCountLabel.text() == "0/0")
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
    defer host.shutdown()
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(fileName)
    completeQueuedViewerFile(&host, window)
    window.searchBox.setFocus()
    window.searchBox.setText("cat")
    completeViewerSearch(&host, window)

    Swag.assert(window.searchMatches.count == 5 and window.searchIndex == 0 and window.searchMatch == 0)
    Swag.assert(window.searchCountLabel.text() == "1/5")
    Swag.assert(window.searchBox.hasFocus())
    discard host.render(window)
    host.fireTimers()
    Swag.assert(window.searchOverlay.isLocallyVisible())
    let basic = cast(*TextView) window.currentView!
    Swag.assert(basic.editor.selectedText() == "Cat")
    var matchBounds: Math.Rectangle
    Swag.assert(textSearchBounds(basic, window.searchMatches[window.searchIndex], &matchBounds))
    Swag.assert(window.searchOverlay.position.width == Math.round(matchBounds.width + ViewerSearchOverlayInsetX * 2))
    Swag.assert(window.searchOverlay.position.height == Math.round(matchBounds.height + ViewerSearchOverlayInsetY * 2))
    window.searchOverlay.phase = 0.25
    let firstPulse = host.render(window)
    window.searchOverlay.invalidate()
    let repeatedPulse = host.render(window)
    Swag.assert(Hash.hashBytes32(firstPulse.pixels.toSlice()) == Hash.hashBytes32(repeatedPulse.pixels.toSlice()))

    window.findPrevious()
    Swag.assert(window.searchIndex == 4 and window.searchMatch == 25 and window.searchCountLabel.text() == "5/5")
    window.findNext()
    Swag.assert(window.searchIndex == 0 and window.searchMatch == 0)

    window.searchWholeWordOption = true
    window.restartSearch()
    completeViewerSearch(&host, window)
    Swag.assert(window.searchMatches.count == 3 and window.searchCountLabel.text() == "1/3")

    window.searchMatchCaseOption = true
    window.restartSearch()
    completeViewerSearch(&host, window)
    Swag.assert(window.searchMatches.count == 2 and window.searchMatch == 12 and window.searchCountLabel.text() == "1/2")

    window.searchRegexOption     = true
    window.searchMatchCaseOption = false
    window.searchBox.setValidator(window.searchBox.validator)
    window.searchBox.setText(#raw "c.t(a)?")
    completeViewerSearch(&host, window)
    Swag.assert(window.searchBox.isValid() and window.searchMatches.count == 3)

    window.searchBox.setText("(")
    Swag.assert(!window.searchBox.isValid() and window.searchTimer == null)
    Swag.assert(window.searchCountLabel.text() == "0/0" and window.searchCountLabel.toolTip == appStrings().ui_SearchInvalidRegularExpression)

    window.searchRegexOption = false
    window.searchBox.setValidator(window.searchBox.validator)

    window.searchBox.setText("absent")
    completeViewerSearch(&host, window)
    Swag.assert(window.searchMatches.isEmpty() and window.searchCountLabel.text() == "0/0")
    Swag.assert(window.searchBox.hasFocus() and !window.searchOverlay.isLocallyVisible())

    window.searchBox.setText("cat")
    completeViewerSearch(&host, window)
    Swag.assert(!window.searchBox.children.isEmpty())
    window.searchBox.setText(null)
    Swag.assert(!(window.searchBox.text()).count)
    Swag.assert(!(window.searchCountLabel.text()).count and !window.searchOverlay.isLocallyVisible())
    Swag.assert((cast(*TextView) window.currentView!).editor.isSelectionEmpty())
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

    expect File.writeAllBytes(fileName, source.toString())

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(fileName)
    completeQueuedViewerFile(&host, window)

    var markdownIndex = Swag.U32.Max
    for choice, choiceIndex in window.choices where choice.key == "markdown" do
        markdownIndex = cast(u32) choiceIndex
    Swag.assert(markdownIndex != Swag.U32.Max)
    window.selectViewer(markdownIndex)
    window.searchBox.setFocus()
    window.searchBox.setText(Query)
    completeViewerSearch(&host, window)
    Swag.assert(window.searchMatches.count == 3 and window.searchMatch == offsets[0])

    for 2_048 where !window.searchOverlay.isLocallyVisible() do
        host.fireTimers()
    Swag.assert(window.searchOverlay.isLocallyVisible())

    window.findNext()
    Swag.assert(window.searchIndex == 1 and window.searchMatch == offsets[1])
    window.searchOverlay.hide()
    for 2_048 where !window.searchOverlay.isLocallyVisible() do
        host.fireTimers()
    Swag.assert(window.searchOverlay.isLocallyVisible())

    window.findNext()
    Swag.assert(window.searchIndex == 2 and window.searchMatch == offsets[2])
    window.searchOverlay.hide()
    for 2_048 where !window.searchOverlay.isLocallyVisible() do
        host.fireTimers()
    Swag.assert(window.searchOverlay.isLocallyVisible())

    window.findPrevious()
    Swag.assert(window.searchIndex == 1 and window.searchMatch == offsets[1])
    window.searchOverlay.hide()
    for 2_048 where !window.searchOverlay.isLocallyVisible() do
        host.fireTimers()
    Swag.assert(window.searchOverlay.isLocallyVisible())

    let markdown = cast(*Markdown.View) window.currentView!
    var bounds: Math.Rectangle
    Swag.assert(markdown.searchMatchRect(&bounds))

    let beforeSearchPage = bounds.y
    host.keyPress(.PageDown)
    for 2_048 where bounds.y >= beforeSearchPage
    {
        host.fireTimers()
        discard markdown.searchMatchRect(&bounds)
    }

    Swag.assert(markdown.searchMatchRect(&bounds))
    let afterSearchPage = bounds.y
    Swag.assert(afterSearchPage < beforeSearchPage)
    Swag.assert(window.searchBox.hasFocus())

    markdown.setFocus()
    host.keyPress(.PageUp)
    Swag.assert(markdown.searchMatchRect(&bounds))
    Swag.assert(bounds.y > afterSearchPage)
    Swag.assert(markdown.hasFocus())

    window.searchBox.setText(null)
    Swag.assert(!markdown.searchMatchRect(&bounds))
    Swag.assert(!window.searchOverlay.isLocallyVisible())
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    host.app.theme.setSwagDark()
    host.app.notifyThemeChanged()

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.applyLayout()

    Swag.assert(window.commandBar.position.height == ViewerActionBarHeight)
    Swag.assert(window.viewerCombo.parent == window.commandBar)
    Swag.assert(window.appearanceButton.parent == &host.surfaceWnd)
    Swag.assert(window.searchGroup.parent == window.commandBar)
    Swag.assert(window.searchBox.parent == window.searchGroup)
    Swag.assert(window.searchNavigation.parent == window.searchGroup)
    Swag.assert(window.fullScreenButton.parent == window.commandBar)
    Swag.assert(window.fullScreenButton.flags.has(.Toggle) and window.fullScreenButton.checkIndicator == .Frame)
    Swag.assert(window.openDefaultButton.parent == window.commandBar and !window.openDefaultButton.isEnabled())
    Swag.assert(!window.searchGroup.isLocallyVisible() and window.searchBox.isHidden())
    Swag.assert(window.searchPrevious.icon.isValid() and window.searchNext.icon.isValid())
    Swag.assert(!window.searchPrevious.isEnabled() and !window.searchNext.isEnabled())
    Swag.assert(window.infoBar.position.height == ViewerInfoHeight)
    let panelGutter = window.themeMetrics().panel_GutterSize
    Swag.assert(window.infoBarHost.position.height == ViewerInfoHeight + 2 * panelGutter)
    Swag.assert(window.infoBarHost.dockStyle == .Top and window.infoBar.dockStyle == .Center)
    Swag.assert(window.backgroundStyle == .Application and window.infoBarHost.backgroundStyle == .ToolBar)
    Swag.assert(window.infoBar.backgroundStyle == .InformationPanel and window.infoBar.parent == window.infoBarHost)
    Swag.assert(window.infoBarHost.padding.x == panelGutter and window.infoBarHost.padding.y == panelGutter and window.infoBarHost.padding.z == panelGutter and window.infoBarHost.padding.w == panelGutter)
    Swag.assert(window.commandBar.backgroundStyle == .ToolBar)
    Swag.assert(window.filePanelHost.backgroundStyle == .ToolBar and window.filePanel.backgroundStyle == .Transparent)
    Swag.assert(window.filePanelHost.padding.x == panelGutter and window.filePanelHost.padding.z == 0)
    Swag.assert(window.filePanelHost.padding.y == 0 and window.filePanelHost.padding.w == 0)
    Swag.assert(window.documentHost.backgroundStyle == .ToolBar and window.documentPanel.backgroundStyle == .Panel)
    Swag.assert(window.documentHost.padding.x == panelGutter and window.documentHost.padding.z == panelGutter)
    Swag.assert(window.documentPanel.padding == {})
    Swag.assert(window.documentPanel.parent == window.documentHost and window.emptyView.parent == window.documentPanel)
    Swag.assert(window.recentPane.backgroundStyle == .Panel and window.folderPane.backgroundStyle == .Panel)
    Swag.assert(window.filesButton.parent == window.infoContentGroup)
    Swag.assert(window.viewerBar.backgroundStyle == .ToolBar)
    Swag.assert(window.themeColors().view_Bk != window.themeColors().informationBar_Bk)
    Swag.assert(window.themeColors().view_Bk != window.themeColors().bk)
    Swag.assert(window.themeColors().view_Bk != window.themeColors().wnd_Bk)
    Swag.assert(window.themeColors().informationBar_Bk != window.themeColors().bk and window.themeColors().informationBar_Bk != window.themeColors().wnd_Bk)
    Swag.assert(window.themeColors().commandBar_Bk != window.themeColors().wnd_Bk and window.themeColors().commandBar_Bk != window.themeColors().informationBar_Bk)
    Swag.assert(window.themeColors().toolBar_Bk != window.themeColors().wnd_Bk and window.themeColors().toolBar_Bk != window.themeColors().informationBar_Bk)
    Swag.assert(window.themeColors().informationBar_Bk.relativeLuminance() < window.themeColors().wnd_Bk.relativeLuminance())
    Swag.assert(window.themeColors().informationBar_Bk.relativeLuminance() < window.themeColors().commandBar_Bk.relativeLuminance())
    Swag.assert(window.themeColors().bk != window.themeColors().wnd_Bk)
    Swag.assert(window.infoBarHost.isLocallyVisible())
    Swag.assert(window.viewerBar.dockStyle == .Bottom and window.viewerBar.isLocallyVisible())
    Swag.assert(window.viewerBar.position.height == panelGutter)
    Swag.assert(window.infoNameLabel.name.raw.isEmpty())
    Swag.assert(window.surface!.minSize.x == ViewerMinWidth)
    Swag.assert(Utf8.contains(window.emptyLabel.name.raw, appStrings().ui_DropTitle))

    // The large empty-state glyph is intentionally deferred until the surface's Init event.
    Swag.assert(window.emptyView.isLocallyVisible() and !window.emptyIconLabel.icon.isValid())
    Swag.assert(window.documentHost.position.y >= window.infoBarHost.position.bottom())
    Swag.assert(window.infoBar.surfaceRect().y - window.openButton.surfaceRect().bottom() == panelGutter)
    Swag.assert(window.emptyHintLabel.text() == appStrings().ui_DropHint)
    Swag.assert(window.currentView == null)
    Swag.assert(window.currentCommands == null)
    Swag.assert(window.currentActions == null and window.currentInfo == null)
    Swag.assert(window.filesButton.flags.has(.Toggle) and window.filesButton.checkIndicator == .Frame)
    Swag.assert(!window.filesButton.isChecked and !window.loadingOverlay.isLocallyVisible())
    Swag.assert(!window.viewerCombo.isLocallyVisible())
    Swag.assert(window.infoNameLabel.parent == window.infoFileGroup)
    Swag.assert(window.infoSizeLabel.parent == window.infoFileGroup)
    Swag.assert(window.infoNameLabel.textVerticalAlignment == .OpticalCenter)
    Swag.assert(window.infoSizeLabel.textVerticalAlignment == .OpticalCenter)
    Swag.assert(window.infoStatsLabel.textVerticalAlignment == .OpticalCenter)
    Swag.assert(window.recentClearButton.parent == window.recentLabel.parent)
    Swag.assert(window.infoStatsLabel.parent == window.infoContentGroup and window.infoContentGroup.parent == window.infoBar)
    Testing.assertContentFits(window)

    // Viewer tools have their own full-width band and cannot collide with the global selector.
    window.resize(ViewerMinWidth, 680)
    window.viewerCombo.show()
    let widestCommands = Wnd.create'Wnd(window.viewerBar, {0, 0, 0, 36})
    widestCommands.dockStyle         = .Center
    window.viewerBar.position.height = ViewerBarHeight
    window.viewerBar.show()
    window.applyLayout()
    Swag.assert(window.viewerCombo.parent == window.commandBar and widestCommands.parent == window.viewerBar)
    Swag.assert(window.viewerCombo.position.bottom() <= window.infoBarHost.position.y)
    Swag.assert(widestCommands.position.y >= window.viewerBar.clientRect().y)
}

// Search is chrome only when the selected viewer exposes search. Switching to a viewer without
// that contract removes the complete group and never leaves keyboard focus in an invisible field.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.openFile(viewerFixturePath().toString())
    completeQueuedViewerFile(&host, window)
    window.applyLayout()

    Swag.assert(window.searchGroup.isLocallyVisible() and window.searchBox.isVisible() and window.searchBox.isEnabled())
    Swag.assert(window.searchPrevious.isVisible() and window.searchNext.isVisible())
    Swag.assert(window.searchOptionsButton.isVisible() and window.searchOptionsButton.icon.sizeX == themeActionIconSize(window.themeMetrics()))
    Swag.assert(window.searchOptionsButton.position.height == window.openButton.position.height)
    Swag.assert(window.searchPrevious.icon.sizeX == themeActionIconSize(window.themeMetrics()) and window.searchNext.icon.sizeX == themeActionIconSize(window.themeMetrics()))
    Swag.assert(window.searchPrevious.position.height == window.openButton.position.height)
    Swag.assert(window.searchNext.position.height == window.openButton.position.height)
    Swag.assert(window.searchGroup.children.count == 3)
    Swag.assert(window.searchGroup.children[0] == window.searchOptionsButton)
    Swag.assert(window.searchGroup.children[1] == window.searchBox)
    Swag.assert(window.searchGroup.children[2] == window.searchNavigation)
    Swag.assert(window.searchNavigation.children.count == 3)
    Swag.assert(window.searchNavigation.children[0] == window.searchPrevious)
    Swag.assert(window.searchNavigation.children[1] == window.searchNext)
    Swag.assert(window.searchNavigation.children[2] == window.searchCountLabel)
    Swag.assert(window.searchCountLabel.textHorizontalAlignment == .Left)
    Swag.assert(Math.abs(window.searchGroup.position.horzCenter() - window.commandBar.paddedClientRect().horzCenter()) < 0.01)

    window.searchBox.setFocus()
    Swag.assert(window.searchBox.hasFocus())
    let midiFile = Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), "viewer.mid")
    window.openFile(midiFile.toString())
    completeQueuedViewerFile(&host, window)

    Swag.assert(!window.searchGroup.isLocallyVisible() and window.searchBox.isHidden())
    Swag.assert(window.searchPrevious.isHidden() and window.searchNext.isHidden())
    Swag.assert(window.searchOptionsButton.isHidden())
    Swag.assert(!window.searchBox.hasFocus())

    window.openFile(viewerFixturePath().toString())
    completeQueuedViewerFile(&host, window)
    Swag.assert(window.searchGroup.isLocallyVisible() and window.searchBox.isVisible() and window.searchBox.isEnabled())
}

// File metadata can arrive after the first frame. Publishing it lays out the identity row
// immediately, without waiting for a resize, theme change, or another outer layout pass.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(ViewerMinWidth, 680)
    window.applyLayout()
    Swag.assert(window.infoNameLabel.position.width == 0 and window.infoSizeLabel.position.width == 0)

    window.currentFile     = viewerFixturePath()
    window.currentFileSize = "1.2 KiB"
    window.choices.add(ViewerPluginChoice{pluginIndex: 0, key: "html"})
    window.activeChoiceIndex = 0
    window.updateFileInfo("UTF-8 · streamed")

    Swag.assert((window.infoNameLabel.text()).count > 0 and (window.infoSizeLabel.text()).count > 0)
    Swag.assert(window.infoNameLabel.position.width > 0 and window.infoSizeLabel.position.width > 0)
    Swag.assert(window.infoNameLabel.position.width >= Math.ceil(window.infoNameLabel.itf.measureContent({}).x))
    Swag.assert(window.infoStatsLabel.position.width > 0)
    Swag.assert(window.infoStatsLabel.position.width >= Math.ceil(window.infoStatsLabel.itf.measureContent({}).x))
    Swag.assert(Math.abs(window.infoContentGroup.position.x + window.infoStatsLabel.position.right() - window.infoBar.paddedClientRect().right()) < 0.01)
    Swag.assert(window.infoIconLabel.position.right() <= window.infoNameLabel.position.x)
    Swag.assert(window.infoNameLabel.position.right() <= window.infoSizeLabel.position.x)

    // Fractional glyph extents vary with the name. Every short name receives the whole measured
    // line rather than occasionally losing its last glyph to the ellipsis.
    let shortNames: [6] string = ["a.txt", "ii.txt", "notes.txt", "readme.md", "small.json", "brief-source.swg"]
    for name in shortNames
    {
        window.currentFile = name
        window.updateFileInfo("UTF-8 · streamed")
        Swag.assert(window.infoNameLabel.position.width >= Math.ceil(window.infoNameLabel.itf.measureContent({}).x))
    }

    // General details end at the right edge of the band, which is what leaves them the whole
    // band to spend. Only a real shortage shrinks the line.
    let wideDetails = "3840 × 2160 · 120000 frames · 59.94 fps · 01:02:03 · AAC-LC · 48000 Hz · 6 channels · 24 bit · Swag CPU decoder"
    window.resize(1600, 680)
    window.currentFile = "clip.mp4"
    window.updateFileInfo(wideDetails)
    let wideClient      = window.infoBar.paddedClientRect()
    let wideFileWidth   = Math.ceil(window.infoFileGroup.itf.measureContent({wideClient.width, wideClient.height}).x)
    let wideDetailWidth = Math.ceil(window.infoStatsLabel.itf.measureContent({}).x)
    Swag.assert(wideFileWidth + wideDetailWidth <= wideClient.width)
    Swag.assert(window.infoStatsLabel.position.width >= wideDetailWidth)
    Swag.assert(Math.abs(window.infoContentGroup.position.x + window.infoStatsLabel.position.right() - wideClient.right()) < 0.01)
    Swag.assert(window.infoFileGroup.position.right() <= window.infoStatsLabel.position.x)

    window.resize(ViewerMinWidth, 680)
    window.currentFile = "a-very-long-file-name-that-needs-the-left-side-of-the-information-bar.mp4"
    window.updateFileInfo(wideDetails)
    let narrowClient      = window.infoBar.paddedClientRect()
    let narrowFileWidth   = Math.ceil(window.infoFileGroup.itf.measureContent({narrowClient.width, narrowClient.height}).x)
    let narrowDetailWidth = Math.ceil(window.infoStatsLabel.itf.measureContent({}).x)
    Swag.assert(narrowFileWidth + narrowDetailWidth > narrowClient.width)
    Swag.assert(window.infoStatsLabel.position.width < narrowDetailWidth)
    Swag.assert(Math.abs(window.infoContentGroup.position.x + window.infoStatsLabel.position.right() - narrowClient.right()) < 0.01)
    Swag.assert(window.infoFileGroup.position.right() <= window.infoStatsLabel.position.x)
}

// F11 preserves the exact window state around a content-only presentation. Moving at either
// screen edge reveals the corresponding chrome over the content without shrinking it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(viewerFixturePath(), remember: false)
    completeQueuedViewerFile(&host, window)
    window.setFilePanelVisible(true)
    let position = host.surface.position
    let flags    = host.surface.flags

    var key = KeyEvent{kind: .Pressed, key: .F11}
    window.sendEvent(&key)
    Swag.assert(window.fullScreen and window.fullScreenButton.isChecked)
    Swag.assert(host.surface.flags.has(.NoShadow) and host.surface.flags.has(.TopMost))
    Swag.assert(!host.surface.flags.has(.LargeCaption) and !host.surface.flags.has(.Border))
    Swag.assert(!window.commandBar.isLocallyVisible() and !window.infoBarHost.isLocallyVisible())
    Swag.assert(!window.viewerBar.isLocallyVisible() and !window.filePanelHost.isLocallyVisible())

    window.updateFullScreenChrome({10, 1})
    Swag.assert(window.commandBar.isLocallyVisible() and window.infoBarHost.isLocallyVisible())
    Swag.assert(!window.viewerBar.isLocallyVisible())
    window.updateFullScreenChrome({10, window.clientRect().height / 2})
    Swag.assert(!window.commandBar.isLocallyVisible() and !window.infoBarHost.isLocallyVisible())
    window.updateFullScreenChrome({10, window.clientRect().height - 1})
    Swag.assert(window.viewerBar.isLocallyVisible())

    window.setFullScreen(false)
    Swag.assert(!window.fullScreen and !window.fullScreenButton.isChecked)
    Swag.assert(host.surface.flags == flags and host.surface.position == position)
    Swag.assert(window.commandBar.isLocallyVisible() and window.infoBarHost.isLocallyVisible())
    Swag.assert(window.viewerBar.isLocallyVisible() and window.filePanelHost.isLocallyVisible())
}

// The framework owns one centered, themed presentation for every viewer decoder reason.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 420)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let view = ViewerErrorView.create(&host.root, "PNG chunk CRC does not match its payload")
    view.dockStyle = .Center
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)

    Swag.assert(view.iconLabel.icon.isValid())
    Swag.assert(view.iconLabel.iconColor == view.themeColors().error)
    Swag.assert(view.summaryLabel.text() == appStrings().ui_ViewerError)
    Swag.assert(view.reasonLabel.text() == "PNG chunk CRC does not match its payload")
    Swag.assert(Math.abs(view.iconLabel.position.center().x - view.position.center().x) <= 1)
    Testing.assertContentFits(view)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "error")
}

// A decoder error discovered after creation replaces the active viewer and its commands in place.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 420)
    defer host.shutdown()

    let index    = createViewerPluginRegistry()
    let window   = ViewerWindow.create(&host.surfaceWnd, #move index)
    let failed   = Wnd.create'Wnd(window)
    let commands = Wnd.create'Wnd(window.viewerBar)
    var retired: bool
    failed.userData = &retired
    window.choices.add(ViewerPluginChoice{pluginIndex: 0, key: "html"})
    window.instances.add(ViewerSession{view: failed, commands: commands, retire: &markTestViewerRetired})
    window.currentView       = failed
    window.currentCommands   = commands
    window.activeChoiceIndex = 0
    window.currentFile       = "sample.bin"

    reportViewerFailure(failed, "payload ends before its declared length")

    Swag.assert(retired and failed.isPendingDestroy and commands.isPendingDestroy)
    Swag.assert(window.currentCommands == null)
    Swag.assert(window.currentView != null and window.currentView != failed)
    Swag.assert(window.instances[0].failureReason == "payload ends before its declared length")
    let errorView = cast(*ViewerErrorView) window.currentView!
    Swag.assert(errorView.reasonLabel.text() == window.instances[0].failureReason.toString())
}

// Progressive content keeps streaming without covering useful output. A viewer asks for the
// shared wait presentation separately when it has nothing useful to show yet.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()

    let fileName = writeTempFile("html", cast(const [..] u8) "<p>ready</p>")
    defer discard catch File.delete(fileName.toString())

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.currentFile = fileName
    window.choices.add(ViewerPluginChoice{pluginIndex: 0, key: "html"})
    window.choices.add(ViewerPluginChoice{pluginIndex: 1, key: "code"})
    window.viewerCombo.addItem("First")
    window.viewerCombo.addItem("Second")
    window.instances.resize(2)

    let loading = Wnd.create'Wnd(window.documentPanel)
    var retired: bool
    loading.userData              = &retired
    window.instances[0].view      = loading
    window.instances[0].details   = "streamed"
    window.instances[0].isLoading = func(wnd)->bool { discard wnd; return true }
    window.instances[0].retire    = &markTestViewerRetired
    window.currentView            = loading
    window.activeChoiceIndex      = 0
    loading.setPosition({17, 83, 611, 391})

    reportViewerLoadingChanged(loading)
    Swag.assert(!window.loadingOverlay.isLocallyVisible() and window.loadingTimer != null)

    window.instances[0].needsLoadingOverlay = func(wnd)->bool { discard wnd; return true }
    reportViewerLoadingChanged(loading)
    Swag.assert(window.loadingOverlay.isLocallyVisible())
    Swag.assert(window.loadingOverlay.position == loading.position)
    Swag.assert(window.loadingOverlay.backgroundStyle == .Transparent)
    Swag.assert(window.loadingOverlay.wndFlags.has(.Disabled))
    Swag.assert(window.documentPanel.children.back() == window.loadingOverlay)
    Swag.assert(window.loadingOverlay.spinner.position.width == ViewerLoadingSpinnerSize and window.loadingOverlay.spinner.position.height == ViewerLoadingSpinnerSize)
    let spinnerSmall = viewerLoadingSpinnerGeometry(0)
    let spinnerLarge = viewerLoadingSpinnerGeometry(0.5)
    Swag.assert(spinnerSmall.radius == ViewerLoadingSpinnerMinRadius and spinnerLarge.radius == ViewerLoadingSpinnerMaxRadius)
    Swag.assert(spinnerSmall.sweep == ViewerLoadingSpinnerMinSweep and spinnerLarge.sweep == ViewerLoadingSpinnerMaxSweep)
    Swag.assert(spinnerLarge.radius > spinnerSmall.radius and spinnerLarge.sweep > spinnerSmall.sweep)
    let spinnerCenter = window.loadingOverlay.spinner.position.center()
    let overlayCenter = window.loadingOverlay.clientRect().center()
    Swag.assert(Math.abs(spinnerCenter.x - overlayCenter.x) <= 0.5 and Math.abs(spinnerCenter.y - overlayCenter.y) <= 0.5)
    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "loading")

    // A newly selected progressive viewer loads behind the preceding document. The activity
    // mark belongs over that preserved document until the replacement can publish its first frame.
    let outgoing = Wnd.create'Wnd(window)
    outgoing.setPosition({23, 71, 577, 363})
    window.outgoingView = outgoing
    window.currentView  = outgoing
    reportViewerLoadingChanged(loading)
    Swag.assert(window.loadingOverlay.isLocallyVisible() and window.loadingOverlay.position == outgoing.position)
    window.outgoingView = null
    window.currentView  = loading
    outgoing.destroy()

    window.instances[0].needsLoadingOverlay = null
    reportViewerLoadingChanged(loading)
    Swag.assert(!window.loadingOverlay.isLocallyVisible() and window.loadingTimer != null)
    Swag.assert(window.activateChoice(1))
    Swag.assert(retired and loading.isPendingDestroy)
    Swag.assert(window.instances[0].view == null)
    Swag.assert(window.currentView != null and window.currentView != loading)
    Swag.assert(window.instances[1].view == window.currentView)
    Swag.assert(!window.loadingOverlay.isLocallyVisible() and window.loadingTimer == null)
}

// File selection never waits for a viewer that needs another event-loop turn to retire. The
// generic host keeps the previous content visible, then opens the queued file on its timer.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    let old    = Wnd.create'Wnd(window)
    old.setPosition({19, 73, 617, 389})
    var retireCalls: u32
    old.userData = &retireCalls
    window.instances.add(ViewerSession{view: old, retire: &delayTestViewerRetirement})
    window.currentView       = old
    window.activeChoiceIndex = 0

    let fileName = viewerFixturePath()
    window.openFile(fileName, remember: false)
    Swag.assert(window.currentView == old and retireCalls == 0)
    Swag.assert(window.pendingFile == fileName and window.startupTimer != null)
    Swag.assert(window.loadingOverlay.isLocallyVisible() and window.loadingOverlay.position == old.position)

    host.fireTimer(window.startupTimer)
    Jobs.wait(&window.choiceLoad.job)
    host.fireTimer(window.startupTimer)
    Swag.assert(window.currentView == old and retireCalls == 1)
    Swag.assert(window.pendingFile == fileName and window.startupTimer != null)

    host.fireTimer(window.startupTimer)
    Swag.assert(retireCalls == 2 and old.isPendingDestroy)
    Swag.assert(window.currentView != null and window.currentView != old)
    Swag.assert(window.pendingFile.isEmpty() and window.startupTimer == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.currentView     = Wnd.create'Wnd(window)
    window.currentCommands = Wnd.create'Wnd(window.viewerBar)
    window.instances.resize(1)
    window.instances[0].view     = window.currentView
    window.instances[0].commands = window.currentCommands
    window.currentFile           = "sample.cpp"
    window.showEmpty(appStrings().ui_Unsupported)
    Swag.assert(window.currentView == null)
    Swag.assert(window.currentCommands == null)
    Swag.assert(window.instances.isEmpty())
    Swag.assert(window.currentFile.isEmpty())
    Swag.assert(window.infoNameLabel.name.raw.isEmpty())
    Swag.assert(window.infoNameLabel.position.width == 0 and window.infoStatsLabel.position.width == 0)
    Swag.assert(window.infoBarHost.isLocallyVisible() and !window.infoIconLabel.icon.isValid())
    Swag.assert(window.emptyView.isLocallyVisible() and window.documentHost.position.y >= window.infoBarHost.position.bottom())
}

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("scope_cached_view_%.txt", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    let source = "cached text"
    discard expect File.writeAllBytes(fileName, Swag.makeSlice(cast(const [*] u8) source.buffer, source.count))

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.surface!.setTitle(appStrings().ui_WindowTitle)
    window.openFile(fileName)
    completeQueuedViewerFile(&host, window)

    let textView = cast(*TextView) window.currentView!
    textView.setInitialFocus(textView.editor)
    Swag.assert(textView.editor.hasFocus())
    var comboPoint = window.viewerCombo.surfaceRect().center()
    window.viewerCombo.surface!.surfaceToScreen(&comboPoint)
    host.sendMouseEvent(window.viewerCombo, .Pressed, comboPoint, .Left, .None)
    Swag.assert(window.viewerCombo.hasFocus() and !window.viewerCombo.hasVisibleFocus())
    host.keyPress(Input.Key.Escape)
    Swag.assert(textView.editor.hasFocus())

    let cachedView     = window.currentView
    let cachedCommands = window.currentCommands
    let childCount     = window.children.count
    let commandCount   = window.viewerBar.children.count
    window.activeChoiceIndex = 1
    Swag.assert(window.activateChoice(0))
    Swag.assert(window.currentView == cachedView)
    Swag.assert(window.currentCommands == cachedCommands)
    Swag.assert(window.children.count == childCount)
    Swag.assert(window.viewerBar.children.count == commandCount)
    Swag.assert(window.surface!.wnd.name.raw == appStrings().ui_WindowTitle)
}

// Replacing a streaming document retires its short-period loader before deferred destruction.
// This is the path exercised by quickly moving from one file to the next in the sibling browser.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let firstFile     = Path.combine(tempDirectory.toString(), Format.toString("scope_switch_first_%.txt", Guid64.random()).toString())
    let secondFile    = Path.combine(tempDirectory.toString(), Format.toString("scope_switch_second_%.txt", Guid64.random()).toString())
    defer discard catch File.delete(firstFile)
    defer discard catch File.delete(secondFile)

    var source: String
    for 2_000 do
        source += "A streamed document keeps loading while another file is selected.\n"
    let bytes = Swag.makeSlice(cast(const [*] u8) source.buffer!, source.length)
    discard expect File.writeAllBytes(firstFile, bytes)
    discard expect File.writeAllBytes(secondFile, bytes)

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(firstFile)
    host.fireTimer(window.startupTimer)
    Jobs.wait(&window.choiceLoad.job)
    host.fireTimer(window.startupTimer)

    let discardedView  = cast(*TextView) window.currentView!
    let discardedTimer = discardedView.loadTimer!
    window.openFile(secondFile)
    host.fireTimer(window.startupTimer)
    Jobs.wait(&window.choiceLoad.job)
    host.fireTimer(window.startupTimer)

    Swag.assert(window.currentView != discardedView)

    // A test can keep the timer's address for identity after the host has reclaimed it. Firing
    // that stale address must be a no-op and, in particular, must never dereference its target.
    host.fireTimer(discardedTimer)
}

// Pins the shipped empty surface: one accent line, one compact command row, and no eager
// format-specific controls before a file has selected a viewer.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    window.applyLayout()
    host.settleAnimations(window, 4)

    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "surface")
}

// A desktop file lights the document target before it is released, then uses the usual queued
// opening path without keeping an acknowledgement on screen.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    let file   = viewerFixturePath()
    window.resize(960, 680)
    window.applyLayout()

    var point = window.documentPanel.surfaceRect().center()
    window.surface!.surfaceToScreen(&point)
    Swag.assert(host.dragFilesOver(point, [file.toString()]) == DropEffect.Copy)
    Swag.assert(window.dropHighlight.isLocallyVisible())
    Swag.assert(window.dropHighlight.parent == window.documentPanel)
    Swag.assert(window.dropHighlight.prompt.text() == appStrings().ui_DropTitle)
    Swag.assert(!window.dropHighlight.prompt.isLocallyVisible())
    Swag.assert(window.dropHighlight.wndFlags.has(.Disabled))
    Swag.assert(window.dropHighlight.clientRect().width == window.documentPanel.clientRect().width)
    Swag.assert(window.dropHighlight.clientRect().height == window.documentPanel.clientRect().height)
    Swag.assert(window.pendingFile.isEmpty() and window.startupTimer == null)

    host.cancelDrag()
    Swag.assert(!window.dropHighlight.isLocallyVisible())
    Swag.assert(window.pendingFile.isEmpty() and window.startupTimer == null)

    Swag.assert(host.dragFilesOver(point, [file.toString()]) == DropEffect.Copy)
    Swag.assert(window.dropHighlight.isLocallyVisible())

    window.applyLayout()
    Testing.assertContentFits(window)

    Swag.assert(host.dropFiles(point, [file.toString()]) == DropEffect.Copy)
    Swag.assert(!window.dropHighlight.isLocallyVisible())
    Swag.assert(window.pendingFile == file and window.startupTimer != null)
    completeQueuedViewerFile(&host, window)
    Swag.assert(window.currentFile == file)

    Swag.assert(host.dragFilesOver(point, [file.toString()]) == DropEffect.Copy)
    Swag.assert(window.dropHighlight.prompt.isLocallyVisible())
    host.cancelDrag()
}

// Pins the open-document composition in Swag dark and neutral light: global navigation and file
// identity stay above the document, while the active viewer owns the dedicated band below it.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.openFile(viewerFixturePath().toString())
    completeQueuedViewerFile(&host, window)
    window.applyLayout()
    host.settleAnimations(window, 4)

    Swag.assert(window.viewerCombo.isLocallyVisible())
    Swag.assert(window.openDefaultButton.isEnabled())
    Swag.assert(window.infoBarHost.isLocallyVisible() and !window.emptyView.isLocallyVisible())
    Swag.assert(window.infoIconLabel.icon.isValid())
    Swag.assert(window.infoIconLabel.position.right() <= window.infoNameLabel.position.x)
    Swag.assert(window.infoNameLabel.position.right() <= window.infoSizeLabel.position.x)
    Swag.assert(window.currentView!.parent == window.documentPanel)
    Swag.assert(window.currentCommands!.parent == window.viewerBar and window.viewerBar.isLocallyVisible())
    Swag.assert(window.currentCommands!.backgroundStyle == .Transparent)
    Swag.assert(window.searchBox.isLocallyVisible() and window.searchBox.isEnabled())
    var dark = host.render(window)
    assertViewerPanelCorner(&dark, window.documentPanel)
    Pixel.Testing.assertImageGolden(&dark, "viewer.dark")

    window.searchBox.setText("verification marker")
    completeViewerSearch(&host, window)
    discard host.render(window)
    host.fireTimers()
    window.searchOverlay.phase = 0.125
    var searchDark = host.render(window)
    Pixel.Testing.assertImageGolden(&searchDark, "search.dark")
    window.searchBox.setText("")

    window.applyTheme(cast(u32) AppearanceTheme.Light)
    host.notify(.ThemeChanged)
    host.settleAnimations(window, 4)
    var light = host.render(window)
    assertViewerPanelCorner(&light, window.documentPanel)
    Pixel.Testing.assertImageGolden(&light, "viewer.light")

    window.searchBox.setText("verification marker")
    completeViewerSearch(&host, window)
    discard host.render(window)
    host.fireTimers()
    window.searchOverlay.phase = 0.125
    var searchLight = host.render(window)
    Pixel.Testing.assertImageGolden(&searchLight, "search.light")
}

// The folder filter walks only the neighbours of the current file's kind: registered viewers
// group their extensions, and an unregistered kind groups by its extension alone.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory.toString(), Format.toString("scope_kind_%", Guid64.random()).toString())
    expect Directory.create(folder.toString())
    defer discard catch Directory.delete(folder.toString(), recurse: true)

    let names: [5] string = ["pic1.png", "pic2.jpg", "notes.txt", "more.txt", "readme.md"]
    for one in names do
        discard expect File.writeAllBytes(Path.combine(folder.toString(), one).toString(), cast(const [..] u8) "a readable line\n")

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.openFile(Path.combine(folder.toString(), "pic1.png").toString())
    completeQueuedViewerFile(&host, window)

    window.rebuildSiblings()
    Swag.assert(window.siblings.count == 5)

    // Pictures walk pictures: both image extensions belong to one registered viewer.
    window.setFolderSameKind(true)
    window.rebuildSiblings()
    Swag.assert(window.siblings.count == 2)
    window.navigate(1)
    completeQueuedViewerFile(&host, window)
    Swag.assert(Path.fileName(window.currentFile.toString()) == "pic2.jpg")
    window.navigate(1)
    completeQueuedViewerFile(&host, window)
    Swag.assert(Path.fileName(window.currentFile.toString()) == "pic1.png")

    // A kind nothing registers falls back to the extension.
    window.openFile(Path.combine(folder.toString(), "notes.txt").toString())
    completeQueuedViewerFile(&host, window)
    window.rebuildSiblings()
    Swag.assert(window.siblings.count == 2)

    window.setFolderSameKind(false)
    window.rebuildSiblings()
    Swag.assert(window.siblings.count == 5)

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
    loadViewerState(window, cast(const [..] u8) state.toString())
    Swag.assert(window.folderSameKind and window.searchMatchCaseOption and window.searchWholeWordOption and window.searchRegexOption)
}

// Bare arrows never navigate files globally. The image viewer is the one document type that
// deliberately owns that gesture and asks the host for its neighboring image.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory.toString(), Format.toString("scope_arrows_%", Guid64.random()).toString())
    expect Directory.create(folder.toString())
    defer discard catch Directory.delete(folder.toString(), recurse: true)

    discard expect File.writeAllBytes(Path.combine(folder.toString(), "t1.txt").toString(), cast(const [..] u8) "a readable line\n")
    discard expect File.writeAllBytes(Path.combine(folder.toString(), "t2.txt").toString(), cast(const [..] u8) "a readable line\n")
    let imageSource = expect File.readAllText(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/sample.svg"))
    let imageBytes  = Swag.makeSlice(cast(const [*] u8) imageSource.buffer!, imageSource.length)
    discard expect File.writeAllBytes(Path.combine(folder.toString(), "pic1.svg").toString(), imageBytes)
    discard expect File.writeAllBytes(Path.combine(folder.toString(), "pic2.svg").toString(), imageBytes)

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    // The text editor owns the caret keys: with the keyboard parked on a toolbar button, the
    // arrow reaches the editor instead of walking the folder, and the keyboard follows it.
    window.openFile(Path.combine(folder.toString(), "t1.txt").toString())
    completeQueuedViewerFile(&host, window)
    let textView = cast(*TextView) window.currentView!
    window.openButton.setFocus()
    Swag.assert(!textView.editor.hasFocus())
    host.keyPress(Input.Key.Right)
    Swag.assert(Path.fileName(window.currentFile.toString()) == "t1.txt")
    Swag.assert(textView.editor.hasFocus())

    // The same key does navigate once an image viewer explicitly owns it.
    window.openFile(Path.combine(folder.toString(), "pic1.svg").toString())
    completeQueuedViewerFile(&host, window)
    window.setFolderSameKind(true)
    window.openButton.setFocus()
    host.keyPress(Input.Key.Right)
    completeQueuedViewerFile(&host, window)
    Swag.assert(Path.fileName(window.currentFile.toString()) == "pic2.svg")
}
