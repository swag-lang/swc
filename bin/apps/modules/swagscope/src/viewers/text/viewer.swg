#global internal
#global namespace Viewers.PlainText

using Core, Pixel, Gui

private var g_ZoomPercent: u32 = 100

// Whether basic text numbers its lines. The choice follows the reader from file to file.
private var g_LineNumbers: bool

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

    // The encodings offered in the action bar, in the order the selector lists them.
    const Encodings: [6] Text.Encoding = [.Utf8, .Utf16Le, .Utf16Be, .Utf32Le, .Utf32Be, .Windows1252]

    // Names of those encodings. They are the standard spelling of a format rather than prose, so they
    // read the same in every language.
    const EncodingNames: [6] string = ["UTF-8", "UTF-16 LE", "UTF-16 BE", "UTF-32 LE", "UTF-32 BE", "Windows-1252"]
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
        commands:      *Wnd
        info:          *Wnd
        editor:        *RichEditCtrl
        optionsButton: *IconButton
        zoomLabel:     *IconButton
    }

    read:               Read
    residentText:       String
    pendingMatch:       String
    pendingNavigation:  Input.Key
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
    windowNumbered:     bool
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
    while not Swag.isCancelled()
    {
        let chunk = try stream.readTextChunk(StreamChunkSize, encoding)
        if chunk.isEmpty() do
            break
        counter.append(chunk)
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

    mtd detailsText()->String
    {
        let encoding    = .encodingName()
        let currentLine = Format.toString(texts().ui_CurrentLine, .editor.cursorLogicalLineIndex() + 1)

        // Statistics describe the byte interpretation that produced them. Switching encoding
        // keeps the already finished worker available for retirement, but its totals must not be
        // presented as facts about the newly decoded document.
        if not .hasStatistics or
           .statisticsEncoding != .encoding or
           .statisticsStart != .contentStart do
            return Format.toString(texts().ui_Details, encoding, currentLine)
        let lines      = .statistics.lines == 1 ? String.from(texts().ui_OneLine) : Format.toString(texts().ui_Lines, .statistics.lines)
        let words      = .statistics.words == 1 ? String.from(texts().ui_OneWord) : Format.toString(texts().ui_Words, .statistics.words)
        let characters = .statistics.characters == 1 ? String.from(texts().ui_OneCharacter) : Format.toString(texts().ui_Characters, .statistics.characters)
        return Format.toString(texts().ui_DetailsStats, encoding, currentLine, lines, words, characters)
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

    mtd encodingName()->string
    {
        for candidate, index in Encodings where candidate == .encoding do
            return EncodingNames[index]
        return EncodingNames[0]
    }

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
            if not .pendingMatch.isEmpty()
            {
                if .encoding == .Utf8 do
                    Viewer.highlightRichEditMatch(.editor, .read.text, .pendingSeekOffset - .residentStart, .pendingMatch.length)
                else do
                    discard .editor.findText(.pendingMatch)
                .pendingMatch.clear()
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
            let start     = requested > RevealContextSize ? requested - RevealContextSize : 0
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
    mtd revealOffset(offset: u64, text: string)->bool
    {
        if text.count and
           .displayedEncoding == .encoding and
           not .pendingSeek and
           not (.read.started and .read.replace) and
           offset >= .residentStart and
           offset + text.count <= .bytesRead
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
        if .lineNumbers and .windowNumbered do
            flags.add(.LineNumbers)
        .editor.setFlags(flags)
        .scheduleMore()
    }

    // Gives the line numbers of the resident window the count of the lines before it, in the
    // encoding that decoded it. A window too deep in the file to count without a visible pause is
    // shown without numbers rather than with wrong ones.
    mtd numberWindow()
    {
        .windowNumbered = false
        if .lineNumbers
        {
            let line = .lines.lineAt(.fileName, .residentStart, .encoding, .contentStart)
            if line
            {
                .editor.setFirstLineNumber(line)
                .windowNumbered = true
            }
        }

        .updateWrap()
    }

    mtd toggleLineNumbers()
    {
        .lineNumbers  = not .lineNumbers
        g_LineNumbers = .lineNumbers
        .numberWindow()
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

    mtd setZoom(percent: u32)
    {
        .zoomPercent  = Viewer.clampZoom(percent)
        g_ZoomPercent = .zoomPercent
        let base = .themeMetrics().defaultFixedFontSize
        let size = cast(u32, Math.max(Math.round(cast(f32, base) * cast(f32, .zoomPercent) / 100), 1))
        .editor.style.setFont(.theme().createDefaultFontFs(size), .Regular)
        .editor.setFlags(.editor.flags)
        .zoomLabel.setText(Viewer.zoomText(.zoomPercent))
        .updateEstimatedHeight()
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
        if evt.kind == .LanguageChanged do
            .retranslate()
        else do
            evt.accepted = false
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if Viewer.isZoomKey(evt) do
            .setZoom(Viewer.zoomAfterKey(evt, .zoomPercent))
        elif isWrapKey(evt) do
            .toggleWrap()
        else do
            evt.accepted = false
    }
}

impl Panel
{
    // Creates the streamed text view of the host's file, with its commands and zoom control.
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

        result.createCommandBar(host)
        result.createZoomControl(host)
        result.createEditor()
        result.hookEvents()
        result.startReading()

        result.numberWindow()
        result.setZoom(g_ZoomPercent)
        result.applyLayout()
        result.scheduleMore()
        result.startStatistics()
        result.setInitialFocus(result.editor)
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

    // Creates the options button in the viewer's command group.
    private mtd createCommandBar(host: Viewer.Host)
    {
        .commands = host.createCommandGroup(themeDropDownButtonWidth(.themeMetrics()))

        with .optionsButton = Viewer.createOptionsButton(.commands)
        {
            .dockStyle  = .Left
            .sigPressed += func|view = me|(_) { view.showOptions() }
        }
    }

    // Gives the lens the layout of the text, its encodings and its zoom.
    mtd describeLens(entries: *Viewer.LensEntries)
    {
        let strings = texts()
        entries.add(strings.ui_Wrap, func|view = me|() { view.toggleWrap() }, checked: .wrapping, shortcut: Input.formatKeyShortcut(.Control, .W))
        entries.add(strings.ui_Numbers, func|view = me|() { view.toggleLineNumbers() }, checked: .lineNumbers)
        for encoding, index in Encodings
        {
            let name = Format.toString("% · %", strings.ui_Encoding, EncodingNames[index])
            entries.add(name, func|view = me, encoding|() { view.applyEncoding(encoding) }, checked: encoding == .encoding)
        }

        entries.addZoom(.In, .zoomPercent, func|view = me, percent = Viewer.zoomTarget(.In, me.zoomPercent)|() { view.setZoom(percent) })
        entries.addZoom(.Out, .zoomPercent, func|view = me, percent = Viewer.zoomTarget(.Out, me.zoomPercent)|() { view.setZoom(percent) })
        entries.addZoom(.Reset, .zoomPercent, func|view = me, percent = Viewer.zoomTarget(.Reset, me.zoomPercent)|() { view.setZoom(percent) })
        entries.add(appStrings().cmd_Options, func|view = me|() { view.showOptions() })
    }

    // Opens how the text is laid out and decoded: wrapping, line numbers, and the encoding.
    mtd showOptions()
    {
        let sheet = OptionSheet.View.create(.optionsButton, func|view = me|(page) { view.describeOptions(page) }, owner: me)
        sheet.doModal(.optionsButton, autoDestroy: true)
    }

    mtd describeOptions(page: *OptionSheet.Page)
    {
        let strings = texts()
        page.addToggle(strings.ui_Wrap, .wrapping, func|view = me|(_) { view.toggleWrap() })
        page.addToggle(strings.ui_Numbers, .lineNumbers, func|view = me|(_) { view.toggleLineNumbers() })

        // The detected encoding is shown rather than assumed: a file that reads as nonsense is
        // usually one whose encoding was guessed wrong, and this is where a reader corrects it.
        page.addLink(strings.ui_Encoding, .encodingName(), func|view = me|(encodings)
        {
            for encoding, index in Encodings do
                encodings.addChoice(EncodingNames[index], encoding == view.encoding, func|view, encoding|() { view.applyEncoding(encoding) })
        })
    }

    // Creates the zoom menu button in the viewer's information group.
    private mtd createZoomControl(host: Viewer.Host)
    {
        .info = host.createInfoGroup(Viewer.ZoomSlotWidth)

        .zoomLabel = Viewer.createZoomButton(.info, "scope.text.zoom", texts().ui_ZoomMenu)
        .zoomLabel.sigPressed += func|view = me|(_) { view.showZoomMenu() }
    }

    // Creates the read-only editor that shows the resident window of the file.
    private mtd createEditor()
    {
        with .editor = RichEditCtrl.create(me)
        {
            .dockStyle   = .Center
            .marginLeft  = 12
            .marginRight = 12
            .style.setFont(me.theme().createDefaultFontFs(me.themeMetrics().defaultFixedFontSize), .Regular)
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

            case MouseEvent as mouse where mouse.kind == .Wheel and mouse.modifiers.has(.Control):
                if mouse.delta.y > 0 do
                    view.setZoom(Viewer.zoomIn(view.zoomPercent))
                elif mouse.delta.y < 0 do
                    view.setZoom(Viewer.zoomOut(view.zoomPercent))
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

// Creates the streamed plain-text view.
func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)
    host.attachView(view)
    host.setDetails(view.detailsText())

    with var search: Viewer.SearchApi
    {
        .revealMatch = func|view|(match, text)->bool => view.revealOffset(match.offset, text)
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
