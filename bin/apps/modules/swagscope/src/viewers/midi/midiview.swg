#global internal

using Core, Pixel, Gui

private const MidiHeaderHeight  = 76.0
private const MidiAxisHeight    = 28.0
private const MidiKeyboardWidth = 72.0
private const MidiContentInset  = 24.0
private const MidiQuarterWidth  = 64.0
private const MidiMinZoom       = 0.01'f32
private const MidiMaxZoom       = 16.0'f32

// Paints a MIDI document as a scrolling piano roll under a summary header.
struct MidiRollView
{
    using wnd: Wnd

    late
    {
        scroll:    *ScrollWnd
        titleFont: *Font
        labelFont: *Font
        codeFont:  *Font
    }

    document:       MidiDocument
    selectedTrack        = Swag.U32.Max
    zoom = 1'f32
    fit:            bool = true
    lowKey:         u8
    highKey:        u8
    plotTop:        f32
    rowHeight:      f32
    beatTicks:      u64
    pixelsPerTick:  f32
    timelineWidth:  f32
    sigZoomChanged: SigArray'func||(*MidiRollView)
}

// Names a key in scientific pitch notation, where middle C, key 60, is C4.
private func midiPitchName(key: u8)->String
{
    const Names: [12] string = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    var result = String.from(Names[key % 12])
    result += Format.toString("%", cast(s32) key / 12 - 1)
    return result
}

private func midiIsBlackKey(key: u8)->bool
{
    let note = key % 12
    return note == 1 or note == 3 or note == 6 or note == 8 or note == 10
}

impl MidiRollView
{
    mtd selectedNoteCount()->u64
    {
        if .selectedTrack == Swag.U32.Max do
            return .document.notes.count
        if .selectedTrack >= .document.tracks.count do
            return 0
        return .document.tracks[.selectedTrack].noteCount
    }

    mtd summaryText()->String => Format.toString(midiStrings().ui_Summary, .document.tracks.count, .selectedNoteCount(), Viewer.durationText(.document.durationSeconds), .document.bpm(), .document.meterText(), .document.keyText())

