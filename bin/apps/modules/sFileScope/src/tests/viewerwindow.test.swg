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

func completeViewerSearch(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    var steps = 0'u32
    while window.searchTimer and steps < 128
    {
        host.fireTimer(window.searchTimer)
        steps += 1
    }

    @assert(window.searchTimer == null)
}

#test
{
    const Source = "Cat catalog cat catapult\ncat"
    var matches: Array'ViewerSearchMatch
    collectViewerTextMatches(Source, "cat", {}, 0, 0, 0, &matches)
    @assert(matches.count == 5)

    matches.clear()
    collectViewerTextMatches(Source, "cat", {wholeWord: true}, 0, 0, 0, &matches)
    @assert(matches.count == 3 and matches[0].offset == 0 and matches[1].offset == 12 and matches[2].offset == 25)

    matches.clear()
    collectViewerTextMatches(Source, "cat", {matchCase: true, wholeWord: true}, 0, 0, 0, &matches)
    @assert(matches.count == 2 and matches[0].offset == 12 and matches[1].offset == 25)
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

func assertFolderFiles(window: *ViewerWindow, names: const [..] String)
{
    @assert(window.folderFiles.count == @countof(names) and window.siblings.count == @countof(names) and window.folderList.lineCount() == @countof(names))
    for name, index in names
    {
        @assert(window.folderFiles[index] == name[] and window.siblings[index] == name[])
        @assert(window.folderList.lineAt(cast(u32) index)!.itemAt(0).name.raw == (Path.fileName(name[].toString()) orelse name[].toString()))
    }
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
    completeQueuedViewerFile(&host, window)

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
    assertFolderFiles(window, names.toSlice())
    @assert(window.recentList.lineCount() == 1)
    for i in window.folderList.lineCount()
    {
        let icon = window.folderList.lineAt(i)!.itemAt(0).icon
        @assert(icon.isValid() and icon.index == cast(s32) ViewerIcons.Text)
    }

    let recentIcon = window.recentList.lineAt(0)!.itemAt(0).icon
    @assert(recentIcon.isValid() and recentIcon.index == cast(s32) ViewerIcons.Text)

    // Choosing a sibling opens it, and the recent list grows by exactly that file.
    window.folderList.selectLine(2)
    completeQueuedViewerFile(&host, window)
    @assert(window.currentFile == names[2])
    @assert(window.recent.count == 2 and window.recent[0] == names[2])
    assertFolderFiles(window, names.toSlice())

    // A recent row keeps the list under the pointer stable while it opens its file.
    window.recentList.selectLine(1)
    completeQueuedViewerFile(&host, window)
    @assert(window.currentFile == names[0])
    @assert(window.recent.count == 2 and window.recent[0] == names[2] and window.recent[1] == names[0])
    assertFolderFiles(window, names.toSlice())

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
    completeQueuedViewerFile(&host, window)
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

    for one in names
    {
        window.openFile(one[].toString())
        completeQueuedViewerFile(&host, window)
    }

    window.setFilePanelVisible(true)
    @assert(window.recent.count == 3 and window.recentList.lineCount() == 3)

    // The most recent file is at the head, and forgetting one leaves the others in their order.
    window.forgetRecent(names[2].toString())
    @assert(window.recent.count == 2 and window.recentList.lineCount() == 2)
    @assert(window.recent[0] == names[1] and window.recent[1] == names[0])

    // Forgetting what the history does not hold changes nothing, and the file stays open.
    window.forgetRecent(Path.combine(folder.toString(), "absent.txt").toString())
    @assert(window.recent.count == 2 and window.currentFile == names[2])

    @assert(window.recentClearButton.parent == window.recentLabel.parent)
    @assert(window.recentClearButton.icon.isValid())
    @assert(!Utf8.contains(appStrings().ui_ConfirmClearHistory, "?"))

    host.clickModalButtonWhenShown(Dialog.BtnNo)
    window.confirmClearRecent()
    host.pump()
    @assert(host.autoHandled and window.recent.count == 2)

    host.clickModalButtonWhenShown(Dialog.BtnYes)
    window.confirmClearRecent()
    host.pump()
    @assert(host.autoHandled)
    @assert(window.recent.isEmpty() and window.recentList.lineCount() == 0)
    @assert(!window.filePanel.isPaneVisible(0) and !window.recentPane.isLocallyVisible())
    @assert(window.currentFile == names[2] and window.folderList.lineCount() == 3)
}

// The history row menu offers what that file can do, and its own entry removes one file.
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

    for one in names
    {
        window.openFile(one[].toString())
        completeQueuedViewerFile(&host, window)
    }

    window.setFilePanelVisible(true)
    window.applyLayout()

    let list = window.recentList
    @assert(list.lineCount() == 3)

    // The row naming the file read before the one that is open, which the panel opens on its own
    // when it is picked: what the menu acts on is the row, not the document.
    list.selectLine(1)
    completeQueuedViewerFile(&host, window)
    @assert(window.currentFile == names[1])

    host.clickPopupMenuItemWhenShown("sFileScope.file.copyPath")
    window.showFileMenu(list, window.recent.toSlice(), {120, 120})
    host.pump()
    @assert(host.autoHandled and Clipboard.getString() == names[1])

    host.clickPopupMenuItemWhenShown("sFileScope.file.copyName")
    window.showFileMenu(list, window.recent.toSlice(), {120, 120})
    host.pump()
    @assert(host.autoHandled and Clipboard.getString() == "file1.txt")

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
    completeQueuedViewerFile(&host, window)
    @assert(window.choices.count == 3 and window.choices[0].key == BasicTextViewerKey)
    @assert(window.activeChoiceIndex == 0 and window.preferences.isEmpty())

    // Every entry of the selector says which viewer it is before its name is read.
    @assert(window.viewerCombo.items.count == window.choices.count)
    for item in window.viewerCombo.items do
        @assert(item!.icon.isValid())

    window.selectViewer(2)
    @assert(window.choices[window.activeChoiceIndex].key == "hex")
    @assert(window.preferences.count == 1 and window.preferences[0].kind == BasicTextViewerKey and window.preferences[0].viewer == "hex")

    // The next file of the same kind opens where the reader left the previous one.
    window.openFile(second.toString())
    completeQueuedViewerFile(&host, window)
    @assert(window.choices[window.activeChoiceIndex].key == "hex")

    // The decision crosses a session with the other panel choices.
    let state = saveViewerState(window)
    window.preferences.clear()
    loadViewerState(window, state.toSlice())
    @assert(window.preferences.count == 1 and window.preferences[0].viewer == "hex")

    window.selectViewer(0)
    @assert(window.preferences.isEmpty())
    window.openFile(first.toString())
    completeQueuedViewerFile(&host, window)
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
    completeQueuedViewerFile(&host, window)
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
    for 64
    {
        view.loadNextChunk()
        @assert(view.virtualHeight >= firstVirtualHeight)
        @assert(view.editor.scrollableClientRect().height >= firstVirtualHeight)
    }

    @assert(view.bytesRead - view.residentStart <= 256 * 1024 + 16 * 1024)
    @assert(@countof(view.editor.text()) <= 256 * 1024 + 16 * 1024)
    @assert(view.bytesRead < view.fileSize)

    let firstStart = view.residentStart
    view.editor.setScrollPosition({0, view.virtualHeight * 0.5})
    @assert(view.pendingSeek)
    host.fireTimers()
    @assert(view.residentStart > firstStart)
    @assert(view.bytesRead - view.residentStart <= 256 * 1024 + 16 * 1024)

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

// Rapid scrollbar scrubbing coalesces to the latest byte window and remains stable when the
// direction changes repeatedly. Each completed seek keeps the requested viewport instead of
// snapping back to the resident window it replaced.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_text_scrub_%.txt", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String
    for index in 70_000 do
        source += Format.toString("Distinct streamed line % keeps scrollbar seeks observable.\n", index)
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

    view.editor.setScrollPosition({0, view.virtualHeight * 0.85})
    @assert(view.pendingSeek)
    view.editor.setScrollPosition({0, 0})
    @assert(!view.pendingSeek)

    view.editor.setScrollPosition({0, view.virtualHeight * 0.85})
    view.editor.setScrollPosition({0, view.virtualHeight * 0.2})
    @assert(view.pendingSeek and view.loadTimer != null)
    host.fireTimer(view.loadTimer)
    let lowOffset = cast(u64) (0.2 * cast(f32) view.fileSize)
    @assert(view.residentStart <= lowOffset and view.bytesRead >= lowOffset)

    let ratios = [0.8'f32, 0.1'f32, 0.65'f32, 0.3'f32, 0.9'f32, 0.05'f32]
    for ratio in ratios
    {
        let requestedY = view.virtualHeight * ratio
        view.editor.setScrollPosition({0, requestedY})
        @assert(view.pendingSeek and view.loadTimer != null)
        host.fireTimer(view.loadTimer)
        let offset = cast(u64) (ratio * cast(f32) view.fileSize)
        @assert(view.residentStart <= offset and view.bytesRead >= offset)
        @assert(Math.abs(view.editor.scrollPosition().y - requestedY) <= 1)
        @assert(!view.editor.text().isEmpty())
    }
}

