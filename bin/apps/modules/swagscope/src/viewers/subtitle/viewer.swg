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

// One line of a cue's words as the list sets it: a byte range of the words, and the width it takes.
struct CueLine
{
    start: u64
    end:   u64
}

// Where one cue stands in the reading list, at the width the list was last laid out at.
struct CueRow
{
    top:    f32
    height: f32
    lines:  Array'CueLine
}

// The search occurrence the list shows, in the words of one cue.
struct CueMatch
{
    cue:    u64 = Swag.U64.Max
    offset: u64
    length: u64
}

// Formats a cue time as HH:MM:SS,mmm, the way a subtitle file writes it.
private func clockText(seconds: f64)->String
{
    let millis   = cast(u64, Math.max(Math.round(seconds * 1_000), 0.0))
    let hours    = millis / 3_600_000
    let minutes  = millis / 60_000 % 60
    let rest     = millis / 1_000 % 60
    let fraction = millis % 1_000
    return Format.toString("%{02}:%{02}:%{02},%{03}", hours, minutes, rest, fraction)
}

// Formats a time as HH:MM:SS, the reading at the foot of the list.
private func secondsText(seconds: f64)->String
{
    let whole = cast(u64, Math.max(Math.floor(seconds), 0.0))
    return Format.toString("%{02}:%{02}:%{02}", whole / 3_600, whole / 60 % 60, whole % 60)
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

/*
The cues of a subtitle file as a reading list, after `scope.subtitle`.

The name of the file heads a measured column, with a mono line under it: how many cues, how long,
in which syntax. Each cue is a row: its number, its time range in mono, and its words beside them,
wrapped to the column. The current cue stands on the selection ground. The list scrolls under the
strip; only the rows in view are set.
*/
struct CueSheet
{
    using wnd: Wnd

    late panel: *Panel

    rows:        Array'CueRow
    layoutWidth: f32
    headHeight:  f32
}

impl CueSheet
{
    const ColumnWidth  = 800'f32     // Width of the reading column.
    const Gutter       = 32'f32      // Least air between the column and an edge of the window.
    const HeadAir      = 32'f32      // Air between the strip and the name of the file.
    const TitleSize    = 28'u32      // Size of the name of the file.
    const IdentityGap  = 8'f32       // Air between the name and its mono line.
    const RowsGap      = 28'f32      // Air between the mono line and the first row.
    const RowPadding   = 16'f32      // Air above and below the words of a row.
    const NumberX      = 16'f32      // Where the number of a cue starts, in the column.
    const TimesX       = 64'f32      // Where its time range starts.
    const WordsX       = 274'f32     // Where its words start.
    const WordsRight   = 24'f32      // Air the words keep before the end of the column.
    const WordsSize    = 15'u32      // Size of the words.
    const WordsLeading = 24'f32      // Height of one line of words.
    const TimesHeight  = 32'f32      // Height of the two lines of a time range.
    const BottomRoom   = 120'f32     // Room kept under the last row for the rhythm and the readings.

    mtd wordsFont()->*Font => .theme().createDefaultFont(WordsSize)
    mtd monoFont()->*Font  => .theme().createDefaultFontFs(.themeMetrics().defaultFixedFontSize)
    mtd titleFont()->*Font => .theme().createDefaultFont(TitleSize, .Bold)

    mtd column()->Math.Rectangle
    {
        let room  = .clientRect()
        let width = Math.min(ColumnWidth, Math.max(0, room.width - 2 * Gutter))
        return Math.Rectangle{Math.round((room.width - width) * 0.5), 0, width, room.height}
    }

    // Splits the words of cue `index` into the lines they take at `width`, breaking between words
    // and at the line breaks the cue carries.
    mtd wrapCue(index: u64, width: f32, result: *Array'CueLine)
    {
        let font  = .wordsFont()
        let words = .panel.track!.cueContent(index)
        result.clear()

        var lineStart = 0'u64
        var lastBreak = Swag.U64.Max
        var scan      = 0'u64
        while scan <= words.count
        {
            let atEnd = scan == words.count
            if atEnd or words[scan] == '\n'
            {
                result.add(CueLine{lineStart, scan})
                lineStart = scan + 1
                lastBreak = Swag.U64.Max
                scan      += 1
                continue
            }

            if words[scan] == ' ' do
                lastBreak = scan
            if lastBreak != Swag.U64.Max and Painter.measureString(words[lineStart until scan + 1], font).width > width
            {
                result.add(CueLine{lineStart, lastBreak})
                lineStart = lastBreak + 1
                lastBreak = Swag.U64.Max
            }

            scan += 1
        }
    }

    // Measures every row at the width of the view, and tells the scroll window how tall the list is.
    mtd relayout()
    {
        // The scroll window lays its view out as soon as it makes it, before the list is joined to its panel.
        if .panel == null do
            return

        let column = .column()
        let words  = Math.max(1, column.width - WordsX - WordsRight)
        .layoutWidth = .clientRect().width
        .headHeight  = .panel.stripInset() + HeadAir + .titleFont().height + IdentityGap + .monoFont().height + RowsGap

        var y = .headHeight
        .rows.resize(.panel.track!.cueCount())
        for &row, index in .rows
        {
            .wrapCue(index, words, &row.lines)
            row.top    = y
            row.height = Math.max(TimesHeight, cast(f32, row.lines.count) * WordsLeading) + 2 * RowPadding
            y          += row.height
        }

        .panel.scroll.setScrollSize(0, y + BottomRoom)
        .invalidate()
    }

    // Returns the band of row `index` in the coordinates of the list, across the column.
    mtd rowRect(index: u64)->Math.Rectangle
    {
        let column = .column()
        let row    = &.rows[index]
        return Math.Rectangle{column.x, row.top, column.width, row.height}
    }

    // Returns the cue whose row holds the point `pt` of the list, or `Swag.U64.Max`.
    mtd cueAt(pt: Math.Point)->u64
    {
        for &row, index in .rows where pt.y >= row.top and pt.y < row.top + row.height do
            return index
        return Swag.U64.Max
    }

    // Scrolls the least that brings row `index` into view, clear of the strip.
    mtd reveal(index: u64)
    {
        if index >= .rows.count do
            return
        let row    = &.rows[index]
        let top    = .scrollPos.y + .panel.stripInset()
        let bottom = .scrollPos.y + .clientRect().height - BottomRoom
        if row.top < top do
            .panel.scroll.setScrollPos(0, row.top - .panel.stripInset())
        elif row.top + row.height > bottom do
            .panel.scroll.setScrollPos(0, row.top + row.height - .clientRect().height + BottomRoom)
    }

    // Returns where the match is set, in the coordinates of the list.
    mtd matchRect(match: CueMatch)->Math.Rectangle
    {
        var result: #returntype
        if match.cue >= .rows.count do
            return result

        let font   = .wordsFont()
        let column = .column()
        let words  = .panel.track!.cueContent(match.cue)
        let row    = &.rows[match.cue]
        for line, index in row.lines where match.offset >= line.start and match.offset <= line.end
        {
            let x     = column.x + WordsX + Painter.measureString(words[line.start until match.offset], font).width
            let end   = Math.min(match.offset + match.length, line.end)
            let width = Painter.measureString(words[match.offset until end], font).width
            let top   = row.top + RowPadding + cast(f32, index) * WordsLeading
            return Math.Rectangle{x, top, width, WordsLeading}
        }

        return result
    }

    // Writes the name of the file and its mono line at the head of the column.
    mtd paintHead(painter: *Painter, column: Math.Rectangle)
    {
        let colors = .themeColors()
        let title  = .titleFont()
        let mono   = .monoFont()
        var y      = .panel.stripInset() + HeadAir
        painter.drawString(column.x, y, Path.fileName(.panel.fileName) orelse .panel.fileName, title, colors.text)
        y += title.height + IdentityGap
        painter.drawString(column.x, y, .panel.identity(), mono, colors.faintText)
    }

    // Writes row `index`: the selection ground of the current cue, its number, its time range and
    // its words.
    mtd paintRow(painter: *Painter, index: u64)
    {
        let colors  = .themeColors()
        let metrics = .themeMetrics()
        let mono    = .monoFont()
        let words   = .wordsFont()
        let band    = .rowRect(index)
        let current = index == .panel.currentCue
        if current
        {
            painter.setParams(.Antialiased)
            painter.fillRoundRect(band, metrics.corner_Control, metrics.corner_Control, colors.selection)
        }

        let top = band.y + RowPadding
        painter.drawString(band.x + NumberX, top, Format.toString("%", index + 1), mono, colors.faintText)

        let track = unwrap .panel.track
        painter.drawString(band.x + TimesX, top, clockText(track.cueStartTime(index)), mono, current ? colors.text : colors.softText)
        let ending = Format.toString("→ %", clockText(track.cueEndTime(index)))
        painter.drawString(band.x + TimesX, top + TimesHeight * 0.5, ending, mono, colors.faintText)

        let text = track.cueContent(index)
        for line, lineIndex in .rows[index].lines
        {
            let y = top + cast(f32, lineIndex) * WordsLeading + (WordsLeading - words.height) * 0.5
            painter.drawString(band.x + WordsX, y, text[line.start until line.end], words, colors.text)
        }
    }
}

impl IWnd for CueSheet
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        if .rows.count != .panel.track!.cueCount() or .layoutWidth != .clientRect().width do
            .relayout()

        let painter = evt.paintContext.painter
        let column  = .column()
        .paintHead(painter, column)

        // The list is set in document coordinates; only the rows in view are written.
        var band = .clientRect()
        band.offset(.scrollPos)
        for &row, index in .rows where row.top + row.height >= band.y and row.top <= band.bottom() do
            .paintRow(painter, index)
    }

    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        .relayout()
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .ThemeChanged and .rows.count do
            .relayout()
        evt.accepted = false
    }

    // A click makes its cue the current one.
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind != .Pressed or evt.button != .Left
        {
            evt.accepted = false
            return
        }

        .setFocus()
        let cue = .cueAt(.surfaceToLocal(evt.surfacePos) + .scrollPos)
        if cue != Swag.U64.Max do
            .panel.setCurrentCue(cue)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        let panel = .panel
        switch
        {
        case evt.modifiers == .Control and (evt.key == .PageUp or evt.key == .Up):     discard panel.navigateCue(false)
        case evt.modifiers == .Control and (evt.key == .PageDown or evt.key == .Down): discard panel.navigateCue(true)
        case evt.modifiers == .Control and evt.key == .Home:                           discard panel.navigateCueBoundary(false)
        case evt.modifiers == .Control and evt.key == .End:                            discard panel.navigateCueBoundary(true)
        case evt.modifiers == .Control and evt.key == .C:                              panel.copyCurrentCue()
        case evt.modifiers == .None and evt.key == .Up:                                discard panel.navigateCue(false)
        case evt.modifiers == .None and evt.key == .Down:                              discard panel.navigateCue(true)
        case evt.modifiers == .None and evt.key == .Home:                              discard panel.navigateCueBoundary(false)
        case evt.modifiers == .None and evt.key == .End:                               discard panel.navigateCueBoundary(true)
        default: evt.accepted = false
        }
    }
}

