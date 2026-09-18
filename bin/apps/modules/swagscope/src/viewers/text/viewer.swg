#global internal

using Core, Pixel, Gui

// Stable identity and smoke input of the text plugin.
const TextViewerKey    = "text"
const TextSmokeFixture = "comprehensive.txt"

// What the text surface owns by name, like every other format-specific viewer.
private const NamedExtensions = ".txt;.text;.log;.nfo;.diz;.rst;.adoc;.asc;.srt;.vtt;.sub;.ssa;.ass;.lrc;.diff;.patch;readme;license;licence;changelog;authors;copying;install;news;todo"

private func textPluginName()->string => textStrings().ui_Name

// Offers the text surface for whatever reads as text, once the formats have had their turn.
//
// Reading the head is a weak question asked alone: a PDF, an office document and a font all open
// with enough printable bytes to pass it, and offering to read one of them as a page of text says
// something untrue about the file. The formats that recognize themselves answer first, so what
// reaches this probe is either a file nothing claimed — an extensionless note, a log named `.dat`,
// a UTF-16 export — or a document whose viewer reads text anyway, where the raw source is a second
// reading of the same thing rather than a contradiction of the first.
private func textPluginProbe(content: Viewer.ProbeContent)->bool
{
    if content.claimed and not content.claimedText do
        return false
    if not content.head.count do
        return false
    return TextViewer.probeHead(content.head).accepted
}

// Describes the text viewer to the host.
//
// The surface registers the extensions and extensionless names it owns, and answers for any other
// file whose beginning reads as text, whichever encoding spells it.
func textViewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = TextViewerKey
        .resolveName  = &textPluginName
        .attach       = &registerTextStrings
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32) ViewerIcons.Text
        .create       = &createTextViewer
        .probe        = &textPluginProbe
        .textual      = true
        .smokeFixture = TextSmokeFixture
        .addSelectors(NamedExtensions)
    }

    return result
}

private const TextStreamChunkSize = 16 * 1024'u64

// Viewport heights of text kept loaded from the top of the visible one: it and five more.
private const TextStreamLookAhead    = 6.0
private const TextResidentWindowSize = 256 * 1024'u64
private const TextRevealContextSize  = 16 * 1024'u64

// The encodings offered in the action bar, in the order the selector lists them.
private const TextEncodings: [6] Text.Encoding = [.Utf8, .Utf16Le, .Utf16Be, .Utf32Le, .Utf32Be, .Windows1252]

// Names of those encodings. They are the standard spelling of a format rather than prose, so they
// read the same in every language.
private const TextEncodingNames: [6] string = ["UTF-8", "UTF-16 LE", "UTF-16 BE", "UTF-32 LE", "UTF-32 BE", "Windows-1252"]

// What the head of a file says about how it spells its characters.
struct TextProbe
{
    encoding:     Text.Encoding     // How the bytes read as characters.
    contentStart: u64               // First byte of text, past a byte-order mark.
    accepted:     bool              // Whether what it decodes to is text a reader should be shown.
}

// Text view available for readable content independently of the format-specific viewers.
struct TextViewer
{
    using wnd: Wnd

    late
    {
        commands:      *Wnd
        info:          *Wnd
        editor:        *RichEditCtrl
        wrapButton:    *IconButton
        encodingCombo: *ComboBox
        zoomLabel:     *IconButton
    }

    read:               TextRead
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
    statisticsThread:   Threading.Thread
    statisticsTimer:    *Timer?
    statisticsState:    u32
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
    wrapping = true
    zoomPercent:        u32 = 100
    reportDetails:      Viewer.ReportDetails?
}

