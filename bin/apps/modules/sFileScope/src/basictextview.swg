using Core, Pixel, Gui

private const TextStreamChunkSize    = 16 * 1024'u64
private const TextStreamLookAhead    = 2.0
private const TextResidentWindowSize = 256 * 1024'u64
private const TextRevealContextSize  = 4 * 1024'u64

// Head of the file the encoding is decided from. A few kilobytes name every encoding a text file
// uses; reading more answers no better and delays the first screen.
private const TextProbeSize = 4 * 1024'u64

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
struct BasicTextView
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commands:      *ViewerCommandBar
        editor:        *RichEditCtrl
        wrapButton:    *IconButton
        encodingCombo: *ComboBox
    }

    stream:            File.FileStream
    fileName:          String
    fileSize:          u64
    bytesRead:         u64
    residentStart:     u64
    residentOffsetY:   f32
    virtualHeight:     f32
    loadTimer:         #null *Timer
    hasText:           bool
    pauseStreaming:    bool
    pendingSeek:       bool
    pendingSeekOffset: u64
    repositioning:     bool
    encoding:          Text.Encoding
    contentStart:      u64
    wrapping = true
    reportDetails:     #null ViewerReportDetails
}

func basicTextRevealMatch(wnd: *Wnd, match: ViewerSearchMatch, text: string)->bool
{
    return (cast(*BasicTextView) wnd).revealOffset(match.offset, text)
}

func basicTextSearchBounds(wnd: *Wnd, match: ViewerSearchMatch, result: *Math.Rectangle)->bool
{
    discard match
    return richEditSearchBounds((cast(*BasicTextView) wnd).editor, result)
}

func basicTextClearSearch(wnd: *Wnd)
{
    clearRichEditSearch((cast(*BasicTextView) wnd).editor)
}

func basicTextIsLoading(wnd: *Wnd)->bool => (cast(*BasicTextView) wnd).loadTimer != null

impl BasicTextView
{
    mtd encodingName()->string
    {
        for candidate, index in TextEncodings where candidate == .encoding do
            return TextEncodingNames[index]
        return TextEncodingNames[0]
    }

    // Reads the head of a file once and reports how it spells its characters.
    //
    // Deciding and accepting are two questions: code page 1252 gives every byte a meaning, so an
    // executable also decodes into characters. The encoding answers the first, and what those
    // characters are answers the second.
    func probe(fileName: string)->TextProbe
    {
        var result: retval
        var stream = catch File.openRead(fileName) as openError
        if openError != null do
            return result
        defer stream.close()

        var bytes: Array'u8
        bytes.resize(TextProbeSize)
        let count = catch stream.read(bytes.toSlice()) as readError
        if readError != null do
            return result
        bytes.resize(count)

        result.encoding     = Text.detectEncoding(bytes.toSlice())
        result.contentStart = Text.hasBom(bytes.toSlice(), result.encoding) ? Text.bomLength(result.encoding) : 0
        result.accepted     = Text.looksLikeText(bytes.toSlice()[result.contentStart to], result.encoding)
        return result
    }

    // Reports whether the beginning of a file reads as text. The basic renderer is a fallback for
    // textual content, not an alternate spelling of every binary format.
    func supports(fileName: string)->bool
    {
        return probe(fileName).accepted
    }

    mtd hasMore()->bool
    {
        return .stream.isOpen() and .bytesRead < .fileSize
    }

    mtd needsMore()->bool
    {
        if !.hasMore() do
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
        if !consumed do
            return
        if .bytesRead >= .fileSize and !.residentStart
        {
            .editor.setEstimatedDocumentHeight(0)
            return
        }

        let loadedHeight = .editor.loadedDocumentHeight()
        .residentOffsetY = .fileSize ? .virtualHeight * cast(f32) .residentStart / cast(f32) .fileSize : 0
        if loadedHeight <= 0
        {
            if .virtualHeight > 0 do
                .editor.setVirtualDocumentRange(.residentOffsetY, .virtualHeight)
            return
        }

        .virtualHeight   = Math.max(.virtualHeight, loadedHeight * cast(f32) .fileSize / cast(f32) consumed, loadedHeight)
        .residentOffsetY = .fileSize ? .virtualHeight * cast(f32) .residentStart / cast(f32) .fileSize : 0
        .editor.setVirtualDocumentRange(.residentOffsetY, .virtualHeight)
    }

