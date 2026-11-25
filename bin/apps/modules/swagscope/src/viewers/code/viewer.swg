#global internal
#global namespace Viewers.Code

using Core, Pixel, Gui

private var g_ZoomPercent: u32 = 100

// Whether source code marks its spaces and tabulations. The choice follows the reader from file to file.
private var g_Blanks: bool

// Whether source code wraps long lines. The choice follows the reader from file to file.
private var g_Wrapping: bool

// Whether source code shows logical line numbers. The choice follows the reader from file to file.
private var g_LineNumbers: bool = true

// Width of a tab stop in source code, in spaces. The choice follows the reader from file to file.
private var g_TabWidth: s32 = 4

internal func defaultTabWidth()->s32 => g_TabWidth

internal func setDefaultTabWidth(width: s32)
{
    g_TabWidth = width == 2 or width == 4 or width == 8 ? width : 4
}

// Test-only override for the directory containing per-file language choices. The application
// uses the user-data directory; functional tests give each case an isolated temporary one.
internal var g_CodeOverrideDirectory: String

private const LanguageOverrideHeader = "SwagScope code language v1\n"

// Returns the directory used for the small, viewer-owned language preference records.
private func languageOverrideDirectory()->String
{
    if g_CodeOverrideDirectory.count do
        return g_CodeOverrideDirectory
    return Path.combine(Env.getSpecialDirectory(.UserAppData), "Swag", "scope", "code-language")
}

// Produces an opaque filename from a canonical path. The clear path is never written to disk.
internal func languageOverridePath(fileName: string)->String
{
    let absolute = catch Path.absolute(fileName) { return "" }
    let digest   = Hash.Sha256.compute(cast(const [..] u8, absolute.toString()))
    var name: String
    for word in digest do
        name += Format.toString("%{X08}", word)
    return Path.combine(languageOverrideDirectory(), Format.toString("%.txt", name))
}

// Includes file metadata in the preference identity so a replacement at the same path does not
// inherit the previous file's manual choice. Hashing the metadata keeps the record opaque.
internal func languageOverrideIdentity(fileName: string)->String
{
    let absolute = catch Path.absolute(fileName) { return "" }
    let info     = catch File.info(absolute) { return "" }
    let material = Format.toString("scope-code-language-v1\n%\n%\n%\n%",
                                   absolute,
                                   info.size,
                                   Hash.hash64(info.creationTime),
                                   Hash.hash64(info.lastWriteTime))
    let digest = Hash.Sha256.compute(cast(const [..] u8, material.toString()))
    var result: String
    for word in digest do
        result += Format.toString("%{X08}", word)
    return result
}

private func languageOverrideName(language: SourceLanguage, swag: bool)->string
{
    if swag do
        return "Swag"

    // The user-facing name of Plain Text is translated, so keep a stable storage token instead.
    return language == .PlainText ? "PlainText" : displayName(language)
}

// Loads only a known language name and a record for the current file version. Damaged or
// unsupported records are ignored and detection remains the fallback.
private func readLanguageOverride(fileName: string)->String
{
    let path     = languageOverridePath(fileName)
    let identity = languageOverrideIdentity(fileName)
    if not path.count or not identity.count or not File.exists(path) do
        return ""
    let contents = catch File.readAllText(path) { return "" }
    if not Utf8.startsWith(contents, LanguageOverrideHeader) do
        return ""
    let lines = Tokenize.split(contents[LanguageOverrideHeader.count to], '\n'u8)
    if lines.count != 2 or lines[0] != identity do
        return ""
    let name = lines[1]
    if name == "Swag" or name == "PlainText" do
        return name
    for language in SourceLanguage where languageOverrideName(language, false) == name do
        return name
    return ""
}

// Saves an explicit language choice atomically; a failed preference write must not affect the
// reader's ability to view the source.
private func writeLanguageOverride(fileName: string, language: SourceLanguage, swag: bool)
{
    let path     = languageOverridePath(fileName)
    let identity = languageOverrideIdentity(fileName)
    if not path.count or not identity.count do
        return
    catch Directory.create(languageOverrideDirectory(), recurse: true) { return; }
    let temp = Format.toString("%.%.tmp", path, Guid128.random())
    discard catch File.writeAllText(temp,
                                    Format.toString("%\n%\n%\n", LanguageOverrideHeader, identity, languageOverrideName(language, swag)))
    {
        return
    }

    catch File.move(path, temp)
    {
        discard catch File.delete(temp)
    }
}