/*
The rhythm of the track under the list: each cue a short rule as long as it lasts, the current
one marked with the caret.

It shows the cues of the minute around the current cue, so the reader sees where the dialogue
thickens and where it rests.
*/
struct CueRhythm
{
    using wnd: Wnd

    late panel: *Panel
}

impl CueRhythm
{
    const Height    = 56'f32       // Height of the strip the rhythm stands in.
    const Span      = 60'f64       // Seconds the strip shows at once.
    const Lead      = 0.35'f64     // Share of them that comes before the current cue.
    const RuleSize  = 4'f32        // Thickness of the rule of a cue.
    const RuleGap   = 4'f32        // Least air between two rules.
    const MarkWidth = 2'f32        // Width of the mark of the current cue.
    const MarkSize  = 16'f32       // Height of that mark.
}

impl IWnd for CueRhythm
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let panel = .panel
        let track = unwrap panel.track
        if not track.cueCount() do
            return

        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let room    = .clientRect()
        let width   = Math.min(CueSheet.ColumnWidth, Math.max(0, room.width - 2 * CueSheet.Gutter)) - 2 * CueSheet.NumberX
        let left    = Math.round((room.width - width) * 0.5)
        let centerY = room.vertCenter()

        // The minute shown leads to the current cue and goes on past it, from the first cue at most.
        let focus = panel.currentCue == Swag.U64.Max ? 0 : panel.currentCue
        let start = Math.max(track.cueStartTime(0), track.cueStartTime(focus) - Span * Lead)
        let scale = cast(f64, width) / Span

        painter.setParams(.Antialiased)
        for index in track.cueCount()
        {
            let first = track.cueStartTime(index)
            let last  = track.cueEndTime(index)
            if last < start or first > start + Span do
                continue

            let x0 = left + cast(f32, (Math.max(first, start) - start) * scale)
            let x1 = left + cast(f32, (Math.min(last, start + Span) - start) * scale) - RuleGap
            if x1 <= x0 do
                continue
            painter.fillRoundRect(Math.Rectangle{x0, centerY - RuleSize * 0.5, x1 - x0, RuleSize}, RuleSize * 0.5, RuleSize * 0.5, colors.strongLine)
        }

        if panel.currentCue != Swag.U64.Max
        {
            let x = left + cast(f32, (track.cueStartTime(panel.currentCue) - start) * scale)
            painter.fillRect(Math.Rectangle{Math.round(x), centerY - MarkSize * 0.5, MarkWidth, MarkSize}, colors.caret)
        }
    }
}

