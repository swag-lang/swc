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
    let index  = expect ViewerPluginIndex.parse(cast(string) DefaultPluginIndex, "plugins")
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.openFile(names[0].toString())

    @assert(!window.panelVisible and !window.filePanel.isLocallyVisible())
    window.toggleFilePanel()
    @assert(window.panelVisible and window.filePanel.isLocallyVisible())
    @assert(window.filesButton.isChecked)
    @assert(window.filePanel.position.width == ViewerPanelWidth)
    @assert(window.filePanel.minSize.x == ViewerPanelWidth and window.filePanel.maxSize.x == ViewerPanelWidth)
    @assert(window.recentList.listFlags.has(.Ellipsis) and window.folderList.listFlags.has(.Ellipsis))
    @assert(window.recentList.scrollWnd.flags.has(.DisableHorizontal) and window.folderList.scrollWnd.flags.has(.DisableHorizontal))
    @assert(window.folderList.lineCount() == 3)
    @assert(window.recentList.lineCount() == 1)

    // Choosing a sibling opens it, and the recent list grows by exactly that file.
    window.folderList.selectLine(2)
    @assert(window.currentFile == names[2])
    @assert(window.recent.count == 2 and window.recent[0] == names[2])

    // A recent row keeps the list under the pointer stable while it opens its file.
    window.recentList.selectLine(1)
    @assert(window.currentFile == names[0])
    @assert(window.recent.count == 2 and window.recent[0] == names[2] and window.recent[1] == names[0])

    window.setFilePanelVisible(false)
    @assert(!window.filesButton.isChecked)
    window.setFilePanelVisible(true)

    let state = saveViewerState(window)
    window.recent.clear()
    window.setFilePanelVisible(false)
    loadViewerState(window, state.toSlice())
    @assert(window.recent.count == 2 and window.panelVisible)
}

// The panel opens before any file has been read: there is no folder to name, so the section keeps
// its own title and both lists stay empty.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = expect ViewerPluginIndex.parse(cast(string) DefaultPluginIndex, "plugins")
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)

    @assert(window.currentFile.isEmpty())
    window.setFilePanelVisible(true)
    @assert(window.panelVisible and window.filePanel.isLocallyVisible())
    @assert(window.folderList.lineCount() == 0 and window.recentList.lineCount() == 0)
    @assert(!window.recentList.isLocallyVisible())
    @assert(window.folderLabel.text() == appStrings().ui_Folder)
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

    let index  = expect ViewerPluginIndex.parse(cast(string) DefaultPluginIndex, "plugins")
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

    let index  = expect ViewerPluginIndex.parse(cast(string) DefaultPluginIndex, "plugins")
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
    let index  = expect ViewerPluginIndex.parse("unused|Unused|unused.dll|.unused", "plugins")
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

    let index  = expect ViewerPluginIndex.parse(cast(string) DefaultPluginIndex, "plugins")
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.applyLayout()

    @assert(window.commandBar.position.height == ViewerBarHeight)
    @assert(window.viewerCombo.parent == window.commandBar)
    @assert(window.appearanceButton.parent == &host.surfaceWnd)
    @assert(window.searchBox.parent == window.commandBar)
    @assert(window.searchBox.isLocallyVisible() and !window.searchBox.isEnabled())
    @assert(window.infoBar.position.height == ViewerInfoHeight)
    @assert(window.infoBar.dockStyle == .Bottom)
    @assert(window.infoBar.backgroundStyle != window.backgroundStyle)
    @assert(window.openButton.position.x < window.previousButton.position.x)
    @assert(window.openButton.position.x < window.searchBox.position.x)
    @assert(window.searchBox.position.x < window.previousButton.position.x)
    @assert(window.previousButton.position.x < window.nextButton.position.x)
    @assert(window.infoTypeLabel.name.raw == "NO FILE")
    @assert(Utf8.contains(window.emptyLabel.name.raw, appStrings().ui_DropTitle))
    @assert(!window.previousButton.isEnabled())
    @assert(!window.nextButton.isEnabled())
    @assert(window.currentView == null)
    @assert(window.currentCommands == null)
    @assert(window.filesButton.flags.has(.Toggle) and window.filesButton.checkIndicator == .Frame)
    @assert(!window.filesButton.isChecked and !window.loadingSpinner.isLocallyVisible())
    @assert(window.plugins.first == null)
    @assert(!window.viewerCombo.isLocallyVisible())
    Testing.assertContentFits(window)
}

