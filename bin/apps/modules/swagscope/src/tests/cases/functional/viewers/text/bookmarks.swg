#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

private func textBookmarkRows(view: *PlainText.Panel, host: *Testing.HeadlessHost, query: string)->Lens.Results
{
    var results = Testing.lensResults(query)
    var entries = Viewer.LensEntries.create(&results, PlainText.texts().ui_Name, host.theme)
    view.describeLens(&entries)
    return results
}

// Named bookmarks reject ambiguous names, navigate in file order, can be renamed, and clear.
#test
{
    let fileName = Testing.tempFilePath("scope-text-bookmarks-", ".txt")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "first\nsecond\nthird\nfourth\n")

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    let view = assume cast(*PlainText.Panel, session.view)
    completeTextReads(&host, view)
    let first = view.lines.offsetOfLine(fileName, 1, view.encoding, view.contentStart)
    let third = view.lines.offsetOfLine(fileName, 3, view.encoding, view.contentStart)
    Swag.require(view.storeBookmark("Start", 1, first))
    Swag.require(view.addCurrentPositionBookmark("Here"))
    Swag.require(view.storeBookmark("Middle", 3, third))
    Swag.require(not view.storeBookmark("start", 2, first))
    Swag.require(not view.storeBookmark("  ", 2, first))

    Swag.require(view.navigateToBookmark(2))
    completeTextReads(&host, view)
    Swag.require(view.currentByteOffset() == third)
    var previousKey = KeyEvent{kind: .Pressed, key: .PageUp, modifiers: .Control | .Shift}
    Swag.require(view.handleBookmarkKey(&previousKey))
    completeTextReads(&host, view)
    Swag.require(view.currentByteOffset() == first)
    var nextKey = KeyEvent{kind: .Pressed, key: .PageDown, modifiers: .Control | .Shift}
    Swag.require(view.handleBookmarkKey(&nextKey))
    completeTextReads(&host, view)
    Swag.require(view.currentByteOffset() == third)
    Swag.require(view.navigateBookmark(-1))
    completeTextReads(&host, view)
    Swag.require(view.currentByteOffset() == first)
    Swag.require(not view.navigateBookmark(-1))
    Swag.require(view.navigateBookmark(1))
    completeTextReads(&host, view)
    Swag.require(view.currentByteOffset() == third)
    Swag.require(view.revealLensDestination(third + 1))
    completeTextReads(&host, view)
    Swag.require(view.navigateBookmark(-1))
    completeTextReads(&host, view)
    Swag.require(view.currentByteOffset() == first)
    Swag.require(not view.navigateBookmark(-1))
    Swag.require(view.renameBookmark(2, "End"))
    Swag.require(not view.renameBookmark(2, "Start"))

    let rows = textBookmarkRows(view, &host, "End")
    var found = false
    for section in rows.sections
    {
        for entry in section!.entries where entry.title == "End" do
            found = not entry.disabled and entry.detail == Format.toString(PlainText.texts().ui_BookmarkLine, 3)
    }
    Swag.require(found)

    host.clickModalButtonWhenShown(Dialog.BtnYes)
    view.confirmClearBookmarks()
    host.pump()
    Swag.require(view.bookmarks.isEmpty())
}

