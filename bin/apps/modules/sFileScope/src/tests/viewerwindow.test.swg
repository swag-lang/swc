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

func viewerFixturePath()->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/comprehensive.txt")
}

// A deliberately passive viewer used to exercise the application's file-navigation fallback.
func createPassiveTestViewer(request: const *ViewerRequest, result: *ViewerResult)
{
    result.view    = Wnd.create'Wnd(request.contentParent)
    result.details = "Passive test viewer"
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
    if window.startupTimer do
        host.fireTimer(window.startupTimer)
}

#test
{
    let executable         = Env.executablePath()
    let direct: [1] string = [executable]
    @assert(viewerStartupFile(direct).isEmpty())

    let withFile: [2] string = [executable, executable]
    @assert(viewerStartupFile(withFile) == executable)
}

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_text_stream_%.txt", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    let fixture = Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/comprehensive.txt")
    var source  = expect File.readAllText(fixture)
    for 2_000 do
        source += "A source line that stays readable while the rest remains on disk.\n"
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()
    let commands = Wnd.create'Wnd(&host.root, {0, 0, 200, 36})
    let view     = BasicTextView.create(&host.root, commands, fileName)
    view.resize(800, 520)
    view.applyLayout()

    let loaded = view.editor.text()
    @assert(@countof(loaded) <= 16 * 1024)
    @assert(view.stream.isOpen())
    @assert(expect view.stream.position() < view.fileSize)

    var image = host.render(view)
    view.updateEstimatedHeight()
    let loadedHeight = view.editor.loadedDocumentHeight()
    @assert(image.isValid() and loadedHeight > 0)
    @assert(view.editor.scrollableClientRect().height > loadedHeight)

    view.editor.setScrollPosition({0, loadedHeight * 2})
    let position = view.editor.scrollPosition()
    @assert(position.y > loadedHeight)
    view.loadNextChunk()
    @assert(view.editor.scrollPosition() == position)

    view.editor.setScrollPosition({0, 0})
    let beforeEnd = view.editor.scrollPosition()
    var end       = KeyEvent{kind: .Pressed, key: .End, modifiers: .Control}
    @assert(view.hookOnChildEvent!(view.editor, &end))
    discard host.render(view)
    @assert(view.editor.scrollPosition().y > beforeEnd.y)
}

func writeTempFile(suffix: string, bytes: const [..] u8)->String
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_%_%", Guid64.random(), suffix).toString())
    discard expect File.writeAllBytes(fileName.toString(), bytes)
    return fileName
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

    @assert(BasicTextView.supports(wideFile.toString()))
    let probed = BasicTextView.probe(wideFile.toString())
    @assert(probed.encoding == .Utf16Le and probed.contentStart == 2 and probed.accepted)

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()
    let commands = Wnd.create'Wnd(&host.root, {0, 0, 240, 36})
    let view     = BasicTextView.create(&host.root, commands, wideFile.toString())
    view.resize(800, 520)
    view.applyLayout()

    @assert(view.encoding == .Utf16Le)
    @assert(view.encodingName() == "UTF-16 LE")
    @assert(view.editor.text() == "Hello, wide world")
    @assert(view.encodingCombo.selectedIndex == 1)
}

// A single-byte page has no mark to announce it, and every byte decodes, so the accented byte is
// what the reader is shown rather than a fallback to bytes.
#test
{
    let latin: [11] u8 = ['c', 'a', 'f', 0xE9, ' ', 'n', 'a', 0xEF, 'v', 'e', '\n']
    let file           = writeTempFile("cp1252.txt", latin)
    defer discard catch File.delete(file.toString())

    @assert(BasicTextView.probe(file.toString()).encoding == .Windows1252)

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()
    let commands = Wnd.create'Wnd(&host.root, {0, 0, 240, 36})
    let view     = BasicTextView.create(&host.root, commands, file.toString())
    view.resize(800, 520)
    view.applyLayout()
    @assert(view.editor.text() == "café naïve\n")

    // A reader who disagrees with the detection corrects it, and the same bytes read differently.
    view.applyEncoding(.Utf16Le)
    @assert(view.encoding == .Utf16Le)
    @assert(view.editor.text() != "café naïve\n")
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
    let commands = Wnd.create'Wnd(&host.root, {0, 0, 240, 36})
    let view     = BasicTextView.create(&host.root, commands, file.toString())
    view.resize(800, 520)
    view.applyLayout()

    @assert(view.encoding == .Utf8 and view.loadTimer != null)
    host.fireTimer(view.loadTimer)
    @assert(view.encoding == .Windows1252)
    @assert(Utf8.endsWith(view.editor.text(), "é\n"))
    @assert(!Utf8.contains(view.editor.text(), appStrings().ui_NotText))
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
    @assert(!BasicTextView.supports(file.toString()))
}

