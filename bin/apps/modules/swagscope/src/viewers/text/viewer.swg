#global internal
#global namespace Viewers.PlainText

using Core, Pixel, Gui

private var g_ZoomPercent: u32 = 100

// Whether basic text numbers its lines. The choice follows the reader from file to file.
private var g_LineNumbers: bool

// Whether basic text marks its spaces and tabulations. The choice follows the reader from file to file.
private var g_Blanks: bool

// Width of a tab stop in basic text, in spaces. The choice follows the reader from file to file.
private var g_TabWidth: s32 = 4

internal func defaultTabWidth()->s32 => g_TabWidth

internal func setDefaultTabWidth(width: s32)
{
    g_TabWidth = width == 2 or width == 4 or width == 8 ? width : 4
}

// Stable identity and smoke input of the text plugin.
const ViewerKey    = "text"
const SmokeFixture = "comprehensive.txt"

// What the text surface owns by name, like every other format-specific viewer.
private const NamedExtensions = ".txt;.text;.log;.nfo;.diz;.rst;.adoc;.asc;.srt;.vtt;.sub;.ssa;.ass;.lrc;.diff;.patch;readme;license;licence;changelog;authors;copying;install;news;todo"

private func pluginName()->string => texts().ui_Name

// Offers the text surface for whatever reads as text, once the formats have had their turn.
//
// Reading the head is a weak question asked alone: a PDF, an office document and a font all open
// with enough printable bytes to pass it, and offering to read one of them as a page of text says
// something untrue about the file. The formats that recognize themselves answer first, so what
// reaches this probe is either a file nothing claimed — an extensionless note, a log named `.dat`,
// a UTF-16 export — or a document whose viewer reads text anyway, where the raw source is a second
// reading of the same thing rather than a contradiction of the first.
private func pluginProbe(content: Viewer.ProbeContent)->bool
{
    if content.claimed and not content.claimedText do
        return false
    if not content.head.count do
        return false
    return Panel.probeHead(content.head).accepted
}

// Describes the text viewer to the host.
//
// The surface registers the extensions and extensionless names it owns, and answers for any other
// file whose beginning reads as text, whichever encoding spells it.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = ViewerKey
        .resolveName  = &pluginName
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Text)
        .create       = &createViewer
        .probe        = &pluginProbe
        .textual      = true
        .smokeFixture = SmokeFixture
        .addSelectors(NamedExtensions)
    }

    return result
}

private
{
    const StreamChunkSize = 16 * 1024'u64

    // Viewport heights of text kept loaded from the top of the visible one: it and five more.
    const StreamLookAhead    = 6.0
    const ResidentWindowSize = 256 * 1024'u64
    const RevealContextSize  = 16 * 1024'u64
    const LensHistoryLimit   = 64'u64
    const BookmarkNameLimit  = 128'u64

    // Bytes the window is counted over to name the cursor line when the gutter does not ask for it.
    const QuietLineCountLimit = 4 * 1024 * 1024'u64

    // The encodings offered in the action bar, in the order the selector lists them.
    const Encodings: [6] Text.Encoding = [.Utf8, .Utf16Le, .Utf16Be, .Utf32Le, .Utf32Be, .Windows1252]
}

// A session bookmark survives replacement of the resident text window.
internal struct Bookmark
{
    label:  String
    line:   u64
    offset: u64
}

private func textFileIdentity(fileName: string)->String
{
    let absolute = catch Path.absolute(fileName) { return "" }
    let info     = catch File.info(absolute) { return "" }
    return Format.toString("%\n%\n%\n%",
                          absolute,
                          info.size,
                          Hash.hash64(info.creationTime),
                          Hash.hash64(info.lastWriteTime))
}

// What the head of a file says about how it spells its characters.
struct Probe
{
    encoding:     Text.Encoding     // How the bytes read as characters.
    contentStart: u64      // First byte of text, past a byte-order mark.
    accepted:     bool     // Whether what it decodes to is text a reader should be shown.
}

// Text view available for readable content independently of the format-specific viewers.
struct Panel
{
    using wnd: Wnd

    late
    {
        info:          *Wnd
        editor:        *RichEditCtrl
        optionsButton: *IconButton
        zoomLabel:     *IconButton
    }

    read:               Read
    residentText:       String
    pendingMatch:       String
    pendingCaret:       bool     // Whether the window being read is to place the caret at `pendingSeekOffset`.
    pendingCaretColumn: u64
    pendingHasCaretColumn: bool
    hasEstimatedLine:  bool
    estimatedLine:     u64
    pendingNavigation:  Input.Key
    internal lensHistory: Array'u64
    internal lensHistoryIndex: u64 = Swag.U64.Max
    internal replayingLensHistory: bool
    fileIdentity:       String
    internal bookmarkIdentity: String
    internal bookmarks: Array'Bookmark
    internal bookmarksStale: bool
    internal bookmarksPersistable: bool = true
    retiring:           bool
    readFailed:         bool
    fileName:           String
    fileSize:           u64
    bytesRead:          u64
    residentStart:      u64
    residentOffsetY:    f32
    virtualHeight:      f32
    loadTimer:          *Timer?
    statisticsTask:     Swag.Task'TextStatistics
    hasStatistics:      bool
    statistics:         TextStatistics
    statisticsEncoding: Text.Encoding
    statisticsStart:    u64
    hasText:            bool
    pauseStreaming:     bool
    pendingSeek:        bool
    pendingSeekOffset:  u64
    repositioning:      bool
    encoding:           Text.Encoding
    displayedEncoding:  Text.Encoding
    contentStart:       u64
    wrapping:           bool = true
    lineNumbers:        bool
    blanks:             bool
    tabWidth:           s32  = 4
    windowLine:         u64     // Number of the resident window's first line, or zero when it is not counted.
    lines:              Viewer.LineCounter
    zoomPercent:        u32  = 100
    services:           Viewer.HostServices
}

// Reports whether `evt` is the wrap shortcut, Ctrl+W with no other modifier. The editor's hook and
// the panel both answer it, so the shortcut behaves the same wherever the focus is.
private func isWrapKey(evt: const *KeyEvent)->bool => evt.kind == .Pressed and evt.key == .W and evt.modifiers == .Control

// Counts the text statistics of `fileName` from `start` to the end, as `encoding` decodes it.
//
// A count asked to stop returns what it has so far; the viewer never shows those totals.
private func countStatistics(fileName: string, start: u64, encoding: Text.Encoding)->TextStatistics fail
{
    var stream = try File.openReadLive(fileName)
    discard catch stream.seek(.Begin, start)

    var counter: TextStatisticsCounter
    counter.totals.bytes = start
    while not Swag.isCancelled()
    {
        let previousPosition = try stream.position()
        let chunk = try stream.readTextChunk(StreamChunkSize, encoding)
        if chunk.isEmpty()
        {
            return counter.finish(.Exact)
        }
        let position = try stream.position()
        counter.append(chunk, position - previousPosition)
    }

    return counter.finish()
}

impl Panel
{
    mtd searchBounds(result: *Math.Rectangle)->bool
    {
        if not .pendingMatch.isEmpty() do
            return false
        return Viewer.richEditMatchBounds(.editor, result)
    }

    mtd clearSearch()
    {
        .pendingMatch.clear()
        Viewer.clearRichEditMatch(.editor)
    }

    // Returns the number of the line under the cursor in the whole file, or zero when the lines
    // before the resident window are not counted. The editor holds one window of the file, so its
    // own line index starts again at every window.
    mtd currentLine()->u64 => .windowLine ? .windowLine + .editor.cursorLogicalLineIndex() : 0

    // Returns the exact source byte under the caret while its whole-file line is known.
    mtd currentByteOffset()->u64
    {
        let line = .currentLine()
        if not line do
            return Swag.U64.Max
        let start = .lines.offsetOfLine(.fileName, line, .encoding, .contentStart)
        if start == Swag.U64.Max do
            return Swag.U64.Max
        return .offsetOfColumn(start, .editor.cursorLogicalCharPos() + 1).offset
    }

