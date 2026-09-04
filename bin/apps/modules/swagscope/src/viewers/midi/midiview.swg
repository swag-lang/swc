#global internal

using Core, Pixel, Gui

private const MidiHeaderHeight  = 76.0
private const MidiAxisHeight    = 28.0
private const MidiKeyboardWidth = 72.0
private const MidiContentInset  = 24.0
private const MidiQuarterWidth  = 64.0
private const MidiMinZoom       = 0.01'f32
private const MidiMaxZoom       = 16.0'f32

internal struct MidiRollView
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
    zoom                 = 1'f32
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

private func midiViewKeyName(value: s32)->string
{
    switch value
    {
    case -7: return "C-flat"
    case -6: return "G-flat"
    case -5: return "D-flat"
    case -4: return "A-flat"
    case -3: return "E-flat"
    case -2: return "B-flat"
    case -1: return "F"
    case 0:  return "C"
    case 1:  return "G"
    case 2:  return "D"
    case 3:  return "A"
    case 4:  return "E"
    case 5:  return "B"
    case 6:  return "F-sharp"
    case 7:  return "C-sharp"
    }

    return "?"
}

private func midiPitchName(key: u8)->String
{
    var name: string = "B"
    switch key % 12
    {
    case 0:  name = "C"
    case 1:  name = "C#"
    case 2:  name = "D"
    case 3:  name = "D#"
    case 4:  name = "E"
    case 5:  name = "F"
    case 6:  name = "F#"
    case 7:  name = "G"
    case 8:  name = "G#"
    case 9:  name = "A"
    case 10: name = "A#"
    case 11: name = "B"
    }

    var result = String.from(name)
    let octave = Format.toString("%", cast(s32) key / 12 - 1)
    result.append(octave.toString())
    return result
}

private func midiIsBlackKey(key: u8)->bool
{
    let note = key % 12
    return note == 1 or note == 3 or note == 6 or note == 8 or note == 10
}

internal func midiMeterText(document: const *MidiDocument)->String
{
    if document.timeSignatures.count
    {
        let meter = &document.timeSignatures[0]
        return Format.toString("%/%", meter.numerator, meter.denominator)
    }

    return String.from("4/4")
}

internal func midiKeyText(document: const *MidiDocument)->String
{
    if !document.keySignatures.count do
        return Format.toString("C %", midiStrings().ui_Major)
    let key = &document.keySignatures[0]
    return Format.toString("% %", midiViewKeyName(key.sharps), key.minor ? midiStrings().ui_Minor : midiStrings().ui_Major)
}

internal func midiBpm(document: const *MidiDocument)->u32
{
    if !document.tempos.count or !document.tempos[0].microsPerQuarter do
        return 120
    return 60_000_000'u32 / document.tempos[0].microsPerQuarter
}

internal impl MidiRollView
{
    mtd selectedNoteCount()->u64
    {
        if .selectedTrack == Swag.U32.Max do
            return .document.notes.count
        if .selectedTrack >= .document.tracks.count do
            return 0
        return .document.tracks[.selectedTrack].noteCount
    }

    mtd summaryText()->String
    {
        return Format.toString(midiStrings().ui_Summary,
                               .document.tracks.count,
                               .selectedNoteCount(),
                               Viewer.durationText(.document.durationSeconds),
                               midiBpm(&.document),
                               midiMeterText(&.document),
                               midiKeyText(&.document))
    }

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

internal impl IWnd for MidiRollView
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
            .titleFont = .theme().createDefaultFont(24, .Bold)
            .labelFont = .theme().createDefaultFont(11, .Bold)
            .codeFont  = .theme().createDefaultFontFS(11)
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
        if .document.notes.count do
            .paintNotes(painter)
        else
        {
            let colors = .themeColors()
            painter.drawString(.scrollPos.x + MidiKeyboardWidth + 2 * MidiContentInset, .plotTop + 24, midiStrings().ui_NoNotes, .codeFont, colors.label_TextFaint)
        }

        .paintKeyboard(painter)
    }
}

internal impl MidiRollView
{
    func create(parent: *Wnd, document: MidiDocument)->*MidiRollView
    {
        let scroll = Wnd.create'ScrollWnd(parent, "scope.midi.scroll", {})
        scroll.dockStyle = .Center
        scroll.updateFlags(.CompactBars | .TransparentBars)

        let result = scroll.createView'MidiRollView()
        result.scroll          = scroll
        result.document        = #move document
        result.backgroundStyle = .View
        result.focusPolicy     = .Tab
        result.wndFlags        |= WndFlags.NoFocusRing
        result.titleFont       = result.theme().createDefaultFont(24, .Bold)
        result.labelFont       = result.theme().createDefaultFont(11, .Bold)
        result.codeFont        = result.theme().createDefaultFontFS(11)
        result.refreshLayout()
        return result
    }
}