private func runTextStatistics(thread: Threading.Thread)
{
    let view    = cast(*TextViewer) thread.userParam!
    let context = Swag.getContext()
    context.allocator = context.defaultAllocator!

    var stream = catch File.openReadLive(view.fileName.toString()) as openError
    if openError != null
    {
        Atomic.exchange(&view.statisticsState, 2)
        return
    }

    defer stream.close()
    discard catch stream.seek(.Begin, view.statisticsStart)

    var counter: TextStatisticsCounter
    while not thread.requestEnd
    {
        let chunk = catch stream.readTextChunk(TextStreamChunkSize, view.statisticsEncoding) as readError
        if readError != null
        {
            Atomic.exchange(&view.statisticsState, 2)
            return
        }

        if chunk.isEmpty() do
            break

        counter.append(chunk.toString())
    }

    if thread.requestEnd do
        return
    view.statistics = counter.finish()
    Atomic.exchange(&view.statisticsState, 1)
}

func textRevealMatch(wnd: *Wnd, match: Viewer.SearchMatch, text: string)->bool => (cast #assume (*TextViewer) wnd).revealOffset(match.offset, text)

func textSearchBounds(wnd: *Wnd, match: Viewer.SearchMatch, result: *Math.Rectangle)->bool
{
    discard match
    let view = cast #assume (*TextViewer) wnd
    if not view.pendingMatch.isEmpty() do
        return false
    return Viewer.richEditMatchBounds(view.editor, result)
}

func textClearSearch(wnd: *Wnd)
{
    let view = cast #assume (*TextViewer) wnd
    view.pendingMatch.clear()
    Viewer.clearRichEditMatch(view.editor)
}

func textIsLoading(wnd: *Wnd)->bool => (cast #assume (*TextViewer) wnd).loadTimer != null

impl TextViewer
{
    mtd detailsText()->String
    {
        let encoding = .encodingName()

        // Statistics describe the byte interpretation that produced them. Switching encoding
        // keeps the already finished worker available for retirement, but its totals must not be
        // presented as facts about the newly decoded document.
        if Atomic.get(&.statisticsState) != 1 or .statisticsEncoding != .encoding or .statisticsStart != .contentStart do
            return Format.toString(textStrings().ui_Details, encoding)
        let lines = .statistics.lines == 1 ? String.from(textStrings().ui_OneLine) : Format.toString(textStrings().ui_Lines, .statistics.lines)
        let words = .statistics.words == 1 ? String.from(textStrings().ui_OneWord) : Format.toString(textStrings().ui_Words, .statistics.words)
        return Format.toString(textStrings().ui_DetailsStats, encoding, lines, words)
    }

    mtd reportStatistics()
    {
        if .reportDetails do
            .reportDetails(me, .detailsText().toString())
    }

    mtd retranslate()
    {
        .wrapButton.toolTip    = .wrapping ? textStrings().ui_WrapOn : textStrings().ui_WrapOff
        .encodingCombo.toolTip = textStrings().ui_Encoding
        .zoomLabel.toolTip     = textStrings().ui_ZoomMenu
        .reportStatistics()
    }

    mtd startStatistics()
    {
        .statisticsState    = 0
        .statisticsEncoding = .encoding
        .statisticsStart    = .contentStart
        catch .statisticsThread.init(&runTextStatistics, me, priority: .BelowNormal) as initError
        if initError != null do
            return
        catch .statisticsThread.start() as startError
        if startError != null do
            return
        .statisticsTimer = .addTimer(Viewer.BackgroundPollInterval)
    }

    mtd retire()->bool
    {
        .retiring = true
        .stopLoading()
        if .statisticsTimer
        {
            .removeTimer(.statisticsTimer)
            .statisticsTimer = null
        }

        if .statisticsThread.isValid() and not .statisticsThread.isDone()
        {
            .statisticsThread.safeForceEnd()
            return false
        }

        if .statisticsThread.isValid() do
            .statisticsThread.wait()
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
        for candidate, index in TextEncodings where candidate == .encoding do
            return TextEncodingNames[index]
        return TextEncodingNames[0]
    }

    // Reads the head of a file once and reports how it spells its characters.
    //
    // A file that cannot be read reports the default probe, which accepts nothing.
    func probe(fileName: string)->TextProbe
    {
        var stream = catch File.openReadLive(fileName) as openError
        if openError != null do
            return {}
        defer stream.close()

        var bytes: Array'u8
        bytes.resize(Viewer.ProbeHeadSize)
        let count = catch stream.read(bytes.toSlice()) as readError
        if readError != null do
            return {}
        bytes.resize(count)
        return probeHead(bytes.toSlice())
    }

    // Reports how the beginning of a file spells its characters, and whether it is text at all.
    //
    // Deciding and accepting are two questions: code page 1252 gives every byte a meaning, so an
    // executable also decodes into characters. The encoding answers the first, and what those
    // characters are answers the second.
    func probeHead(head: const [..] u8)->TextProbe
    {
        var result: retval
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
        if .bytesRead - .residentStart >= TextResidentWindowSize do
            return false
        let viewport     = .editor.paddedClientRect()
        let loadedHeight = .editor.loadedDocumentHeight()
        return loadedHeight <= 0 or .editor.scrollPosition().y + viewport.height * TextStreamLookAhead >= .residentOffsetY + loadedHeight
    }

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
        if .repositioning or not .residentStart do
            .residentOffsetY = .fileSize ? .virtualHeight * cast(f32) .residentStart / cast(f32) .fileSize : 0
        if loadedHeight <= 0
        {
            if .virtualHeight > 0 do
                .editor.setVirtualDocumentRange(.residentOffsetY, .virtualHeight)
            return
        }

        .virtualHeight = Math.max(.virtualHeight, loadedHeight * cast(f32) .fileSize / cast(f32) consumed, loadedHeight)
        if .repositioning or not .residentStart do
            .residentOffsetY = .fileSize ? .virtualHeight * cast(f32) .residentStart / cast(f32) .fileSize : 0
        .editor.setVirtualDocumentRange(.residentOffsetY, .virtualHeight)
    }

    mtd scheduleMore()
    {
        if .retiring do
            return
        if .loadTimer or (not .read.started and not .pendingSeek and not .needsMore()) do
            return
        .loadTimer = .addTimer(8'ms)
    }

    mtd stopLoading()
    {
        if .loadTimer
        {
            .removeTimer(.loadTimer)
            .loadTimer = null
        }

        if .read.started do
            Atomic.exchange(&.read.cancelled, 1)
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
        let message = textStrings().ui_NotText
        if not .hasText do
            .editor.setText(message)
        else do
            .editor.addText(Format.toString("\n\n%", message).toString())
        .editor.setEstimatedDocumentHeight(0)
    }

    // Polling never waits for I/O. A newer seek retires the old result before reusing its storage.
    mtd loadNextChunk()
    {
        if .retiring do
            return
        if .read.started
        {
            if not .read.isDone() do
                return
            .read.wait()
            if Atomic.get(&.read.cancelled)
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
                if .statisticsStart != .contentStart
                {
                    if .statisticsThread.isValid() do
                        .statisticsThread.safeForceEnd()
                    if not .statisticsTimer do
                        .statisticsTimer = .addTimer(Viewer.BackgroundPollInterval)
                }

                .residentText = .read.text
                .editor.setText(.residentText.toString())
            }
            else
            {
                .residentText += .read.text.toString()
                .editor.addText(.read.text.toString())
            }

            .displayedEncoding = .read.encoding
            .bytesRead         = .read.end
            .hasText           = .hasText or not .read.text.isEmpty()
            .updateEstimatedHeight()
            .editor.setScrollPosition(oldPosition)
            if not .pendingMatch.isEmpty()
            {
                if .encoding == .Utf8 do
                    Viewer.highlightRichEditMatch(.editor, .read.text.toString(), .pendingSeekOffset - .residentStart, .pendingMatch.length)
                else do
                    discard .editor.findText(.pendingMatch.toString())
                .pendingMatch.clear()
            }

            if .pendingNavigation == .Home or .pendingNavigation == .End
            {
                .editor.keyPressed(.pendingNavigation, .Control)
                .pendingNavigation = .None
            }

            if .read.text.isEmpty() or not .hasMore() do
                .finishLoading()
            .read.text.clear()
            return
        }

        if .pendingSeek
        {
            .pendingSeek = false
            let requested = Math.min(.pendingSeekOffset, .fileSize)
            let start     = requested > TextRevealContextSize ? requested - TextRevealContextSize : 0
            .read.startRead(.fileName.toString(), .encoding, start, 64 * 1024, true)
        }
        elif .needsMore()
        {
            .read.contentStart = .contentStart
            .read.startRead(.fileName.toString(), .encoding, .bytesRead, TextStreamChunkSize, false)
        }

        .scheduleMore()
    }

    mtd revealOffset(offset: u64, text: string)->bool
    {
        if text.count and .displayedEncoding == .encoding and not .pendingSeek and not (.read.started and .read.replace) and offset >= .residentStart and offset + text.count <= .bytesRead
        {
            if .encoding == .Utf8 do
                Viewer.highlightRichEditMatch(.editor, .residentText.toString(), offset - .residentStart, text.count)
            else do
                discard .editor.findText(text)
            return true
        }

        if .read.started do
            Atomic.exchange(&.read.cancelled, 1)
        .pendingSeek       = true
        .pendingSeekOffset = Math.min(offset, .fileSize)
        .pendingMatch      = text
        .pendingNavigation = .None
        .readFailed        = false
        .scheduleMore()
        return true
    }

    mtd updateWrap()
    {
        .editor.setFlags(.ReadOnly | (.wrapping ? RichEditFlags.WordWrap : .None))
        .wrapButton.setChecked(.wrapping)
        .wrapButton.toolTip = .wrapping ? textStrings().ui_WrapOn : textStrings().ui_WrapOff
        .scheduleMore()
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

        .contentStart = 0
        discard .revealOffset(.residentStart, "")
        if .statisticsThread.isValid() do
            .statisticsThread.safeForceEnd()
        if not .statisticsTimer do
            .statisticsTimer = .addTimer(Viewer.BackgroundPollInterval)
        for candidate, index in TextEncodings where candidate == encoding do
            .encodingCombo.setSelectedIndex(cast(u32) index, notify: false)
        .reportStatistics()
    }

    mtd toggleWrap()
    {
        .wrapping = not .wrapping
        .updateWrap()
    }

    mtd setZoom(percent: u32)
    {
        .zoomPercent = Math.clamp(percent, 50'u32, 300'u32)
        let base = .themeMetrics().defaultFixedFontSize
        let size = cast(u32) Math.max(Math.round(cast(f32) base * cast(f32) .zoomPercent / 100), 1)
        .editor.style.setFont(.theme().createDefaultFontFs(size), .Regular)
        .editor.setFlags(.editor.flags)
        .zoomLabel.setText(Format.toString("% %", .zoomPercent, "%"))
        .updateEstimatedHeight()
    }

    mtd showZoomMenu()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem("75%", "scope.text.zoom75")
        menu.addItem("100%", "scope.text.zoom100")
        menu.addItem("125%", "scope.text.zoom125")
        menu.addItem("150%", "scope.text.zoom150")
        menu.addItem("200%", "scope.text.zoom200")
        switch menu.doModal(.zoomLabel, autoDestroy: true) orelse ""
        {
        case "scope.text.zoom75":  .setZoom(75)
        case "scope.text.zoom100": .setZoom(100)
        case "scope.text.zoom125": .setZoom(125)
        case "scope.text.zoom150": .setZoom(150)
        case "scope.text.zoom200": .setZoom(200)
        }
    }
}

