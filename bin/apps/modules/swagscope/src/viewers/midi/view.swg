#global internal
#global namespace Viewers.Midi

using Core, Pixel, Gui

private
{
    const HeaderHeight  = 76.0
    const AxisHeight    = 28.0
    const KeyboardWidth = 72.0
    const ContentInset  = 24.0
    const QuarterWidth  = 64.0
    const MinZoom       = 0.01'f32
    const MaxZoom       = 16.0'f32
    const MinPitchZoom  = 0.5'f32
    const MaxPitchZoom  = 8.0'f32

    // The measures of the tracks presentation, after `scope.midi`.
    const LaneColumn  = 208.0     // Width of the column the names of the tracks stand in.
    const AxisTop     = 40.0      // Distance from the strip to the line of bar numbers.
    const PlotTop     = 60.0      // Distance from the strip to the top of the lanes.
    const PlotBottom  = 168.0     // Room kept under the lanes for the transport and the readings.
    const LanePadding = 12.0      // Air at the top and the bottom of a lane.
    const NoteHeight  = 7.0       // Height of the rule of a note.
    const BarStride   = 4'u64     // Bars between two numbered bar lines.
    const DotSize     = 8.0       // Diameter of the dot of a track.
}

// How the roll lays the piece out.
enum RollMode
{
    Pitches     // One row per key across the piece, under a piano keyboard.
    Tracks      // One lane per track, its notes spread by pitch in its own range.
}

// One lane of the tracks presentation: the track, the channel it plays on, and its range of keys.
struct RollLane
{
    track:   u32
    channel: u8
    lowKey:  u8 = 127
    highKey: u8
}

// Paints a MIDI document as a scrolling piano roll under a summary header.
struct RollView
{
    using wnd: Wnd

    late
    {
        scroll:    *ScrollWnd
        titleFont: *Font
        labelFont: *Font
        codeFont:  *Font
    }

    document:       Document
    mode:           RollMode = .Pitches
    lanes:          Array'RollLane
    selectedTrack:  u32      = Swag.U32.Max
    zoom:           f32      = 1
    pitchZoom:      f32      = 1
    keyboardWidth:  f32      = KeyboardWidth
    fit:            bool     = true
    pitchLabelMode: PitchLabelMode
    lowKey:         u8
    highKey:        u8
    plotTop:        f32
    rowHeight:      f32
    beatTicks:      u64
    pixelsPerTick:  f32
    timelineWidth:  f32
    sigZoomChanged: SigArray'func||(*Wnd)
}

// Names a key in scientific pitch notation, where middle C, key 60, is C4.
private func pitchName(key: u8)->String
{
    const Names: [12] string = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    var result = String.from(Names[key % 12])
    result += Format.toString("%", cast(s32, key) / 12 - 1)
    return result
}

private func isBlackKey(key: u8)->bool
{
    let note = key % 12
    return note == 1 or note == 3 or note == 6 or note == 8 or note == 10
}

enum PitchLabelMode
{
    Scientific
    MidiNumber
}

impl RollView
{
    mtd selectedNoteCount()->u64
    {
        if .selectedTrack == Swag.U32.Max do
            return .document.notes.count
        if .selectedTrack >= .document.tracks.count do
            return 0
        return .document.tracks[.selectedTrack].noteCount
    }

    // The number of keys the roll shows, one row each, from `highKey` at the top down to `lowKey`.
    mtd const keyCount()->u32        => cast(u32, .highKey - .lowKey + 1)
    mtd const keyAtRow(row: u32)->u8 => cast(u8, cast(u32, .highKey) - row)

    mtd summaryText()->String => Format.toString(texts().ui_Summary, trackCountText(.document.tracks.count), noteCountText(.selectedNoteCount()), Viewer.durationText(.document.durationSeconds), .document.bpm(), .document.meterText(), .document.keyText())

    // Shows the piece as lanes of tracks or as rows of keys.
    mtd setMode(mode: RollMode)
    {
        .mode = mode
        .refreshLayout()
        .scroll.setScrollPos(0, 0)
    }

    // Returns the left edge of the notes: after the keyboard, or after the names of the tracks.
    mtd plotLeft()->f32 => .mode == .Tracks ? LaneColumn + ContentInset : .keyboardWidth + ContentInset