// The panel lists what is beside the current file and what was read before it, and a row opens
// its file without the window being rebuilt.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_panel_%", Guid64.random()).toString())
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
    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.openFile(names[0].toString())

    @assert(!window.panelVisible and !window.filePanel.isLocallyVisible())
    window.toggleFilePanel()
    @assert(window.panelVisible and window.filePanel.isLocallyVisible())
    @assert(window.filesButton.isChecked)
    @assert(window.filePanel.position.width == ViewerPanelWidth)
    @assert(window.filePanel.minSize.x == ViewerPanelWidth and window.filePanel.maxSize.x == ViewerPanelWidth)
    @assert(window.filePanel.isVertical() and window.filePanel.items.count == 2)
    @assert(window.filePanel.items[0]!.minimumSize == ViewerPaneMinSize)
    @assert(window.recentList.listFlags.has(.Ellipsis) and window.folderList.listFlags.has(.Ellipsis))
    @assert(window.recentList.scrollWnd.flags.has(.DisableHorizontal) and window.folderList.scrollWnd.flags.has(.DisableHorizontal))
    @assert(window.folderList.lineCount() == 3)
    @assert(window.recentList.lineCount() == 1)

    // Choosing a sibling opens it, and the recent list grows by exactly that file.
    window.folderList.selectLine(2)
    completeQueuedViewerFile(&host, window)
    @assert(window.currentFile == names[2])
    @assert(window.recent.count == 2 and window.recent[0] == names[2])

    // A recent row keeps the list under the pointer stable while it opens its file.
    window.recentList.selectLine(1)
    completeQueuedViewerFile(&host, window)
    @assert(window.currentFile == names[0])
    @assert(window.recent.count == 2 and window.recent[0] == names[2] and window.recent[1] == names[0])

    window.setFilePanelVisible(false)
    @assert(!window.filesButton.isChecked)
    window.setFilePanelVisible(true)

    window.filePanel.setPaneSize(0, 120)
    let state = saveViewerState(window)
    window.recent.clear()
    window.filePanel.setPaneSize(0, 180)
    window.setFilePanelVisible(false)
    loadViewerState(window, state.toSlice())
    @assert(window.recent.count == 2 and window.panelVisible)
    @assert(window.recentPaneSize == 120 and window.filePanel.items[0]!.size == 120)
}

// Rebuilding the lists after a recent-file choice keeps the viewport under the pointer, and the
// folder pane continues to own file names rather than borrowing document text.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_recent_scroll_%", Guid64.random()).toString())
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
    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.openFile(names[0].toString())
    window.recent.clear()
    for name in names do
        window.recent.add(name[])
    window.setFilePanelVisible(true)
    window.applyLayout()

    window.recentList.scrollWnd.setScrollPos(0, 80)
    let before = window.recentList.scrollWnd.scrollPosition()
    @assert(before.y > 0)
    window.recentList.selectLine(8)
    completeQueuedViewerFile(&host, window)
    @assert(window.currentFile == names[8])
    @assert(window.recentList.scrollWnd.scrollPosition() == before)

    for i in window.folderList.lineCount()
    {
        let label = window.folderList.lineAt(i)!.itemAt(0).name.raw
        @assert(Utf8.startsWith(label, "file") and Utf8.endsWith(label, ".txt"))
        @assert(!Utf8.contains(label, "document text"))
    }
}

// The panel opens before any file has been read: there is no folder to name, so the section keeps
// its own title and both lists stay empty.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    @assert(window.currentFile.isEmpty())
    window.setFilePanelVisible(true)
    @assert(window.panelVisible and window.filePanel.isLocallyVisible())
    @assert(window.folderList.lineCount() == 0 and window.recentList.lineCount() == 0)
    @assert(!window.filePanel.isPaneVisible(0) and !window.recentPane.isLocallyVisible())
    @assert(window.folderLabel.text() == appStrings().ui_Folder)
}