// A known resident position can be bookmarked when whole-file line counting is unavailable.
#test
{
    let fileName = Testing.tempFilePath("scope-text-bookmarks-unknown-line-", ".txt")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "first\nsecond\nthird\n")

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName)
    let view = assume cast(*PlainText.Panel, session.view)
    completeTextReads(&host, view)
    let second = view.lines.offsetOfLine(fileName, 2, view.encoding, view.contentStart)
    let third = view.lines.offsetOfLine(fileName, 3, view.encoding, view.contentStart)
    Swag.require(view.revealLensDestination(second, "", caret: true))
    completeTextReads(&host, view)
    view.windowLine = 0

    Swag.require(view.currentLine() == 0 and view.currentByteOffset() == second)
    Swag.require(view.canBookmarkCurrentPosition())
    Swag.require(view.addCurrentPositionBookmark("Here"))
    Swag.require(view.bookmarks[0].line == 0 and view.bookmarks[0].offset == second)
    Swag.require(view.storeBookmark("Later", 3, third))

    let rows = textBookmarkRows(view, &host, "Here")
    var found = false
    for section in rows.sections
    {
        for entry in section!.entries where entry.title == "Here" do
            found = not entry.disabled and entry.detail == Format.toString(PlainText.texts().ui_BookmarkOffset, second)
    }
    Swag.require(found)
    Swag.require(view.navigateBookmark(1))
    completeTextReads(&host, view)
    Swag.require(view.currentByteOffset() == third)
    Swag.require(view.navigateBookmark(-1))
    completeTextReads(&host, view)
    Swag.require(view.currentByteOffset() == second)
}

// The resident byte fallback respects a BOM and multibyte code units in the active encoding.
#test
{
    let fileName = Testing.tempFilePath("scope-text-bookmarks-unknown-line-utf16-", ".txt")
    defer discard catch File.delete(fileName)
    let bytes = [0xFF'u8, 0xFE, 0x61, 0, 0x0A, 0, 0xE9, 0, 0x78, 0, 0x0A, 0, 0x7A, 0]
    discard expect File.writeAllBytes(fileName, bytes)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName)
    let view = assume cast(*PlainText.Panel, session.view)
    completeTextReads(&host, view)
    Swag.require(view.encoding == .Utf16Le and view.contentStart == 2)
    let second = view.lines.offsetOfLine(fileName, 2, view.encoding, view.contentStart)
    Swag.require(view.revealLensDestination(second, "", caret: true, caretColumn: 1))
    completeTextReads(&host, view)
    view.windowLine = 0

    Swag.require(view.currentLine() == 0 and view.currentByteOffset() == second + 2)
    Swag.require(view.addCurrentPositionBookmark("Wide"))
    Swag.require(view.bookmarks[0].line == 0 and view.bookmarks[0].offset == second + 2)
}

// Bookmark storage is bounded, and an offset remains usable after the resident window is evicted.
#test
{
    let fileName = Testing.tempFilePath("scope-text-bookmarks-stream-", ".txt")
    defer discard catch File.delete(fileName)
    var source: String
    for line in 0 until 50_000 do
        source += Format.toString("line %\n", line)
    discard expect File.writeAllText(fileName, source)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var session = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName)
    let view = assume cast(*PlainText.Panel, session.view)
    completeTextReads(&host, view)
    let distant = view.lines.offsetOfLine(fileName, 40_000, view.encoding, view.contentStart)
    Swag.require(distant > 256 * 1024)
    Swag.require(view.storeBookmark("Far", 40_000, distant))
    for index in 1 until 64 do
        Swag.require(view.storeBookmark(Format.toString("Mark %", index), 1, 0))
    Swag.require(not view.storeBookmark("Too Many", 1, 0))

    let rows = textBookmarkRows(view, &host, "Bookmark Current Line")
    for section in rows.sections
    {
        for entry in section!.entries where entry.title == PlainText.texts().ui_BookmarkCurrentPosition do
            Swag.require(entry.disabled)
    }

    Swag.require(view.navigateToBookmark(0))
    completeTextReads(&host, view)
    Swag.require(view.residentStart > 0 and view.currentByteOffset() == distant)
}