    // Gathers the tracks that hold notes, in the order of the file, each with the first channel it
    // plays on and its range of keys.
    mtd collectLanes()
    {
        var ranges: Array'RollLane
        ranges.resize(.document.tracks.count)
        for &range, index in ranges do
            range.track = cast(u32, index)

        // A range still empty has its low key above its high one.
        for note in .document.notes where note.track < ranges.count
        {
            let range = &ranges[note.track]
            if range.lowKey > range.highKey do
                range.channel = note.channel
            range.lowKey  = Math.min(range.lowKey, note.key)
            range.highKey = Math.max(range.highKey, note.key)
        }

        .lanes.clear()
        for range in ranges where range.lowKey <= range.highKey do
            .lanes.add(range)
    }

    // Returns the ticks of one bar, from the first time signature.
    mtd barTicks()->u64
    {
        var numerator   = 4'u64
        var denominator = 4'u64
        if not .document.timeSignatures.isEmpty()
        {
            numerator   = Math.max(cast(u64, .document.timeSignatures[0].numerator), 1)
            denominator = Math.max(cast(u64, .document.timeSignatures[0].denominator), 1)
        }

        return Math.max(.beatTicks * numerator * 4 / denominator, 1)
    }

    // Returns the band lane `index` stands in, in the coordinates of the view.
    mtd laneRect(index: u64)->Math.Rectangle
    {
        let top    = .scroll.stripInset() + PlotTop
        let bottom = Math.max(.clientRect().height - PlotBottom, top + 1)
        let height = (bottom - top) / cast(f32, Math.max(.lanes.count, 1))
        return Math.Rectangle{.plotLeft(), top + cast(f32, index) * height, .timelineWidth, height}
    }