// The history is a list the reader owns: one file leaves it, or all of them do, and the section
// closes itself once it has nothing left to offer.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_history_%", Guid64.random()).toString())
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
    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    for one in names do
        window.openFile(one[].toString())
    window.setFilePanelVisible(true)
    @assert(window.recent.count == 3 and window.recentList.lineCount() == 3)

    // The most recent file is at the head, and forgetting one leaves the others in their order.
    window.forgetRecent(names[2].toString())
    @assert(window.recent.count == 2 and window.recentList.lineCount() == 2)
    @assert(window.recent[0] == names[1] and window.recent[1] == names[0])

    // Forgetting what the history does not hold changes nothing, and the file stays open.
    window.forgetRecent(Path.combine(folder.toString(), "absent.txt").toString())
    @assert(window.recent.count == 2 and window.currentFile == names[2])

    window.clearRecent()
    @assert(window.recent.isEmpty() and window.recentList.lineCount() == 0)
    @assert(!window.filePanel.isPaneVisible(0) and !window.recentPane.isLocallyVisible())
    @assert(window.currentFile == names[2] and window.folderList.lineCount() == 3)
}

// The history row menu offers what that file can do, and the two entries only the history can
// answer for take one file out of the list, then all of them.
//
// The folder list is not a list the reader owns, so the same menu there stops at the actions that
// do not touch the history.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_menu_%", Guid64.random()).toString())
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
    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    for one in names do
        window.openFile(one[].toString())
    window.setFilePanelVisible(true)
    window.applyLayout()

    let list = window.recentList
    @assert(list.lineCount() == 3)

    // The row naming the file read before the one that is open, which the panel opens on its own
    // when it is picked: what the menu acts on is the row, not the document.
    list.selectLine(1)
    completeQueuedViewerFile(&host, window)
    @assert(window.currentFile == names[1])

    host.clickPopupMenuItemWhenShown("sFileScope.file.forget")
    window.showFileMenu(list, window.recent.toSlice(), {120, 120})
    host.pump()
    @assert(host.autoHandled)
    @assert(window.recent.count == 2 and window.recent[0] == names[2] and window.recent[1] == names[0])
    @assert(list.lineCount() == 2 and window.currentFile == names[1])

    // A folder row names a file the folder holds, and nothing offers to take it out of a list it
    // was never in: the armed step finds no such entry and dismisses the menu instead.
    window.folderList.selectLine(0)
    completeQueuedViewerFile(&host, window)
    host.clickPopupMenuItemWhenShown("sFileScope.file.forget", maxFrames: 4)
    window.showFileMenu(window.folderList, window.siblings.toSlice(), {120, 120})
    host.pump()
    @assert(!host.autoHandled)

    list.selectLine(0)
    completeQueuedViewerFile(&host, window)
    host.clickPopupMenuItemWhenShown("sFileScope.file.clearHistory")
    window.showFileMenu(list, window.recent.toSlice(), {120, 120})
    host.pump()
    @assert(host.autoHandled)
    @assert(window.recent.isEmpty() and list.lineCount() == 0)
    @assert(!window.filePanel.isPaneVisible(0))
    @assert(window.folderList.lineCount() == 3)
}

// The viewer a reader picks for one file becomes the viewer that kind of file opens in, and
// choosing the ordinary one back is the removal of that decision rather than one more.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_preferred_%", Guid64.random()).toString())
    expect Directory.create(folder.toString())
    defer discard catch Directory.delete(folder.toString(), recurse: true)

    let first  = Path.combine(folder.toString(), "notes.txt")
    let second = Path.combine(folder.toString(), "other.txt")
    for one in [first, second] do
        discard expect File.writeAllBytes(one[].toString(), cast(const [..] u8) "a readable line\n")

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    window.openFile(first.toString())
    @assert(window.choices.count == 2 and window.choices[0].key == BasicTextViewerKey)
    @assert(window.activeChoiceIndex == 0 and window.preferences.isEmpty())

    // Every entry of the selector says which viewer it is before its name is read.
    @assert(window.viewerCombo.items.count == window.choices.count)
    for item in window.viewerCombo.items do
        @assert(item!.icon.isValid())

    window.selectViewer(1)
    @assert(window.choices[window.activeChoiceIndex].key == "hex")
    @assert(window.preferences.count == 1 and window.preferences[0].kind == BasicTextViewerKey and window.preferences[0].viewer == "hex")

    // The next file of the same kind opens where the reader left the previous one.
    window.openFile(second.toString())
    @assert(window.choices[window.activeChoiceIndex].key == "hex")

    // The decision crosses a session with the other panel choices.
    let state = saveViewerState(window)
    window.preferences.clear()
    loadViewerState(window, state.toSlice())
    @assert(window.preferences.count == 1 and window.preferences[0].viewer == "hex")

    window.selectViewer(0)
    @assert(window.preferences.isEmpty())
    window.openFile(first.toString())
    @assert(window.choices[window.activeChoiceIndex].key == BasicTextViewerKey)
}