// Presents a timed subtitle file as a reading list of its cues.
struct Panel
{
    using wnd: Wnd

    late
    {
        scroll:     *ScrollWnd
        sheet:      *CueSheet
        rhythm:     *CueRhythm
        timeButton: *IconButton
    }

    track:      *Subtitle.Track?
    fileName:   String
    services:   Viewer.HostServices
    currentCue: u64 = Swag.U64.Max
    duration:   f64
    match:      CueMatch
}

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

impl Panel
{
    // Returns the mono line under the name: how many cues, how long, in which syntax.
    mtd identity()->String => Format.toString("% · % · %", cueCountText(.track!.cueCount()), Viewer.durationText(.duration), formatText(.track.sourceFormat()))

    // Returns what the readings say on the left: the current cue among all, or how many there are.
    mtd cuePosition()->String
    {
        if .currentCue == Swag.U64.Max do
            return cueCountText(.track!.cueCount())
        return Format.toString(texts().ui_CuePosition, .currentCue + 1, .track!.cueCount())
    }

    mtd retranslate()
    {
        .timeButton.toolTip = texts().ui_GoToTime
        .refreshReadings()
        .sheet.invalidate()
    }

    // Says the current cue on the readings at the foot: its rank on the left, its time on the right.
    mtd refreshReadings()
    {
        .services.showDetails(me, .cuePosition())
        let time = .currentCue == Swag.U64.Max ? Viewer.durationText(.duration) : secondsText(.track!.cueStartTime(.currentCue))
        .timeButton.setQuietText(time)
        .services.chromeChanged(me)
    }

