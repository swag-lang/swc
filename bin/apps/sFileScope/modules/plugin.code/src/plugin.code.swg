#global public

using Core, Pixel, Gui

private const ViewerPluginApiVersion = 3'u32
private const CodeStreamChunkSize = 16 * 1024'u64
private const CodeStreamLookAhead = 2.0

internal struct CodePluginView
{
    using wnd: Wnd

    #[Swag.Late]
    editor: *RichEditCtrl

    swagLexer: RichEditLexerSwag
    codeLexer: GenericCodeLexer
    languageName: String
    stream:    File.FileStream
    fileSize:  u64
    bytesRead: u64
    loadTimer: #null *Timer
    hasText:   bool
    jumpToEnd: bool
}

internal impl CodePluginView
{
    mtd hasMore()->bool => .stream.isOpen() and .bytesRead < .fileSize

    mtd needsMore()->bool
    {
        if !.hasMore() do
            return false
        if .jumpToEnd do
            return true
        let viewport     = .editor.paddedClientRect()
        let loadedHeight = .editor.loadedDocumentHeight()
        return loadedHeight <= 0 or .editor.scrollPosition().y + viewport.height * CodeStreamLookAhead >= loadedHeight
    }

    mtd updateEstimatedHeight()
    {
        if !.bytesRead or .bytesRead >= .fileSize
        {
            if .bytesRead >= .fileSize do
                .editor.setEstimatedDocumentHeight(0)
            return
        }

        let loadedHeight = .editor.loadedDocumentHeight()
        if loadedHeight <= 0 do
            return
        let estimate = loadedHeight * cast(f32) .fileSize / cast(f32) .bytesRead
        .editor.setEstimatedDocumentHeight(Math.max(estimate, loadedHeight))
    }

    mtd scheduleMore()
    {
        if .loadTimer or !.needsMore() do
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
        .editor.setEstimatedDocumentHeight(0)
        if .jumpToEnd
        {
            .jumpToEnd = false
            .editor.keyPressed(.End, .Control)
        }
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

    func create(contentParent: *Wnd, fileName: string)->*CodePluginView
    {
        let result = Wnd.create'CodePluginView(contentParent, "sFileScope.code")
        result.backgroundStyle = .View

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
            discard oldPosition
            discard newPosition
            view.scheduleMore()
        }
        result.hookOnChildEvent = func|view = result|(wnd, evt)
        {
            discard wnd
            switch evt
            {
            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .End and keyEvt.modifiers == .Control:
                if view.hasMore()
                {
                    view.jumpToEnd = true
                    view.scheduleMore()
                }
                else do
                    view.editor.keyPressed(.End, .Control)
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .Home and keyEvt.modifiers == .Control:
                view.jumpToEnd = false
                view.editor.keyPressed(.Home, .Control)
                return true

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
        .updateEstimatedHeight()
        if .needsMore() do
            .loadNextChunk()
        .scheduleMore()
    }
}

// Creates the syntax-colored Swag source view exported through the sFileScope plugin ABI.
func sFileScopePluginCreate(contentParent, commandParent: *Wnd, fileName: string, apiVersion: u32, commands: *#null *Wnd, details: *String)->#null *Wnd
{
    discard commandParent
    if apiVersion != ViewerPluginApiVersion do
        return null
    commands[] = null
    let view = CodePluginView.create(contentParent, fileName)
    details[] = Format.toString("% · UTF-8 · streamed", view.languageName)
    return view
}
