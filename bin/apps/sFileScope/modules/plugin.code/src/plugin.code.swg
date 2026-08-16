#global public

using Core, Pixel, Gui

private const ViewerPluginApiVersion = 4'u32
private const CodeStreamChunkSize = 16 * 1024'u64
private const CodeStreamLookAhead = 2.0
private const CodeResidentWindowSize = 256 * 1024'u64

internal struct CodePluginView
{
    using wnd: Wnd

    #[Swag.Late]
    editor: *RichEditCtrl

    swagLexer: RichEditLexerSwag
    codeLexer: GenericCodeLexer
    languageName: String
    stream:    File.FileStream
    fileName:  String
    fileSize:  u64
    bytesRead: u64
    residentStart:   u64
    residentOffsetY: f32
    virtualHeight:   f32
    loadTimer: #null *Timer
    hasText:   bool
    pauseStreaming: bool
    pendingSeek:       bool
    pendingSeekOffset: u64
}

internal impl CodePluginView
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
        .virtualHeight   = Math.max(loadedHeight * cast(f32) .fileSize / cast(f32) consumed, loadedHeight)
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
        let message = "This file does not contain supported UTF-8 source text. Select Hexadecimal to inspect its bytes."
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

        let oldPosition = .editor.scrollPosition()
        let chunk       = catch .stream.readUtf8Chunk(CodeStreamChunkSize) as readError
        if readError != null or Utf8.indexOf(chunk.toSlice(), 0'rune) != Swag.U64.Max
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
        let start = Math.min(offset, .fileSize)
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
            .bytesRead = positionError == null ? position : actual + chunk.length
            .hasText   = !chunk.isEmpty()
            .virtualHeight   = Math.max(previousHeight, .editor.paddedClientRect().height)
            .residentOffsetY = .fileSize ? .virtualHeight * cast(f32) actual / cast(f32) .fileSize : 0
            .editor.setVirtualDocumentRange(.residentOffsetY, .virtualHeight)
            if @countof(text) do
                discard .editor.findText(text)
            .scheduleMore()
            return true
        }
        return false
    }

    func create(contentParent: *Wnd, fileName: string)->*CodePluginView
    {
        let result = Wnd.create'CodePluginView(contentParent, "sFileScope.code")
        result.backgroundStyle = .View
        result.fileName        = fileName

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

internal impl IWnd for CodePluginView
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

// Creates the syntax-colored Swag source view exported through the sFileScope plugin ABI.
func sFileScopePluginCreate(contentParent, commandParent: *Wnd, fileName: string, apiVersion: u32, commands: *#null *Wnd, details: *String, revealMatch: *#null func||(*Wnd, u64, string)->bool)->#null *Wnd
{
    discard commandParent
    if apiVersion != ViewerPluginApiVersion do
        return null
    commands[] = null
    let view = CodePluginView.create(contentParent, fileName)
    revealMatch[] = func(wnd, offset, text)->bool { return (cast(*CodePluginView) wnd).revealOffset(offset, text) }
    details[] = Format.toString("% · UTF-8 · streamed", view.languageName)
    return view
}