    mtd scheduleMore()
    {
        if .loadTimer or (!.pendingSeek and !.needsMore()) do
            return
        .loadTimer = .addTimer(8'ms)
    }

    mtd stopLoading()
    {
        if .loadTimer
        {
            .removeTimer(.loadTimer!)
            .loadTimer = null
        }

        .stream.close()
    }

    mtd finishLoading()
    {
        .stream.close()
        .bytesRead = .fileSize
        if !.residentStart do
            .editor.setEstimatedDocumentHeight(0)
    }

    mtd showReadError()
    {
        .stopLoading()
        let message = appStrings().ui_NotText
        if !.hasText do
            .editor.setText(message)
        else do
            .editor.addText(Format.toString("\n\n%", message).toString())
        .editor.setEstimatedDocumentHeight(0)
    }

    mtd loadNextChunk()
    {
        if !.hasMore() do
            return
        if .bytesRead - .residentStart >= TextResidentWindowSize do
            return

        let oldPosition = .editor.scrollPosition()
        let chunk       = catch .stream.readTextChunk(TextStreamChunkSize, .encoding) as readError
        if readError != null
        {
            // An unmarked legacy file can open with an ASCII-only probe and reveal its first
            // code-page byte much later. UTF-8 is then only the probe's tentative answer: reread
            // the resident document as the single-byte fallback instead of rejecting the file.
            if .encoding == .Utf8 and !.contentStart and readError is Errors.InvalidFormatError
            {
                .applyEncoding(.Windows1252)
                return
            }

            .showReadError()
            return
        }

        if Utf8.indexOf(chunk.toSlice(), 0'rune) != Swag.U64.Max
        {
            .showReadError()
            return
        }

        if chunk.isEmpty()
        {
            .finishLoading()
            return
        }

        .editor.addText(chunk.toString())
        let position = catch .stream.position() as positionError
        if positionError == null do
            .bytesRead = position
        .hasText = true
        .updateEstimatedHeight()
        .editor.setScrollPosition(oldPosition)
        if !.hasMore() do
            .finishLoading()
    }

    mtd revealOffset(offset: u64, text: string)->bool
    {
        .stopLoading()
        .pendingSeek   = false
        .repositioning = true
        defer .repositioning = false
        let requested = Math.min(offset, .fileSize)

        // The window opens on a character boundary. UTF-8 finds it by stepping forward until the
        // bytes decode, and a wide encoding by counting whole units from the first byte of text.
        let unit  = Text.unitSize(.encoding)
        var start = requested > TextRevealContextSize ? requested - TextRevealContextSize : 0
        start = Math.max(start, .contentStart)
        start -= (start - .contentStart) % unit
        for adjustment in 4
        {
            .stream = catch File.openRead(.fileName.toString()) as openError
            if openError != null do
                return false
            let actual = Math.min(start + adjustment * unit, .fileSize)
            discard catch .stream.seek(.Begin, actual)
            let chunk = catch .stream.readTextChunk(TextResidentWindowSize, .encoding) as readError
            if readError != null
            {
                .stream.close()
                continue
            }

            let previousHeight = Math.max(.virtualHeight, .editor.scrollableClientRect().height)
            .residentStart = actual
            .editor.setText(chunk.toString())
            let position = catch .stream.position() as positionError
            .bytesRead     = positionError == null ? position : actual + chunk.length
            .hasText       = !chunk.isEmpty()
            .virtualHeight = previousHeight
            .updateEstimatedHeight()
            if @countof(text)
            {
                if .encoding == .Utf8 do
                    highlightRichEditMatch(.editor, chunk.toString(), requested - actual, @countof(text))
                else do
                    discard .editor.findText(text)
            }

            .scheduleMore()
            return true
        }

        return false
    }

    mtd updateWrap()
    {
        .editor.setFlags(.ReadOnly | (.wrapping ? RichEditFlags.WordWrap : .None))
        .wrapButton.setChecked(.wrapping)
        .wrapButton.toolTip = .wrapping ? appStrings().ui_WrapOn : appStrings().ui_WrapOff
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

        var head: Array'u8
        head.resize(Text.bomLength(encoding))
        var stream = catch File.openRead(.fileName.toString()) as openError
        if openError == null
        {
            let count = catch stream.read(head.toSlice()) as readError
            head.resize(readError == null ? count : 0)
            stream.close()
        }

        .contentStart  = Text.hasBom(head.toSlice(), encoding) ? Text.bomLength(encoding) : 0
        .virtualHeight = 0
        discard .revealOffset(Math.max(.residentStart, .contentStart), "")
        if .reportDetails do
            .reportDetails!(me, Format.toString(appStrings().ui_TextDetails, .encodingName()))
    }

    mtd toggleWrap()
    {
        .wrapping = !.wrapping
        .updateWrap()
    }
}

impl IWnd for BasicTextView
{
    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .stopLoading()
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .loadTimer
        {
            evt.accepted = false
            return
        }

        .removeTimer(evt.timer)
        .loadTimer = null
        if .pendingSeek
        {
            let offset = .pendingSeekOffset
            .pendingSeek = false
            discard .revealOffset(offset, "")
            return
        }

        .updateEstimatedHeight()
        if .needsMore() do
            .loadNextChunk()
        .scheduleMore()
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind == .Pressed and evt.key == .W and evt.modifiers.has(.Control) do
            .toggleWrap()
        else do
            evt.accepted = false
    }
}

impl BasicTextView
{
    func create(contentParent, commandParent: *Wnd, fileName: string, reportDetails: #null ViewerReportDetails = null)->*BasicTextView
    {
        let result = Wnd.create'BasicTextView(contentParent, "sFileScope.basicText")
        result.backgroundStyle = .View
        result.fileName        = fileName
        result.reportDetails   = reportDetails

        let probed = probe(fileName)
        result.encoding     = probed.encoding
        result.contentStart = probed.contentStart

        result.commands = ViewerCommandBar.create(commandParent, 200)

        with result.wrapButton = IconButton.create(result.commands, result.theme().icon(.Wrap), {0, 0, 36, 36}, flags: .Toggle)
        {
            .dockStyle = .Left
            .toolTip   = appStrings().ui_WrapOn
            .setCheckIndicator(.Frame)
            .sigCheckedChanged += func|view = result|(button)
            {
                discard button
                view.toggleWrap()
            }
        }

        // The detected encoding is shown rather than assumed: a file that reads as nonsense is
        // usually one whose encoding was guessed wrong, and this is where a reader corrects it.
        with result.encodingCombo = ComboBox.create(result.commands, {0, 0, 156, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = appStrings().ui_Encoding
            for name in TextEncodingNames do
                .addItem(name)
            for candidate, index in TextEncodings where candidate == probed.encoding do
                .setSelectedIndex(cast(u32) index, notify: false)
            .sigChanged += func|view = result|(combo, index)
            {
                discard combo
                view.applyEncoding(TextEncodings[index])
            }
        }

        result.editor             = RichEditCtrl.create(result)
        result.editor.dockStyle   = .Center
        result.editor.marginLeft  = 12
        result.editor.marginRight = 12
        result.editor.style.setFont(result.theme().createDefaultFontFS(result.themeMetrics().defaultFixedFontSize), .Regular)
        result.editor.sigScrollPositionChanged += func|view = result|(editor, oldPosition, newPosition)
        {
            discard editor
            if view.repositioning do
                return
            if view.pauseStreaming and newPosition.y < oldPosition.y do
                view.pauseStreaming = false
            let laidOutHeight  = view.editor.loadedDocumentHeight()
            let residentHeight = laidOutHeight > 0 ? laidOutHeight : (view.fileSize ? view.virtualHeight * cast(f32) (view.bytesRead - view.residentStart) / cast(f32) view.fileSize : 0)
            if view.virtualHeight > 0 and (newPosition.y + view.editor.paddedClientRect().height < view.residentOffsetY or newPosition.y > view.residentOffsetY + residentHeight)
            {
                let ratio = Math.clamp(newPosition.y / view.virtualHeight, 0, 1)
                view.pendingSeekOffset = cast(u64) (ratio * cast(f32) view.fileSize)
                view.pendingSeek       = true
            }
            else do
                view.pendingSeek = false

            view.scheduleMore()
        }
        result.hookOnChildEvent = func|view = result|(wnd, evt)
        {
            discard wnd
            switch evt
            {
            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .W and keyEvt.modifiers == .Control:
                view.toggleWrap()
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .End and (keyEvt.modifiers == .None or keyEvt.modifiers == .Control):
                view.pauseStreaming = true
                discard view.revealOffset(view.fileSize > TextResidentWindowSize ? view.fileSize - TextResidentWindowSize : 0, "")
                view.editor.keyPressed(.End, .Control)
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .Home and (keyEvt.modifiers == .None or keyEvt.modifiers == .Control):
                view.pauseStreaming = false
                discard view.revealOffset(0, "")
                view.editor.keyPressed(.Home, .Control)
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and (keyEvt.key == .Down or keyEvt.key == .PageDown or keyEvt.key == .Space):
                view.pauseStreaming = false
                view.scheduleMore()
                return false

            default:
                return false
            }
        }
        result.hookOnEvent = func|view = result|(wnd, evt)
        {
            discard wnd
            if evt is ResizeEvent
            {
                view.updateEstimatedHeight()
                view.scheduleMore()
            }

            return false
        }

        result.stream = catch File.openRead(fileName) as openError
        if openError != null do
            result.showReadError()
        else
        {
            let size = catch result.stream.size() as sizeError
            if sizeError != null do
                result.showReadError()
            else
            {
                result.fileSize = size
                if !size do
                    result.stream.close()
                else
                {
                    // A byte-order mark is part of the file and not part of the text, so reading
                    // starts past it and every offset the view reports stays a file offset.
                    discard catch result.stream.seek(.Begin, result.contentStart)
                    result.bytesRead     = result.contentStart
                    result.residentStart = result.contentStart
                    result.loadNextChunk()
                }
            }
        }

        result.updateWrap()
        result.applyLayout()
        result.scheduleMore()
        result.setInitialFocus(result.editor)
        return result
    }
}