    // Records Lens destinations as file offsets, independent of the resident window.
    private mtd recordLensDestination(offset, from: u64)
    {
        if .replayingLensHistory or offset > .fileSize do
            return
        let origin = Math.min(from, .fileSize)

        if not .lensHistory.count
        {
            .lensHistory.add(origin)
            .lensHistoryIndex = 0
        }
        elif .lensHistoryIndex < .lensHistory.count and .lensHistory[.lensHistoryIndex] != origin
        {
            .lensHistory.resize(.lensHistoryIndex + 1)
            .lensHistory.add(origin)
            .lensHistoryIndex = .lensHistory.count - 1
        }

        if .lensHistoryIndex < .lensHistory.count and .lensHistory[.lensHistoryIndex] == offset do
            return
        if .lensHistoryIndex != Swag.U64.Max and .lensHistoryIndex + 1 < .lensHistory.count do
            .lensHistory.resize(.lensHistoryIndex + 1)
        .lensHistory.add(offset)
        .lensHistoryIndex = .lensHistory.count - 1

        if .lensHistory.count > LensHistoryLimit
        {
            .lensHistory.remove(0, .lensHistory.count - LensHistoryLimit)
            .lensHistoryIndex = .lensHistory.count - 1
        }
    }

    // Opens a Lens destination and records its file offset with the current caret as a return point.
    internal mtd revealLensDestination(offset: u64,
                                       text: string = "",
                                       caret = true,
                                       caretColumn = Swag.U64.Max,
                                       estimatedLine = 0'u64)->bool
    {
        if offset > .fileSize do
            return false
        let current = .currentByteOffset()
        let from = current == Swag.U64.Max ? .residentStart : current
        var destination = Math.min(offset, .fileSize)
        if caretColumn != Swag.U64.Max and caretColumn do
            destination = .offsetOfColumn(destination, caretColumn + 1).offset
        if not .revealOffset(offset, text, caret: caret, caretColumn: caretColumn, estimatedLine: estimatedLine) do
            return false
        .recordLensDestination(destination, from)
        return true
    }

    // Returns to a recorded Lens destination, without adding another history visit.
    private mtd navigateLensHistory(direction: s32)->bool
    {
        if .lensHistoryIndex == Swag.U64.Max do
            return false
        let next = cast(s64, .lensHistoryIndex) + direction
        if next < 0 or next >= cast(s64, .lensHistory.count) do
            return false
        .replayingLensHistory = true
        defer .replayingLensHistory = false
        let offset = .lensHistory[cast(u64, next)]
        if not .revealOffset(offset, "", caret: true) do
            return false
        .lensHistoryIndex = cast(u64, next)
        return true
    }

    mtd handleLensHistoryKey(evt: const *KeyEvent)->bool
    {
        let direction = Viewer.historyKeyDirection(evt)
        if direction < 0 do
            return .navigateLensHistory(-1)
        if direction > 0 do
            return .navigateLensHistory(1)
        return false
    }

    mtd handleBookmarkKey(evt: const *KeyEvent)->bool
    {
        if evt.kind != .Pressed do
            return false
        let modifiers = Input.KeyModifiers.Control | .Shift
        if evt.modifiers != modifiers do
            return false
        switch evt.key
        {
        case .B:
            .promptBookmarkCurrentLine()
            return true
        case .PageUp:
            return .navigateBookmark(-1)
        case .PageDown:
            return .navigateBookmark(1)
        default:
            return false
        }
    }

    mtd refreshBookmarkStaleness()->bool
    {
        if .bookmarks.isEmpty()
        {
            .bookmarksStale = false
            return false
        }
        let currentIdentity = textFileIdentity(.fileName)
        .bookmarksStale = currentIdentity.isEmpty() or currentIdentity != .bookmarkIdentity
        return .bookmarksStale
    }

    mtd canBookmarkCurrentLine()->bool
    {
        if not .currentLine() or
           .bookmarks.count >= ViewerTextBookmarkLimit or
           .fileIdentity.isEmpty() or
           .refreshBookmarkStaleness() or
           textFileIdentity(.fileName) != .fileIdentity do
            return false
        return .lines.offsetOfLine(.fileName, .currentLine(), .encoding, .contentStart) != Swag.U64.Max
    }

    // Stores one named line after the current file and its exact line start are checked.
    internal mtd addCurrentLineBookmark(label: string)->bool
    {
        if not .canBookmarkCurrentLine() do
            return false
        let line = .currentLine()
        let offset = .lines.offsetOfLine(.fileName, line, .encoding, .contentStart)
        return .storeBookmark(label, line, offset)
    }

    // Adds a bookmark at a known exact line start; shared by the lens prompt and focused tests.
    internal mtd storeBookmark(label: string, line, offset: u64)->bool
    {
        let name = Latin1.trim(label)
        if name.count == 0 or name.count > BookmarkNameLimit or
           not line or offset > .fileSize or .bookmarks.count >= ViewerTextBookmarkLimit or
           .fileIdentity.isEmpty() or .refreshBookmarkStaleness() or
           textFileIdentity(.fileName) != .fileIdentity do
            return false
        for bookmark in .bookmarks where Utf8.compare(bookmark.label, name, .Latin1NoCase) == 0 do
            return false

        if .bookmarks.isEmpty() do
            .bookmarkIdentity = .fileIdentity
        .bookmarks.add(Bookmark{String.from(name), line, offset})
        .bookmarksStale = false
        return true
    }

    internal mtd restoreBookmarks(saved: const [..] Bookmark, identity: string)
    {
        .bookmarks.clear()
        for bookmark in saved do
            .bookmarks.add(bookmark)
        .bookmarkIdentity = identity
        discard .refreshBookmarkStaleness()
    }

    internal mtd renameBookmark(index: u64, label: string)->bool
    {
        if index >= .bookmarks.count do
            return false
        let name = Latin1.trim(label)
        if name.count == 0 or name.count > BookmarkNameLimit do
            return false
        for bookmark, other in .bookmarks where other != index and
                                                Utf8.compare(bookmark.label, name, .Latin1NoCase) == 0 do
            return false
        .bookmarks[index].label = String.from(name)
        return true
    }

    mtd navigateToBookmark(index: u64)->bool
    {
        if index >= .bookmarks.count or .refreshBookmarkStaleness() do
            return false
        return .revealLensDestination(.bookmarks[index].offset)
    }

    mtd bookmarkIndexInDirection(direction: s32)->u64
    {
        if .bookmarks.isEmpty() or .refreshBookmarkStaleness() do
            return Swag.U64.Max
        let current = .currentLine()
        if not current do
            return Swag.U64.Max
        var found = Swag.U64.Max
        if direction < 0
        {
            var best = 0'u64
            for bookmark, index in .bookmarks where bookmark.line < current and
                                                       (found == Swag.U64.Max or bookmark.line > best)
            {
                found = index
                best = bookmark.line
            }
        }
        else
        {
            var best = Swag.U64.Max
            for bookmark, index in .bookmarks where bookmark.line > current and
                                                       (found == Swag.U64.Max or bookmark.line < best)
            {
                found = index
                best = bookmark.line
            }
        }
        return found
    }

    mtd navigateBookmark(direction: s32)->bool
    {
        let found = .bookmarkIndexInDirection(direction)
        if found == Swag.U64.Max do
            return false
        return .navigateToBookmark(found)
    }

    internal mtd promptBookmarkCurrentLine()
    {
        if not .canBookmarkCurrentLine() do
            return
        let strings = texts()
        let dialog = EditDlg.createSingleLine(unwrap .surface,
                                              {title: strings.ui_BookmarkCurrentLine,
                                               message: strings.ui_BookmarkNameHint,
                                               text: Format.toString(strings.ui_BookmarkDefaultName, .currentLine()),
                                               confirmButtonText: strings.ui_BookmarkAdd})
        if dialog.doModal() != Dialog.BtnOk do
            return
        if not .addCurrentLineBookmark(dialog.text()) do
            MessageDlg.error(.surface,
                             strings.ui_BookmarkNameInvalid,
                             options: {title: strings.ui_BookmarkCurrentLine})
    }

    internal mtd promptRenameBookmark(index: u64)
    {
        if index >= .bookmarks.count do
            return
        let strings = texts()
        let dialog = EditDlg.createSingleLine(unwrap .surface,
                                              {title: Format.toString(strings.ui_RenameBookmark, .bookmarks[index].label),
                                               message: strings.ui_BookmarkNameHint,
                                               text: .bookmarks[index].label,
                                               confirmButtonText: strings.ui_Rename})
        if dialog.doModal() != Dialog.BtnOk do
            return
        if not .renameBookmark(index, dialog.text()) do
            MessageDlg.error(.surface,
                             strings.ui_BookmarkNameInvalid,
                             options: {title: Format.toString(strings.ui_RenameBookmark, .bookmarks[index].label)})
    }

    internal mtd clearBookmarks()
    {
        .bookmarks.clear()
        .bookmarkIdentity = .fileIdentity
        .bookmarksStale = false
    }

    internal mtd confirmClearBookmarks()
    {
        if .bookmarks.isEmpty() do
            return
        var options: MessageDlgOptions
        options.title = texts().ui_ClearBookmarks
        if MessageDlg.confirm(unwrap .surface, texts().ui_ClearBookmarksMessage, options: options) == Dialog.BtnYes do
            .clearBookmarks()
    }

    // Turns a one-based character column into a file byte offset without assuming UTF-8 storage.
    // The read ends at the requested character or the first line break, whichever comes first.
    mtd offsetOfColumn(lineStart, column: u64)->{offset: u64, column: u64}
    {
        if column <= 1 do
            return {lineStart, 1}

        let unit = Text.unitSize(.encoding)
        let available = .fileSize - Math.min(lineStart, .fileSize)
        let requested = column - 1 > (Swag.U64.Max - 8) / 4 ? Swag.U64.Max : (column - 1) * 4 + 8
        let byteLimit = Math.min(available, requested)
        var file = catch File.openReadLive(.fileName) { return {lineStart, 1} }
        defer file.close()
        discard catch file.seek(.Begin, lineStart) { return {lineStart, 1} }

        var bytes: Array'u8
        bytes.resize(byteLimit)
        let count = catch file.read(bytes.toSlice()) { return {lineStart, 1} }
        bytes.resize(count)

        var at = 0'u64
        var reached = 1'u64
        while at < count
        {
            var width = unit
            var lineBreak = false
            if .encoding == .Utf8
            {
                let decoded = Utf8.decodeRune(bytes.toSlice()[at to])
                width = Math.max(cast(u64, decoded.eat), 1)
                lineBreak = decoded.c == '\n' or decoded.c == '\r'
            }
            elif .encoding == .Utf16Le or .encoding == .Utf16Be
            {
                if count - at < 2 do
                    break
                let first = .encoding == .Utf16Le ?
                            cast(u16, bytes[at]) | (cast(u16, bytes[at + 1]) << 8) :
                            (cast(u16, bytes[at]) << 8) | cast(u16, bytes[at + 1])
                lineBreak = first == 10 or first == 13
                if first >= 0xD800 and first <= 0xDBFF and count - at >= 4
                {
                    let second = .encoding == .Utf16Le ?
                                 cast(u16, bytes[at + 2]) | (cast(u16, bytes[at + 3]) << 8) :
                                 (cast(u16, bytes[at + 2]) << 8) | cast(u16, bytes[at + 3])
                    if second >= 0xDC00 and second <= 0xDFFF do
                        width = 4
                }
            }
            elif .encoding == .Utf32Le or .encoding == .Utf32Be
            {
                if count - at < 4 do
                    break
                let value = .encoding == .Utf32Le ?
                            cast(u32, bytes[at]) | (cast(u32, bytes[at + 1]) << 8) |
                            (cast(u32, bytes[at + 2]) << 16) | (cast(u32, bytes[at + 3]) << 24) :
                            (cast(u32, bytes[at]) << 24) | (cast(u32, bytes[at + 1]) << 16) |
                            (cast(u32, bytes[at + 2]) << 8) | cast(u32, bytes[at + 3])
                lineBreak = value == 10 or value == 13
            }
            else
            {
                lineBreak = bytes[at] == 10 or bytes[at] == 13
            }

            if lineBreak do
                return {lineStart + at, reached}
            at += width
            reached += 1
            if reached == column do
                return {lineStart + at, reached}
        }

        return {lineStart + at, reached}
    }

    // Counts decoded characters from `lineStart` to a boundary-aligned byte offset.
    mtd columnAtOffset(lineStart, offset: u64)->u64
    {
        let countLimit = Math.min(offset - Math.min(lineStart, offset), .fileSize - Math.min(lineStart, .fileSize))
        var file = catch File.openReadLive(.fileName) { return 1 }
        defer file.close()
        discard catch file.seek(.Begin, lineStart) { return 1 }

        var bytes: Array'u8
        bytes.resize(countLimit)
        let count = catch file.read(bytes.toSlice()) { return 1 }
        bytes.resize(count)

        var at = 0'u64
        var column = 1'u64
        while at < count
        {
            var width = 0'u64
            var lineBreak = false
            if .encoding == .Utf8
            {
                let decoded = Utf8.decodeRune(bytes.toSlice()[at to])
                width = Math.max(cast(u64, decoded.eat), 1)
                lineBreak = decoded.c == '\n' or decoded.c == '\r'
            }
            elif .encoding == .Utf16Le or .encoding == .Utf16Be
            {
                if count - at < 2 do
                    break
                let first = .encoding == .Utf16Le ?
                            cast(u16, bytes[at]) | (cast(u16, bytes[at + 1]) << 8) :
                            (cast(u16, bytes[at]) << 8) | cast(u16, bytes[at + 1])
                lineBreak = first == 10 or first == 13
                var size = 2'u64
                if first >= 0xD800 and first <= 0xDBFF and count - at >= 4
                {
                    let second = .encoding == .Utf16Le ?
                                 cast(u16, bytes[at + 2]) | (cast(u16, bytes[at + 3]) << 8) :
                                 (cast(u16, bytes[at + 2]) << 8) | cast(u16, bytes[at + 3])
                    if second >= 0xDC00 and second <= 0xDFFF do
                        size = 4
                }
                width = size
            }
            elif .encoding == .Utf32Le or .encoding == .Utf32Be
            {
                if count - at < 4 do
                    break
                let value = .encoding == .Utf32Le ?
                            cast(u32, bytes[at]) | (cast(u32, bytes[at + 1]) << 8) |
                            (cast(u32, bytes[at + 2]) << 16) | (cast(u32, bytes[at + 3]) << 24) :
                            (cast(u32, bytes[at]) << 24) | (cast(u32, bytes[at + 1]) << 16) |
                            (cast(u32, bytes[at + 2]) << 8) | cast(u32, bytes[at + 3])
                lineBreak = value == 10 or value == 13
                width = 4
            }
            else
            {
                lineBreak = bytes[at] == 10 or bytes[at] == 13
                width = 1
            }

            if lineBreak do
                break
            at += width
            column += 1
        }

        return column
    }

    // Keeps file-offset jumps on a decoded character boundary for the active encoding.
    mtd alignOffset(offset: u64)->u64
    {
        if .fileSize <= .contentStart do
            return .contentStart
        let target = Math.clamp(offset, .contentStart, .fileSize - 1)
        if .encoding != .Utf8
        {
            let unit = Text.unitSize(.encoding)
            return .contentStart + (target - .contentStart) / unit * unit
        }

        if target <= .contentStart do
            return .contentStart
        let start = Math.max(.contentStart, target > 3 ? target - 3 : 0)
        var file = catch File.openReadLive(.fileName) { return target }
        defer file.close()
        discard catch file.seek(.Begin, start) { return target }
        var bytes: [4] u8
        let count = catch file.read(bytes) { return target }
        for index in count where start + index <= target
        {
            let decoded = Utf8.decodeRune(bytes[index until count])
            let width = Math.max(cast(u64, decoded.eat), 1)
            if start + index + width > target do
                return start + index
        }
        return target
    }

    // Adds a typed line, line/column, byte offset, or percentage jump to the text lens.
    // False leaves non-position queries to the existing whole-file text search.
    mtd describeTypedPosition(results: *Lens.Results)->bool
    {
        if results.prefix != .Line do
            return false
        let query = Latin1.trim(results.query.toString())
        if not query.count do
            return false

        var separator = Swag.U64.Max
        var digits = true
        for value, index in query
        {
            if value == ':' and separator == Swag.U64.Max and index > 0 and index + 1 < query.count do
                separator = index
            elif not Latin1.isDigit(value) do
                digits = false
        }

        let strings = appStrings()
        if digits
        {
            let wantedText = separator == Swag.U64.Max ? query : query[0 until separator]
            let wanted = catch StrConv.toU64(wantedText) { return false }
            if not wanted do
                return false
            let sample = .lines.estimateOffsetOfLine(.fileName, wanted, .encoding, .contentStart)
            var start = Swag.U64.Max
            var estimated = false
            if sample != Swag.U64.Max
            {
                let anchor = wanted >= .lines.numberedLine ? .lines.numberedOffset : .contentStart
                let distance = sample >= anchor ? sample - anchor : anchor - sample
                if distance > Viewer.LineCountScanLimit
                {
                    start = sample
                    estimated = true
                }
            }

            if start == Swag.U64.Max
            {
                start = .lines.offsetOfLine(.fileName, wanted, .encoding, .contentStart)
                if start == Swag.U64.Max
                {
                    if sample == Swag.U64.Max do
                        return false
                    start = sample
                    estimated = true
                }
                else
                {
                    let actualLine = .lines.lineAt(.fileName, start, .encoding, .contentStart)
                    if actualLine != wanted do
                        return false
                }
            }

            if estimated
            {
                if start == Swag.U64.Max do
                    return false
                start = .alignOffset(start)
            }

            var offset = start
            var column = 0'u64
            if separator != Swag.U64.Max
            {
                let position = .offsetOfColumn(start, catch StrConv.toU64(query[separator + 1 to]) orelse 1)
                offset = position.offset
                column = position.column
            }
            let section = results.addSection(strings.lens_InFile)
            let lineTitle = separator == Swag.U64.Max ? Format.toString(strings.lens_GoToLine, wanted) :
                            Format.toString(strings.lens_GoToLineColumn, wanted, column)
            let title = estimated ? Format.toString("% · %", lineTitle, texts().ui_Estimated) : lineTitle
            with let entry = section.addEntry(title)
            {
                .lead = separator == Swag.U64.Max ? Format.toString("%", wanted) : Format.toString("%:%", wanted, column)
                let caretColumn = separator == Swag.U64.Max ? 0 : column - 1
                .run = func|view = me, start, caretColumn, estimated, wanted|()
                {
                    discard view.revealLensDestination(start, "", caret: true, caretColumn: caretColumn, estimatedLine: estimated ? wanted : 0)
                }
            }
            return true
        }

        let isOffset = Utf8.startsWith(query, "0x") or Utf8.startsWith(query, "0X") or
                       Utf8.startsWith(query, "0d") or Utf8.startsWith(query, "0D") or
                       query[query.count - 1] == '%'
        if not isOffset do
            return false
        let target = parseFileOffset(query, 0, .fileSize)
        if target == Swag.U64.Max do
            return false
        let offset = .alignOffset(target)
        let value = Format.toString("0x%{X}", offset)
        let line = .lines.lineAt(.fileName, offset, .encoding, .contentStart)
        var start = offset
        var caretColumn = 0'u64
        var hasLine = false
        if line
        {
            let lineStart = .lines.offsetOfLine(.fileName, line, .encoding, .contentStart)
            if lineStart != Swag.U64.Max
            {
                start = lineStart
                caretColumn = .columnAtOffset(lineStart, offset) - 1
                hasLine = true
            }
        }
        let section = results.addSection(strings.lens_InFile)
        with let entry = section.addEntry(Viewer.jumpRowText(strings.lens_GoToOffset, value, query))
        {
            if hasLine
            {
                .run = func|view = me, start, caretColumn|() { discard view.revealLensDestination(start, "", caret: true, caretColumn: caretColumn) }
            }
            else
            {
                .run = func|view = me, offset|() { discard view.revealLensDestination(offset, "", caret: true) }
            }
        }
        return true
    }

    mtd detailsText()->String
    {
        var result = String.from(.encodingName())
        let line   = .currentLine()
        if .displayedEncoding == .encoding and line
        {
            result += Format.toString(" · %", Format.toString(texts().ui_CurrentLine, line))
            let column = .editor.cursorLogicalCharPos() + 1
            let offset = .currentByteOffset()
            result += Format.toString(" · %", Format.toString(texts().ui_CurrentColumn, column))
            if offset != Swag.U64.Max do
                result += Format.toString(" · %", Format.toString(texts().ui_CurrentByte, Format.toString("%{X}", offset)))
        }
        elif .displayedEncoding == .encoding and .hasEstimatedLine
        {
            result += Format.toString(" · %", Format.toString(texts().ui_EstimatedLine, .estimatedLine))
            result += Format.toString(" · %", Format.toString(texts().ui_CurrentColumn, .editor.cursorLogicalCharPos() + 1))
            result += Format.toString(" · %", Format.toString(texts().ui_EstimatedOffset, Format.toString("%{X}", .residentStart)))
        }

        // Statistics describe the byte interpretation that produced them. Switching encoding
        // keeps the already finished worker available for retirement, but its totals must not be
        // presented as facts about the newly decoded document.
        if not .hasStatistics or
           .statisticsEncoding != .encoding or
           .statisticsStart != .contentStart do
            return result
        let lines      = .statistics.lines == 1 ? String.from(texts().ui_OneLine) : Format.toString(texts().ui_Lines, .statistics.lines)
        let words      = .statistics.words == 1 ? String.from(texts().ui_OneWord) : Format.toString(texts().ui_Words, .statistics.words)
        let characters = .statistics.characters == 1 ? String.from(texts().ui_OneCharacter) : Format.toString(texts().ui_Characters, .statistics.characters)
        result += Format.toString(" · % · % · %", lines, words, characters)
        return result
    }

    mtd reportStatistics()
    {
        .services.showDetails(me, .detailsText())
    }

    mtd retranslate()
    {
        .optionsButton.toolTip = appStrings().ui_Options
        .zoomLabel.toolTip     = texts().ui_ZoomMenu
        .reportStatistics()
    }

    // Counts lines and words in the background for the current encoding and content start. The
    // totals reach the information band when the count's [[Gui.TaskEvent]] arrives.
    mtd startStatistics()
    {
        .hasStatistics      = false
        .statisticsEncoding = .encoding
        .statisticsStart    = .contentStart

        let view     = me
        let start    = .statisticsStart
        let encoding = .statisticsEncoding
        .statisticsTask.submit(func|view, start, encoding|()->TextStatistics fail => try countStatistics(view.fileName, start, encoding),
                               .taskNotifier(&.statisticsTask),
                               .Background)
    }

    // Counts again for the current interpretation. A count still running is asked to stop, and
    // its end starts the new one.
    mtd restartStatistics()
    {
        if .statisticsTask.isPending()
        {
            .statisticsTask.cancel()
            return
        }

        .startStatistics()
    }

    // Stops loading and statistics so the viewer can be destroyed. Returns false while the
    // statistics count or the background read is still finishing; the caller retries.
    mtd retire()->bool
    {
        .retiring = true
        .stopLoading()

        .statisticsTask.cancel()
        if .statisticsTask.isPending() do
            return false
        if .read.started
        {
            if not .read.isDone() do
                return false
            .read.wait()
        }

        return true
    }

    mtd encodingName()->string => Viewer.encodingName(.encoding)

    // Reads the head of a file once and reports how it spells its characters.
    //
    // A file that cannot be read reports the default probe, which accepts nothing.
    func probe(fileName: string)->Probe
    {
        var stream = catch File.openReadLive(fileName) { return {} }

        var bytes: Array'u8
        bytes.resize(Viewer.ProbeHeadSize)
        let count = catch stream.read(bytes.toSlice()) { return {} }
        bytes.resize(count)
        return probeHead(bytes.toSlice())
    }

    // Reports how the beginning of a file spells its characters, and whether it is text at all.
    //
    // Deciding and accepting are two questions: code page 1252 gives every byte a meaning, so an
    // executable also decodes into characters. The encoding answers the first, and what those
    // characters are answers the second.
    func probeHead(head: const [..] u8)->Probe
    {
        var result: #returntype
        result.encoding     = Text.detectEncoding(head)
        result.contentStart = Text.hasBom(head, result.encoding) ? Text.bomLength(result.encoding) : 0
        result.accepted     = Text.looksLikeText(head[result.contentStart to], result.encoding)
        return result
    }

    // Reports whether the beginning of a file reads as text.
    //
    // The basic renderer is a fallback for textual content, not an alternate spelling of every
    // binary format.
    func supports(fileName: string)->bool => probe(fileName).accepted

    mtd hasMore()->bool => not .readFailed and .bytesRead < .fileSize

    mtd needsMore()->bool
    {
        if not .hasMore() do
            return false
        if .pauseStreaming do
            return false
        if .bytesRead - .residentStart >= ResidentWindowSize do
            return false
        let viewport     = .editor.paddedClientRect()
        let loadedHeight = .editor.loadedDocumentHeight()
        return loadedHeight <= 0 or .editor.scrollPosition().y + viewport.height * StreamLookAhead >= .residentOffsetY + loadedHeight
    }

    // Extrapolates the full document height from the bytes read so far and places the resident
    // window within it, so the scroll bar spans the whole file while only part of it is loaded.
    mtd updateEstimatedHeight()
    {
        let consumed = .bytesRead - .residentStart
        if not consumed do
            return
        if .bytesRead >= .fileSize and not .residentStart
        {
            .editor.setEstimatedDocumentHeight(0)
            return
        }

        let loadedHeight = .editor.loadedDocumentHeight()
        if loadedHeight > 0 do
            .virtualHeight = Math.max(.virtualHeight, loadedHeight * cast(f32, .fileSize) / cast(f32, consumed), loadedHeight)
        if .virtualHeight <= 0
        {
            .residentOffsetY = 0
            return
        }

        // The resident window sits where its first byte falls in the estimate, which is what makes
        // a scroll position name the right part of the file. A raised estimate moves it, and the
        // reader's view moves by as much, so the text on screen stays where it was.
        let previousOffset = .residentOffsetY
        .residentOffsetY = .fileSize ? .virtualHeight * cast(f32, .residentStart) / cast(f32, .fileSize) : 0
        .editor.setVirtualDocumentRange(.residentOffsetY, .virtualHeight)
        if .repositioning or not .residentStart or .residentOffsetY == previousOffset do
            return

        .repositioning = true
        defer .repositioning = false
        let position = .editor.scrollPosition()
        .editor.setScrollPosition(Math.Point{position.x, position.y + .residentOffsetY - previousOffset})
    }

    // Schedules the next read when the reader needs one and none is in flight. The short delay
    // lets a burst of scrolling settle on its last position; a read in flight continues the
    // stream itself, from its task event.
    mtd scheduleMore()
    {
        if .retiring or .read.started or .loadTimer do
            return
        if .pendingSeek or .needsMore() do
            .loadTimer = .addTimer(8'ms)
    }

    // Reports whether text is still being read for the view.
    mtd const isStreaming()->bool => .read.started or .pendingSeek or .loadTimer != null

    mtd stopLoading()
    {
        .stopTimer(&.loadTimer)
        .pendingSeek = false
        .pendingHasCaretColumn = false
        if .read.started do
            .read.cancel()
    }

    mtd finishLoading()
    {
        .bytesRead = .fileSize
        if not .residentStart do
            .editor.setEstimatedDocumentHeight(0)
    }

    mtd showReadError()
    {
        .stopLoading()
        .readFailed = true
        let message = texts().ui_NotText
        if not .hasText do
            .editor.setText(message)
        else do
            .editor.addText(Format.toString("\n\n%", message))
        .editor.setEstimatedDocumentHeight(0)
    }

    // Publishes a finished read, or starts the next one; never waits for I/O. A newer seek retires
    // the old result before reusing its storage.
    mtd loadNextChunk()
    {
        if .retiring do
            return
        if .read.started
        {
            if not .read.isDone() do
                return
            .read.wait()
            if .read.wasCancelled()
            {
                .scheduleMore()
                return
            }

            if .read.failed
            {
                if .read.invalidUtf8
                {
                    .applyEncoding(.Windows1252)
                    return
                }

                .showReadError()
                return
            }

            .repositioning = true
            defer .repositioning = false
            let oldPosition = .editor.scrollPosition()
            if .read.replace
            {
                .residentStart = .read.start
                .contentStart  = .read.contentStart
                if .statisticsStart != .contentStart do
                    .restartStatistics()

                .residentText = .read.text
                .editor.setText(.residentText)
            }
            else
            {
                .residentText += .read.text
                .editor.addText(.read.text)
            }

            .displayedEncoding = .read.encoding
            .bytesRead         = .read.end
            .hasText           = .hasText or not .read.text.isEmpty()
            if .read.replace do
                .numberWindow()
            .updateEstimatedHeight()
            .editor.setScrollPosition(oldPosition)
            if not .pendingMatch.isEmpty() or .pendingCaret
            {
                if .encoding == .Utf8 do
                    Viewer.highlightRichEditMatch(.editor, .read.text, .pendingSeekOffset - .residentStart, .pendingMatch.length)
                elif not .pendingMatch.isEmpty() do
                    discard .editor.findText(.pendingMatch)
                else do
                    Viewer.highlightRichEditMatch(.editor, .read.text, 0, 0)
                if .pendingHasCaretColumn
                {
                    .editor.setCursorPos(.editor.cursorFromLogicalPosition(0, .pendingCaretColumn))
                    .pendingHasCaretColumn = false
                }
                .pendingMatch.clear()
                .pendingCaret = false
            }

            if .pendingNavigation == .Home or .pendingNavigation == .End
            {
                .editor.keyPressed(.pendingNavigation, .Control)
                .pendingNavigation = .None
            }

            .reportStatistics()

            if .read.text.isEmpty() or not .hasMore() do
                .finishLoading()
            .read.text.clear()
            return
        }

        if .pendingSeek
        {
            .pendingSeek = false
            let requested = Math.min(.pendingSeekOffset, .fileSize)
            var start     = requested > RevealContextSize ? requested - RevealContextSize : 0

            // A file offset cannot be found again in text decoded from another encoding than
            // UTF-8, so a place with no words to find there starts the window instead. A typed
            // column also starts at its line so the caret can be placed by decoded characters.
            if .pendingHasCaretColumn or (.pendingCaret and .pendingMatch.isEmpty() and .encoding != .Utf8) do
                start = requested
            .read.startRead(.fileName, .encoding, start, 64 * 1024, true, me)
        }
        elif .needsMore()
        {
            .read.contentStart = .contentStart
            .read.startRead(.fileName, .encoding, .bytesRead, StreamChunkSize, false, me)
        }

        .scheduleMore()
    }

    // Highlights `text` at `offset` when it already lies in the resident text in the displayed
    // encoding; otherwise cancels the read in progress and reloads there, highlighting the match
    // once it arrives.
    //
    // With `caret`, the caret is placed at `offset` and brought into view even without text to
    // highlight; without it, an empty `text` only loads the part of the file around `offset` and
    // leaves the view where it is.
    mtd revealOffset(offset: u64, text: string, caret = false, caretColumn = Swag.U64.Max, estimatedLine = 0'u64)->bool
    {
        if (text.count or (caret and .encoding == .Utf8)) and
           caretColumn == Swag.U64.Max and
           .displayedEncoding == .encoding and
           not .pendingSeek and
           not (.read.started and .read.replace) and
           offset >= .residentStart and
           offset <= .bytesRead and
           text.count <= .bytesRead - offset
        {
            if .encoding == .Utf8 do
                Viewer.highlightRichEditMatch(.editor, .residentText, offset - .residentStart, text.count)
            else do
                discard .editor.findText(text)
            .reportStatistics()
            return true
        }

        if .read.started do
            .read.cancel()
        .pendingSeek       = true
        .pendingSeekOffset = Math.min(offset, .fileSize)
        .pendingMatch      = text
        .pendingCaret      = caret
        .pendingHasCaretColumn = caretColumn != Swag.U64.Max
        .pendingCaretColumn = caretColumn == Swag.U64.Max ? 0 : caretColumn
        .hasEstimatedLine = estimatedLine != 0
        .estimatedLine = estimatedLine
        .pendingNavigation = .None
        .readFailed        = false
        .scheduleMore()
        return true
    }

    // Applies wrapping and line numbers to the editor and to the buttons that switch them.
    mtd updateWrap()
    {
        var flags = RichEditFlags.ReadOnly
        if .wrapping do
            flags.add(.WordWrap)
        if .lineNumbers and .windowLine do
            flags.add(.LineNumbers)
        if .blanks do
            flags.add(.DrawBlanks)
        .editor.tabSize = .tabWidth
        .editor.setFlags(flags)
        .scheduleMore()
    }

    // Gives the line numbers of the resident window the count of the lines before it, in the
    // encoding that decoded it. A window too deep in the file to count without a visible pause is
    // shown without numbers rather than with wrong ones.
    //
    // Without the gutter, the window is counted only when that reads little: the line under the
    // cursor is then left unnamed rather than paid for with a pause the reader did not ask for.
    mtd numberWindow()
    {
        let limit = .lineNumbers ? Viewer.LineCountScanLimit : QuietLineCountLimit
        .windowLine = .lines.lineAt(.fileName, .residentStart, .encoding, .contentStart, limit)
        if .windowLine
        {
            .hasEstimatedLine = false
            .estimatedLine    = 0
            .editor.setFirstLineNumber(.windowLine)
        }

        .updateWrap()
    }

    mtd toggleLineNumbers()
    {
        .lineNumbers  = not .lineNumbers
        g_LineNumbers = .lineNumbers
        .numberWindow()
    }

    mtd toggleBlanks()
    {
        .blanks  = not .blanks
        g_Blanks = .blanks
        .updateWrap()
    }

    // Sets the tab stops of the text every `width` spaces.
    mtd setTabWidth(width: s32)
    {
        if width != 2 and width != 4 and width != 8 do
            return
        .tabWidth  = width
        g_TabWidth = width
        .updateWrap()
    }

    // Rereads the resident window under `encoding`, keeping the reader where they were.
    //
    // A byte-order mark only belongs to the encoding that writes it, so a file read against
    // another one shows its mark as content rather than hiding bytes that mean nothing there.
    mtd applyEncoding(encoding: Text.Encoding)
    {
        if encoding == .encoding do
            return
        .encoding = encoding
        .lines.reset()

        .contentStart = 0
        discard .revealOffset(.residentStart, "")
        .restartStatistics()
        .reportStatistics()
    }

    mtd toggleWrap()
    {
        .wrapping = not .wrapping
        .updateWrap()
    }

    mtd setZoom(percent: u32, remember = true)
    {
        .zoomPercent  = Viewer.clampZoom(percent)
        if remember do
            g_ZoomPercent = .zoomPercent
        .applyMeasure()
        .zoomLabel.setText(Viewer.zoomText(.zoomPercent))
        .updateEstimatedHeight()
    }

    // Sets the text in the reading face at the zoom in force, on its lines, in its column.
    mtd applyMeasure()
    {
        let scale = cast(f32, .zoomPercent) / 100
        let size  = cast(u32, Math.max(Math.round(cast(f32, Viewer.ProseFontSize) * scale), 1))
        let font  = .theme().createDefaultFont(size)
        .editor.style.setFont(font, .Regular)
        Viewer.setLinePitch(.editor, font, size, Viewer.ProsePitch)
        Viewer.centerColumn(.editor, Viewer.ProseColumn * scale)
    }

    mtd showZoomMenu()
    {
        let percent = Viewer.pickZoom(me, .zoomLabel, .zoomPercent)
        if percent do
            .setZoom(percent)
    }
}

impl IWnd for Panel
{
    // The column stays centred whatever the width of the window.
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .editor != null do
            Viewer.centerColumn(.editor, Viewer.ProseColumn * cast(f32, .zoomPercent) / 100)
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        discard .retire()
        .read.wait()
        .statisticsTask.wait()
    }

    // Publishes the statistics count that just ended.
    mtd finishStatistics()
    {
        if not .statisticsTask.isDone() do
            return

        // A count that was asked to stop, or that describes an interpretation the reader has
        // since left, is replaced rather than shown.
        let stopped = .statisticsTask.isCancelled()
        var countErrorOutcome: Swag.Error
        var counted: #decltype(expect .statisticsTask.take())
        catch { counted = try .statisticsTask.take() } as countErrorOutcome
        let countError = countErrorOutcome.value()
        if .retiring do
            return
        if stopped or .statisticsEncoding != .encoding or .statisticsStart != .contentStart
        {
            .startStatistics()
            return
        }

        .statistics    = counted
        .hasStatistics = countError == null
        .reportStatistics()
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .loadTimer
        {
            evt.accepted = false
            return
        }

        .stopTimer(&.loadTimer)
        .updateEstimatedHeight()
        .loadNextChunk()
        .scheduleMore()
    }

    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if not .read.claim(evt)
        {
            if evt.task != &.statisticsTask do
                evt.accepted = false
            else do
                .finishStatistics()
            return
        }

        .updateEstimatedHeight()
        .loadNextChunk()
        .scheduleMore()
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        // A theme carries its own faces: the reading face is set again in the new one.
        switch evt.kind
        {
        case .LanguageChanged: .retranslate()
        case .ThemeChanged:    .applyMeasure()
        case .ChildFocusChanged, .PressedElsewhere, .KeyboardLayoutChanged, .ShortcutsChanged: break
        }

        evt.accepted = evt.kind == .LanguageChanged
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if .handleLensHistoryKey(evt) do
            evt.accepted = true
        elif .handleBookmarkKey(evt) do
            evt.accepted = true
        elif Viewer.isZoomKey(evt) do
            .setZoom(Viewer.zoomAfterKey(evt, .zoomPercent))
        elif isWrapKey(evt) do
            .toggleWrap()
        else do
            evt.accepted = false
    }
}

impl Panel
{
    // Creates the streamed text view of the host's file, with its options and zoom on the line of readings.
    func create(host: Viewer.Host)->*Panel
    {
        with let result = Wnd.create'Panel(host.contentParent(), "scope.text")
        {
            // The document host owns the rounded view ground. Keeping the viewer transparent lets
            // those antialiased corners remain visible instead of repainting them with a square view.
            .backgroundStyle = .Transparent
            .fileName        = host.fileName()
            .services        = host.services()
        }

        let probed = probe(host.fileName())
        result.encoding     = probed.encoding
        result.contentStart = probed.contentStart
        result.lineNumbers  = g_LineNumbers
        result.blanks       = g_Blanks
        result.tabWidth     = g_TabWidth
        result.fileIdentity = textFileIdentity(host.fileName())
        result.bookmarkIdentity = result.fileIdentity
        result.lensHistory.clear()
        result.lensHistoryIndex = Swag.U64.Max
        result.replayingLensHistory = false

        result.createReadingControls(host)
        result.createEditor()
        result.hookEvents()
        result.startReading()

        result.numberWindow()
        result.setZoom(g_ZoomPercent)
        result.applyLayout()
        result.scheduleMore()
        result.startStatistics()
        return result
    }