// All three application palettes cross the same state boundary as the surface placement.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    @assert(window.appearanceButton.appearanceTheme == .SwagDark)

    window.applyTheme(cast(u32) AppearanceTheme.Dark)
    host.notify(.ThemeChanged)
    @assert(window.themeIndex == cast(u32) AppearanceTheme.Dark)
    @assert(host.app.theme.colors.view_Bk == ThemeColors.darkPalette().view)

    window.applyTheme(cast(u32) AppearanceTheme.Light)
    host.notify(.ThemeChanged)
    @assert(window.themeIndex == cast(u32) AppearanceTheme.Light)
    @assert(host.app.theme.colors.view_Bk == 0xFFFFFFFF)
    @assert(window.themeColors().view_Bk == 0xFFFFFFFF)

    let state = saveViewerState(window)
    window.applyTheme(0)
    loadViewerState(window, state.toSlice())
    window.applyTheme(window.themeIndex)
    host.notify(.ThemeChanged)
    @assert(window.themeIndex == cast(u32) AppearanceTheme.Light and host.app.theme.colors.view_Bk == 0xFFFFFFFF)
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
    completeQueuedViewerFile(&host, window)
    window.searchBox.setText(query)
    window.findNext()

    completeViewerSearch(&host, window)
    @assert(window.searchMatch == target)
    @assert(window.searchMatches.count == 1 and window.searchIndex == 0)
    @assert(window.searchCountLabel.text() == "1/1")
    let textView = cast(*BasicTextView) window.currentView!
    @assert(textView.editor.selectedText() == query)
    @assert(textView.bytesRead < textView.fileSize)
    discard host.render(textView)
    textView.updateEstimatedHeight()
    @assert(textView.editor.scrollableClientRect().height > textView.editor.paddedClientRect().height)
}

