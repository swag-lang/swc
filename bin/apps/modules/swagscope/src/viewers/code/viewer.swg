#global internal
#global namespace Viewers.Code

using Core, Pixel, Gui

private func pluginProbe(content: Viewer.ProbeContent)->bool => not content.claimed and shebang(cast(string, content.head)).found

// Describes the source-code viewer to the host.
//
// A file with no known extension is still offered the viewer when it opens with an interpreter
// line, which is how a script without a suffix names the language it is written in.
func viewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "code"
        .staticName   = "Code"
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Code)
        .create       = &createViewer
        .probe        = &pluginProbe
        .textual      = true
        .smokeFixture = "sample.cpp"
        .addSelectors([
            ".swg", ".swgs", ".c", ".h", ".cc", ".cpp", ".cxx", ".hh", ".hpp", ".hxx", ".inl",
            ".ipp", ".cs", ".java", ".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".mts", ".cts",
            ".go", ".rs", ".py", ".pyw", ".pyi", ".rb", ".rake", ".gemspec", ".sh", ".bash", ".zsh",
            ".fish", ".ps1", ".psm1", ".psd1", ".php", ".phtml", ".lua", ".sql", ".json", ".jsonc",
            ".json5", ".xml", ".xsd", ".xsl", ".xslt", ".csproj", ".vcxproj", ".props", ".targets",
            ".css", ".scss", ".sass", ".less", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".conf",
            ".properties", ".kt", ".kts", ".swift", ".dart", ".r", ".pl", ".pm", ".vb", ".glsl",
            ".vert", ".frag", ".geom", ".comp", ".hlsl", ".fx", ".cmake", ".bat", ".cmd", ".htm",
            ".html", ".shtml", ".xht", ".xhtml", ".asm", ".s", ".incasm", ".zig", ".nim", ".nims",
            ".nimble", ".hs", ".lhs", ".scala", ".sc", ".groovy", ".gvy", ".gy", ".gsh", ".ex",
            ".exs", ".erl", ".hrl", ".clj", ".cljs", ".cljc", ".edn", ".jl", ".f", ".for", ".f77",
            ".f90", ".f95", ".f03", ".f08", ".pas", ".pp", ".lpr", ".d", ".di", ".m", ".mm", ".tcl",
            ".tk", ".awk", ".vim", ".tex", ".sty", ".cls", ".bib", ".proto", ".graphql", ".gql",
            ".gradle", ".mk", ".mak", ".make", "makefile", "gnumakefile", "bsdmakefile",
            ".dockerfile", "dockerfile", "containerfile", "cmakelists.txt", "justfile", "rakefile",
            "gemfile", "vagrantfile", "podfile", "brewfile", "jenkinsfile", "meson.build",
            ".gitignore", ".gitattributes", ".gitmodules", ".editorconfig", ".clang-format",
            ".clang-tidy", ".prettierrc", ".eslintrc", ".npmrc", ".yarnrc", ".env", ".nix"])
    }

    return result
}

private
{
    const StreamChunkSize = 16 * 1024'u64

    // Viewport heights of text kept loaded from the top of the visible one: it and five more.
    const StreamLookAhead    = 6.0
    const ResidentWindowSize = 256 * 1024'u64
    const RevealContextSize  = 64 * 1024'u64
}

// The source-code viewer: a read-only editor colored by the Swag lexer or the generic one,
// over a bounded window of the file streamed in the background.
struct Panel
{
    using wnd: Wnd

    late editor: *RichEditCtrl

    info:              *Wnd?
    zoomLabel:         *IconButton?
    zoomPercent:       u32 = 100
    swagLexer:         RichEditLexerSwag
    codeLexer:         GenericLexer
    languageName:      String
    stream:            File.FileStream
    fileName:          String
    fileSize:          u64
    bytesRead:         u64
    residentStart:     u64
    residentOffsetY:   f32
    virtualHeight:     f32
    loadTimer:         *Timer?
    hasText:           bool
    pauseStreaming:    bool
    pendingSeek:       bool
    pendingSeekOffset: u64
    repositioning:     bool
    services:          Viewer.HostServices
    failureReason:     String
}

impl Panel
{
    mtd hasMore()->bool => .stream.isOpen() and .bytesRead < .fileSize

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
        if loadedHeight <= 0
        {
            if .repositioning or not .residentStart do
                .residentOffsetY = .fileSize ? .virtualHeight * cast(f32, .residentStart) / cast(f32, .fileSize) : 0
            if .virtualHeight > 0 do
                .editor.setVirtualDocumentRange(.residentOffsetY, .virtualHeight)
            return
        }