    // Decides whether scrolling from `oldPosition` to `newPosition` leaves the resident window,
    // and asks for the part of the file it reaches when it does.
    mtd followScroll(oldPosition, newPosition: Math.Point)
    {
        if .repositioning do
            return
        if .pauseStreaming and newPosition.y < oldPosition.y do
            .pauseStreaming = false
        let viewport     = .editor.paddedClientRect()
        let loadedHeight = .editor.loadedDocumentHeight()

        var residentHeight = 0'f32
        if loadedHeight > 0
        {
            residentHeight = loadedHeight
        }
        elif .fileSize
        {
            let scaledBytes = .virtualHeight * cast(f32, .bytesRead - .residentStart)
            residentHeight = scaledBytes / cast(f32, .fileSize)
        }

        let residentEnd = .residentOffsetY + residentHeight
        let before      = .residentStart > 0 and
                          newPosition.y < oldPosition.y and
                          newPosition.y < .residentOffsetY + viewport.height * StreamLookAhead
        let after = .hasMore() and
                    .bytesRead - .residentStart >= ResidentWindowSize and
                    newPosition.y > oldPosition.y and
                    newPosition.y + viewport.height * StreamLookAhead > residentEnd
        let outside = newPosition.y < .residentOffsetY or newPosition.y + viewport.height > residentEnd
        .pendingSeek = .displayedEncoding != .encoding or (.virtualHeight > 0 and (before or after or outside))
        .pendingMatch.clear()
        .pendingCaret      = false
        .pendingHasCaretColumn = false
        .pendingNavigation = .None

        // Returning to resident text also supersedes an in-flight replacement.
        if .read.started and (.pendingSeek or .read.replace) do
            .read.cancel()
        if .pendingSeek
        {
            let ratio = Math.clamp(newPosition.y / .virtualHeight, 0, 1)
            .pendingSeekOffset = cast(u64, (ratio * cast(f32, .fileSize)))
        }

        .scheduleMore()
    }