// Pins the file panel: two named sections share the left edge, the row naming the open file is
// the selected one, and the document keeps the rest of the surface.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory.toString(), "sfilescope_panel_golden")
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

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.openFile(Path.combine(folder.toString(), "notes.txt").toString())
    window.toggleFilePanel()
    window.applyLayout()
    host.settleAnimations(window, 4)

    @assert(window.folderList.lineCount() == 4)
    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "sfilescope.panel")
    Testing.assertContentFits(window)
}

// Keeps the virtual document extent monotonic while several large-file chunks arrive between
// paints, and exercises complete keyboard navigation through the real focused editor.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_large_scroll_%.txt", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String
    for 70_000 do
        source += "A large source line keeps the virtual scrollbar stable between frames.\n"
    @assert(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()
    let commands = Wnd.create'Wnd(&host.root, {0, 0, 200, 36})
    let view     = BasicTextView.create(&host.root, commands, fileName)
    view.resize(800, 520)
    view.applyLayout()
    discard host.render(view)
    view.updateEstimatedHeight()

    view.setInitialFocus(view.editor)
    @assert(view.editor.hasFocus())
    host.keyPress(Input.Key.Down)
    @assert(view.editor.selectionEnd().lineIndex == 1)
    host.keyPress(Input.Key.Up)
    @assert(view.editor.selectionEnd().lineIndex == 0)
    host.keyPress(Input.Key.PageDown)
    let pageLine = view.editor.selectionEnd().lineIndex
    @assert(pageLine > 1)
    host.keyPress(Input.Key.PageUp)
    @assert(view.editor.selectionEnd().lineIndex < pageLine)

    let firstVirtualHeight = view.virtualHeight
    @assert(firstVirtualHeight > view.editor.paddedClientRect().height)
    for 8
    {
        view.loadNextChunk()
        @assert(view.virtualHeight >= firstVirtualHeight)
        @assert(view.editor.scrollableClientRect().height >= firstVirtualHeight)
    }

    host.keyPress(Input.Key.End)
    discard host.render(view)
    @assert(view.residentStart > 0)
    @assert(view.editor.scrollPosition().y > 0)
    host.keyPress(Input.Key.Home)
    discard host.render(view)
    @assert(view.residentStart == 0)
    @assert(view.editor.selectionEnd().lineIndex == 0)
    @assert(view.editor.scrollPosition().y == 0)
}

// The global palette choice crosses the same state boundary as the surface placement.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.applyTheme(1)
    host.notify(.ThemeChanged)
    @assert(window.themeIndex == 1)
    @assert(host.app.theme.colors.view_Bk == 0xFFFFFFFF)
    @assert(window.themeColors().view_Bk == 0xFFFFFFFF)

    let state = saveViewerState(window)
    window.applyTheme(0)
    loadViewerState(window, state.toSlice())
    window.applyTheme(window.themeIndex)
    host.notify(.ThemeChanged)
    @assert(window.themeIndex == 1 and host.app.theme.colors.view_Bk == 0xFFFFFFFF)
    @assert(window.themeColors().view_Bk == 0xFFFFFFFF)
}

// The caption appearance action reaches the standard application about dialog.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    @assert(!window.appearanceButton.sigAboutRequested.isEmpty())
    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    window.showAbout()
    host.pump()

    @assert(host.autoHandled)
    @assert(host.openedSurfaceCount() == 0)
}