// A reload transfers in-memory bookmarks, then marks them stale if the file identity changed.
#test
{
    let fileName = Testing.tempFilePath("scope-text-bookmarks-stale-", ".txt")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "first\nsecond\nthird\n")

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var original = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName)
    let originalView = assume cast(*PlainText.Panel, original.view)
    completeTextReads(&host, originalView)
    let second = originalView.lines.offsetOfLine(fileName, 2, originalView.encoding, originalView.contentStart)
    Swag.require(originalView.storeBookmark("Saved", 2, second))
    var state: ViewerReadingState
    state.capture(&original, "text", "")

    discard expect File.writeAllText(fileName, "replacement has a different length\n")
    var replacement = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName)
    let replacementView = assume cast(*PlainText.Panel, replacement.view)
    completeTextReads(&host, replacementView)
    Swag.require(state.restore(&replacement))
    Swag.require(replacementView.bookmarks.count == 1 and replacementView.refreshBookmarkStaleness())
    Swag.require(not replacementView.navigateToBookmark(0))

    let rows = textBookmarkRows(replacementView, &host, "Saved")
    var foundStale = false
    for section in rows.sections
    {
        for entry in section!.entries where entry.title == "Saved" do
            foundStale = entry.disabled and entry.detail == PlainText.texts().ui_BookmarkStale
    }
    Swag.require(foundStale)
}

// Text bookmarks survive a window state round-trip and restore when the same file opens again.
#test
{
    let fileName = Testing.tempFilePath("scope-text-bookmarks-persisted-", ".txt")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "first\nsecond\nthird\n")

    var host: Testing.HeadlessHost
    host.setup(800, 560)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    window.openFile(fileName, remember: false)
    completeQueuedViewerFile(&host, window)
    let view = assume cast(*PlainText.Panel, window.currentView)
    let second = view.lines.offsetOfLine(fileName, 2, view.encoding, view.contentStart)
    Swag.require(view.storeBookmark("Saved", 2, second))

    let saved = saveViewerState(window)
    Swag.require(window.textBookmarkFiles.count == 1)

    var reopenedHost: Testing.HeadlessHost
    reopenedHost.setup(800, 560)
    let reopened = ViewerWindow.create(&reopenedHost.surfaceWnd, createViewerPluginRegistry())
    loadViewerState(reopened, saved.toSlice())
    Swag.require(reopened.textBookmarkFiles.count == 1)
    reopened.openFile(fileName, remember: false)
    completeQueuedViewerFile(&reopenedHost, reopened)
    let restored = assume cast(*PlainText.Panel, reopened.currentView)
    Swag.require(restored.bookmarks.count == 1)
    Swag.require(restored.bookmarks[0].label == "Saved" and not restored.refreshBookmarkStaleness())
    Swag.require(restored.navigateToBookmark(0))
    completeTextReads(&reopenedHost, restored)
    Swag.require(restored.currentLine() == 2)

    discard expect File.writeAllText(fileName, "replacement has a different length\n")
    reopened.openFile(fileName, remember: false)
    completeQueuedViewerFile(&reopenedHost, reopened)
    let replaced = assume cast(*PlainText.Panel, reopened.currentView)
    Swag.require(replaced.bookmarks.count == 1 and replaced.refreshBookmarkStaleness())
}

// Durable text bookmark storage evicts the least recently stored file at its fixed bound.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 560)
    let window = ViewerWindow.create(&host.surfaceWnd, createViewerPluginRegistry())
    var bookmarks: Array'Viewers.PlainText.Bookmark
    for bookmark in 80 do
        bookmarks.add(Viewers.PlainText.Bookmark{String.from(Format.toString("Mark %", bookmark)), bookmark + 1, bookmark})
    for file in 65
    {
        window.storeTextBookmarkFile(Format.toString("text-bookmark-%", file), "identity", bookmarks.toSlice())
    }

    Swag.require(window.textBookmarkFiles.count == 64)
    Swag.require(not Path.equals(window.textBookmarkFiles[0].path, "text-bookmark-0"))
    Swag.require(Path.equals(window.textBookmarkFiles[63].path, "text-bookmark-64"))
    Swag.require(window.textBookmarkFiles[63].bookmarks.count == 64)
    Swag.require(window.textBookmarkFiles[63].bookmarks[0].label == "Mark 16")
}