    // Gives the lens the layout of the text, its encodings and its zoom.
    mtd describeLens(entries: *Viewer.LensEntries)
    {
        let strings = texts()
        discard .refreshBookmarkStaleness()
        let canGoBack = .lensHistoryIndex != Swag.U64.Max and .lensHistoryIndex > 0
        let canGoForward = .lensHistoryIndex != Swag.U64.Max and .lensHistoryIndex + 1 < .lensHistory.count
        let bookmarkIsStale = .bookmarksStale
        let canBookmark = .canBookmarkCurrentLine()
        let canBookmarkBack = not bookmarkIsStale and .bookmarkIndexInDirection(-1) != Swag.U64.Max
        let canBookmarkForward = not bookmarkIsStale and .bookmarkIndexInDirection(1) != Swag.U64.Max
        entries.add(strings.ui_Back,
                    .ChevronLeft,
                    func|view = me|() { discard view.navigateLensHistory(-1) },
                    disabled: not canGoBack,
                    defaultKey: {modifiers: .Alt, key: .Left},
                    bindId: "scope.text.history.back")
        entries.add(strings.ui_Forward,
                    .ChevronRight,
                    func|view = me|() { discard view.navigateLensHistory(1) },
                    disabled: not canGoForward,
                    defaultKey: {modifiers: .Alt, key: .Right},
                    bindId: "scope.text.history.forward")
        entries.add(strings.ui_BookmarkCurrentLine,
                    .GoTo,
                    func|view = me|() { view.promptBookmarkCurrentLine() },
                    disabled: not canBookmark,
                    defaultKey: {modifiers: Input.KeyModifiers.Control | .Shift, key: .B},
                    bindId: "scope.text.bookmark.add")
        entries.add(strings.ui_PreviousBookmark,
                    .ChevronLeft,
                    func|view = me|() { discard view.navigateBookmark(-1) },
                    disabled: not canBookmarkBack,
                    defaultKey: {modifiers: Input.KeyModifiers.Control | .Shift, key: .PageUp},
                    bindId: "scope.text.bookmark.previous")
        entries.add(strings.ui_NextBookmark,
                    .ChevronRight,
                    func|view = me|() { discard view.navigateBookmark(1) },
                    disabled: not canBookmarkForward,
                    defaultKey: {modifiers: Input.KeyModifiers.Control | .Shift, key: .PageDown},
                    bindId: "scope.text.bookmark.next")
        entries.add(strings.ui_ClearBookmarks,
                    .Edit,
                    func|view = me|() { view.confirmClearBookmarks() },
                    disabled: .bookmarks.isEmpty(),
                    bindId: "scope.text.bookmark.clear")
        for bookmark, index in .bookmarks
        {
            let name = bookmark.label
            let line = bookmark.line
            let stale = bookmarkIsStale
            let destination = entries.add(name,
                                          .GoTo,
                                          func|view = me, index|() { discard view.navigateToBookmark(index) },
                                          disabled: stale)
            if destination do
                destination.detail = stale ? strings.ui_BookmarkStale : Format.toString(strings.ui_BookmarkLine, line)

            entries.add(Format.toString(strings.ui_RenameBookmark, name),
                        .Edit,
                        func|view = me, index|() { view.promptRenameBookmark(index) },
                        bindId: Format.toString("scope.text.bookmark.rename.%", index))
        }
        entries.add(strings.ui_Wrap, .Wrap, func|view = me|() { view.toggleWrap() }, checked: .wrapping, defaultKey: {modifiers: .Control, key: .W}, bindId: "scope.text.wrap")
        entries.add(strings.ui_Numbers, .LineNumbers, func|view = me|() { view.toggleLineNumbers() }, checked: .lineNumbers, bindId: "scope.text.numbers")
        entries.add(strings.ui_Blanks, .Whitespace, func|view = me|() { view.toggleBlanks() }, checked: .blanks, bindId: "scope.text.blanks")

        // The tab stops and the encodings answer a query rather than fill the empty lens; the
        // options list them too.
        for width in Viewer.TabWidths where entries.query.count or entries.results.collectingShortcuts do
            entries.add(Viewer.tabWidthRowText(strings.ui_TabWidth, width), .Whitespace, func|view = me, width|() { view.setTabWidth(width) }, checked: .tabWidth == width, bindId: Format.toString("scope.text.tabWidth.%", width))
        for encoding in Encodings where entries.query.count or entries.results.collectingShortcuts
        {
            let name = Format.toString("% · %", strings.ui_Encoding, Viewer.encodingName(encoding))
            entries.add(name,
                        .FileCode,
                        func|view = me, encoding|() { view.applyEncoding(encoding) },
                        checked: encoding == .encoding,
                        bindId: Format.toString("scope.text.encoding.%", encoding))
        }

        entries.addZoom(.In, .zoomPercent, func|view = me, percent = Viewer.zoomTarget(.In, me.zoomPercent)|() { view.setZoom(percent) })
        entries.addZoom(.Out, .zoomPercent, func|view = me, percent = Viewer.zoomTarget(.Out, me.zoomPercent)|() { view.setZoom(percent) })
        entries.addZoom(.Reset, .zoomPercent, func|view = me, percent = Viewer.zoomTarget(.Reset, me.zoomPercent)|() { view.setZoom(percent) })
        entries.add(appStrings().cmd_ZoomMenu, .ZoomLevels, func|view = me|() { view.showZoomMenu() }, bindId: "scope.text.zoomMenu")
        entries.add(appStrings().cmd_Options, .Settings, func|view = me|() { view.showOptions() }, bindId: "scope.text.options")
    }

