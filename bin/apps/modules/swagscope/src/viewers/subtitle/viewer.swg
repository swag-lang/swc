#global internal
#global namespace Viewers.Captions

using Core, Core.Errors, Pixel, Gui, Video

// Describes the subtitle viewer to the host.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "subtitle"
        .staticName   = "Subtitles"
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Subtitle)
        .create       = &createViewer
        .textual      = true
        .smokeFixture = "viewer.srt"
        .addSelectors(".srt;.vtt;.ass;.ssa;.lrc;.sub")
    }

    return result
}

// Locates the text of one cue inside the transcript.
struct ViewerCue
{
    textOffset: u64
    textLength: u64
    firstLine:  u64
    lastLine:   u64
}

// Sets the time range of each cue back from its words, so the transcript reads as dialogue with
// its timing beside it rather than as a column of numbers.
struct TranscriptLexer
{
    enum Style: RichEditStyleRef
    {
        Default
        Time
    }
}

impl IRichEditLexer for TranscriptLexer
{
    mtd impl setup(_: *RichEditCtrl) {}

    mtd impl setupTheme(ed: *RichEditCtrl)
    {
        var time = ed.themeColors().richEdit_TextSpecial
        time.ensureContrast(ed.themeColors().richEdit_Bk, 4.5)
        ed.styles[cast(u64, Style.Time)].colFg = time
    }

    mtd impl insertRune(_: *RichEditCtrl, _: rune)->bool => false

    // A time line is the one shape the transcript builder writes: `HH:MM:SS.mmm  →  HH:MM:SS.mmm`.
    mtd impl compute(_: *RichEditLine?, line: *RichEditLine, _: *RichEditLine?)
    {
        let isTime = line.length() >= 29 and
                     line.runeAt(2) == ':' and
                     line.runeAt(5) == ':' and
                     line.runeAt(8) == '.' and
                     line.runeAt(14) == '→'
        let style = cast(RichEditStyleRef, isTime ? Style.Time : Style.Default)
        for index in line.length() do
            line.setStyleAt(index, style)
    }
}

// Presents a timed subtitle file as a searchable transcript of its cues.
struct Panel
{
    using wnd: Wnd

    late
    {
        editor:         *RichEditCtrl
        cueButton:      *IconButton
        durationButton: *IconButton
    }

    track:      *Subtitle.Track?
    lexer:      TranscriptLexer
    transcript: String
    cueText:    Array'ViewerCue
    currentCue: u64 = Swag.U64.Max
    duration:   f64
}

// Formats a cue time as HH:MM:SS.mmm, a form the go-to-time dialog also accepts.
private func clockText(seconds: f64)->String
{
    let millis   = cast(u64, Math.max(Math.round(seconds * 1_000), 0.0))
    let hours    = millis / 3_600_000
    let minutes  = millis / 60_000 % 60
    let rest     = millis / 1_000 % 60
    let fraction = millis % 1_000
    return Format.toString("%{02}:%{02}:%{02}.%{03}", hours, minutes, rest, fraction)
}

// Returns the established name of a subtitle syntax.
private func formatText(format: Subtitle.Format)->string
{
    switch #complete format
    {
    case .SubRip:          return "SubRip"
    case .WebVtt:          return "WebVTT"
    case .SubStationAlpha: return "ASS/SSA"
    case .Lyric:           return "LRC"
    case .MicroDvd:        return "MicroDVD"
    case .MatroskaText:    return "Matroska text"
    }
}

// Returns the cue count with the noun that count calls for.
private func cueCountText(count: u64)->String => count == 1 ? texts().ui_OneCue : Format.toString(texts().ui_Cues, count)

impl IWnd for Panel
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        if .track do
            Subtitle.Track.destroy(.track)
        .track = null
    }
}

private impl Panel
{
    mtd retranslate()
    {
        .refreshCueButton()
        .cueButton.toolTip      = texts().ui_CueNavigationTip
        .durationButton.toolTip = texts().ui_GoToTime
    }

    mtd refreshCueButton()
    {
        let label = .currentCue == Swag.U64.Max
                    ? cueCountText(.track!.cueCount())
                    : Format.toString(texts().ui_CuePosition, .currentCue + 1, .cueText.count)
        .cueButton.setText(label)
    }

    mtd setCurrentCue(index: u64)
    {
        if .currentCue == index do
            return
        .currentCue = index
        .refreshCueButton()
    }

    // Tracks the cue containing the editor caret, including wrapped display lines.
    internal mtd syncCurrentCue()
    {
        if .cueText.isEmpty() do
            return
        let line = .editor.cursorLogicalLineIndex()
        for index in .cueText.count where line <= .cueText[index].lastLine
        {
            .setCurrentCue(index)
            return
        }

        .setCurrentCue(.cueText.count - 1)
    }