// The shared result set drives counts, wraparound navigation, case matching and whole-word
// boundaries without changing what the viewer marks.
#test
{
    let fileName = Gui.Testing.tempFilePath("sfilescope-search-", ".txt")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "Cat catalog cat catapult\ncat")

    var host: Testing.HeadlessHost
    host.setup(880, 560)
    defer host.shutdown()
    var index: ViewerIndex
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(fileName)
    completeQueuedViewerFile(&host, window)
    window.searchBox.setFocus()
    window.searchBox.setText("cat")
    completeViewerSearch(&host, window)

    @assert(window.searchMatches.count == 5 and window.searchIndex == 0 and window.searchMatch == 0)
    @assert(window.searchCountLabel.text() == "1/5")
    @assert(window.searchBox.hasFocus())
    discard host.render(window)
    host.fireTimers()
    @assert(window.searchOverlay.isLocallyVisible())
    let basic = cast(*BasicTextView) window.currentView!
    @assert(basic.editor.selectedText() == "Cat")
    var matchBounds: Math.Rectangle
    @assert(basicTextSearchBounds(basic, window.searchMatches[window.searchIndex], &matchBounds))
    @assert(window.searchOverlay.position.width == Math.round(matchBounds.width + ViewerSearchOverlayInset * 2))
    @assert(window.searchOverlay.position.height == Math.round(matchBounds.height + ViewerSearchOverlayInset * 2))
    window.searchOverlay.phase = 0.25
    let firstPulse = host.render(window)
    window.searchOverlay.invalidate()
    let repeatedPulse = host.render(window)
    @assert(Hash.hashBytes32(firstPulse.pixels.toSlice()) == Hash.hashBytes32(repeatedPulse.pixels.toSlice()))

    window.findPrevious()
    @assert(window.searchIndex == 4 and window.searchMatch == 25 and window.searchCountLabel.text() == "5/5")
    window.findNext()
    @assert(window.searchIndex == 0 and window.searchMatch == 0)

    window.searchWholeWordOption = true
    window.searchWholeWord.setChecked(true)
    window.restartSearch()
    completeViewerSearch(&host, window)
    @assert(window.searchMatches.count == 3 and window.searchCountLabel.text() == "1/3")

    window.searchMatchCaseOption = true
    window.searchMatchCase.setChecked(true)
    window.restartSearch()
    completeViewerSearch(&host, window)
    @assert(window.searchMatches.count == 2 and window.searchMatch == 12 and window.searchCountLabel.text() == "1/2")

    window.searchBox.setText("absent")
    completeViewerSearch(&host, window)
    @assert(window.searchMatches.isEmpty() and window.searchCountLabel.text() == "0/0")
    @assert(window.searchBox.hasFocus() and !window.searchOverlay.isLocallyVisible())

    window.searchBox.setText("cat")
    completeViewerSearch(&host, window)
    @assert(!window.searchBox.children.isEmpty())
    window.searchBox.setText(null)
    @assert(!@countof(window.searchBox.text()))
    @assert(!@countof(window.searchCountLabel.text()) and !window.searchOverlay.isLocallyVisible())
    @assert((cast(*BasicTextView) window.currentView!).editor.isSelectionEmpty())
}

