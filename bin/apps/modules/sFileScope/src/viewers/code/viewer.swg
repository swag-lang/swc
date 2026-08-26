#global internal

using Core, Pixel, Gui

private const CodeStreamChunkSize = 16 * 1024'u64
private const CodeStreamLookAhead = 2.0
private const CodeResidentWindowSize = 256 * 1024'u64
private const CodeRevealContextSize = 4 * 1024'u64

internal struct CodeViewer
{
    using wnd: Wnd

    #[Swag.Late]
    editor: *RichEditCtrl

    swagLexer:         RichEditLexerSwag
    codeLexer:         GenericCodeLexer
    languageName:      String
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
    reportFailure:     #null ViewerReportFailure
    failureReason:     String
}

internal impl CodeViewer
{
    mtd hasMore()->bool => .stream.isOpen() and .bytesRead < .fileSize

    mtd needsMore()->bool
    {
        if !.hasMore() do
            return false
        if .pauseStreaming do
            return false
        let viewport     = .editor.paddedClientRect()
        let loadedHeight = .editor.loadedDocumentHeight()
        return loadedHeight <= 0 or .editor.scrollPosition().y + viewport.height * CodeStreamLookAhead >= .residentOffsetY + loadedHeight
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
        if loadedHeight <= 0 do
            return
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

    mtd showReadError(reason: string)
    {
        .stopLoading()
        .failureReason = reason
        if .failureReason.isEmpty() do
            .failureReason = "source stream could not be read"
        .editor.setEstimatedDocumentHeight(0)
        if .hasText and .reportFailure do
            .reportFailure!(me, .failureReason.toString())
    }

    mtd loadNextChunk()
    {
        if !.hasMore() do
            return

        let oldPosition = .editor.scrollPosition()
        let chunk       = catch .stream.readUtf8Chunk(CodeStreamChunkSize) as readError
        if readError != null
        {
            .showReadError(Errors.message(readError))
            return
        }

        if Utf8.indexOf(chunk.toSlice(), 0'rune) != Swag.U64.Max
        {
            .showReadError("source contains a zero byte and is not supported UTF-8 text")
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
        let start     = requested > CodeRevealContextSize ? requested - CodeRevealContextSize : 0
        for adjustment in 4
        {
            .stream = catch File.openRead(.fileName.toString()) as openError
            if openError != null do
                return false
            let actual = Math.min(start + adjustment, .fileSize)
            discard catch .stream.seek(.Begin, actual)
            let chunk = catch .stream.readUtf8Chunk(CodeResidentWindowSize) as readError
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
            if @countof(text) do
                highlightRichEditMatch(.editor, chunk.toString(), requested - actual, @countof(text))
            .scheduleMore()
            return true
        }

        return false
    }

    func create(contentParent: *Wnd, fileName: string, reportFailure: #null ViewerReportFailure = null)->*CodeViewer
    {
        let result = Wnd.create'CodeViewer(contentParent, "sFileScope.code")
        result.backgroundStyle = .View
        result.fileName        = fileName
        result.reportFailure   = reportFailure

        result.editor             = RichEditCtrl.create(result)
        result.editor.dockStyle   = .Center
        result.editor.marginLeft  = 12
        result.editor.marginRight = 12
        result.editor.style.setFont(result.theme().createDefaultFontFS(result.themeMetrics().defaultFixedFontSize), .Regular)
        result.editor.setFlags(.ReadOnly)
        let extension = Path.lowercaseExtension(fileName)
        if extension == ".swg" or extension == ".swgs"
        {
            result.languageName = "Swag"
            result.editor.setLexer(&result.swagLexer)
        }
        else
        {
            let language = codeLanguage(fileName)
            result.languageName = codeLanguageName(language)
            result.codeLexer.configure(language)
            result.editor.setLexer(&result.codeLexer)
        }

        result.editor.sigScrollPositionChanged += func|view = result|(editor, oldPosition, newPosition)
        {
            discard editor
            if view.repositioning do
                return
            if view.pauseStreaming and newPosition.y < oldPosition.y do
                view.pauseStreaming = false
            let loadedHeight = view.editor.loadedDocumentHeight()
            if loadedHeight > 0 and view.virtualHeight > 0 and (newPosition.y + view.editor.paddedClientRect().height < view.residentOffsetY or newPosition.y > view.residentOffsetY + loadedHeight)
            {
                let ratio = Math.clamp(newPosition.y / view.virtualHeight, 0, 1)
                view.pendingSeekOffset = cast(u64) (ratio * cast(f32) view.fileSize)
                view.pendingSeek       = true
            }

            view.scheduleMore()
        }
        result.hookOnChildEvent = func|view = result|(wnd, evt)
        {
            discard wnd
            switch evt
            {
            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .End and (keyEvt.modifiers == .None or keyEvt.modifiers == .Control):
                view.pauseStreaming = true
                discard view.revealOffset(view.fileSize > CodeResidentWindowSize ? view.fileSize - CodeResidentWindowSize : 0, "")
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
            result.showReadError(Errors.message(openError))
        else
        {
            let size = catch result.stream.size() as sizeError
            if sizeError != null do
                result.showReadError(Errors.message(sizeError))
            else
            {
                result.fileSize = size
                if !size do
                    result.finishLoading()
                else do
                    result.loadNextChunk()
            }
        }

        result.applyLayout()
        result.scheduleMore()
        result.setInitialFocus(result.editor)
        return result
    }
}

internal impl IWnd for CodeViewer
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
}

// Creates the integrated syntax-colored source view.
func createCodeViewer(request: const *ViewerRequest, result: *ViewerResult)
{
    registerCodeStrings(request.contentParent.app())
    let view = CodeViewer.create(request.contentParent, request.fileName, request.reportFailure)
    if !view.failureReason.isEmpty()
    {
        result.failureReason = #move view.failureReason
        view.destroy()
        return
    }

    result.view        = view
    result.details     = Format.toString(codeStrings().ui_Details, view.languageName)
    result.revealMatch = func(wnd, match, text)->bool { return (cast(*CodeViewer) wnd).revealOffset(match.offset, text) }
    result.isLoading   = func(wnd)->bool { return (cast(*CodeViewer) wnd).loadTimer != null }
}