    // Opens how the text is laid out and decoded: wrapping, line numbers, tab stops, and the
    // encoding.
    mtd showOptions()
    {
        let sheet = OptionSheet.View.create(.optionsButton, func|view = me|(page) { view.describeOptions(page) }, owner: me)
        sheet.doModal(.optionsButton, autoDestroy: true)
    }

    mtd describeOptions(page: *OptionSheet.Page)
    {
        let strings = texts()
        page.addToggle(strings.ui_Wrap, .wrapping, func|view = me|(_) { view.toggleWrap() }, icon: .theme().icon(.Wrap, themeRowIconSize(.themeMetrics())))
        page.addToggle(strings.ui_Numbers, .lineNumbers, func|view = me|(_) { view.toggleLineNumbers() }, icon: .theme().icon(.LineNumbers, themeRowIconSize(.themeMetrics())))
        page.addToggle(strings.ui_Blanks, .blanks, func|view = me|(_) { view.toggleBlanks() }, icon: .theme().icon(.Whitespace, themeRowIconSize(.themeMetrics())))
        page.addLink(strings.ui_TabWidth,
                     Format.toString("%", .tabWidth),
                     func|view = me|(widths)
                     {
                         for width in Viewer.TabWidths do
                             widths.addChoice(Format.toString("%", width), width == view.tabWidth, func|view, width|() { view.setTabWidth(width) })
                     },
                     icon: .theme().icon(.Whitespace, themeRowIconSize(.themeMetrics())))

        // The detected encoding is shown rather than assumed: a file that reads as nonsense is
        // usually one whose encoding was guessed wrong, and this is where a reader corrects it.
        page.addLink(strings.ui_Encoding,
                     .encodingName(),
                     func|view = me|(encodings)
                     {
                         for encoding in Encodings do
                             encodings.addChoice(Viewer.encodingName(encoding), encoding == view.encoding, func|view, encoding|() { view.applyEncoding(encoding) })
                     },
                     icon: .theme().icon(.FileCode, themeRowIconSize(.themeMetrics())))
    }