// Search navigation over a streamed Markdown file materializes every distant occurrence in both
// directions, and clearing the query removes the viewer-owned mark as well as the shared halo.
#test
{
    let fileName = Gui.Testing.tempFilePath("sfilescope-search-markdown-", ".md")
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
    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(fileName)
    completeQueuedViewerFile(&host, window)

    var markdownIndex = Swag.U32.Max
    for choice, choiceIndex in window.choices where choice.key == "markdown" do
        markdownIndex = cast(u32) choiceIndex
    @assert(markdownIndex != Swag.U32.Max)
    window.selectViewer(markdownIndex)
    window.searchBox.setFocus()
    window.searchBox.setText(Query)
    completeViewerSearch(&host, window)
    @assert(window.searchMatches.count == 3 and window.searchMatch == offsets[0])

    for 2_048 where !window.searchOverlay.isLocallyVisible() do
        host.fireTimers()
    @assert(window.searchOverlay.isLocallyVisible())

    window.findNext()
    @assert(window.searchIndex == 1 and window.searchMatch == offsets[1])
    window.searchOverlay.hide()
    for 2_048 where !window.searchOverlay.isLocallyVisible() do
        host.fireTimers()
    @assert(window.searchOverlay.isLocallyVisible())

    window.findNext()
    @assert(window.searchIndex == 2 and window.searchMatch == offsets[2])
    window.searchOverlay.hide()
    for 2_048 where !window.searchOverlay.isLocallyVisible() do
        host.fireTimers()
    @assert(window.searchOverlay.isLocallyVisible())

    window.findPrevious()
    @assert(window.searchIndex == 1 and window.searchMatch == offsets[1])
    window.searchOverlay.hide()
    for 2_048 where !window.searchOverlay.isLocallyVisible() do
        host.fireTimers()
    @assert(window.searchOverlay.isLocallyVisible())

    let markdown = cast(*Markdown.View) window.currentView!
    var bounds: Math.Rectangle
    @assert(markdown.searchMatchRect(&bounds))

    let beforeSearchPage = bounds.y
    host.keyPress(.PageDown)
    for 2_048 where bounds.y >= beforeSearchPage
    {
        host.fireTimers()
        discard markdown.searchMatchRect(&bounds)
    }

    @assert(markdown.searchMatchRect(&bounds))
    let afterSearchPage = bounds.y
    @assert(afterSearchPage < beforeSearchPage)
    @assert(window.searchBox.hasFocus())

    markdown.setFocus()
    host.keyPress(.PageUp)
    @assert(markdown.searchMatchRect(&bounds))
    @assert(bounds.y > afterSearchPage)
    @assert(markdown.hasFocus())

    window.searchBox.setText(null)
    @assert(!markdown.searchMatchRect(&bounds))
    @assert(!window.searchOverlay.isLocallyVisible())
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
    @assert(window.searchGroup.parent == window.commandBar)
    @assert(window.searchBox.parent == window.searchGroup)
    @assert(window.fullScreenButton.parent == window.commandBar)
    @assert(window.fullScreenButton.flags.has(.Toggle) and window.fullScreenButton.checkIndicator == .Frame)
    @assert(!window.searchGroup.isLocallyVisible() and window.searchBox.isHidden())
    @assert(window.searchPrevious.icon.isValid() and window.searchNext.icon.isValid())
    @assert(!window.searchPrevious.isEnabled() and !window.searchNext.isEnabled())
    @assert(window.infoBar.position.height == ViewerInfoHeight)
    @assert(window.infoBar.dockStyle == .Top)
    @assert(window.backgroundStyle == .View and window.infoBar.backgroundStyle == .InformationBar)
    @assert(window.commandBar.backgroundStyle == .CommandBar)
    @assert(window.filePanel.backgroundStyle == .Window)
    @assert(window.recentPane.backgroundStyle == .Window and window.folderPane.backgroundStyle == .Window)
    @assert(window.viewerBar.backgroundStyle == .ToolBar)
    @assert(window.themeColors().view_Bk != window.themeColors().informationBar_Bk)
    @assert(window.themeColors().view_Bk != window.themeColors().bk)
    @assert(window.themeColors().view_Bk != window.themeColors().wnd_Bk)
    @assert(window.themeColors().informationBar_Bk != window.themeColors().bk and window.themeColors().informationBar_Bk != window.themeColors().wnd_Bk)
    @assert(window.themeColors().commandBar_Bk != window.themeColors().wnd_Bk and window.themeColors().commandBar_Bk != window.themeColors().informationBar_Bk)
    @assert(window.themeColors().toolBar_Bk != window.themeColors().wnd_Bk and window.themeColors().toolBar_Bk != window.themeColors().informationBar_Bk)
    @assert(window.themeColors().informationBar_Bk.relativeLuminance() < window.themeColors().wnd_Bk.relativeLuminance())
    @assert(window.themeColors().informationBar_Bk.relativeLuminance() < window.themeColors().commandBar_Bk.relativeLuminance())
    @assert(window.themeColors().bk != window.themeColors().wnd_Bk)
    @assert(window.infoBar.isLocallyVisible())
    @assert(window.viewerBar.dockStyle == .Bottom and !window.viewerBar.isLocallyVisible())
    @assert(window.infoNameLabel.name.raw.isEmpty())
    @assert(window.surface!.minSize.x == ViewerMinWidth)
    @assert(Utf8.contains(window.emptyLabel.name.raw, appStrings().ui_DropTitle))

    // The large empty-state glyph is intentionally deferred until the surface's Init event.
    @assert(window.emptyView.isLocallyVisible() and !window.emptyIconLabel.icon.isValid())
    @assert(window.emptyView.position.y >= window.infoBar.position.bottom())
    @assert(window.emptyHintLabel.text() == appStrings().ui_DropHint)
    @assert(window.currentView == null)
    @assert(window.currentCommands == null)
    @assert(window.filesButton.flags.has(.Toggle) and window.filesButton.checkIndicator == .Frame)
    @assert(!window.filesButton.isChecked and !window.loadingOverlay.isLocallyVisible())
    @assert(!window.viewerCombo.isLocallyVisible())
    @assert(window.infoNameLabel.parent == window.infoFileGroup)
    @assert(window.infoSizeLabel.parent == window.infoFileGroup)
    @assert(window.infoNameLabel.textVerticalAlignment == .OpticalCenter)
    @assert(window.infoSizeLabel.textVerticalAlignment == .OpticalCenter)
    @assert(window.infoStatsLabel.textVerticalAlignment == .OpticalCenter)
    @assert(window.recentClearButton.parent == window.recentLabel.parent)
    @assert(window.infoStatsLabel.parent == window.infoBar)
    Testing.assertContentFits(window)

    // Viewer tools have their own full-width band and cannot collide with the global selector.
    window.resize(ViewerMinWidth, 680)
    window.viewerCombo.show()
    let widestCommands = Wnd.create'Wnd(window.viewerBar, {0, 0, 0, 36})
    widestCommands.dockStyle = .Center
    window.viewerBar.show()
    window.applyLayout()
    @assert(window.viewerCombo.parent == window.commandBar and widestCommands.parent == window.viewerBar)
    @assert(window.viewerCombo.position.bottom() <= window.infoBar.position.y)
    @assert(widestCommands.position.y >= window.viewerBar.clientRect().y)
}