// Finds a match split across scanner chunks in a multi-megabyte file and materializes it in the
// resident text window without losing the virtual scroll range.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_large_search_%.txt", Guid64.random()).toString())
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
    @assert(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()
    var index: ViewerIndex
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(fileName)
    window.searchBox.setText(query)
    window.findNext()

    var steps = 0'u32
    while window.searchTimer and steps < 32
    {
        host.fireTimer(window.searchTimer)
        steps += 1
    }

    @assert(window.searchTimer == null)
    @assert(window.searchMatch == target)
    let textView = cast(*BasicTextView) window.currentView!
    @assert(textView.editor.selectedText() == query)
    @assert(textView.bytesRead < textView.fileSize)
    discard host.render(textView)
    textView.updateEstimatedHeight()
    @assert(textView.editor.scrollableClientRect().height > textView.editor.paddedClientRect().height)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    host.app.theme.setSwagDark()
    host.app.notifyThemeChanged()

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.applyLayout()

    @assert(window.commandBar.position.height == ViewerBarHeight)
    @assert(window.viewerCombo.parent == window.commandBar)
    @assert(window.appearanceButton.parent == &host.surfaceWnd)
    @assert(window.searchBox.parent == window.commandBar)
    @assert(window.fullScreenButton.parent == window.commandBar)
    @assert(window.fullScreenButton.flags.has(.Toggle) and window.fullScreenButton.checkIndicator == .Frame)
    @assert(window.searchBox.isLocallyVisible() and !window.searchBox.isEnabled())
    @assert(window.infoBar.position.height == ViewerInfoHeight)
    @assert(window.infoBar.dockStyle == .Top)
    @assert(window.infoBar.backgroundStyle == window.backgroundStyle)
    @assert(!window.infoBar.isLocallyVisible())
    @assert(window.viewerBar.dockStyle == .Bottom and !window.viewerBar.isLocallyVisible())
    @assert(window.openButton.position.x < window.previousButton.position.x)
    @assert(window.openButton.position.x < window.searchBox.position.x)
    @assert(window.searchBox.position.x < window.previousButton.position.x)
    @assert(window.previousButton.position.x < window.nextButton.position.x)
    @assert(window.infoNameLabel.name.raw.isEmpty())
    @assert(window.surface!.minSize.x == ViewerMinWidth)
    @assert(Utf8.contains(window.emptyLabel.name.raw, appStrings().ui_DropTitle))
    @assert(window.emptyView.isLocallyVisible() and window.emptyIconLabel.icon.isValid())
    @assert(window.emptyHintLabel.text() == appStrings().ui_DropHint)
    @assert(!window.previousButton.isEnabled())
    @assert(!window.nextButton.isEnabled())
    @assert(window.currentView == null)
    @assert(window.currentCommands == null)
    @assert(window.filesButton.flags.has(.Toggle) and window.filesButton.checkIndicator == .Frame)
    @assert(!window.filesButton.isChecked and !window.loadingOverlay.isLocallyVisible())
    @assert(!window.viewerCombo.isLocallyVisible())
    @assert(window.infoNameLabel.parent == window.infoFileGroup)
    @assert(window.infoSizeLabel.parent == window.infoFileGroup)
    @assert(window.infoStatsLabel.parent == window.infoBar)
    Testing.assertContentFits(window)

    // Viewer tools have their own full-width band and cannot collide with the global selector.
    window.resize(ViewerMinWidth, 680)
    window.viewerCombo.show()
    let widestCommands = Wnd.create'Wnd(window.viewerBar, {0, 0, 0, 36})
    widestCommands.dockStyle = .Center
    window.infoBar.show()
    window.viewerBar.show()
    window.applyLayout()
    @assert(window.viewerCombo.parent == window.commandBar and widestCommands.parent == window.viewerBar)
    @assert(window.viewerCombo.position.bottom() <= window.infoBar.position.y)
    @assert(widestCommands.position.y >= window.viewerBar.clientRect().y)
}

// F11 preserves the exact window state around a content-only presentation. Moving at either
// screen edge reveals the corresponding chrome over the content without shrinking it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index    = createViewerIndex()
    let window   = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(viewerFixturePath(), remember: false)
    window.setFilePanelVisible(true)
    let position = host.surface.position
    let flags    = host.surface.flags

    var key = KeyEvent{kind: .Pressed, key: .F11}
    window.sendEvent(&key)
    @assert(window.fullScreen and window.fullScreenButton.isChecked)
    @assert(host.surface.flags.has(.NoShadow) and host.surface.flags.has(.TopMost))
    @assert(!host.surface.flags.has(.LargeCaption) and !host.surface.flags.has(.Border))
    @assert(!window.commandBar.isLocallyVisible() and !window.infoBar.isLocallyVisible())
    @assert(!window.viewerBar.isLocallyVisible() and !window.filePanel.isLocallyVisible())

    window.updateFullScreenChrome({10, 1})
    @assert(window.commandBar.isLocallyVisible() and window.infoBar.isLocallyVisible())
    @assert(!window.viewerBar.isLocallyVisible())
    window.updateFullScreenChrome({10, window.clientRect().height / 2})
    @assert(!window.commandBar.isLocallyVisible() and !window.infoBar.isLocallyVisible())
    window.updateFullScreenChrome({10, window.clientRect().height - 1})
    @assert(window.viewerBar.isLocallyVisible())

    window.setFullScreen(false)
    @assert(!window.fullScreen and !window.fullScreenButton.isChecked)
    @assert(host.surface.flags == flags and host.surface.position == position)
    @assert(window.commandBar.isLocallyVisible() and window.infoBar.isLocallyVisible())
    @assert(window.viewerBar.isLocallyVisible() and window.filePanel.isLocallyVisible())
}