impl IWnd for TextViewer
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        discard evt
        discard .retire()
        .read.wait()
        if .statisticsThread.isValid() do
            .statisticsThread.wait()
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .statisticsTimer
        {
            if .statisticsThread.isValid() and not .statisticsThread.isDone() do
                return
            .removeTimer(evt.timer)
            .statisticsTimer = null
            if .statisticsThread.isValid() do
                .statisticsThread.wait()
            if .statisticsEncoding != .encoding or .statisticsStart != .contentStart or not Atomic.get(&.statisticsState) do
                .startStatistics()
            .reportStatistics()
            return
        }

        if evt.timer != .loadTimer
        {
            evt.accepted = false
            return
        }

        .removeTimer(evt.timer)
        .loadTimer = null
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
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        switch evt.key
        {
        case .W where evt.modifiers.has(.Control):                   .toggleWrap()
        case .Add, .OemPlus where evt.modifiers.has(.Control):       .setZoom(.zoomPercent + 25)
        case .Subtract, .OemMinus where evt.modifiers.has(.Control): .setZoom(.zoomPercent > 50 ? .zoomPercent - 25 : 50)
        case .D0 where evt.modifiers.has(.Control):                  .setZoom(100)
        default: evt.accepted = false
        }
    }
}

impl TextViewer
{
    // Creates the streamed text view of the host's file, with its commands and zoom control.
    func create(host: Viewer.Host)->*TextViewer
    {
        with let result = Wnd.create'TextViewer(host.contentParent(), "scope.text")
        {
            // The document host owns the rounded view ground. Keeping the viewer transparent lets
            // those antialiased corners remain visible instead of repainting them with a square view.
            .backgroundStyle = .Transparent
            .fileName        = host.fileName()
            .reportDetails   = host.services().reportDetails
        }

        let probed = probe(host.fileName())
        result.encoding     = probed.encoding
        result.contentStart = probed.contentStart

        result.createCommandBar(host)
        result.createZoomControl(host)
        result.createEditor()
        result.hookEvents()
        result.startReading()

        result.updateWrap()
        result.setZoom(100)
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

        let residentHeight = loadedHeight > 0 ? loadedHeight : (.fileSize ? .virtualHeight * cast(f32) (.bytesRead - .residentStart) / cast(f32) .fileSize : 0)
        let residentEnd    = .residentOffsetY + residentHeight
        let before         = .residentStart > 0 and newPosition.y < oldPosition.y and newPosition.y < .residentOffsetY + viewport.height * TextStreamLookAhead
        let after          = .hasMore() and .bytesRead - .residentStart >= TextResidentWindowSize and newPosition.y > oldPosition.y and newPosition.y + viewport.height * TextStreamLookAhead > residentEnd
        let outside        = newPosition.y < .residentOffsetY or newPosition.y + viewport.height > residentEnd
        .pendingSeek = .displayedEncoding != .encoding or (.virtualHeight > 0 and (before or after or outside))
        .pendingMatch.clear()
        .pendingNavigation = .None

        // Returning to resident text also supersedes an in-flight replacement.
        if .read.started and (.pendingSeek or .read.replace) do
            Atomic.exchange(&.read.cancelled, 1)
        if .pendingSeek
        {
            let ratio = Math.clamp(newPosition.y / .virtualHeight, 0, 1)
            .pendingSeekOffset = cast(u64) (ratio * cast(f32) .fileSize)
        }

        .scheduleMore()
    }