// Search is chrome only when the selected viewer exposes search. Switching to a viewer without
// that contract removes the complete group and never leaves keyboard focus in an invisible field.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.openFile(viewerFixturePath().toString())
    completeQueuedViewerFile(&host, window)
    window.applyLayout()

    @assert(window.searchGroup.isLocallyVisible() and window.searchBox.isVisible() and window.searchBox.isEnabled())
    @assert(window.searchPrevious.isVisible() and window.searchNext.isVisible())
    @assert(window.searchMatchCase.isVisible() and window.searchWholeWord.isVisible())
    @assert(window.searchGroup.children.count == 6)
    @assert(window.searchGroup.children[0] == window.searchMatchCase)
    @assert(window.searchGroup.children[1] == window.searchWholeWord)
    @assert(window.searchGroup.children[2] == window.searchBox)
    @assert(window.searchGroup.children[3] == window.searchPrevious)
    @assert(window.searchGroup.children[4] == window.searchNext)
    @assert(window.searchGroup.children[5] == window.searchCountLabel)
    @assert(window.searchCountLabel.textHorizontalAlignment == .Left)
    @assert(Math.abs(window.searchGroup.position.horzCenter() - window.commandBar.paddedClientRect().horzCenter()) < 0.01)

    window.searchBox.setFocus()
    @assert(window.searchBox.hasFocus())
    let midiFile = Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), "viewer.mid")
    window.openFile(midiFile.toString())
    completeQueuedViewerFile(&host, window)

    @assert(!window.searchGroup.isLocallyVisible() and window.searchBox.isHidden())
    @assert(window.searchPrevious.isHidden() and window.searchNext.isHidden())
    @assert(window.searchMatchCase.isHidden() and window.searchWholeWord.isHidden())
    @assert(!window.searchBox.hasFocus())

    window.openFile(viewerFixturePath().toString())
    completeQueuedViewerFile(&host, window)
    @assert(window.searchGroup.isLocallyVisible() and window.searchBox.isVisible() and window.searchBox.isEnabled())
}