// The framework owns one centered, themed presentation for every viewer decoder reason.
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

    @assert(view.iconLabel.icon.isValid())
    @assert(view.iconLabel.iconColor == view.themeColors().error)
    @assert(view.summaryLabel.text() == appStrings().ui_ViewerError)
    @assert(view.reasonLabel.text() == "PNG chunk CRC does not match its payload")
    @assert(Math.abs(view.iconLabel.position.center().x - view.position.center().x) <= 1)
    Testing.assertContentFits(view)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "sfilescope.error")
}

// A decoder error discovered after creation replaces the active viewer and its commands in place.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 420)
    defer host.shutdown()

    let index    = createViewerIndex()
    let window   = ViewerWindow.create(&host.surfaceWnd, #move index)
    let failed   = Wnd.create'Wnd(window)
    let commands = Wnd.create'Wnd(window.viewerBar)
    var retired: bool
    failed.userData = &retired
    window.choices.add(ViewerChoice{.Viewer, 0, "Decoder"})
    window.instances.add(ViewerInstance{view: failed, commands: commands, retire: &markTestViewerRetired})
    window.currentView       = failed
    window.currentCommands   = commands
    window.activeChoiceIndex = 0
    window.currentFile       = "sample.bin"

    reportViewerFailure(failed, "payload ends before its declared length")

    @assert(retired and failed.isPendingDestroy and commands.isPendingDestroy)
    @assert(window.currentCommands == null)
    @assert(window.currentView != null and window.currentView != failed)
    @assert(window.instances[0].failureReason == "payload ends before its declared length")
    let errorView = cast(*ViewerErrorView) window.currentView!
    @assert(errorView.reasonLabel.text() == window.instances[0].failureReason.toString())
}

// The host shows progressive work and retires a still-loading renderer before switching views,
// so a hidden HTML document cannot keep parsing while its source view opens.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()

    let fileName = writeTempFile("html", cast(const [..] u8) "<p>ready</p>")
    defer discard catch File.delete(fileName.toString())

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.currentFile = fileName
    window.choices.add(ViewerChoice{.BasicText, Swag.U64.Max, "First"})
    window.choices.add(ViewerChoice{.BasicText, Swag.U64.Max, "Second"})
    window.viewerCombo.addItem("First")
    window.viewerCombo.addItem("Second")
    window.instances.resize(2)

    let loading = Wnd.create'Wnd(window)
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
    @assert(window.loadingOverlay.isLocallyVisible() and window.loadingTimer != null)
    @assert(window.loadingOverlay.position == loading.position)
    @assert(window.loadingOverlay.backgroundStyle == .Transparent)
    @assert(window.loadingOverlay.spinner.preferredSize == {24, 24})
    let spinnerCenter = window.loadingOverlay.spinner.position.center()
    let overlayCenter = window.loadingOverlay.clientRect().center()
    @assert(Math.abs(spinnerCenter.x - overlayCenter.x) <= 1 and Math.abs(spinnerCenter.y - overlayCenter.y) <= 1)
    @assert(window.children.back() == window.loadingOverlay)
    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "sfilescope.loading")
    @assert(window.activateChoice(1))
    @assert(retired and loading.isPendingDestroy)
    @assert(window.instances[0].view == null)
    @assert(window.currentView != null and window.currentView != loading)
    @assert(window.instances[1].view == window.currentView)
    @assert(!window.loadingOverlay.isLocallyVisible() and window.loadingTimer == null)
}