// The framework owns one centered, themed presentation for every plugin decoder reason.
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

// A decoder error discovered after creation replaces the active plugin and its commands in place.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 420)
    defer host.shutdown()

    let index    = expect ViewerPluginIndex.parse(cast(string) DefaultPluginIndex, "plugins")
    let window   = ViewerWindow.create(&host.surfaceWnd, #move index)
    let failed   = Wnd.create'Wnd(window)
    let commands = Wnd.create'Wnd(window.commandBar)
    window.choices.add(ViewerChoice{.Plugin, 0, "Decoder"})
    window.instances.add(ViewerInstance{view: failed, commands: commands})
    window.currentView       = failed
    window.currentCommands   = commands
    window.activeChoiceIndex = 0
    window.currentFile       = "sample.bin"

    reportViewerFailure(failed, "payload ends before its declared length")

    @assert(failed.isPendingDestroy and commands.isPendingDestroy)
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

    let index  = expect ViewerPluginIndex.parse(cast(string) DefaultPluginIndex, "plugins")
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.currentFile = fileName
    window.choices.add(ViewerChoice{.BasicText, Swag.U64.Max, "First"})
    window.choices.add(ViewerChoice{.BasicText, Swag.U64.Max, "Second"})
    window.viewerCombo.addItem("First")
    window.viewerCombo.addItem("Second")
    window.instances.resize(2)

    let loading = Wnd.create'Wnd(window)
    window.instances[0].view      = loading
    window.instances[0].details   = "streamed"
    window.instances[0].isLoading = func(wnd)->bool { discard wnd; return true }
    window.currentView            = loading
    window.activeChoiceIndex      = 0

    window.updateLoadingIndicator()
    @assert(window.loadingSpinner.isLocallyVisible() and window.loadingTimer != null)
    @assert(window.activateChoice(1))
    @assert(loading.isPendingDestroy)
    @assert(window.instances[0].view == null)
    @assert(window.currentView != null and window.currentView != loading)
    @assert(window.instances[1].view == window.currentView)
    @assert(!window.loadingSpinner.isLocallyVisible() and window.loadingTimer == null)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 560)
    defer host.shutdown()

    let index  = expect ViewerPluginIndex.parse(cast(string) DefaultPluginIndex, "plugins")
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.currentView     = Wnd.create'Wnd(window)
    window.currentCommands = Wnd.create'Wnd(window.commandBar)
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

    let index  = expect ViewerPluginIndex.parse(cast(string) DefaultPluginIndex, "plugins")
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
    let commandCount   = window.commandBar.children.count
    window.activeChoiceIndex = 1
    @assert(window.activateChoice(0))
    @assert(window.currentView == cachedView)
    @assert(window.currentCommands == cachedCommands)
    @assert(window.children.count == childCount)
    @assert(window.commandBar.children.count == commandCount)
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

    let index  = expect ViewerPluginIndex.parse(cast(string) DefaultPluginIndex, "plugins")
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
// format-specific controls before a file has selected a plugin.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let index  = expect ViewerPluginIndex.parse(cast(string) DefaultPluginIndex, "plugins")
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

// Pins the open-document composition in both application palettes: navigation, viewer selection
// and contextual actions share one row above the document, with persistent file identity below.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let index  = expect ViewerPluginIndex.parse(cast(string) DefaultPluginIndex, "plugins")
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(960, 680)
    window.openFile(viewerFixturePath().toString())
    window.applyLayout()
    host.settleAnimations(window, 4)

    @assert(window.viewerCombo.isLocallyVisible())
    @assert(window.currentCommands!.parent == window.commandBar)
    @assert(window.searchBox.isLocallyVisible() and window.searchBox.isEnabled())
    var dark = host.render(window)
    Pixel.Testing.assertImageGolden(&dark, "sfilescope.viewer.dark")

    window.applyTheme(1)
    host.notify(.ThemeChanged)
    host.settleAnimations(window, 4)
    var light = host.render(window)
    Pixel.Testing.assertImageGolden(&light, "sfilescope.viewer.light")
}