// File metadata can arrive after the first frame. Publishing it lays out the identity row
// immediately, without waiting for a resize, theme change, or another outer layout pass.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(ViewerMinWidth, 680)
    window.applyLayout()
    @assert(window.infoNameLabel.position.width == 0 and window.infoSizeLabel.position.width == 0)

    window.currentFile     = viewerFixturePath()
    window.currentFileSize = "1.2 KiB"
    window.choices.add(ViewerChoice{.BasicText, Swag.U64.Max, "Basic text"})
    window.activeChoiceIndex = 0
    window.updateFileInfo("UTF-8 · streamed")

    @assert(@countof(window.infoNameLabel.text()) > 0 and @countof(window.infoSizeLabel.text()) > 0)
    @assert(window.infoNameLabel.position.width > 0 and window.infoSizeLabel.position.width > 0)
    @assert(window.infoNameLabel.position.width >= Math.ceil(window.infoNameLabel.itf.measureContent({}).x))
    @assert(window.infoStatsLabel.position.width > 0 and window.infoStatsLabel.position.width < ViewerInfoStatsMaxWidth)
    @assert(window.infoIconLabel.position.right() <= window.infoNameLabel.position.x)
    @assert(window.infoNameLabel.position.right() <= window.infoSizeLabel.position.x)

    // Fractional glyph extents vary with the name. Every short name receives the whole measured
    // line rather than occasionally losing its last glyph to the ellipsis.
    let shortNames: [6] string = ["a.txt", "ii.txt", "notes.txt", "readme.md", "small.json", "brief-source.swg"]
    for name in shortNames
    {
        window.currentFile = name
        window.updateFileInfo("UTF-8 · streamed")
        @assert(window.infoNameLabel.position.width >= Math.ceil(window.infoNameLabel.itf.measureContent({}).x))
    }
}

// F11 preserves the exact window state around a content-only presentation. Moving at either
// screen edge reveals the corresponding chrome over the content without shrinking it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(viewerFixturePath(), remember: false)
    completeQueuedViewerFile(&host, window)
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