// File selection never waits for a viewer that needs another event-loop turn to retire. The
// generic host keeps the previous content covered, then opens the queued file on its timer.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    let old    = Wnd.create'Wnd(window)
    var retireCalls: u32
    old.userData = &retireCalls
    window.instances.add(ViewerInstance{view: old, retire: &delayTestViewerRetirement})
    window.currentView       = old
    window.activeChoiceIndex = 0

    let fileName = viewerFixturePath()
    window.openFile(fileName, remember: false)
    @assert(window.currentView == old and retireCalls == 1)
    @assert(window.pendingFile == fileName and window.startupTimer != null)
    @assert(window.loadingOverlay.isLocallyVisible())

    host.fireTimer(window.startupTimer)
    @assert(retireCalls == 2 and old.isPendingDestroy)
    @assert(window.currentView != null and window.currentView != old)
    @assert(window.pendingFile.isEmpty() and window.startupTimer == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.currentView     = Wnd.create'Wnd(window)
    window.currentCommands = Wnd.create'Wnd(window.viewerBar)
    window.instances.resize(1)
    window.instances[0].view     = window.currentView
    window.instances[0].commands = window.currentCommands
    window.currentFile           = "sample.cpp"
    window.previousButton.enable(true)
    window.nextButton.enable(true)

    window.showEmpty(appStrings().ui_Unsupported)
    @assert(window.currentView == null)
    @assert(window.currentCommands == null)
    @assert(window.instances.isEmpty())
    @assert(window.currentFile.isEmpty())
    @assert(!window.previousButton.isEnabled() and !window.nextButton.isEnabled())
    @assert(window.infoNameLabel.name.raw.isEmpty())
    @assert(!window.infoBar.isLocallyVisible() and window.emptyView.isLocallyVisible())
}

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_cached_view_%.txt", Guid64.random()).toString())
    defer discard catch File.delete(fileName)
    let source = "cached text"
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) @dataof(source), @countof(source)))

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.surface!.setTitle(appStrings().ui_WindowTitle)
    window.openFile(fileName)

    let textView = cast(*BasicTextView) window.currentView!
    textView.setInitialFocus(textView.editor)
    @assert(textView.editor.hasFocus())
    var comboPoint = window.viewerCombo.surfaceRect().center()
    window.viewerCombo.surface!.surfaceToScreen(&comboPoint)
    host.sendMouseEvent(window.viewerCombo, .Pressed, comboPoint, .Left, .None)
    @assert(window.viewerCombo.hasFocus() and !window.viewerCombo.hasVisibleFocus())
    host.keyPress(Input.Key.Escape)
    @assert(textView.editor.hasFocus())

    let cachedView     = window.currentView
    let cachedCommands = window.currentCommands
    let childCount     = window.children.count
    let commandCount   = window.viewerBar.children.count
    window.activeChoiceIndex = 1
    @assert(window.activateChoice(0))
    @assert(window.currentView == cachedView)
    @assert(window.currentCommands == cachedCommands)
    @assert(window.children.count == childCount)
    @assert(window.viewerBar.children.count == commandCount)
    @assert(window.surface!.wnd.name.raw == appStrings().ui_WindowTitle)
}

// Replacing a streaming document retires its short-period loader before deferred destruction.
// This is the path exercised by quickly moving from one file to the next in the sibling browser.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let firstFile     = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_switch_first_%.txt", Guid64.random()).toString())
    let secondFile    = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_switch_second_%.txt", Guid64.random()).toString())
    defer discard catch File.delete(firstFile)
    defer discard catch File.delete(secondFile)

    var source: String
    for 2_000 do
        source += "A streamed document keeps loading while another file is selected.\n"
    let bytes = @mkslice(cast(const [*] u8) source.buffer!, source.length)
    discard expect File.writeAllBytes(firstFile, bytes)
    discard expect File.writeAllBytes(secondFile, bytes)

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(firstFile)

    let discardedView  = cast(*BasicTextView) window.currentView!
    let discardedTimer = discardedView.loadTimer!
    window.openFile(secondFile)

    @assert(discardedView.isPendingDestroy)
    @assert(window.currentView != discardedView)
    host.fireTimer(discardedTimer)
    @assert(discardedView.loadTimer == discardedTimer)
    host.pumpTimerQueues()
}

// Pins the shipped empty surface: one accent line, one compact command row, and no eager
// format-specific controls before a file has selected a viewer.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    window.applyLayout()
    host.settleAnimations(window, 4)

    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "sfilescope.surface")
}