    // Creates the wrap toggle and the encoding selector in the viewer's command group.
    private mtd createCommandBar(host: Viewer.Host)
    {
        .commands = host.createCommandGroup(200)

        with .wrapButton = IconButton.create(.commands, .theme().icon(.Wrap, themeActionIconSize(.themeMetrics())), {0, 0, themeActionButtonSize(.themeMetrics()), themeActionButtonSize(.themeMetrics())}, flags: .Toggle)
        {
            .dockStyle = .Left
            .toolTip   = textStrings().ui_WrapOn
            .setCheckIndicator(.Frame)
            .sigCheckedChanged += func|view = me|(button)
            {
                discard button
                view.toggleWrap()
            }
        }

        // The detected encoding is shown rather than assumed: a file that reads as nonsense is
        // usually one whose encoding was guessed wrong, and this is where a reader corrects it.
        with .encodingCombo = ComboBox.create(.commands, {0, 0, 156, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = textStrings().ui_Encoding
            for name in TextEncodingNames do
                .addItem(name)
            for candidate, index in TextEncodings where candidate == me.encoding do
                .setSelectedIndex(cast(u32) index, notify: false)
            .sigChanged += func|view = me|(combo, index)
            {
                discard combo
                view.applyEncoding(TextEncodings[index])
            }
        }
    }

    // Creates the zoom menu button in the viewer's information group.
    private mtd createZoomControl(host: Viewer.Host)
    {
        .info = host.createInfoGroup(ViewerZoomSlotWidth)

        with .zoomLabel = IconButton.create(.info, {}, {0, 0, ViewerZoomButtonWidth, 32}, "scope.text.zoom", .CenterContent)
        {
            .dockStyle = .Center
            .margin    = {ViewerInfoControlInset, 0, ViewerInfoControlInset, 0}
            .setText("100%")
            .setArrowPosition(.RightDownward)
            .setForm(.Rectangle)
            .style.setFont(me.theme().createDefaultFontFs(11), .Regular)
            .toolTip    = textStrings().ui_ZoomMenu
            .sigPressed += func|view = me|(button)
            {
                discard button
                view.showZoomMenu()
            }
        }
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
            .sigScrollPositionChanged += func|view = me|(editor, oldPosition, newPosition)
            {
                discard editor
                view.followScroll(oldPosition, newPosition)
            }
        }
    }