    // Makes cue `index` the current one, brings its row into view, and says it at the foot.
    mtd setCurrentCue(index: u64)
    {
        if .currentCue == index do
            return
        .currentCue = index
        .sheet.reveal(index)
        .refreshReadings()
        .sheet.invalidate()
        .rhythm.invalidate()
    }

    mtd copyCurrentCue()
    {
        if .currentCue != Swag.U64.Max do
            Clipboard.setString(.track!.cueContent(.currentCue))
    }

    mtd collectMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        for index in .track!.cueCount() do
            Viewer.collectTextMatches(.track.cueContent(index), text, options, index, 0, 0, result)
    }

    mtd revealMatch(match: Viewer.SearchMatch, _: string)->bool
    {
        if match.major >= .track!.cueCount() do
            return false
        .match = CueMatch{match.major, match.offset, match.length}
        .setCurrentCue(match.major)
        .sheet.reveal(match.major)
        .sheet.invalidate()
        return true
    }

    // Reports where the revealed match is written, in surface coordinates.
    mtd searchBounds(result: *Math.Rectangle)->bool
    {
        var rect = .sheet.matchRect(.match)
        if rect.isEmpty() do
            return false
        rect.offset(-.sheet.scrollPos.x, -.sheet.scrollPos.y)
        let origin = .sheet.localToSurface(Math.Point{})
        rect.offset(origin.x, origin.y)
        result[] = rect
        return true
    }

    mtd clearSearch()
    {
        .match = {}
        .sheet.invalidate()
    }

    mtd revealCue(index: u64)->bool
    {
        if index >= .track!.cueCount() do
            return false
        .setCurrentCue(index)
        .sheet.setFocus()
        return true
    }

    // Moves to an adjacent cue. With no current cue, begin at the first cue in either direction.
    mtd navigateCue(forward: bool)->bool
    {
        let count = .track!.cueCount()
        if not count do
            return false
        if .currentCue == Swag.U64.Max do
            return .revealCue(0)
        if forward and .currentCue + 1 < count do
            discard .revealCue(.currentCue + 1)
        elif not forward and .currentCue do
            discard .revealCue(.currentCue - 1)
        return true
    }

    mtd navigateCueBoundary(last: bool)->bool
    {
        let count = .track!.cueCount()
        if not count do
            return false
        return .revealCue(last ? count - 1 : 0)
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
        let count = .track!.cueCount()
        if not count do
            return
        let message = Format.toString(texts().ui_CueRange, count)
        let dialog  = EditDlg.createSingleLine(unwrap .surface, {title: texts().ui_GoToCue, message: message, text: "1"})
        if dialog.doModal() != Dialog.BtnOk do
            return
        var parseErrorOutcome: Swag.Error
        var cue: #decltype(expect StrConv.toU64(dialog.text()))
        catch { cue = try StrConv.toU64(dialog.text()) } as parseErrorOutcome
        let parseError = parseErrorOutcome.value()
        if parseError == null and cue and cue <= count do
            discard .revealCue(cue - 1)
    }

    // Asks for a time and reveals the first cue that has not ended by then, or the last cue.
    mtd promptGoToTime()
    {
        let count = .track!.cueCount()
        if not count do
            return
        let dialog = EditDlg.createSingleLine(unwrap .surface, {title: texts().ui_GoToTime, message: texts().ui_TimeRange, text: "00:00:00"})
        if dialog.doModal() != Dialog.BtnOk do
            return

        var seconds: f64
        if not timeSeconds(dialog.text(), &seconds) do
            return
        for index in count where .track.cueEndTime(index) >= seconds
        {
            discard .revealCue(index)
            return
        }

        discard .revealCue(count - 1)
    }

    // Builds the reading list, the rhythm under it, and the time at the foot that asks for a time
    // to reach. Fails when the track cannot be loaded.
    func create(host: Viewer.Host)->*Panel fail
    {
        with let result = Wnd.create'Panel(host.contentParent(), "scope.subtitle")
        {
            .backgroundStyle = .View
            .track           = try Subtitle.Track.loadOwned(host.fileName())
            .fileName        = host.fileName()
            .services        = host.services()
            .duration        = .track.durationInSeconds()
        }

        with result.rhythm = Wnd.create'CueRhythm(result, {0, 0, 0, CueRhythm.Height})
        {
            .panel           = result
            .dockStyle       = .Bottom
            .backgroundStyle = .Transparent
        }

        with result.scroll = Wnd.create'ScrollWnd(result, "scope.subtitle.scroll", {})
        {
            .dockStyle = .Center
            .updateFlags(.TransparentBars | .DisableHorizontal)
        }

        with result.sheet = result.scroll.createView'CueSheet()
        {
            .panel           = result
            .backgroundStyle = .Transparent
            .focusPolicy     = .Tab
            .wndFlags        |= WndFlags.NoFocusRing
        }

        let info = host.createInfoGroup(160)
        with result.timeButton = IconButton.createQuiet(info, "scope.subtitle.time", menu: false)
        {
            .dockStyle = .Right
            .toolTip   = texts().ui_GoToTime
            .style.setFont(result.theme().createDefaultFontFs(12), .Regular)
            .sigPressed += func|view = result|(_) { view.promptGoToTime() }
        }

        result.timeButton.setQuietText(Viewer.durationText(result.duration))
        result.applyLayout()
        result.sheet.relayout()
        result.setInitialFocus(result.sheet)
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
        host.setDetails(cueCountText(view.track!.cueCount()))

        host.setSearch(Viewer.searchApi(view))
        host.setLensSource(func|view|(entries) { view.describeLens(entries) })
    }
    {
        host.reject(Viewer.failureText(Swag.err))
    }
}