    // Creates the options and the zoom of the text on the line of readings.
    private mtd createReadingControls(host: Viewer.Host)
    {
        .info = host.createInfoGroup(Viewer.InfoOptionsWidth + Viewer.ZoomSlotWidth)
        with .optionsButton = Viewer.createInfoOptionsButton(.info)
        {
            .sigPressed += func|view = me|(_) { view.showOptions() }
        }

        with .zoomLabel = Viewer.createZoomButton(.info, "scope.text.zoom", texts().ui_ZoomMenu)
        {
            .dockStyle  = .Right
            .sigPressed += func|view = me|(_) { view.showZoomMenu() }
        }
    }

    // Creates the read-only editor that shows the resident window of the file.
    private mtd createEditor()
    {
        with .editor = RichEditCtrl.create(me)
        {
            .dockStyle   = .Center
            .marginLeft  = Viewer.ColumnInset
            .marginRight = Viewer.ColumnInset
            .style.setFont(me.theme().createDefaultFont(Viewer.ProseFontSize), .Regular)
            .sigScrollPositionChanged += func|view = me|(_, oldPosition, newPosition) { view.followScroll(oldPosition, newPosition) }
        }
    }

    // Routes the keys the text view answers for, and keeps painting and resizing from reloading text.
    private mtd hookEvents()
    {
        .hookOnChildEvent = func|view = me|(_, evt)
        {
            switch evt
            {
            case PaintEvent as paintEvt:

                // Caret placement and wrapping publish scroll corrections during paint. They
                // must not reload the text whose lines the renderer is currently traversing.
                let previous = view.repositioning
                view.repositioning = true
                defer view.repositioning = previous
                paintEvt.target!.processEvent(evt)
                return true

            case KeyEvent as keyEvt where Viewer.isZoomKey(keyEvt):
                view.setZoom(Viewer.zoomAfterKey(keyEvt, view.zoomPercent))
                return true

            case MouseEvent as mouse where Viewer.isZoomWheel(mouse):
                view.setZoom(Viewer.zoomAfterWheel(mouse, view.zoomPercent))
                return true

            case KeyEvent as keyEvt where isWrapKey(keyEvt):
                view.toggleWrap()
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and
                                          keyEvt.key == .End and
                                          (keyEvt.modifiers == .None or keyEvt.modifiers == .Control):
                view.pauseStreaming = true
                discard view.revealOffset(view.fileSize, "")
                view.pendingNavigation = .End
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and
                                          keyEvt.key == .Home and
                                          (keyEvt.modifiers == .None or keyEvt.modifiers == .Control):
                view.pauseStreaming = false
                discard view.revealOffset(0, "")
                view.pendingNavigation = .Home
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and (keyEvt.key == .Down or keyEvt.key == .PageDown):
                view.pauseStreaming = false
                view.scheduleMore()
                let line = view.editor.cursorLogicalLineIndex()
                keyEvt.target!.processEvent(evt)
                if view.editor.cursorLogicalLineIndex() != line do
                    view.reportStatistics()
                return keyEvt.accepted

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .Space:
                view.pauseStreaming = false
                view.scheduleMore()
                return false

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and
                                          view.editor.commandForShortcut(keyEvt.key, keyEvt.modifiers) != .None:
                let line = view.editor.cursorLogicalLineIndex()
                keyEvt.target!.processEvent(evt)
                if view.editor.cursorLogicalLineIndex() != line do
                    view.reportStatistics()
                return keyEvt.accepted

            case MouseEvent as mouseEvt where mouseEvt.kind == .Pressed or
                                              mouseEvt.kind == .Released or
                                              mouseEvt.kind == .Move or
                                              mouseEvt.kind == .DoubleClick:
                let line = view.editor.cursorLogicalLineIndex()
                mouseEvt.target!.processEvent(evt)
                if view.editor.cursorLogicalLineIndex() != line do
                    view.reportStatistics()
                return mouseEvt.accepted

            default:
                return false
            }
        }

        .hookOnEvent = func|view = me|(_, evt)
        {
            if evt is ResizeEvent
            {
                view.updateEstimatedHeight()
                view.scheduleMore()
            }

            return false
        }
    }