// Progressive content keeps streaming without covering useful output. A viewer asks for the
// shared wait presentation separately when it has nothing useful to show yet.
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
    @assert(!window.loadingOverlay.isLocallyVisible() and window.loadingTimer != null)

    window.instances[0].needsLoadingOverlay = func(wnd)->bool { discard wnd; return true }
    reportViewerLoadingChanged(loading)
    @assert(window.loadingOverlay.isLocallyVisible())
    @assert(window.loadingOverlay.position == loading.position)
    @assert(window.loadingOverlay.backgroundStyle == .Transparent)
    @assert(window.loadingOverlay.wndFlags.has(.Disabled))
    @assert(window.children.back() == window.loadingOverlay)
    @assert(window.loadingOverlay.spinner.position.width == ViewerLoadingSpinnerSize and window.loadingOverlay.spinner.position.height == ViewerLoadingSpinnerSize)
    let spinnerSmall = viewerLoadingSpinnerGeometry(0)
    let spinnerLarge = viewerLoadingSpinnerGeometry(0.5)
    @assert(spinnerSmall.radius == ViewerLoadingSpinnerMinRadius and spinnerLarge.radius == ViewerLoadingSpinnerMaxRadius)
    @assert(spinnerSmall.sweep == ViewerLoadingSpinnerMinSweep and spinnerLarge.sweep == ViewerLoadingSpinnerMaxSweep)
    @assert(spinnerLarge.radius > spinnerSmall.radius and spinnerLarge.sweep > spinnerSmall.sweep)
    let spinnerCenter = window.loadingOverlay.spinner.position.center()
    let overlayCenter = window.loadingOverlay.clientRect().center()
    @assert(Math.abs(spinnerCenter.x - overlayCenter.x) <= 0.5 and Math.abs(spinnerCenter.y - overlayCenter.y) <= 0.5)
    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "sfilescope.loading")

    // A newly selected progressive viewer loads behind the preceding document. The activity
    // mark belongs over that preserved document until the replacement can publish its first frame.
    let outgoing = Wnd.create'Wnd(window)
    outgoing.setPosition({23, 71, 577, 363})
    window.outgoingView = outgoing
    window.currentView  = outgoing
    reportViewerLoadingChanged(loading)
    @assert(window.loadingOverlay.isLocallyVisible() and window.loadingOverlay.position == outgoing.position)
    window.outgoingView = null
    window.currentView  = loading
    outgoing.destroy()

    window.instances[0].needsLoadingOverlay = null
    reportViewerLoadingChanged(loading)
    @assert(!window.loadingOverlay.isLocallyVisible() and window.loadingTimer != null)
    @assert(window.activateChoice(1))
    @assert(retired and loading.isPendingDestroy)
    @assert(window.instances[0].view == null)
    @assert(window.currentView != null and window.currentView != loading)
    @assert(window.instances[1].view == window.currentView)
    @assert(!window.loadingOverlay.isLocallyVisible() and window.loadingTimer == null)
}

// File selection never waits for a viewer that needs another event-loop turn to retire. The
// generic host keeps the previous content visible, then opens the queued file on its timer.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    let old    = Wnd.create'Wnd(window)
    old.setPosition({19, 73, 617, 389})
    var retireCalls: u32
    old.userData = &retireCalls
    window.instances.add(ViewerInstance{view: old, retire: &delayTestViewerRetirement})
    window.currentView       = old
    window.activeChoiceIndex = 0

    let fileName = viewerFixturePath()
    window.openFile(fileName, remember: false)
    @assert(window.currentView == old and retireCalls == 0)
    @assert(window.pendingFile == fileName and window.startupTimer != null)
    @assert(window.loadingOverlay.isLocallyVisible() and window.loadingOverlay.position == old.position)

    host.fireTimer(window.startupTimer)
    Jobs.wait(&window.choiceLoad.job)
    host.fireTimer(window.startupTimer)
    @assert(window.currentView == old and retireCalls == 1)
    @assert(window.pendingFile == fileName and window.startupTimer != null)

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
    window.showEmpty(appStrings().ui_Unsupported)
    @assert(window.currentView == null)
    @assert(window.currentCommands == null)
    @assert(window.instances.isEmpty())
    @assert(window.currentFile.isEmpty())
    @assert(window.infoNameLabel.name.raw.isEmpty())
    @assert(window.infoNameLabel.position.width == 0 and window.infoStatsLabel.position.width == 0)
    @assert(window.infoBar.isLocallyVisible() and !window.infoIconLabel.icon.isValid())
    @assert(window.emptyView.isLocallyVisible() and window.emptyView.position.y >= window.infoBar.position.bottom())
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
    completeQueuedViewerFile(&host, window)

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
    host.fireTimer(window.startupTimer)
    Jobs.wait(&window.choiceLoad.job)
    host.fireTimer(window.startupTimer)

    let discardedView  = cast(*BasicTextView) window.currentView!
    let discardedTimer = discardedView.loadTimer!
    window.openFile(secondFile)
    host.fireTimer(window.startupTimer)
    Jobs.wait(&window.choiceLoad.job)
    host.fireTimer(window.startupTimer)

    @assert(window.currentView != discardedView)

    // A test can keep the timer's address for identity after the host has reclaimed it. Firing
    // that stale address must be a no-op and, in particular, must never dereference its target.
    host.fireTimer(discardedTimer)
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