    mtd refreshLayout()
    {
        let client = .clientRect()
        .lowKey    = cast(u8) Math.max(cast(s32) .document.minKey - 2, 0)
        .highKey   = cast(u8) Math.min(cast(s32) .document.maxKey + 2, 127)
        .plotTop   = MidiHeaderHeight + MidiAxisHeight
        .rowHeight = Math.max((client.height - .plotTop - MidiContentInset) / cast(f32) (.highKey - .lowKey + 1), 3)

        if .document.division & 0x8000
        {
            let encoded = cast(u8) (.document.division >> 8)
            .beatTicks = cast(u64) (256'u32 - encoded) * cast(u64) (.document.division & 0xFF)
        }
        else do
            .beatTicks = .document.division
        .beatTicks = Math.max(.beatTicks, 1)

        let viewport = Math.max(client.width - MidiKeyboardWidth - 2 * MidiContentInset, 1)
        let natural  = Math.max(cast(f32) .document.durationTicks / cast(f32) .beatTicks * MidiQuarterWidth, 1)
        if .fit do
            .zoom = Math.clamp(viewport / natural, MidiMinZoom, 1)
        .timelineWidth = Math.max(viewport, natural * .zoom)
        .pixelsPerTick = .timelineWidth / cast(f32) Math.max(.document.durationTicks, 1)
        .scroll.setScrollSize(MidiKeyboardWidth + 2 * MidiContentInset + .timelineWidth, 0)
        .invalidate()
        .sigZoomChanged.call(me)
    }

    mtd setTrack(index: u32)
    {
        .selectedTrack = index
        .invalidate()
    }

    mtd applyZoom(value: f32)
    {
        .fit  = false
        .zoom = Math.clamp(value, MidiMinZoom, MidiMaxZoom)
        .refreshLayout()
    }

    mtd zoomIn()  => .applyZoom(.zoom * 1.5)
    mtd zoomOut() => .applyZoom(.zoom / 1.5)

    mtd zoomToFit()
    {
        .fit = true
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
        let left   = .scrollPos.x + MidiContentInset
        let title  = Format.toString("MIDI · format %", .document.format)
        painter.drawString(left, 18, title.toString(), .titleFont, colors.label_Text)
        let summary = .summaryText()
        painter.drawString(left, 48, summary.toString(), .codeFont, colors.label_TextFaint)
        painter.drawLine(left, MidiHeaderHeight - 1, .scrollPos.x + .clientRect().width - MidiContentInset, MidiHeaderHeight - 1, colors.border, 1)
    }

    mtd paintGrid(painter: *Painter)
    {
        let colors     = .themeColors()
        let plotLeft   = MidiKeyboardWidth + MidiContentInset
        let plotRight  = plotLeft + .timelineWidth
        let plotBottom = .plotTop + cast(f32) (.highKey - .lowKey + 1) * .rowHeight

        for keyValue in cast(u32) (.highKey - .lowKey + 1)
        {
            let key = cast(u8) (cast(u32) .highKey - keyValue)
            let y   = .plotTop + cast(f32) keyValue * .rowHeight
            if midiIsBlackKey(key) do
                painter.fillRect(plotLeft, y, .timelineWidth, .rowHeight, colors.edit_Bk)
            painter.drawLine(plotLeft, y, plotRight, y, colors.border, 1)
        }

        painter.drawLine(plotLeft, plotBottom, plotRight, plotBottom, colors.border, 1)

        let beatWidth = .pixelsPerTick * cast(f32) .beatTicks
        var stride    = 1'u64
        while beatWidth * cast(f32) stride < 72 do
            stride *= 2
        let firstVisible = cast(u64) Math.max(Math.floor(Math.max(.scrollPos.x - plotLeft, 0) / beatWidth), 0)
        var beat         = firstVisible / stride * stride
        let lastBeat     = cast(u64) Math.ceil((.scrollPos.x + .clientRect().width - plotLeft) / beatWidth) + stride
        let maxBeat      = .document.durationTicks / .beatTicks + 1
        while beat < Math.min(lastBeat, maxBeat + 1)
        {
            let x = plotLeft + cast(f32) (beat * .beatTicks) * .pixelsPerTick
            painter.drawLine(x, MidiHeaderHeight, x, plotBottom, colors.border, 1)
            let label = Format.toString("%", beat + 1)
            painter.drawString(x + 5, MidiHeaderHeight + 6, label.toString(), .codeFont, colors.label_TextFaint)
            beat += stride
        }
    }

    mtd paintNotes(painter: *Painter)
    {
        let colors    = .themeColors()
        let plotLeft  = MidiKeyboardWidth + MidiContentInset
        let alternate = .theme().palette.alternate.mark

        for note in .document.notes
        {
            if .selectedTrack != Swag.U32.Max and note.track != .selectedTrack do
                continue
            let x = plotLeft + cast(f32) note.startTick * .pixelsPerTick
            if x > .scrollPos.x + .clientRect().width do
                break
            let width = Math.max(cast(f32) (note.endTick - note.startTick) * .pixelsPerTick, 2)
            if x + width < .scrollPos.x + MidiKeyboardWidth do
                continue
            let y        = .plotTop + cast(f32) (.highKey - note.key) * .rowHeight + 1
            let strength = 0.58'f32 + cast(f32) (note.track % 4) * 0.09
            let color    = Color.lerp(colors.view_Bk, alternate, strength)
            painter.fillRoundRect({x, y, width, Math.max(.rowHeight - 2, 1)}, 2, 2, color)
        }
    }

    mtd paintKeyboard(painter: *Painter)
    {
        let colors = .themeColors()
        let left   = .scrollPos.x
        painter.fillRect(left, MidiHeaderHeight, MidiKeyboardWidth + MidiContentInset, .clientRect().height - MidiHeaderHeight, colors.view_Bk)
        painter.drawString(left + MidiContentInset, MidiHeaderHeight + 6, midiStrings().ui_PianoRoll, .labelFont, colors.label_TextFaint)

        for keyValue in cast(u32) (.highKey - .lowKey + 1)
        {
            let key = cast(u8) (cast(u32) .highKey - keyValue)
            let y   = .plotTop + cast(f32) keyValue * .rowHeight
            if midiIsBlackKey(key) do
                painter.fillRect(left + MidiContentInset, y, MidiKeyboardWidth, .rowHeight, colors.edit_Bk)
            painter.drawLine(left + MidiContentInset, y, left + MidiContentInset + MidiKeyboardWidth, y, colors.border, 1)
            if key % 12 == 0 and .rowHeight >= 7
            {
                let label = midiPitchName(key)
                painter.drawString(left + MidiContentInset + 8, y + Math.max((.rowHeight - .codeFont.height) * 0.5, 0), label.toString(), .codeFont, colors.label_TextLight)
            }
        }

        painter.drawLine(left + MidiContentInset + MidiKeyboardWidth, .plotTop, left + MidiContentInset + MidiKeyboardWidth, .clientRect().height - MidiContentInset, colors.border, 1)
    }
}

impl IWnd for MidiRollView
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        discard evt
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
        else do
            evt.accepted = false
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        switch evt.key
        {
        case .Add, .OemPlus:       .zoomIn()
        case .Subtract, .OemMinus: .zoomOut()
        case .F:                   .zoomToFit()
        case .Left:                .scroll.setScrollPos(.scrollPos.x - 96, 0)
        case .Right:               .scroll.setScrollPos(.scrollPos.x + 96, 0)
        case .Home:                .scroll.setScrollPos(0, 0)
        case .End:                 .scroll.setScrollPos(.timelineWidth, 0)
        default:                   evt.accepted = false
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        painter.setParams(.Antialiased)
        .paintHeader(painter)
        .paintGrid(painter)
        if not .document.notes.isEmpty() do
            .paintNotes(painter)
        else
        {
            let colors = .themeColors()
            painter.drawString(.scrollPos.x + MidiKeyboardWidth + 2 * MidiContentInset, .plotTop + 24, midiStrings().ui_NoNotes, .codeFont, colors.label_TextFaint)
        }

        .paintKeyboard(painter)
    }
}

impl MidiRollView
{
    func create(parent: *Wnd, document: MidiDocument)->*MidiRollView
    {
        with let scroll = Wnd.create'ScrollWnd(parent, "scope.midi.scroll", {})
        {
            .dockStyle = .Center
            .updateFlags(.CompactBars | .TransparentBars)
        }

        with let result = scroll.createView'MidiRollView()
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