    // Measures the file and starts reading its first chunk, or shows why it cannot be read.
    private mtd startReading()
    {
        var openErrorOutcome: Swag.Error
        var stream: #decltype(expect File.openReadLive(.fileName))
        catch { stream = try File.openReadLive(.fileName) } as openErrorOutcome
        let openError = openErrorOutcome.value()
        if openError != null
        {
            .showReadError()
            return
        }

        let size = catch stream.size()
        {
            .showReadError()
            return
        }

        .fileSize = size
        if not size do
            return

        // A byte-order mark is part of the file and not part of the text, so reading starts past
        // it and every offset the view reports stays a file offset.
        .bytesRead     = .contentStart
        .residentStart = .contentStart
        .loadNextChunk()
    }
}

// What the information sheet says of a text file.
impl Panel
{
    // Describes the text in the information sheet: its lines, words and characters once they are
    // counted for the encoding in force, then that encoding and how its lines end. Where the
    // cursor stands is a reading of the foot of the document, not of the file.
    mtd describeInformation(sheet: *InfoSheet)
    {
        var data: MediaInfoData
        data.add(.Text, group: true)
        data.add(.Encoding, .encodingName())
        var longestLine = 0'u64
        if .hasStatistics and .statisticsEncoding == .encoding and .statisticsStart == .contentStart
        {
            data.addTextStatistics(&.statistics)
            longestLine = .statistics.longestLine
        }
        data.describe(sheet)
        if longestLine do
            sheet.addLink(Format.toString(appStrings().lens_GoToLine, longestLine), ViewerCommands.TextLongestLine)
    }