    // Builds the transcript, each cue as its time range followed by its content, and records where
    // each cue's content sits so it can be revealed.
    mtd buildTranscript()
    {
        var line = 0'u64
        for index in .track!.cueCount()
        {
            if not .transcript.isEmpty()
            {
                .transcript += "\n\n"
                line        += 2
            }

            let firstLine = line
            .transcript += clockText(.track.cueStartTime(index))
            .transcript += "  →  "
            .transcript += clockText(.track.cueEndTime(index))
            .transcript += "\n"
            line        += 1
            let offset  = .transcript.length
            let content = .track.cueContent(index)
            .transcript += content
            for character in content where character == '\n' do
                line += 1
            .cueText.add(ViewerCue{offset, content.count, firstLine, line})
        }
    }

    internal mtd collectMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        for index in .track!.cueCount() do
            Viewer.collectTextMatches(.track.cueContent(index), text, options, index, 0, 0, result)
    }

    internal mtd revealMatch(match: Viewer.SearchMatch, _: string)->bool
    {
        if match.major >= .cueText.count do
            return false
        .setCurrentCue(match.major)
        let cue = .cueText[match.major]
        Viewer.highlightRichEditMatch(.editor, .transcript, cue.textOffset + match.offset, match.length)
        return true
    }

    internal mtd searchBounds(result: *Math.Rectangle)->bool => Viewer.richEditMatchBounds(.editor, result)
    internal mtd clearSearch() => Viewer.clearRichEditMatch(.editor)

    internal mtd revealCue(index: u64)->bool
    {
        if index >= .cueText.count do
            return false
        .setCurrentCue(index)
        let cue = .cueText[index]
        Viewer.highlightRichEditMatch(.editor, .transcript, cue.textOffset, cue.textLength)
        .editor.setFocus()
        return true
    }

    // Moves to an adjacent cue. With no current cue, begin at the first cue in either direction.
    mtd navigateCue(forward: bool)->bool
    {
        if .cueText.isEmpty() do
            return false
        if .currentCue == Swag.U64.Max do
            return .revealCue(0)
        if forward
        {
            if .currentCue + 1 < .cueText.count do
                discard .revealCue(.currentCue + 1)
        }
        elif .currentCue
        {
            discard .revealCue(.currentCue - 1)
        }

        return true
    }

    mtd navigateCueBoundary(last: bool)->bool
    {
        if .cueText.isEmpty() do
            return false
        return .revealCue(last ? .cueText.count - 1 : 0)
    }

    // Gives the lens the ways through the cues and the time of the track.
    mtd describeLens(entries: *Viewer.LensEntries)
    {
        let strings = texts()
        entries.add(strings.ui_GoToCue, func|view = me|() { view.promptGoToCue() })
        entries.add(strings.ui_GoToTime, func|view = me|() { view.promptGoToTime() })
        entries.add(strings.ui_PreviousCue, func|view = me|() { discard view.navigateCue(false) }, shortcut: Input.formatKeyShortcut(.Control, .PageUp))
        entries.add(strings.ui_NextCue, func|view = me|() { discard view.navigateCue(true) }, shortcut: Input.formatKeyShortcut(.Control, .PageDown))
        entries.add(strings.ui_FirstCue, func|view = me|() { discard view.navigateCueBoundary(false) }, shortcut: Input.formatKeyShortcut(.Control, .Home))
        entries.add(strings.ui_LastCue, func|view = me|() { discard view.navigateCueBoundary(true) }, shortcut: Input.formatKeyShortcut(.Control, .End))
    }

    mtd promptGoToCue()
    {
        if .cueText.isEmpty() do
            return
        let message = Format.toString(texts().ui_CueRange, .cueText.count)
        let dialog  = EditDlg.createSingleLine(unwrap .surface, {title: texts().ui_GoToCue, message: message, text: "1"})
        if dialog.doModal() != Dialog.BtnOk do
            return
        var parseErrorOutcome: Swag.Error
        var cue: #decltype(expect StrConv.toU64(dialog.text()))
        catch { cue = try StrConv.toU64(dialog.text()) } as parseErrorOutcome
        let parseError = parseErrorOutcome.value()
        if parseError == null and cue and cue <= .cueText.count do
            discard .revealCue(cue - 1)
    }

    // Asks for a time and reveals the first cue that has not ended by then, or the last cue.
    mtd promptGoToTime()
    {
        if .cueText.isEmpty() do
            return
        let dialog = EditDlg.createSingleLine(unwrap .surface, {title: texts().ui_GoToTime, message: texts().ui_TimeRange, text: "00:00:00.000"})
        if dialog.doModal() != Dialog.BtnOk do
            return

        var seconds: f64
        if not timeSeconds(dialog.text(), &seconds) do
            return
        for index in .track!.cueCount() where .track.cueEndTime(index) >= seconds
        {
            discard .revealCue(index)
            return
        }

        discard .revealCue(.cueText.count - 1)
    }

    // Builds the subtitle panel: a read-only transcript of the cues, with duration and cue count
    // buttons that prompt for a time or a cue to reach. Fails when the track cannot be loaded.
    func create(host: Viewer.Host)->*Panel fail
    {
        with let result = Wnd.create'Panel(host.contentParent(), "scope.subtitle")
        {
            .backgroundStyle = .View
            .track           = try Subtitle.Track.loadOwned(host.fileName())
            .duration        = .track.durationInSeconds()
            .buildTranscript()
        }

        let info = host.createInfoGroup(220)
        with result.durationButton = IconButton.create(info, {}, {0, 0, 104, 32}, "scope.subtitle.time", .CenterContent)
        {
            .dockStyle = .Right
            .margin.x  = 8
            .toolTip   = texts().ui_GoToTime
            .setText(Viewer.durationText(result.duration))
            .setForm(.Rectangle)
            .sigPressed += func|view = result|(_) { view.promptGoToTime() }
        }

        with result.cueButton = IconButton.create(info, {}, {0, 0, 108, 32}, "scope.subtitle.cue", .CenterContent)
        {
            .dockStyle = .Right
            .toolTip   = texts().ui_CueNavigationTip
            .setText(cueCountText(result.track!.cueCount()))
            .setForm(.Rectangle)
            .sigPressed += func|view = result|(_) { view.promptGoToCue() }
        }

        with result.editor = RichEditCtrl.create(result)
        {
            .dockStyle   = .Center
            .marginLeft  = 20
            .marginRight = 20
            .lineSpacing = 4
            .style.setFont(result.theme().createDefaultFont(result.themeMetrics().defaultFixedFontSize), .Regular)
            .setFlags(.ReadOnly | .WordWrap)
            .setLexer(&result.lexer)
            .setText(result.transcript)
        }

        result.hookOnChildEvent = func|view = result|(_, evt)
        {
            switch evt
            {
            case KeyEvent as key where key.kind == .Pressed and key.modifiers == .Control and key.key == .PageUp:
                return view.navigateCue(false)

            case KeyEvent as key where key.kind == .Pressed and key.modifiers == .Control and key.key == .PageDown:
                return view.navigateCue(true)

            case KeyEvent as key where key.kind == .Pressed and key.modifiers == .Control and key.key == .Home:
                return view.navigateCueBoundary(false)

            case KeyEvent as key where key.kind == .Pressed and key.modifiers == .Control and key.key == .End:
                return view.navigateCueBoundary(true)

            case KeyEvent as key:
                key.target!.processEvent(evt)
                view.syncCurrentCue()
                return key.accepted

            case MouseEvent as mouse:
                mouse.target!.processEvent(evt)
                view.syncCurrentCue()
                return mouse.accepted

            default:
                return false
            }
        }

        result.applyLayout()
        result.setInitialFocus(result.editor)
        return result
    }
}