// Reports whether `c` opens or closes a pair the source viewer matches: (), [] or {}.
func isDelimiter(c: rune)->bool => c == '(' or c == ')' or c == '[' or c == ']' or c == '{' or c == '}'

// Returns the delimiter that closes or opens the pair `c` belongs to.
func delimiterPartner(c: rune)->rune
{
    switch c
    {
    case '(': return ')'
    case ')': return '('
    case '[': return ']'
    case ']': return '['
    case '{': return '}'
    }

    return '{'
}

private func pluginProbe(content: Viewer.ProbeContent)->bool => not content.claimed and shebang(cast(string, content.head)).found

// Describes the source-code viewer to the host.
//
// A file with no known extension is still offered the viewer when it opens with an interpreter
// line, which is how a script without a suffix names the language it is written in.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
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
    const StreamChunkSize   = 16 * 1024'u64
    const RevealContextSize = 64 * 1024'u64
}

// The source-code viewer: a read-only editor colored by the Swag lexer or the generic one,
// over a bounded window of the file streamed in the background.
struct Panel
{
    using wnd: Wnd

    late editor: *RichEditCtrl

    // Whether every line of the resident window is colored since the window last changed, which
    // pairing brackets needs and a jump between brackets would otherwise redo every time.
    lexed: bool

    info:              *Wnd?
    optionsButton:     *IconButton?
    zoomLabel:         *IconButton?
    zoomPercent:       u32 = 100
    swagLexer:         RichEditLexerSwag
    codeLexer:         GenericLexer
    languageName:      String
    languageEvidence:  String
    stream:            File.FileStream
    fileName:          String
    fileSize:          u64
    detectedText:      Viewer.TextProbe
    encoding:          Text.Encoding
    contentStart:      u64
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
    wrapping:          bool
    lineNumbers:       bool
    blanks:            bool
    tabWidth:          s32
    lines:             Viewer.LineCounter
    services:          Viewer.HostServices
    failureReason:     String

    // The whole file counted in the background for the information sheet, apart from the window
    // the editor streams.
    statisticsTask:     Swag.Task'TextStatistics
    statisticsEncoding: Text.Encoding
    statisticsStart:    u64
    statistics:         TextStatistics
    hasStatistics:      bool
    retiring:           bool
}

impl Panel
{
    mtd hasMore()->bool => .stream.isOpen() and .bytesRead < .fileSize

    mtd needsMore()->bool
        => .hasMore() and not .pauseStreaming and Viewer.needsMoreText(.editor, .bytesRead - .residentStart, .residentOffsetY)