    // Reveals the current longest line when its information-sheet command is received.
    mtd revealLongestLine()->bool
    {
        if not .isLocallyVisible() or
           not .hasStatistics or
           .statisticsEncoding != .encoding or
           .statisticsStart != .contentStart or
           not .statistics.longestLine do
            return false

        let line = .statistics.longestLine
        let offset = .lines.offsetOfLine(.fileName, line, .encoding, .contentStart)
        if offset != Swag.U64.Max do
            return .revealLensDestination(offset, "", caret: true)

        let estimate = .lines.estimateOffsetOfLine(.fileName, line, .encoding, .contentStart)
        if estimate == Swag.U64.Max do
            return false
        return .revealLensDestination(estimate, "", caret: true, estimatedLine: line)
    }
}

func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)
    host.attachView(view)
    host.setDetails(view.detailsText())
    host.setInformation(func|view|(sheet) { view.describeInformation(sheet) })

    with var search: Viewer.SearchApi
    {
        .revealMatch = func|view|(match, text)->bool => view.revealOffset(match.offset, text, caret: true)
        .matchBounds = func|view|(_, bounds)->bool { return view.searchBounds(bounds) }
        .clear       = func|view|() => view.clearSearch()
    }

    host.setSearch(search)
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })

    with var lifecycle: Viewer.LifecycleApi
    {
        .isLoading = func|view|()->bool => view.isStreaming()
        .retire    = func|view|()->bool => view.retire()
    }

    host.setLifecycle(lifecycle)
}