        .virtualHeight = Math.max(.virtualHeight, loadedHeight * cast(f32, .fileSize) / cast(f32, consumed), loadedHeight)
        if .repositioning or not .residentStart do
            .residentOffsetY = .fileSize ? .virtualHeight * cast(f32, .residentStart) / cast(f32, .fileSize) : 0
        .editor.setVirtualDocumentRange(.residentOffsetY, .virtualHeight)
    }

    mtd scheduleMore()
    {
        if .loadTimer or (not .pendingSeek and not .needsMore()) do
            return
        .loadTimer = .addTimer(8'ms)
    }

    mtd stopLoading()
    {
        .stopTimer(&.loadTimer)

        .stream.close()
    }

    mtd finishLoading()
    {
        .stream.close()
        .bytesRead = .fileSize
        if not .residentStart do
            .editor.setEstimatedDocumentHeight(0)
    }

    mtd showReadError(reason: string)
    {
        .stopLoading()
        .failureReason = reason
        if .failureReason.isEmpty() do
            .failureReason = texts().err_Read
        .editor.setEstimatedDocumentHeight(0)
        if .hasText do
            .services.failed(me, .failureReason)
    }

    // Appends the next chunk of the stream to the editor while the resident window has room,
    // keeping the scroll position. A zero byte stops the load with an error, as the file is then
    // not text.
    mtd loadNextChunk()
    {
        if .bytesRead - .residentStart >= ResidentWindowSize do
            return
        if not .hasMore() do
            return

        let oldPosition = .editor.scrollPosition()
        let chunk       = catch .stream.readUtf8Chunk(StreamChunkSize) as readError
        if readError != null
        {
            .showReadError(Errors.message(readError))
            return
        }

        if Utf8.indexOf(chunk.toSlice(), 0'rune) != Swag.U64.Max
        {
            .showReadError(texts().err_ZeroByte)
            return
        }

        if chunk.isEmpty()
        {
            .finishLoading()
            return
        }

        .editor.addText(chunk)
        let position = catch .stream.position() as positionError
        if positionError == null do
            .bytesRead = position
        .hasText = true
        .updateEstimatedHeight()
        .editor.setScrollPosition(oldPosition)
        if not .hasMore() do
            .finishLoading()
    }

    // Reloads the resident window to start shortly before `offset` and highlights `text` there. A
    // start inside a UTF-8 sequence does not decode, so it moves forward up to three bytes to reach
    // the next character. Returns false when the file cannot be read there.
    mtd revealOffset(offset: u64, text: string)->bool
    {
        .stopLoading()
        .pendingSeek   = false
        .repositioning = true
        defer .repositioning = false
        let requested = Math.min(offset, .fileSize)
        let start     = requested > RevealContextSize ? requested - RevealContextSize : 0
        for adjustment in 4
        {
            .stream = catch File.openReadLive(.fileName) as openError
            if openError != null do
                return false
            let actual = Math.min(start + adjustment, .fileSize)
            discard catch .stream.seek(.Begin, actual)
            let chunk = catch .stream.readUtf8Chunk(ResidentWindowSize) as readError
            if readError != null
            {
                .stream.close()
                continue
            }

            let previousHeight = Math.max(.virtualHeight, .editor.scrollableClientRect().height)
            .residentStart = actual
            .editor.setText(chunk)
            let position = catch .stream.position() as positionError
            .bytesRead     = positionError == null ? position : actual + chunk.length
            .hasText       = not chunk.isEmpty()
            .virtualHeight = previousHeight
            .updateEstimatedHeight()
            if text.count do
                Viewer.highlightRichEditMatch(.editor, chunk, requested - actual, text.count)
            .scheduleMore()
            return true
        }

        return false
    }

    mtd setZoom(percent: u32)
    {
        .zoomPercent = Viewer.clampZoom(percent)
        let base = .themeMetrics().defaultFixedFontSize
        let size = cast(u32, Math.max(Math.round(cast(f32, base) * cast(f32, .zoomPercent) / 100), 1))
        .editor.style.setFont(.theme().createDefaultFontFs(size), .Regular)
        .editor.setFlags(.editor.flags)
        .zoomLabel?.setText(Viewer.zoomText(.zoomPercent))
        .updateEstimatedHeight()
    }

    mtd showZoomMenu()
    {
        if not .zoomLabel do
            return
        let percent = Viewer.pickZoom(me, .zoomLabel, .zoomPercent)
        if percent do
            .setZoom(percent)
    }

    // Creates the streamed, syntax-colored view of `fileName` under `contentParent`.
    //
    // `info` receives the zoom control when the view is hosted with an information group, and
    // `services` hear about read errors discovered once text is already shown.
    func create(contentParent: *Wnd, fileName: string, services: Viewer.HostServices = {}, info: *Wnd? = null)->*Panel
    {
        with let result = Wnd.create'Panel(contentParent, "scope.code")
        {
            .backgroundStyle = .View
            .fileName        = fileName
            .services        = services
            .info            = info
        }

        result.createEditor()
        if info do
            result.createZoomControl(info)
        result.selectLexer()
        result.hookEvents()
        result.startReading()

        result.applyLayout()
        result.setZoom(100)
        result.scheduleMore()
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
        .pendingSeek = .virtualHeight > 0 and (before or after or outside)
        if .pendingSeek
        {
            let ratio = Math.clamp(newPosition.y / .virtualHeight, 0, 1)
            .pendingSeekOffset = cast(u64, (ratio * cast(f32, .fileSize)))

            // A continuous gesture must have its bytes before the next paint, even when
            // the timer was delayed. Ordinary prefetch still runs on the short timer.
            if outside and Math.abs(newPosition.y - oldPosition.y) <= viewport.height
            {
                if not before and not after and .needsMore()
                {
                    .pendingSeek = false
                    .loadNextChunk()
                }
                else
                {
                    discard .revealOffset(.pendingSeekOffset, "")
                }
            }
        }

        .scheduleMore()
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
            .setFlags(.ReadOnly)
        }
    }

    // Creates the zoom menu button in the host's information group `info`.
    private mtd createZoomControl(info: *Wnd)
    {
        .zoomLabel = Viewer.createZoomButton(info, "scope.code.zoom", texts().ui_ZoomMenu)
        .zoomLabel.sigPressed += func|view = me|(_) { view.showZoomMenu() }
    }

    // Colors the editor with the Swag lexer for Swag sources, and with the generic lexer configured
    // for the file's language otherwise.
    private mtd selectLexer()
    {
        let extension = Path.lowercaseExtension(.fileName)
        if extension == ".swg" or extension == ".swgs"
        {
            .languageName = "Swag"
            .editor.setLexer(&.swagLexer)
        }
        else
        {
            let language = detectLanguage(.fileName)
            .languageName = displayName(language)
            .codeLexer.configure(language)
            .editor.setLexer(&.codeLexer)
        }
    }

    // Follows scrolling with the resident window, routes the keys the code view answers for, and
    // keeps painting and resizing from reloading text.
    private mtd hookEvents()
    {
        .editor.sigScrollPositionChanged += func|view = me|(_, oldPosition, newPosition)
        {
            view.followScroll(oldPosition, newPosition)
        }

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

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and
                                          keyEvt.key == .End and
                                          (keyEvt.modifiers == .None or keyEvt.modifiers == .Control):
                view.pauseStreaming = true
                discard view.revealOffset(view.fileSize, "")
                view.repositioning = true
                view.editor.keyPressed(.End, .Control)
                view.repositioning = false
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and
                                          keyEvt.key == .Home and
                                          (keyEvt.modifiers == .None or keyEvt.modifiers == .Control):
                view.pauseStreaming = false
                discard view.revealOffset(0, "")
                view.repositioning = true
                view.editor.keyPressed(.Home, .Control)
                view.repositioning = false
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and (keyEvt.key == .Down or keyEvt.key == .PageDown or keyEvt.key == .Space):
                view.pauseStreaming = false
                view.scheduleMore()
                return false

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

    // Opens the source stream and reads its first chunk, or records why it cannot be read.
    private mtd startReading()
    {
        .stream = catch File.openReadLive(.fileName) as openError
        if openError != null
        {
            .showReadError(Errors.message(openError))
            return
        }

        let size = catch .stream.size() as sizeError
        if sizeError != null
        {
            .showReadError(Errors.message(sizeError))
            return
        }

        .fileSize = size
        if not size do
            .finishLoading()
        else do
            .loadNextChunk()
    }
}

impl IWnd for Panel
{
    mtd impl onPaint(_: *PaintEvent)
    {
        if .pendingSeek do
            discard .revealOffset(.pendingSeekOffset, "")
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged and .zoomLabel do
            .zoomLabel.toolTip = texts().ui_ZoomMenu
        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
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

        .stopTimer(&.loadTimer)
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
func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host.contentParent(), host.fileName(), host.services(), host.createInfoGroup(Viewer.ZoomSlotWidth))
    if not view.failureReason.isEmpty()
    {
        host.reject(view.failureReason)
        view.destroy()
        return
    }

    host.attachView(view)
    host.setDetails(Format.toString(texts().ui_Details, view.languageName))

    with var search: Viewer.SearchApi
    {
        .revealMatch = func|view|(match, text)->bool => view.revealOffset(match.offset, text)
        .matchBounds = func|view|(_, bounds)->bool => Viewer.richEditMatchBounds(view.editor, bounds)
        .clear       = func|view|() => Viewer.clearRichEditMatch(view.editor)
    }

    host.setSearch(search)

    host.setLifecycle({isLoading: func|view|()->bool => view.loadTimer != null})
}