// Pins the open-document composition in both application palettes: global navigation and file
// identity stay above the document, while the active viewer owns the dedicated band below it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.openFile(viewerFixturePath().toString())
    window.applyLayout()
    host.settleAnimations(window, 4)

    @assert(window.viewerCombo.isLocallyVisible())
    @assert(window.infoBar.isLocallyVisible() and !window.emptyView.isLocallyVisible())
    @assert(window.infoIconLabel.icon.isValid())
    @assert(window.currentCommands!.parent == window.viewerBar and window.viewerBar.isLocallyVisible())
    @assert(window.searchBox.isLocallyVisible() and window.searchBox.isEnabled())
    var dark = host.render(window)
    Pixel.Testing.assertImageGolden(&dark, "sfilescope.viewer.dark")

    window.applyTheme(1)
    host.notify(.ThemeChanged)
    host.settleAnimations(window, 4)
    var light = host.render(window)
    Pixel.Testing.assertImageGolden(&light, "sfilescope.viewer.light")
}

// The folder filter walks only the neighbours of the current file's kind: registered viewers
// group their extensions, and an unregistered kind groups by its extension alone.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_kind_%", Guid64.random()).toString())
    expect Directory.create(folder.toString())
    defer discard catch Directory.delete(folder.toString(), recurse: true)

    let names: [5] string = ["pic1.png", "pic2.jpg", "notes.txt", "more.txt", "readme.md"]
    for one in names do
        discard expect File.writeAllBytes(Path.combine(folder.toString(), one).toString(), cast(const [..] u8) "a readable line\n")

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.openFile(Path.combine(folder.toString(), "pic1.png").toString())

    window.rebuildSiblings()
    @assert(window.siblings.count == 5)

    // Pictures walk pictures: both image extensions belong to one registered viewer.
    window.setFolderSameKind(true)
    window.rebuildSiblings()
    @assert(window.siblings.count == 2)
    window.navigate(1)
    completeQueuedViewerFile(&host, window)
    @assert(Path.fileName(window.currentFile.toString()) == "pic2.jpg")
    window.navigate(1)
    completeQueuedViewerFile(&host, window)
    @assert(Path.fileName(window.currentFile.toString()) == "pic1.png")

    // A kind nothing registers falls back to the extension.
    window.openFile(Path.combine(folder.toString(), "notes.txt").toString())
    window.rebuildSiblings()
    @assert(window.siblings.count == 2)

    window.setFolderSameKind(false)
    window.rebuildSiblings()
    @assert(window.siblings.count == 5)

    // The choice survives a session like the other panel decisions.
    window.setFolderSameKind(true)
    let state = saveViewerState(window)
    window.setFolderSameKind(false)
    loadViewerState(window, cast(const [..] u8) state.toString())
    @assert(window.folderSameKind)
}

// A bare arrow gives the active viewer the first say, wherever the focus sits; only a viewer
// that declines the key changes the file.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_arrows_%", Guid64.random()).toString())
    expect Directory.create(folder.toString())
    defer discard catch Directory.delete(folder.toString(), recurse: true)

    var opaque: Array'u8
    for value in 64 do
        opaque.add(cast(u8) value)
    discard expect File.writeAllBytes(Path.combine(folder.toString(), "raw1.bin").toString(), opaque.toSlice())
    discard expect File.writeAllBytes(Path.combine(folder.toString(), "raw2.bin").toString(), opaque.toSlice())
    discard expect File.writeAllBytes(Path.combine(folder.toString(), "t1.txt").toString(), cast(const [..] u8) "a readable line\n")
    discard expect File.writeAllBytes(Path.combine(folder.toString(), "t2.txt").toString(), cast(const [..] u8) "a readable line\n")

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    var index:   ViewerIndex
    var passive: ViewerSpec
    passive.displayName = "Passive"
    passive.create      = &createPassiveTestViewer
    passive.extensions.add("*")
    index.specs.add(#move passive)
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    // The text editor owns the caret keys: with the keyboard parked on a toolbar button, the
    // arrow reaches the editor instead of walking the folder, and the keyboard follows it.
    window.openFile(Path.combine(folder.toString(), "t1.txt").toString())
    let textView = cast(*BasicTextView) window.currentView!
    window.openButton.setFocus()
    @assert(!textView.editor.hasFocus())
    host.keyPress(Input.Key.Right)
    @assert(Path.fileName(window.currentFile.toString()) == "t1.txt")
    @assert(textView.editor.hasFocus())

    // A view with no use for the arrows lets them walk the folder, from wherever the focus is.
    window.openFile(Path.combine(folder.toString(), "raw1.bin").toString())
    window.openButton.setFocus()
    host.keyPress(Input.Key.Right)
    completeQueuedViewerFile(&host, window)
    @assert(Path.fileName(window.currentFile.toString()) == "raw2.bin")
}