    // Extrapolates the full document height from the bytes read so far and places the resident
    // window within it, so the scroll bar spans the whole file while only part of it is loaded.
    mtd updateEstimatedHeight()
    {
        let consumed = .bytesRead - .residentStart
        if not consumed do
            return
        if .bytesRead >= .fileSize and .residentStart == .contentStart
        {
            .editor.setEstimatedDocumentHeight(0)
            return
        }

        let loadedHeight = .editor.loadedDocumentHeight()
        if loadedHeight <= 0
        {
            if .repositioning or .residentStart == .contentStart do
                .residentOffsetY = .fileSize ? .virtualHeight * cast(f32, .residentStart) / cast(f32, .fileSize) : 0
            if .virtualHeight > 0 do
                .editor.setVirtualDocumentRange(.residentOffsetY, .virtualHeight)
            return
        }

        .virtualHeight = Math.max(.virtualHeight, loadedHeight * cast(f32, .fileSize) / cast(f32, consumed), loadedHeight)
        if .repositioning or .residentStart == .contentStart do
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
        if .residentStart == .contentStart do
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
        if .bytesRead - .residentStart >= Viewer.ResidentWindowSize do
            return
        if not .hasMore() do
            return

        let oldPosition = .editor.scrollPosition()
        let chunk       = catch .stream.readTextChunk(StreamChunkSize, .encoding)
        {
            .showReadError(Viewer.failureText(Swag.err))
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
        .lexed = false
        var positionErrorOutcome: Swag.Error
        var position: #decltype(expect .stream.position())
        catch { position = try .stream.position() } as positionErrorOutcome
        let positionError = positionErrorOutcome.value()
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
    //
    // With `caret`, the caret is placed at `offset` and brought into view even without text to
    // highlight; without it, an empty `text` only loads the part of the file around `offset`.
    mtd revealOffset(offset: u64, text: string, caret = false, matchLength = Swag.U64.Max)->bool
    {
        .pendingSeek = false
        return .reloadWindow(offset, .encoding, .contentStart, text, caret, matchLength)
    }

    // Read the replacement before dropping the current stream, so a failed seek or decoder
    // leaves the visible source and its interpretation intact.
    private mtd reloadWindow(offset: u64, encoding: Text.Encoding, contentStart: u64, text: string, caret = false, matchLength = Swag.U64.Max)->bool
    {
        var stream    = catch File.openReadLive(.fileName) { return false }
        let requested = Math.clamp(offset, contentStart, .fileSize)
        let unit      = Text.unitSize(encoding)
        let aligned   = requested - (requested - contentStart) % unit
        let context   = Math.min(aligned - contentStart, RevealContextSize)
        let start     = aligned - (context - context % unit)
        for adjustment in 4
        {
            let actual = Math.min(start + adjustment * unit, aligned)
            catch stream.seek(.Begin, actual) { return false }
            let chunk = catch stream.readTextChunk(Viewer.ResidentWindowSize, encoding) { continue }
            if Utf8.indexOf(chunk.toSlice(), 0'rune) != Swag.U64.Max do
                return false
            let position = catch stream.position() { return false }

            .stopLoading()
            .pendingSeek   = false
            .repositioning = true
            defer .repositioning = false

            let previousHeight = Math.max(.virtualHeight, .editor.scrollableClientRect().height)
            if encoding != .encoding do
                .lines.reset()
            .encoding      = encoding
            .contentStart  = contentStart
            .residentStart = actual
            .bytesRead     = position
            .stream        = #move stream
            .hasText       = not chunk.isEmpty()
            .lexed         = false
            .virtualHeight = previousHeight
            .editor.setText(chunk)
            .numberWindow()
            .updateEstimatedHeight()
            if text.count or caret
            {
                let length = matchLength == Swag.U64.Max ? Viewer.sourceByteCount(text, encoding) : matchLength
                Viewer.highlightSourceMatch(.editor, chunk, requested - actual, length, encoding)
            }

            .scheduleMore()
            return true
        }

        return false
    }

    // Uses whole-file numbering when the start can be counted within the scan budget.
    mtd numberWindow()
    {
        let line = .lineNumbers ? .lines.lineAt(.fileName, .residentStart, .encoding, .contentStart) : 0
        if line do
            .editor.setFirstLineNumber(line)

        var flags = RichEditFlags.ReadOnly
        if line do
            flags.add(.LineNumbers)
        if .wrapping do
            flags.add(.WordWrap)
        if .blanks do
            flags.add(.DrawBlanks)
        .editor.tabSize = .tabWidth
        .editor.setFlags(flags)
    }

    mtd setZoom(percent: u32, remember = true)
    {
        .zoomPercent  = Viewer.clampZoom(percent)
        if remember do
            g_ZoomPercent = .zoomPercent
        .applyMeasure()
        .zoomLabel?.setText(Viewer.zoomText(.zoomPercent))
        .updateEstimatedHeight()
    }

    // Sets the source in the fixed face at the zoom in force, on its lines, in its numbered column.
    mtd applyMeasure()
    {
        let scale = cast(f32, .zoomPercent) / 100
        let base  = .themeMetrics().defaultFixedFontSize
        let size  = cast(u32, Math.max(Math.round(cast(f32, base) * scale), 1))
        let font  = .theme().createDefaultFontFs(size)
        .editor.style.setFont(font, .Regular)
        Viewer.setLinePitch(.editor, font, size, Viewer.CodePitch)
        Viewer.centerColumn(.editor, Viewer.CodeColumn * scale)
    }

    mtd toggleBlanks()
    {
        .blanks  = not .blanks
        g_Blanks = .blanks
        .applyEditorFlag(.DrawBlanks, .blanks)
    }

    mtd toggleWrap()
    {
        .wrapping  = not .wrapping
        g_Wrapping = .wrapping
        .applyEditorFlag(.WordWrap, .wrapping)
    }

    mtd toggleLineNumbers()
    {
        .lineNumbers  = not .lineNumbers
        g_LineNumbers = .lineNumbers
        .numberWindow()
    }

    private mtd applyEditorFlag(flag: RichEditFlags, enabled: bool)
    {
        var flags = .editor.flags
        if enabled do
            flags.add(flag)
        else do
            flags.remove(flag)
        .editor.setFlags(flags)
        .scheduleMore()
    }

    mtd setTabWidth(width: s32)
    {
        if width != 2 and width != 4 and width != 8 do
            return
        .tabWidth       = width
        g_TabWidth      = width
        .editor.tabSize = width
        .editor.setFlags(.editor.flags)
        .scheduleMore()
    }

    // Rereads the code around the current resident window with the selected decoder.
    mtd applyEncoding(encoding: Text.Encoding)
    {
        if encoding == .encoding do
            return

        let contentStart = encoding == .detectedText.encoding ? .detectedText.contentStart : 0
        if not .reloadWindow(.residentStart, encoding, contentStart, "", caret: true)
        {
            .services.showDetails(me, Format.toString(texts().ui_EncodingUnavailable, Viewer.encodingName(encoding)))
            return
        }

        .hasStatistics = false
        if .statisticsTask.isPending() do
            .statisticsTask.cancel()
        else do
            .startStatistics()
        .showLanguageDetails()
        .services.informationChanged(me)
    }

    mtd startStatistics()
    {
        .statisticsEncoding = .encoding
        .statisticsStart    = .contentStart

        let view     = me
        let start    = .statisticsStart
        let encoding = .statisticsEncoding
        .statisticsTask.submit(func|view, start, encoding|()->TextStatistics fail => try TextStatisticsCounter.countFile(view.fileName, start, encoding),
                               .taskNotifier(&.statisticsTask),
                               .Background)
    }

    mtd retire()->bool
    {
        .retiring = true
        .stopLoading()
        .statisticsTask.cancel()
        return not .statisticsTask.isPending()
    }

    // Returns where the delimiter at the caret stands — the one after it, or else the one before
    // it — or an invalid cursor when neither is a parenthesis, a bracket or a brace.
    mtd delimiterAtCaret()->RichEditCursor
    {
        var cp = .editor.cursorFromLogicalPosition(.editor.cursorLogicalLineIndex(), .editor.cursorLogicalCharPos())
        if isDelimiter(.editor.runeAt(cp).char) do
            return cp
        if cp.charPosInLine
        {
            cp.charPosInLine -= 1
            if isDelimiter(.editor.runeAt(cp).char) do
                return cp
        }

        return {Swag.U64.Max, 0}
    }

    // Moves the caret to the delimiter that pairs with the one at the caret, within the text read
    // so far. Only delimiters drawn in the same style count, so one inside a string or a comment
    // pairs with neither code nor another string. Returns false when there is no pair to reach.
    mtd goToMatchingDelimiter()->bool
    {
        let start = .delimiterAtCaret()
        if start.lineIndex == Swag.U64.Max do
            return false

        // Lines are colored as they are painted; the pair may lie on lines never shown.
        if not .lexed
        {
            .editor.lexAll()
            .lexed = true
        }

        let first   = .editor.runeAt(start)
        let partner = delimiterPartner(first.char)
        let forward = first.char == '(' or first.char == '[' or first.char == '{'

        var cp    = start
        var depth = 0'u64
        while true
        {
            if not (forward ? .stepForward(&cp) : .stepBackward(&cp))
            {
                .services.showDetails(me, Format.toString(texts().ui_DelimiterUnavailable, .languageName))
                return false
            }

            let at = .editor.runeAt(cp)
            if at.style != first.style do
                continue
            if at.char == first.char
            {
                depth += 1
            }
            elif at.char == partner
            {
                if not depth
                {
                    .editor.setCursorPos(cp)
                    .editor.ensureCaretIsVisible(center: true)
                    .editor.invalidate()
                    .showLanguageDetails()
                    return true
                }

                depth -= 1
            }
        }

        return false
    }

    // Restores the language summary after a delimiter search temporarily reports its result.
    private mtd showLanguageDetails()
    {
        .services.showDetails(me, .languageDetails())
    }

    mtd languageDetails()->String => Format.toString(texts().ui_Details, .languageName, Viewer.encodingName(.encoding))

    // Moves `cp` to the next rune of the text; the end of a line reads as a line feed.
    private mtd stepForward(cp: *RichEditCursor)->bool
    {
        cp.charPosInLine += 1
        if .editor.runeAt(cp[]).char do
            return true
        cp[] = {cp.lineIndex + 1, 0}
        return .editor.runeAt(cp[]).char != 0
    }

    // Moves `cp` to the previous rune of the text; the end of a line reads as a line feed.
    private mtd stepBackward(cp: *RichEditCursor)->bool
    {
        if cp.charPosInLine
        {
            cp.charPosInLine -= 1
            return true
        }

        if not cp.lineIndex do
            return false
        cp[] = {cp.lineIndex - 1, 0}
        .editor.moveCursorEndLine(cp)
        return true
    }

    // Offers the reading controls and the source-specific commands in the lens.
    mtd describeLens(entries: *Viewer.LensEntries)
    {
        entries.addZoom(.In, .zoomPercent, func|view = me, percent = Viewer.zoomTarget(.In, me.zoomPercent)|() { view.setZoom(percent) })
        entries.addZoom(.Out, .zoomPercent, func|view = me, percent = Viewer.zoomTarget(.Out, me.zoomPercent)|() { view.setZoom(percent) })
        entries.addZoom(.Reset, .zoomPercent, func|view = me, percent = Viewer.zoomTarget(.Reset, me.zoomPercent)|() { view.setZoom(percent) })
        entries.add(appStrings().cmd_ZoomMenu, .ZoomLevels, func|view = me|() { view.showZoomMenu() }, bindId: "scope.code.zoomMenu")

        // A typed language name offers to color the source as that language instead.
        if entries.query.count or entries.results.collectingShortcuts
        {
            entries.add(Format.toString(texts().ui_HighlightAs, "Swag"), .FileCode, func|view = me|() { view.highlightAs(.C, swag: true) }, checked: .languageName == "Swag", bindId: "scope.code.language.Swag")
            for language in SourceLanguage
            {
                let name = displayName(language)
                entries.add(Format.toString(texts().ui_HighlightAs, name), .FileCode, func|view = me, language|() { view.highlightAs(language) }, checked: .languageName == name, bindId: Format.toString("scope.code.language.%", language))
            }
        }

        // The pair is offered only when the caret stands by a bracket, which is when it means something.
        if .delimiterAtCaret().lineIndex != Swag.U64.Max do
            entries.add(texts().ui_MatchingDelimiter, .GoTo, func|view = me|() { discard view.goToMatchingDelimiter() }, defaultKey: {modifiers: .Control, key: .Oem6}, bindId: "scope.code.matchingDelimiter")
        entries.add(texts().ui_Wrap, .Wrap, func|view = me|() { view.toggleWrap() }, checked: .wrapping, defaultKey: {modifiers: .CtrlShift, key: .W}, bindId: "scope.code.wrap")
        entries.add(texts().ui_Numbers, .LineNumbers, func|view = me|() { view.toggleLineNumbers() }, checked: .lineNumbers, bindId: "scope.code.numbers")
        entries.add(texts().ui_Blanks, .Whitespace, func|view = me|() { view.toggleBlanks() }, checked: .blanks, bindId: "scope.code.blanks")

        // The tab stops answer a query, as the languages do, rather than fill the empty lens.
        for width in Viewer.TabWidths where entries.query.count or entries.results.collectingShortcuts do
            entries.add(Viewer.tabWidthRowText(texts().ui_TabWidth, width), .Whitespace, func|view = me, width|() { view.setTabWidth(width) }, checked: .tabWidth == width, bindId: Format.toString("scope.code.tabWidth.%", width))

        PlainText.describeEncodingCommands(me, entries, "scope.code")
        if .optionsButton do
            entries.add(appStrings().cmd_Options, .Settings, func|view = me|() { view.showOptions() }, bindId: "scope.code.options")
    }

    mtd describeOptions(page: *OptionSheet.Page) => PlainText.describeReadingOptions(me, page)

    mtd showOptions()
    {
        let button = .optionsButton
        if not button do
            return
        let sheet = OptionSheet.View.create(button, func|view = me|(page) { view.describeOptions(page) }, owner: me)
        sheet.doModal(button, autoDestroy: true)
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
            .wrapping        = g_Wrapping
            .lineNumbers     = g_LineNumbers
            .blanks          = g_Blanks
            .tabWidth        = g_TabWidth
        }

        result.createEditor()
        if info do
            result.createReadingControls(info)
        result.selectLexer()
        result.hookEvents()
        result.startReading()

        result.applyLayout()
        result.setZoom(g_ZoomPercent)
        result.scheduleMore()
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
                          newPosition.y < .residentOffsetY + viewport.height * Viewer.StreamLookAhead
        let after = .hasMore() and
                    .bytesRead - .residentStart >= Viewer.ResidentWindowSize and
                    newPosition.y > oldPosition.y and
                    newPosition.y + viewport.height * Viewer.StreamLookAhead > residentEnd
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
            .marginLeft  = Viewer.ColumnInset
            .marginRight = Viewer.ColumnInset
            .style.setFont(me.theme().createDefaultFontFs(me.themeMetrics().defaultFixedFontSize), .Regular)
        }
    }

    // Creates the options and zoom controls on the host's line of readings.
    private mtd createReadingControls(info: *Wnd)
    {
        with .optionsButton = Viewer.createInfoOptionsButton(info)
        {
            .sigPressed += func|view = me|(_) { view.showOptions() }
        }

        with .zoomLabel = Viewer.createZoomButton(info, "scope.code.zoom", texts().ui_ZoomMenu)
        {
            .dockStyle  = .Right
            .sigPressed += func|view = me|(_) { view.showZoomMenu() }
        }
    }

    // Colors the editor with the Swag lexer for Swag sources, and with the generic lexer configured
    // for the file's language otherwise.
    private mtd selectLexer()
    {
        let savedName = readLanguageOverride(.fileName)
        if savedName.count
        {
            .languageEvidence = "manual selection"
            if savedName == "Swag"
            {
                .languageName = "Swag"
                .editor.setLexer(&.swagLexer)
                return
            }

            if savedName == "PlainText"
            {
                .languageName = displayName(.PlainText)
                .codeLexer.configure(.PlainText)
                .editor.setLexer(&.codeLexer)
                return
            }

            for language in SourceLanguage where displayName(language) == savedName
            {
                .languageName = displayName(language)
                .codeLexer.configure(language)
                .editor.setLexer(&.codeLexer)
                return
            }
        }

        let extension = Path.lowercaseExtension(.fileName)
        if extension == ".swg" or extension == ".swgs"
        {
            .languageName     = "Swag"
            .languageEvidence = Format.toString(texts().ui_ExtensionEvidence, extension)
            .editor.setLexer(&.swagLexer)
        }
        else
        {
            let language = detectLanguage(.fileName)
            .languageName     = displayName(language)
            .languageEvidence = detectionEvidence(.fileName)
            .codeLexer.configure(language)
            .editor.setLexer(&.codeLexer)
        }
    }

    // Colors the source as `language`, or as Swag with `swag`, whatever its name says, and colors
    // the lines already shown again. The choice holds for this file only.
    internal mtd highlightAs(language: SourceLanguage, swag = false)
    {
        if swag
        {
            .languageName     = "Swag"
            .languageEvidence = "manual selection"
            .editor.setLexer(&.swagLexer)
        }
        else
        {
            .languageName     = displayName(language)
            .languageEvidence = "manual selection"
            .codeLexer.configure(language)
            .editor.setLexer(&.codeLexer)
        }

        .editor.lexAll()
        .lexed = true
        .editor.invalidate()
        writeLanguageOverride(.fileName, language, swag)
        .showLanguageDetails()
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
            let zoom = Viewer.requestedZoom(evt, view.zoomPercent)
            if zoom
            {
                view.setZoom(zoom)
                return true
            }

            switch evt
            {
            case PaintEvent as paintEvt:
                Viewer.paintResidentText(paintEvt, &view.repositioning)
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

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .W and keyEvt.modifiers == .CtrlShift:
                view.toggleWrap()
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .Oem6 and keyEvt.modifiers == .Control:
                discard view.goToMatchingDelimiter()
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
        .stream = catch File.openReadLive(.fileName)
        {
            .showReadError(Viewer.failureText(Swag.err))
            return
        }

        let size = catch .stream.size()
        {
            .showReadError(Viewer.failureText(Swag.err))
            return
        }

        .fileSize = size
        let probe = catch Viewer.probeTextStream(&.stream)
        {
            .showReadError(Viewer.failureText(Swag.err))
            return
        }

        .detectedText  = probe
        .encoding      = probe.encoding
        .contentStart  = probe.contentStart
        .residentStart = .contentStart
        .bytesRead     = .contentStart
        catch .stream.seek(.Begin, .contentStart)
        {
            .showReadError(Viewer.failureText(Swag.err))
            return
        }

        .numberWindow()
        if size <= .contentStart do
            .finishLoading()
        else do
            .loadNextChunk()
    }
}

impl IWnd for Panel
{
    // The count of the whole file arrives: the sheet can give its lines and how they end.
    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if evt.task != &.statisticsTask or not .statisticsTask.isDone() do
            return

        let cancelled = .statisticsTask.isCancelled()
        var countError: Swag.Error
        catch { .statistics = try .statisticsTask.take() } as countError
        if .retiring do
            return
        if cancelled or .statisticsEncoding != .encoding or .statisticsStart != .contentStart
        {
            .startStatistics()
            return
        }

        .hasStatistics = countError.isEmpty()
        .services.informationChanged(me)
    }

    // The column stays centred whatever the width of the window.
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .editor != null do
            Viewer.centerColumn(.editor, Viewer.CodeColumn * cast(f32, .zoomPercent) / 100)
    }