    // Recomputes the piano-roll geometry: the key range with two keys of margin, the row height,
    // the ticks per beat and the timeline width, fitting the whole piece when `fit` is set.
    mtd refreshLayout()
    {
        let client = .clientRect()
        .collectLanes()
        .lowKey  = cast(u8, Math.max(cast(s32, .document.minKey) - 2, 0))
        .highKey = cast(u8, Math.min(cast(s32, .document.maxKey) + 2, 127))
        .plotTop = HeaderHeight + AxisHeight
        let fittedRowHeight = Math.max((client.height - .plotTop - ContentInset) / cast(f32, .keyCount()), 3)
        .rowHeight = Math.max(fittedRowHeight * .pitchZoom, 3)

        if .document.division & 0x8000
        {
            let encoded = cast(u8, .document.division >> 8)
            .beatTicks = cast(u64, 256'u32 - encoded) * cast(u64, .document.division & 0xFF)
        }
        else
        {
            .beatTicks = .document.division
        }

        .beatTicks = Math.max(.beatTicks, 1)

        let viewport = Math.max(client.width - .plotLeft() - ContentInset, 1)
        let natural  = Math.max(cast(f32, .document.durationTicks) / cast(f32, .beatTicks) * QuarterWidth, 1)
        if .fit do
            .zoom = Math.clamp(viewport / natural, MinZoom, 1)
        .timelineWidth = Math.max(viewport, natural * .zoom)
        .pixelsPerTick = .timelineWidth / cast(f32, Math.max(.document.durationTicks, 1))

        // The lanes share the height of the view, so only the time scrolls.
        if .mode == .Tracks do
            .scroll.setScrollSize(.plotLeft() + ContentInset + .timelineWidth, 0)
        else do
            .scroll.setScrollSize(.plotLeft() + ContentInset + .timelineWidth, .plotTop + cast(f32, .keyCount()) * .rowHeight + ContentInset)
        .invalidate()
        .sigZoomChanged.call(me)
    }

    mtd setTrack(index: u32)
    {
        .selectedTrack = index
        .invalidate()
    }

    mtd setPitchLabelMode(mode: PitchLabelMode)
    {
        .pitchLabelMode = mode
        .invalidate()
    }

    mtd setKeyboardWidth(width: f32)
    {
        .keyboardWidth = width
        .refreshLayout()
    }

    mtd pitchLabel(key: u8)->String
    {
        if .pitchLabelMode == .MidiNumber do
            return Format.toString("%", key)
        return pitchName(key)
    }

    mtd applyZoom(value: f32)
    {
        .fit  = false
        .zoom = Math.clamp(value, MinZoom, MaxZoom)
        .refreshLayout()
    }

    mtd zoomIn()  => .applyZoom(.zoom * 1.5)
    mtd zoomOut() => .applyZoom(.zoom / 1.5)

    mtd applyPitchZoom(value: f32)
    {
        let oldRowHeight = .rowHeight
        let centerY      = .scrollPos.y + .clientRect().height * 0.5
        let centerKey    = cast(f32, .highKey) - (centerY - .plotTop) / Math.max(oldRowHeight, 1)
        .pitchZoom = Math.clamp(value, MinPitchZoom, MaxPitchZoom)
        .refreshLayout()

        let newCenterY = .plotTop + (cast(f32, .highKey) - centerKey) * .rowHeight
        .scroll.setScrollPos(.scrollPos.x, newCenterY - .clientRect().height * 0.5)
    }

    mtd zoomToFit()
    {
        .fit       = true
        .pitchZoom = 1
        .refreshLayout()
        .scroll.setScrollPos(0, 0)
    }

    // Creates the title, label, and code fonts from the current theme.
    mtd refreshFonts()
    {
        .titleFont = .theme().createDefaultFont(24, .Bold)
        .labelFont = .theme().createDefaultFont(11, .Bold)
        .codeFont  = .theme().createDefaultFontFs(11)
    }

    mtd paintHeader(painter: *Painter)
    {
        let colors = .themeColors()
        let left   = .scrollPos.x + ContentInset
        let top    = .scrollPos.y
        painter.fillRect(.scrollPos.x, top, .clientRect().width, HeaderHeight, colors.view_Bk)
        painter.drawString(left, top + 18, .document.title, .titleFont, colors.label_Text)
        let summary = .summaryText()
        painter.drawString(left, top + 48, summary, .codeFont, colors.label_TextFaint)
        painter.drawLine(left, top + HeaderHeight - 1, .scrollPos.x + .clientRect().width - ContentInset, top + HeaderHeight - 1, colors.line, 1)
    }

    // Paints the tracks presentation: the numbered bar lines across the lanes, the notes of each
    // track in its hue, spread by pitch in the lane's own range, and the names of the tracks pinned
    // at the left. A chosen track keeps its hue and the others recede.
    mtd paintTracks(painter: *Painter)
    {
        let colors = .themeColors()
        let mono   = .theme().createDefaultFontFs(.themeMetrics().defaultFixedFontSize - 1)
        let left   = .plotLeft()
        let top    = .scroll.stripInset() + PlotTop
        let bottom = Math.max(.clientRect().height - PlotBottom, top + 1)

        // Every fourth bar is numbered and drawn across the lanes; the first stands at the edge.
        let barTicks = .barTicks()
        let axisY    = .scroll.stripInset() + AxisTop
        var bar      = 0'u64
        while bar * barTicks <= .document.durationTicks
        {
            let x     = left + cast(f32, bar * barTicks) * .pixelsPerTick
            let label = Format.toString("%", bar + 1)
            let width = Painter.measureString(label, mono).width
            painter.drawString(bar ? x - width * 0.5 : x, mono.opticalLineTop(axisY), label, mono, colors.faintText)
            if bar do
                painter.fillRect(Math.Rectangle{painter.snapToDeviceX(x), top, painter.hairline(1), bottom - top}, colors.line)
            bar += BarStride
        }

        for &lane, index in .lanes
        {
            let band   = .laneRect(index)
            let range  = Math.max(cast(f32, lane.highKey - lane.lowKey), 1)
            let spread = Math.max(band.height - 2 * LanePadding - NoteHeight, 0)
            var color  = colors.series[index % colors.series.count]
            if .selectedTrack != Swag.U32.Max and .selectedTrack != lane.track do
                color = Color.lerp(colors.ground, color, 0.35)

            for note in .document.notes where note.track == lane.track
            {
                let x = left + cast(f32, note.startTick) * .pixelsPerTick
                if x > .scrollPos.x + .clientRect().width do
                    break
                let width = Math.max(cast(f32, note.endTick - note.startTick) * .pixelsPerTick, 2)
                if x + width < .scrollPos.x + left do
                    continue
                let y = band.y + LanePadding + (cast(f32, lane.highKey - note.key) / range) * spread
                painter.fillRoundRect(Math.Rectangle{x, y, width, NoteHeight}, NoteHeight * 0.5, NoteHeight * 0.5, color)
            }
        }

        // The names stand in their own column, which the notes pass under when the time scrolls.
        let column = Math.Rectangle{.scrollPos.x, top, left, bottom - top}
        painter.fillRect(column, colors.ground)
        let nameFont = .theme().createDefaultFont(.themeMetrics().defaultFontSize)
        for &lane, index in .lanes
        {
            let band  = .laneRect(index)
            let x     = .scrollPos.x + ContentInset + 20
            let muted = .selectedTrack != Swag.U32.Max and .selectedTrack != lane.track
            var color = colors.series[index % colors.series.count]
            if muted do
                color = Color.lerp(colors.ground, color, 0.35)

            let nameY = band.y + LanePadding + nameFont.height * 0.5
            painter.fillCircle(x, nameY, DotSize * 0.5, color)
            let track = &.document.tracks[lane.track]
            let name  = track.name.isEmpty() ? Format.toString(texts().ui_TrackName, lane.track + 1) : String.from(track.name)
            painter.drawString(x + 14, nameFont.opticalLineTop(nameY), name, nameFont, muted ? colors.faintText : colors.text)
            let channel = Format.toString(texts().ui_Channel, cast(u32, lane.channel) + 1)
            painter.drawString(x + 14, nameY + nameFont.height * 0.5 + 6, channel, mono, colors.faintText)
        }
    }

    // Paints the piano-roll grid: shaded black-key rows, row lines, and numbered beat lines,
    // skipping beats by powers of two so labels stay at least 72 pixels apart.
    mtd paintGrid(painter: *Painter)
    {
        let colors     = .themeColors()
        let plotLeft   = .keyboardWidth + ContentInset
        let plotRight  = plotLeft + .timelineWidth
        let plotBottom = .plotTop + cast(f32, .keyCount()) * .rowHeight

        for row in .keyCount()
        {
            let key = .keyAtRow(row)
            let y   = .plotTop + cast(f32, row) * .rowHeight
            if isBlackKey(key) do
                painter.fillRect(plotLeft, y, .timelineWidth, .rowHeight, colors.edit_Bk)
            painter.drawLine(plotLeft, y, plotRight, y, colors.line, 1)
        }

        painter.drawLine(plotLeft, plotBottom, plotRight, plotBottom, colors.line, 1)

        let beatWidth = .pixelsPerTick * cast(f32, .beatTicks)
        var stride    = 1'u64
        while beatWidth * cast(f32, stride) < 72 do
            stride *= 2
        let firstVisible = cast(u64, Math.max(Math.floor(Math.max(.scrollPos.x - plotLeft, 0) / beatWidth), 0))
        var beat         = firstVisible / stride * stride
        let lastBeat     = cast(u64, Math.ceil((.scrollPos.x + .clientRect().width - plotLeft) / beatWidth)) + stride
        let maxBeat      = .document.durationTicks / .beatTicks + 1
        while beat < Math.min(lastBeat, maxBeat + 1)
        {
            let x = plotLeft + cast(f32, beat * .beatTicks) * .pixelsPerTick
            painter.drawLine(x, HeaderHeight, x, plotBottom, colors.line, 1)
            let label = Format.toString("%", beat + 1)
            painter.drawString(x + 5, HeaderHeight + 6, label, .codeFont, colors.label_TextFaint)
            beat += stride
        }
    }

    // Paints the visible notes of the selected track, or of every track, shading each track
    // differently. Notes are sorted by start, so painting stops at the first one past the right
    // edge.
    mtd paintNotes(painter: *Painter)
    {
        let colors    = .themeColors()
        let plotLeft  = .keyboardWidth + ContentInset
        let alternate = .theme().palette.alternate.mark

        for note in .document.notes where .selectedTrack == Swag.U32.Max or note.track == .selectedTrack
        {
            let x = plotLeft + cast(f32, note.startTick) * .pixelsPerTick
            if x > .scrollPos.x + .clientRect().width do
                break
            let width = Math.max(cast(f32, note.endTick - note.startTick) * .pixelsPerTick, 2)
            if x + width < .scrollPos.x + .keyboardWidth do
                continue
            let y        = .plotTop + cast(f32, .highKey - note.key) * .rowHeight + 1
            let strength = 0.58'f32 + cast(f32, note.track % 4) * 0.09
            let color    = Color.lerp(colors.view_Bk, alternate, strength)
            painter.fillRoundRect(Math.Rectangle{x, y, width, Math.max(.rowHeight - 2, 1)}, 2, 2, color)
        }
    }

    // Paints the keyboard column pinned to the left of the scrolled view, shading black keys and
    // labelling each C when rows are tall enough.
    mtd paintKeyboard(painter: *Painter)
    {
        let colors = .themeColors()
        let left   = .scrollPos.x
        painter.fillRect(left, .scrollPos.y + HeaderHeight, .keyboardWidth + ContentInset, .clientRect().height - HeaderHeight, colors.view_Bk)
        painter.drawString(left + ContentInset, .scrollPos.y + HeaderHeight + 6, texts().ui_PianoRoll, .labelFont, colors.label_TextFaint)

        for row in .keyCount()
        {
            let key = .keyAtRow(row)
            let y   = .plotTop + cast(f32, row) * .rowHeight
            if isBlackKey(key) do
                painter.fillRect(left + ContentInset, y, .keyboardWidth, .rowHeight, colors.edit_Bk)
            painter.drawLine(left + ContentInset, y, left + ContentInset + .keyboardWidth, y, colors.line, 1)
            let showLabel = .pitchLabelMode == .MidiNumber ? .rowHeight >= 14 : key % 12 == 0 and .rowHeight >= 7
            if showLabel
            {
                let label = .pitchLabel(key)
                painter.drawString(left + ContentInset + 8, y + Math.max((.rowHeight - .codeFont.height) * 0.5, 0), label, .codeFont, colors.label_TextLight)
            }
        }

        let plotBottom = .plotTop + cast(f32, .keyCount()) * .rowHeight
        painter.drawLine(left + ContentInset + .keyboardWidth, .plotTop, left + ContentInset + .keyboardWidth, plotBottom, colors.line, 1)
    }
}

impl IWnd for RollView
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .scroll != null do
            .refreshLayout()
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .ThemeChanged
        {
            .refreshFonts()
            .refreshLayout()
        }
        else
        {
            evt.accepted = false
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        if evt.modifiers == .Control
        {
            switch evt.key
            {
            case .Add, .OemPlus:       .applyPitchZoom(.pitchZoom * 1.25)
            case .Subtract, .OemMinus: .applyPitchZoom(.pitchZoom / 1.25)
            default: evt.accepted = false
            }

            return
        }

        switch evt.key
        {
        case .Add, .OemPlus:       .zoomIn()
        case .Subtract, .OemMinus: .zoomOut()
        case .PageUp:              .scroll.setScrollPos(.scrollPos.x, .scrollPos.y - .clientRect().height)
        case .PageDown:            .scroll.setScrollPos(.scrollPos.x, .scrollPos.y + .clientRect().height)
        case .F:                   .zoomToFit()
        case .Left:                .scroll.setScrollPos(.scrollPos.x - 96, .scrollPos.y)
        case .Right:               .scroll.setScrollPos(.scrollPos.x + 96, .scrollPos.y)
        case .Home:                .scroll.setScrollPos(0, .scrollPos.y)
        case .End:                 .scroll.setScrollPos(.timelineWidth, .scrollPos.y)
        default:                   evt.accepted = false
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Wheel and evt.modifiers.has(.Control)
        {
            if evt.delta.y > 0 do
                .applyPitchZoom(.pitchZoom * 1.25)
            elif evt.delta.y < 0 do
                .applyPitchZoom(.pitchZoom / 1.25)
            return
        }

        evt.accepted = false
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        painter.setParams(.Antialiased)
        if .mode == .Tracks and not .document.notes.isEmpty()
        {
            .paintTracks(painter)
            return
        }

        .paintGrid(painter)
        if not .document.notes.isEmpty()
        {
            .paintNotes(painter)
        }
        else
        {
            let colors = .themeColors()
            painter.drawString(.scrollPos.x + .keyboardWidth + 2 * ContentInset, .plotTop + 24, texts().ui_NoNotes, .codeFont, colors.label_TextFaint)
        }

        .paintKeyboard(painter)
        .paintHeader(painter)
    }
}

impl RollView
{
    // Builds the piano roll inside its own scroll window, taking ownership of `document`.
    func create(parent: *Wnd, document: #move Document)->*RollView
    {
        with let scroll = Wnd.create'ScrollWnd(parent, "scope.midi.scroll", {})
        {
            .dockStyle = .Center
            .updateFlags(.TransparentBars)
        }

        with let result = scroll.createView'RollView()
        {
            .scroll          = scroll
            .document        = #move document
            .backgroundStyle = .View
            .focusPolicy     = .Tab
            .wndFlags        |= .NoFocusRing
            .refreshFonts()
            .refreshLayout()
        }

        return result
    }
}