    // Routes the keys the text view answers for, and keeps painting and resizing from reloading text.
    private mtd hookEvents()
    {
        .hookOnChildEvent = func|view = me|(wnd, evt)
        {
            discard wnd
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

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and (keyEvt.key == .Add or keyEvt.key == .OemPlus) and keyEvt.modifiers.has(.Control):
                view.setZoom(view.zoomPercent + 25)
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and (keyEvt.key == .Subtract or keyEvt.key == .OemMinus) and keyEvt.modifiers.has(.Control):
                view.setZoom(view.zoomPercent > 50 ? view.zoomPercent - 25 : 50)
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .D0 and keyEvt.modifiers.has(.Control):
                view.setZoom(100)
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .W and keyEvt.modifiers == .Control:
                view.toggleWrap()
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .End and (keyEvt.modifiers == .None or keyEvt.modifiers == .Control):
                view.pauseStreaming = true
                discard view.revealOffset(view.fileSize, "")
                view.pendingNavigation = .End
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .Home and (keyEvt.modifiers == .None or keyEvt.modifiers == .Control):
                view.pauseStreaming = false
                discard view.revealOffset(0, "")
                view.pendingNavigation = .Home
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and (keyEvt.key == .Down or keyEvt.key == .PageDown or keyEvt.key == .Space):
                view.pauseStreaming = false
                view.scheduleMore()
                return false

            default:
                return false
            }
        }

        .hookOnEvent = func|view = me|(wnd, evt)
        {
            discard wnd
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
        var stream = catch File.openReadLive(.fileName.toString()) as openError
        defer stream.close()
        if openError != null
        {
            .showReadError()
            return
        }

        let size = catch stream.size() as sizeError
        if sizeError != null
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
func createTextViewer(host: Viewer.Host)
{
    let view = TextViewer.create(host)
    host.attachView(view)
    host.setDetails(view.detailsText().toString())
    host.setSearch({
        revealMatch: &textRevealMatch,
        matchBounds: &textSearchBounds,
        clear: &textClearSearch})
    host.setLifecycle({
        isLoading: &textIsLoading,
        retire: func(wnd)->bool => (cast #assume (*TextViewer) wnd).retire()})
}