// Pins the open-document composition in Swag dark and neutral light: global navigation and file
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
    completeQueuedViewerFile(&host, window)
    window.applyLayout()
    host.settleAnimations(window, 4)

    @assert(window.viewerCombo.isLocallyVisible())
    @assert(window.infoBar.isLocallyVisible() and !window.emptyView.isLocallyVisible())
    @assert(window.infoIconLabel.icon.isValid())
    @assert(window.infoIconLabel.position.right() <= window.infoNameLabel.position.x)
    @assert(window.infoNameLabel.position.right() <= window.infoSizeLabel.position.x)
    @assert(window.currentCommands!.parent == window.viewerBar and window.viewerBar.isLocallyVisible())
    @assert(window.searchBox.isLocallyVisible() and window.searchBox.isEnabled())
    var dark = host.render(window)
    Pixel.Testing.assertImageGolden(&dark, "sfilescope.viewer.dark")

    window.searchBox.setText("verification marker")
    completeViewerSearch(&host, window)
    discard host.render(window)
    host.fireTimers()
    window.searchOverlay.phase = 0.125
    var searchDark = host.render(window)
    Pixel.Testing.assertImageGolden(&searchDark, "sfilescope.search.dark")
    window.searchBox.setText("")

    window.applyTheme(cast(u32) AppearanceTheme.Light)
    host.notify(.ThemeChanged)
    host.settleAnimations(window, 4)
    var light = host.render(window)
    Pixel.Testing.assertImageGolden(&light, "sfilescope.viewer.light")

    window.searchBox.setText("verification marker")
    completeViewerSearch(&host, window)
    discard host.render(window)
    host.fireTimers()
    window.searchOverlay.phase = 0.125
    var searchLight = host.render(window)
    Pixel.Testing.assertImageGolden(&searchLight, "sfilescope.search.light")
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
    completeQueuedViewerFile(&host, window)

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
    completeQueuedViewerFile(&host, window)
    window.rebuildSiblings()
    @assert(window.siblings.count == 2)

    window.setFolderSameKind(false)
    window.rebuildSiblings()
    @assert(window.siblings.count == 5)

    // The choice survives a session like the other panel decisions.
    window.setFolderSameKind(true)
    window.searchMatchCaseOption = true
    window.searchWholeWordOption = true
    let state = saveViewerState(window)
    window.setFolderSameKind(false)
    window.searchMatchCaseOption = false
    window.searchWholeWordOption = false
    loadViewerState(window, cast(const [..] u8) state.toString())
    @assert(window.folderSameKind and window.searchMatchCaseOption and window.searchWholeWordOption)
    @assert(window.searchMatchCase.isChecked and window.searchWholeWord.isChecked)
}

// Bare arrows never navigate files globally. The image viewer is the one document type that
// deliberately owns that gesture and asks the host for its neighboring image.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let folder        = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_arrows_%", Guid64.random()).toString())
    expect Directory.create(folder.toString())
    defer discard catch Directory.delete(folder.toString(), recurse: true)

    discard expect File.writeAllBytes(Path.combine(folder.toString(), "t1.txt").toString(), cast(const [..] u8) "a readable line\n")
    discard expect File.writeAllBytes(Path.combine(folder.toString(), "t2.txt").toString(), cast(const [..] u8) "a readable line\n")
    let imageSource = expect File.readAllText(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/sample.svg"))
    let imageBytes  = @mkslice(cast(const [*] u8) imageSource.buffer!, imageSource.length)
    discard expect File.writeAllBytes(Path.combine(folder.toString(), "pic1.svg").toString(), imageBytes)
    discard expect File.writeAllBytes(Path.combine(folder.toString(), "pic2.svg").toString(), imageBytes)

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = createViewerIndex()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    // The text editor owns the caret keys: with the keyboard parked on a toolbar button, the
    // arrow reaches the editor instead of walking the folder, and the keyboard follows it.
    window.openFile(Path.combine(folder.toString(), "t1.txt").toString())
    completeQueuedViewerFile(&host, window)
    let textView = cast(*BasicTextView) window.currentView!
    window.openButton.setFocus()
    @assert(!textView.editor.hasFocus())
    host.keyPress(Input.Key.Right)
    @assert(Path.fileName(window.currentFile.toString()) == "t1.txt")
    @assert(textView.editor.hasFocus())

    // The same key does navigate once an image viewer explicitly owns it.
    window.openFile(Path.combine(folder.toString(), "pic1.svg").toString())
    completeQueuedViewerFile(&host, window)
    window.setFolderSameKind(true)
    window.openButton.setFocus()
    host.keyPress(Input.Key.Right)
    completeQueuedViewerFile(&host, window)
    @assert(Path.fileName(window.currentFile.toString()) == "pic2.svg")
}