    mtd impl onPaint(_: *PaintEvent)
    {
        if .pendingSeek do
            discard .revealOffset(.pendingSeekOffset, "")
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged
        {
            if .optionsButton do
                .optionsButton.toolTip = appStrings().ui_Options
            if .zoomLabel do
                .zoomLabel.toolTip = texts().ui_ZoomMenu
        }

        // A theme carries its own faces: the fixed face is set again in the new one.
        if evt.kind == .ThemeChanged do
            .applyMeasure()
        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        discard .retire()
        .statisticsTask.wait()
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

// What the information sheet says of a source file.
impl Panel
{
    // Describes the source in the information sheet: its lines once the whole file is counted,
    // then its language, its encoding and how its lines end.
    mtd describeInformation(sheet: *InfoSheet)
    {
        var data: MediaInfoData
        data.add(.Text, group: true)
        let evidence = .languageEvidence == "manual selection" ? texts().ui_ManualDetails : .languageEvidence.toString()
        data.add(.Language, Format.toString("% · %", .languageName, evidence))
        data.add(.Encoding, Viewer.encodingName(.encoding))
        if .hasStatistics do
            data.addTextStatistics(&.statistics, withWords: false)
        data.describe(sheet)
    }
}

func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host.contentParent(), host.fileName(), host.services(), host.createInfoGroup(Viewer.InfoOptionsWidth + Viewer.ZoomSlotWidth))
    if not view.failureReason.isEmpty()
    {
        host.reject(view.failureReason)
        view.destroy()
        return
    }

    host.attachView(view)
    host.setDetails(view.languageDetails())

    with var search: Viewer.SearchApi
    {
        .fileEncoding = func|view|()->Text.Encoding => view.encoding
        .revealMatch = func|view|(match, text)->bool => view.revealOffset(match.offset, text, caret: true, matchLength: match.length)
        .matchBounds = func|view|(_, bounds)->bool => Viewer.richEditMatchBounds(view.editor, bounds)
        .clear       = func|view|() => Viewer.clearRichEditMatch(view.editor)
    }

    host.setSearch(search)
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })
    host.setInformation(func|view|(sheet) { view.describeInformation(sheet) })

    view.startStatistics()
    host.setLifecycle({isLoading: func|view|()->bool => view.loadTimer != null,
                       retire: func|view|()->bool => view.retire()})
}
