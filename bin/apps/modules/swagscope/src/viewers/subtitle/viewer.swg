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

// One line of a cue's words as the list sets it: a byte range of the words.
struct CueLine
{
    start: u64
    end:   u64
}

// Where one cue stands in the reading list, at the width the list was last laid out at.
struct CueRow
{
    top:     f32
    height:  f32
    visible: bool
    lines:   Array'CueLine
}

// The search occurrence the list shows, in the words of one cue.
struct CueMatch
{
    cue:    u64 = Swag.U64.Max
    offset: u64
    length: u64
}

// A connected run of subtitle cues whose time ranges overlap.
struct CueOverlapGroup
{
    start:    f64
    end:      f64
    firstCue: u64
    endCue:   u64     // Exclusive cue index.
}

// Collects overlap groups in one pass; cues in a group are connected by strict time overlap.
private func collectCueOverlapGroups(track: const *Subtitle.Track)->Array'CueOverlapGroup
{
    var result: Array'CueOverlapGroup
    var group:  CueOverlapGroup
    var active = false
    for index in track.cueCount()
    {
        let start = track.cueStartTime(index)
        let end   = track.cueEndTime(index)
        if active and start < group.end
        {
            group.end    = Math.max(group.end, end)
            group.endCue = index + 1
            continue
        }

        if active and group.endCue - group.firstCue > 1 do
            result.add(group)
        group  = CueOverlapGroup{start, end, index, index + 1}
        active = true
    }

    if active and group.endCue - group.firstCue > 1 do
        result.add(group)
    return result
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
private const NormalizedExportLimit = 64 * 1024 * 1024'u64

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

            // A line only grows wider as it takes characters, so a word overflows exactly when it
            // does with its last character: the line is measured there and at each space, not at
            // every character, which made a relayout quadratic in the length of a line.
            if words[scan] == ' ' do
                lastBreak = scan
            let wordEnd = words[scan] == ' ' or
                          scan + 1 == words.count or
                          words[scan + 1] == ' ' or
                          words[scan + 1] == '\n'
            if lastBreak != Swag.U64.Max and
               wordEnd and
               Painter.measureString(words[lineStart until scan + 1], font).width > width
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
            row.lines.clear()
            row.top     = y
            row.visible = .panel.matchesDuration(index)
            if not row.visible
            {
                row.height = 0
                continue
            }

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
            if row.visible do
                return index
        return Swag.U64.Max
    }

    // Scrolls the least that brings row `index` into view, clear of the strip.
    mtd reveal(index: u64)
    {
        if index >= .rows.count or not .rows[index].visible do
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
        if match.cue >= .rows.count or not .rows[match.cue].visible do
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
        let colors   = .themeColors()
        let metrics  = .themeMetrics()
        let mono     = .monoFont()
        let words    = .wordsFont()
        let band     = .rowRect(index)
        let current  = index == .panel.currentCue
        let selected = .panel.isCueSelected(index)
        if selected
        {
            painter.setParams(.Antialiased)
            painter.fillRoundRect(band, metrics.corner_Control, metrics.corner_Control, colors.selection)
        }

        if current do
            painter.fillRect(Math.Rectangle{band.x, band.y, 3, band.height}, colors.caret)

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

        // The list is set in document coordinates; only the rows in view are written. The rows
        // follow one another down the list, so a binary search finds the first one that reaches
        // the view, and the writing stops at the first one below it.
        var band = .clientRect()
        band.offset(.scrollPos)
        var first = 0'u64
        var last  = .rows.count
        while first < last
        {
            let middle = first + (last - first) / 2
            let row    = &.rows[middle]
            if row.top + row.height < band.y do
                first = middle + 1
            else do
                last = middle
        }

        for index in first until .rows.count
        {
            if .rows[index].top > band.bottom() do
                break
            if .rows[index].visible do
                .paintRow(painter, index)
        }
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

    // A click makes its cue current; Shift extends the selected contiguous range.
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
            .panel.setCurrentCue(cue, extend: evt.modifiers.has(.Shift))
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
        case evt.modifiers == .Control and evt.key == .C:                              panel.copySelectionOrCurrentCue()
        case evt.modifiers == (.Control | .Shift) and evt.key == .C:                   panel.copySelectedCues()
        case evt.modifiers == .Shift and evt.key == .Up:                               discard panel.navigateCue(false, extend: true)
        case evt.modifiers == .Shift and evt.key == .Down:                             discard panel.navigateCue(true, extend: true)
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

    // The left edge of the minute shown, shared by drawing and click-to-time navigation.
    mtd timeWindowStart()->f64
    {
        let track = unwrap .panel.track
        let focus = .panel.currentCue == Swag.U64.Max ? 0 : .panel.currentCue
        return Math.max(track.cueStartTime(0), track.cueStartTime(focus) - Span * Lead)
    }

    // Maps a local point on the ruler to its subtitle time, clamped to the visible minute.
    mtd timeAt(point: Math.Point)->f64
    {
        let room     = .clientRect()
        let width    = Math.min(CueSheet.ColumnWidth, Math.max(0, room.width - 2 * CueSheet.Gutter)) - 2 * CueSheet.NumberX
        let left     = Math.round((room.width - width) * 0.5)
        let fraction = Math.clamp((point.x - left) / Math.max(width, 1), 0, 1)
        return .timeWindowStart() + cast(f64, fraction) * Span
    }
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
        let start = .timeWindowStart()
        let scale = cast(f64, width) / Span

        // The track orders its cues by their start, so the first one that starts past the minute
        // ends the rules. One that started earlier may still last into it, so those are all read.
        painter.setParams(.Antialiased)
        for index in track.cueCount()
        {
            let first = track.cueStartTime(index)
            let last  = track.cueEndTime(index)
            if first > start + Span do
                break
            if last < start do
                continue

            let x0 = left + cast(f32, (Math.max(first, start) - start) * scale)
            let x1 = left + cast(f32, (Math.min(last, start + Span) - start) * scale) - RuleGap
            if x1 <= x0 do
                continue
            painter.fillRoundRect(Math.Rectangle{x0, centerY - RuleSize * 0.5, x1 - x0, RuleSize}, RuleSize * 0.5, RuleSize * 0.5, colors.strongLine)
        }

        // Accent strips group cue intervals that overlap, including connected chains of overlaps.
        for &group in panel.overlapGroups
        {
            if group.end <= start or group.start >= start + Span do
                continue
            let x0 = left + cast(f32, (Math.max(group.start, start) - start) * scale)
            let x1 = left + cast(f32, (Math.min(group.end, start + Span) - start) * scale)
            painter.fillRoundRect(Math.Rectangle{x0, centerY - RuleSize * 1.5, Math.max(2, x1 - x0), RuleSize * 0.5},
                                  RuleSize * 0.25,
                                  RuleSize * 0.25,
                                  colors.arc)
        }

        if panel.currentCue != Swag.U64.Max
        {
            let x = left + cast(f32, (track.cueStartTime(panel.currentCue) - start) * scale)
            painter.fillRect(Math.Rectangle{Math.round(x), centerY - MarkSize * 0.5, MarkWidth, MarkSize}, colors.caret)
        }
    }

    // Clicking the ruler selects the cue at that time; a quiet gap follows Go to Time's rule.
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind != .Pressed or evt.button != .Left or .panel.track == null
        {
            evt.accepted = false
            return
        }

        .panel.revealTime(.timeAt(.surfaceToLocal(evt.surfacePos)))
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

    track:              *Subtitle.Track?
    fileName:           String
    services:           Viewer.HostServices
    currentCue:         u64 = Swag.U64.Max
    selectionAnchor:    u64 = Swag.U64.Max
    duration:           f64
    minimumCueDuration: f64
    overlapGroups:      Array'CueOverlapGroup
    match:              CueMatch
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
    mtd identity()->String
    {
        var result = Format.toString("% · % · %", cueCountText(.track!.cueCount()), Viewer.durationText(.duration), formatText(.track.sourceFormat()))
        if .minimumCueDuration > 0 do
            result += Format.toString(" · %", Format.toString(texts().ui_FilterMarker, .minimumCueDuration))
        return result
    }

    mtd matchesDuration(index: u64)->bool
    {
        if index >= .track!.cueCount() do
            return false
        return .minimumCueDuration <= 0 or .track.cueEndTime(index) - .track.cueStartTime(index) >= .minimumCueDuration
    }

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
        .rhythm.toolTip     = texts().ui_OverlapMarkerHint
        .sheet.toolTip      = texts().ui_SelectCuesHint
        .refreshReadings()
        .sheet.invalidate()
    }

    // Says the current cue on the readings at the foot: its rank on the left, its time on the right,
    // spelled as every clock of Swag Scope spells one.
    mtd refreshReadings()
    {
        .services.showDetails(me, .cuePosition())
        let time = .currentCue == Swag.U64.Max ? Viewer.durationText(.duration) : Viewer.timeText(.track!.cueStartTime(.currentCue))
        .timeButton.setQuietText(time)
        .services.chromeChanged(me)
    }

    // Makes cue `index` the current one, brings its row into view, and says it at the foot.
    mtd isCueSelected(index: u64)->bool
    {
        if index >= .track!.cueCount() or not .matchesDuration(index) do
            return false
        let anchor = .selectionAnchor == Swag.U64.Max ? .currentCue : .selectionAnchor
        return .currentCue != Swag.U64.Max and
               index >= Math.min(anchor, .currentCue) and
               index <= Math.max(anchor, .currentCue)
    }

    mtd selectedCueCount()->u64
    {
        if .currentCue == Swag.U64.Max do
            return 0
        var count = 0'u64
        let first = Math.min(.selectionAnchor == Swag.U64.Max ? .currentCue : .selectionAnchor, .currentCue)
        let last  = Math.max(.selectionAnchor == Swag.U64.Max ? .currentCue : .selectionAnchor, .currentCue)
        for index in first until last + 1 where .matchesDuration(index) do
            count += 1
        return count
    }

    mtd setCurrentCue(index: u64, extend = false)
    {
        if index >= .track!.cueCount() do
            return
        let oldAnchor = .selectionAnchor
        if not extend or .selectionAnchor == Swag.U64.Max do
            .selectionAnchor = index
        if .currentCue == index and oldAnchor == .selectionAnchor do
            return
        .currentCue = index
        .sheet.reveal(index)
        .refreshReadings()
        .sheet.invalidate()
        .rhythm.invalidate()
    }

    mtd setMinimumCueDuration(seconds: f64)
    {
        if not Math.isFinite(seconds) do
            return
        .minimumCueDuration = Math.max(seconds, 0.0)
        if .currentCue < .track!.cueCount() and not .matchesDuration(.currentCue)
        {
            .currentCue      = Swag.U64.Max
            .selectionAnchor = Swag.U64.Max
        }

        .sheet.relayout()
        .scroll.setScrollPos(0, 0)
        .refreshReadings()
        .rhythm.invalidate()
    }

    mtd copyCurrentCue()
    {
        if .currentCue != Swag.U64.Max do
            Clipboard.setString(.track!.cueContent(.currentCue))
    }

    // Copies every visible cue in the selected range with original cue numbers and times.
    mtd selectedCuesText()->String
    {
        var result: String
        if .currentCue == Swag.U64.Max do
            return result
        let anchor = .selectionAnchor == Swag.U64.Max ? .currentCue : .selectionAnchor
        let first  = Math.min(anchor, .currentCue)
        let last   = Math.max(anchor, .currentCue)
        for index in first until last + 1 where .matchesDuration(index)
        {
            if not result.isEmpty() do
                result += "\n"
            result += Format.toString("%\n% --> %\n%", index + 1, clockText(.track!.cueStartTime(index)), clockText(.track.cueEndTime(index)), .track.cueContent(index))
        }

        return result
    }

    mtd copySelectedCues()
    {
        if .selectedCueCount() > 1 do
            Clipboard.setString(.selectedCuesText())
    }

    mtd copySelectionOrCurrentCue()
    {
        if .selectedCueCount() > 1
        {
            .copySelectedCues()
        }
        else
        {
            .copyCurrentCue()
        }
    }

    // Serializes the decoded track to deterministic SubRip; refuses output above the export bound.
    mtd normalizedTranscript()->String fail
    {
        var result: String
        for index in .track!.cueCount()
        {
            let block = Format.toString("%\n% --> %\n%\n\n", index + 1, clockText(.track.cueStartTime(index)), clockText(.track.cueEndTime(index)), .track.cueContent(index))
            if block.count > NormalizedExportLimit - Math.min(result.count, NormalizedExportLimit) do
                fail Errors.UnsupportedFormatError{texts().ui_ExportTooLarge}
            result += block
        }

        return result
    }

    mtd normalizationLossSummary()->String
    {
        return Format.toString(texts().ui_NormalizationLoss,
                               formatText(.track!.sourceFormat()),
                               .track.cueCount(),
                               .track.discardedCueCount())
    }

    private mtd confirmNormalization()->bool
    {
        if not .surface do
            return false
        var options: MessageDlgOptions
        options.title = texts().ui_NormalizationTitle
        return MessageDlg.confirm(.surface, .normalizationLossSummary(), texts().ui_NormalizationQuestion, options: options) == Dialog.BtnYes
    }

    mtd copyNormalizedTranscript()
    {
        if not .confirmNormalization() do
            return
        var text: String
        catch { text = try .normalizedTranscript() }
        {
            .services.failed(me, Viewer.failureText(Swag.err))
            return
        }

        Clipboard.setString(text)
    }

    mtd exportNormalizedTranscriptTo(path: string) fail
    {
        let text = try .normalizedTranscript()
        try File.writeAllText(path, text)
    }

    mtd promptExportNormalizedTranscript()
    {
        if not .surface do
            return
        if not .confirmNormalization() do
            return
        let initialFolder = Path.directoryName(me.fileName) orelse ""
        let initialName   = Format.toString("%.normalized.srt", Path.fileNameWithoutExtension(me.fileName) orelse "subtitles")
        with var options: FileDlgOptions
        {
            .mode          = .CreateFile
            .title         = texts().ui_ExportNormalized
            .initialFolder = initialFolder
            .initialName   = initialName
            .filters.add({texts().ui_NormalizationFile, ".srt"})
        }

        let dialog = FileDlg.create(.surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return
        catch .exportNormalizedTranscriptTo(dialog.selectedPath())
        {
            .services.failed(me, Viewer.failureText(Swag.err))
        }
    }

    // Returns the words of every cue in order, without their times, a blank line between two cues.
    mtd dialogueText()->String
    {
        var result: String
        for index in .track!.cueCount()
        {
            if index do
                result += "\n\n"
            result += .track.cueContent(index)
        }

        return result
    }

    // Shows the first cue still on screen at `seconds`, or the last cue when the track has ended.
    // A cue's end is exclusive: at that very instant, or in the gap after it, the next cue is the
    // one to come.
    mtd revealTime(seconds: f64)
    {
        let count = .track!.cueCount()
        if not count do
            return
        var lastMatch = Swag.U64.Max
        for index in count where .matchesDuration(index)
        {
            lastMatch = index
            if .track.cueEndTime(index) > seconds
            {
                discard .revealCue(index)
                return
            }
        }

        if lastMatch != Swag.U64.Max do
            discard .revealCue(lastMatch)
    }

    mtd collectMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        var matcher = catch Viewer.createNameMatcher(text, options) { return; }
        for index in .track!.cueCount() do
            Viewer.collectTextMatches(.track.cueContent(index), &matcher, index, 0, 0, result)
    }

    mtd revealMatch(match: Viewer.SearchMatch, _: string)->bool
    {
        if match.major >= .track!.cueCount() do
            return false
        if not .matchesDuration(match.major) do
            .setMinimumCueDuration(0)
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

    mtd revealCue(index: u64, extend = false)->bool
    {
        if index >= .track!.cueCount() do
            return false
        if not .matchesDuration(index) do
            .setMinimumCueDuration(0)
        .setCurrentCue(index, extend)
        .sheet.setFocus()
        return true
    }

    // Moves to an adjacent cue. With no current cue, begin at the first cue in either direction.
    mtd navigateCue(forward: bool, extend = false)->bool
    {
        let count = .track!.cueCount()
        if not count do
            return false
        if .currentCue == Swag.U64.Max
        {
            if forward
            {
                for index in count where .matchesDuration(index) do
                    return .revealCue(index, extend)
            }
            else
            {
                for index in reversed(count) where .matchesDuration(index) do
                    return .revealCue(index, extend)
            }

            return false
        }

        if forward
        {
            for index in .currentCue + 1 until count where .matchesDuration(index) do
                return .revealCue(index, extend)
        }
        else
        {
            for index in reversed(.currentCue) where .matchesDuration(index) do
                return .revealCue(index, extend)
        }

        return false
    }

    mtd navigateCueBoundary(last: bool)->bool
    {
        let count = .track!.cueCount()
        if not count do
            return false
        if last
        {
            for index in reversed(count) where .matchesDuration(index) do
                return .revealCue(index)
        }
        else
        {
            for index in count where .matchesDuration(index) do
                return .revealCue(index)
        }

        return false
    }

    // Gives the lens the ways through the cues and the time of the track.
    mtd describeLens(entries: *Viewer.LensEntries)
    {
        let strings = texts()
        let count   = .track!.cueCount()

        // `:` and an instant goes to the cue on screen then; a whole number is also a cue.
        if entries.results.prefix == .Line
        {
            let query  = entries.query.toString()
            let now    = .currentCue < count ? .track.cueStartTime(.currentCue) : 0
            let target = count ? Viewer.parseTimeAddress(query, now, .duration) : -1
            if target >= 0 do
                entries.add(Viewer.timeJumpText(target, query), .GoTo, func|view = me, target|() { view.revealTime(target) })
            let cue = catch StrConv.toU64(Latin1.trim(query)) { return; }
            if cue < 1 or cue > count do
                return
            let entry = entries.add(Format.toString(strings.ui_GoToCueNumber, cue), .GoTo, func|view = me, cue|() { discard view.revealCue(cue - 1) })
            if entry do
                entry.lead = Format.toString("%", cue)
            return
        }

        entries.add(strings.ui_CopyCue, .Copy, func|view = me|() { view.copyCurrentCue() }, disabled: .currentCue >= count, defaultKey: {modifiers: .Control, key: .C}, bindId: "scope.subtitle.copyCue")
        entries.add(strings.ui_CopyDialogue, .Copy, func|view = me|() { Clipboard.setString(view.dialogueText()) }, disabled: not count, bindId: "scope.subtitle.copyDialogue")
        entries.add(strings.ui_CopySelectedCues, .Copy, func|view = me|() { view.copySelectedCues() }, disabled: .selectedCueCount() < 2, defaultKey: {modifiers: .Control | .Shift, key: .C}, bindId: "scope.subtitle.copySelectedCues")
        entries.add(strings.ui_CopyNormalized, .Copy, func|view = me|() { view.copyNormalizedTranscript() }, disabled: not count, bindId: "scope.subtitle.copyNormalized")
        entries.add(strings.ui_ExportNormalized, .SaveAs, func|view = me|() { view.promptExportNormalizedTranscript() }, disabled: not count, bindId: "scope.subtitle.exportNormalized")
        entries.add(strings.ui_GoToCue, .GoTo, func|view = me|() { view.promptGoToCue() }, bindId: "scope.subtitle.goToCue")
        entries.add(strings.ui_GoToTime, .History, func|view = me|() { view.promptGoToTime() }, bindId: "scope.subtitle.goToTime")
        entries.add(.minimumCueDuration > 0 ? strings.ui_ClearDurationFilter : strings.ui_FilterDuration, .Filter, func|view = me|() { view.promptFilterDuration() }, bindId: "scope.subtitle.filterDuration")
        entries.add(strings.ui_PreviousCue, .ChevronLeft, func|view = me|() { discard view.navigateCue(false) }, defaultKey: {modifiers: .Control, key: .PageUp}, bindId: "scope.subtitle.previousCue")
        entries.add(strings.ui_NextCue, .ChevronRight, func|view = me|() { discard view.navigateCue(true) }, defaultKey: {modifiers: .Control, key: .PageDown}, bindId: "scope.subtitle.nextCue")
        entries.add(strings.ui_FirstCue, .ChevronUp, func|view = me|() { discard view.navigateCueBoundary(false) }, defaultKey: {modifiers: .Control, key: .Home}, bindId: "scope.subtitle.firstCue")
        entries.add(strings.ui_LastCue, .ChevronDown, func|view = me|() { discard view.navigateCueBoundary(true) }, defaultKey: {modifiers: .Control, key: .End}, bindId: "scope.subtitle.lastCue")
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
    //
    // The time is read as the lens reads one, but from the start of the track and without an end:
    // an instant past the last cue shows the last cue. Like the Go to Time of a film, the box
    // offers where the reader stands as the clocks spell it: the start of the current cue, or zero
    // before any cue is current, since the track reads zero as the start of a cue it lacks.
    mtd promptGoToTime()
    {
        let count = .track!.cueCount()
        if not count do
            return
        let current = Viewer.timeText(.track.cueStartTime(.currentCue))
        let dialog  = EditDlg.createSingleLine(unwrap .surface, {title: texts().ui_GoToTime, message: texts().ui_TimeRange, text: current})
        if dialog.doModal() != Dialog.BtnOk do
            return

        let seconds = Viewer.parseTimeAddress(dialog.text(), 0, Swag.F64.Max)
        if seconds >= 0 do
            .revealTime(seconds)
    }

    // Filters the transcript to cues at least this long; zero restores the full list.
    mtd promptFilterDuration()
    {
        let current = Format.toString("%{f2}", .minimumCueDuration)
        let dialog  = EditDlg.createSingleLine(unwrap .surface,
                                               {title: texts().ui_FilterDuration, message: texts().ui_FilterDurationHint, text: current})
        if dialog.doModal() != Dialog.BtnOk do
            return
        let seconds = catch StrConv.toF64(Latin1.trim(dialog.text())) { return; }
        if not Math.isFinite(seconds) or seconds < 0 do
            return
        .setMinimumCueDuration(seconds)
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
            .overlapGroups   = collectCueOverlapGroups(.track)
        }

        with result.rhythm = Wnd.create'CueRhythm(result, {0, 0, 0, CueRhythm.Height})
        {
            .panel           = result
            .dockStyle       = .Bottom
            .backgroundStyle = .Transparent
            .toolTip         = texts().ui_OverlapMarkerHint
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
            .toolTip         = texts().ui_SelectCuesHint
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
        return result
    }
}

// Creates the integrated timed-subtitle document view and connects it to the host.
impl Panel
{
    // Describes the subtitles in the information sheet: how many cues, over how long.
    mtd describeInformation(sheet: *InfoSheet)
    {
        let track = .track
        if not track do
            return
        var data: MediaInfoData
        data.addFigure(.Custom, cueCountText(track.cueCount()))
        if .duration > 0 do
            data.addFigure(.Duration, Viewer.durationText(.duration))

        // Timing a subtitler checks: cues that start before the one before them has ended, and
        // the shortest time a cue stays on screen. The track orders its cues by their start.
        let count = track.cueCount()
        if count
        {
            var overlaps = 0'u64
            var shortest = Swag.F64.Max
            var lastEnd  = Swag.F64.NegInf
            for index in count
            {
                let start = track.cueStartTime(index)
                let end   = track.cueEndTime(index)
                if start < lastEnd do
                    overlaps += 1
                lastEnd  = Math.max(lastEnd, end)
                shortest = Math.min(shortest, end - start)
            }

            data.add(.Timing, group: true)
            data.add(.Overlaps, Format.toString("%", overlaps))
            data.add(.ShortestCue, Format.toString("%{f2} s", shortest))
        }

        data.describe(sheet)
    }
}

func createViewer(host: Viewer.Host)
{
    catch
    {
        let view = try Panel.create(host)
        host.attachView(view)
        host.setDetails(cueCountText(view.track!.cueCount()))
        host.setInformation(func|view|(sheet) { view.describeInformation(sheet) })

        host.setSearch(Viewer.searchApi(view))
        host.setLensSource(func|view|(entries) { view.describeLens(entries) })
    }
    {
        host.reject(Viewer.failureText(Swag.err))
    }
}