// Reports whether `text` is a time in one of the three forms the go-to-time dialog advertises, and stores its seconds in `result`.
//
// Once a colon is present, every field after the first is a base-60 component rather than an
// unrestricted decimal number. `result` is left untouched when `text` is rejected.
func timeSeconds(text: string, result: *f64)->bool
{
    let parts = Tokenize.split(text, ':'u8, removeEmpty: false)
    if parts.isEmpty() or parts.count > 3 do
        return false

    var seconds = 0'f64
    for part, index in parts
    {
        if not part.count do
            return false
        var parseErrorOutcome: Swag.Error
        var value: #decltype(expect StrConv.toF64(part))
        catch { value = try StrConv.toF64(part) } as parseErrorOutcome
        let parseError = parseErrorOutcome.value()
        if parseError != null or value < 0 or not Math.isFinite(value) do
            return false
        if index and value >= 60 do
            return false
        if index + 1 < parts.count and value != Math.floor(value) do
            return false
        seconds = seconds * 60 + value
        if not Math.isFinite(seconds) do
            return false
    }

    result[] = seconds
    return true
}

// Creates the integrated timed-subtitle document view and connects it to the host.
func createViewer(host: Viewer.Host)
{
    catch
    {
        let view = try Panel.create(host)
        host.attachView(view)
        host.setDetails(formatText(view.track!.sourceFormat()))

        host.setSearch(Viewer.searchApi(view))
        host.setLensSource(func|view|(entries) { view.describeLens(entries) })
    }
    {
        host.reject(Viewer.failureText(Swag.err))
    }
}
