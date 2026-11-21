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

    // A key or lens step scales the timeline or the pitch by a quarter and a wheel notch by an
    // eighth, as the picture and PDF views scale their canvas, so the same gesture moves every canvas
    // viewer alike.
    const ZoomStep      = 1.25'f32
    const WheelZoomStep = 1.12'f32

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

// One lane of the tracks presentation: the track, the channel it plays on, its range of keys, and
// how many of its notes there are and how many of them are percussion hits.
struct RollLane
{
    track:     u32
    channel:   u8
    lowKey:    u8 = 127
    highKey:   u8
    noteCount: u64
    hitCount:  u64
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
    laneOfTrack:    Array'u32     // Index in `lanes` of each track, or `Swag.U32.Max` for a track with no notes.
    selectedTrack:  u32      = Swag.U32.Max
    zoom:           f32      = 1
    pitchZoom:      f32      = 1
    keyboardWidth:  f32      = KeyboardWidth
    scaleHighlight: bool     = false
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

// Names the General MIDI instrument of `program`, from 0, as the standard spells it.
func instrumentName(program: u8)->string
{
    const Names: [128] string = [
        "Acoustic Grand Piano", "Bright Acoustic Piano", "Electric Grand Piano", "Honky-tonk Piano",
        "Electric Piano 1", "Electric Piano 2", "Harpsichord", "Clavinet", "Celesta", "Glockenspiel",
        "Music Box", "Vibraphone", "Marimba", "Xylophone", "Tubular Bells", "Dulcimer", "Drawbar Organ",
        "Percussive Organ", "Rock Organ", "Church Organ", "Reed Organ", "Accordion", "Harmonica",
        "Tango Accordion", "Acoustic Guitar (nylon)", "Acoustic Guitar (steel)", "Electric Guitar (jazz)",
        "Electric Guitar (clean)", "Electric Guitar (muted)", "Overdriven Guitar", "Distortion Guitar",
        "Guitar Harmonics", "Acoustic Bass", "Electric Bass (finger)", "Electric Bass (pick)",
        "Fretless Bass", "Slap Bass 1", "Slap Bass 2", "Synth Bass 1", "Synth Bass 2", "Violin", "Viola",
        "Cello", "Contrabass", "Tremolo Strings", "Pizzicato Strings", "Orchestral Harp", "Timpani",
        "String Ensemble 1", "String Ensemble 2", "Synth Strings 1", "Synth Strings 2", "Choir Aahs",
        "Voice Oohs", "Synth Voice", "Orchestra Hit", "Trumpet", "Trombone", "Tuba", "Muted Trumpet",
        "French Horn", "Brass Section", "Synth Brass 1", "Synth Brass 2", "Soprano Sax", "Alto Sax",
        "Tenor Sax", "Baritone Sax", "Oboe", "English Horn", "Bassoon", "Clarinet", "Piccolo", "Flute",
        "Recorder", "Pan Flute", "Blown Bottle", "Shakuhachi", "Whistle", "Ocarina", "Lead 1 (square)",
        "Lead 2 (sawtooth)", "Lead 3 (calliope)", "Lead 4 (chiff)", "Lead 5 (charang)", "Lead 6 (voice)",
        "Lead 7 (fifths)", "Lead 8 (bass + lead)", "Pad 1 (new age)", "Pad 2 (warm)", "Pad 3 (polysynth)",
        "Pad 4 (choir)", "Pad 5 (bowed)", "Pad 6 (metallic)", "Pad 7 (halo)", "Pad 8 (sweep)",
        "FX 1 (rain)", "FX 2 (soundtrack)", "FX 3 (crystal)", "FX 4 (atmosphere)", "FX 5 (brightness)",
        "FX 6 (goblins)", "FX 7 (echoes)", "FX 8 (sci-fi)", "Sitar", "Banjo", "Shamisen", "Koto", "Kalimba",
        "Bagpipe", "Fiddle", "Shanai", "Tinkle Bell", "Agogo", "Steel Drums", "Woodblock", "Taiko Drum",
        "Melodic Tom", "Synth Drum", "Reverse Cymbal", "Guitar Fret Noise", "Breath Noise", "Seashore",
        "Bird Tweet", "Telephone Ring", "Helicopter", "Applause", "Gunshot"]
    return Names[program & 0x7F]
}

// Names the General MIDI percussion sound a key plays on the tenth channel, or returns an empty
// string for a key the standard leaves unassigned. The names are the standard's own, as a drum
// map in any sequencer spells them.
func percussionName(key: u8)->string
{
    const FirstKey = 35'u8
    const Names: [47] string = [
        "Acoustic Bass Drum", "Bass Drum 1", "Side Stick", "Acoustic Snare", "Hand Clap",
        "Electric Snare", "Low Floor Tom", "Closed Hi-Hat", "High Floor Tom", "Pedal Hi-Hat",
        "Low Tom", "Open Hi-Hat", "Low-Mid Tom", "Hi-Mid Tom", "Crash Cymbal 1", "High Tom",
        "Ride Cymbal 1", "Chinese Cymbal", "Ride Bell", "Tambourine", "Splash Cymbal", "Cowbell",
        "Crash Cymbal 2", "Vibraslap", "Ride Cymbal 2", "Hi Bongo", "Low Bongo", "Mute Hi Conga",
        "Open Hi Conga", "Low Conga", "High Timbale", "Low Timbale", "High Agogo", "Low Agogo",
        "Cabasa", "Maracas", "Short Whistle", "Long Whistle", "Short Guiro", "Long Guiro", "Claves",
        "Hi Wood Block", "Low Wood Block", "Mute Cuica", "Open Cuica", "Mute Triangle", "Open Triangle"]
    if key < FirstKey or key >= FirstKey + Names.count do
        return ""
    return Names[key - FirstKey]
}

private func isBlackKey(key: u8)->bool
{
    let note = key % 12
    return note == 1 or note == 3 or note == 6 or note == 8 or note == 10
}

// Returns the seven pitch classes of a major key. Its relative minor has the same key signature
// and pitch classes; the event's mode remains available to the information sheet.
private func keyPitchMask(key: const *KeySignature)->u16
{
    if key.sharps < -7 or key.sharps > 7 do
        return 0

    const Tonics: [15] u8 = [11, 6, 1, 8, 3, 10, 5, 0, 7, 2, 9, 4, 11, 6, 1]
    const Steps:  [7] u8  = [0, 2, 4, 5, 7, 9, 11]
    let tonic  = Tonics[cast(u32, key.sharps + 7)]
    var result = 0'u16
    for step in Steps do
        result |= 1'u16 << ((tonic + step) % 12)
    return result
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

    // Returns the signature active at `tick`, or zero when none declares a supported key.
    mtd keyPitchMaskAt(tick: u64)->u16
    {
        var first = 0'u64
        var last  = .document.keySignatures.count
        while first < last
        {
            let middle = first + (last - first) / 2
            if .document.keySignatures[middle].tick <= tick do
                first = middle + 1
            else do
                last = middle
        }

        if not first do
            return 0
        return keyPitchMask(&.document.keySignatures[first - 1])
    }

    // Percussion hits are not pitches. The keyboard uses the signature at the first visible tick;
    // the note rows change tint at each signature event.
    mtd scaleHighlightMaskAt(tick: u64)->u16
    {
        if not .scaleHighlight or .mode != .Pitches or .showsPercussion() do
            return 0
        return .keyPitchMaskAt(tick)
    }

    mtd pitchIsHighlighted(tick: u64, key: u8)->bool => cast(bool, .scaleHighlightMaskAt(tick) & (1'u16 << (key % 12)))

    mtd setScaleHighlight(enabled: bool)
    {
        .scaleHighlight = enabled
        .invalidate()
    }

    mtd visibleFirstTick(plotLeft: f32)->u64
    {
        if not .pixelsPerTick do
            return 0
        return cast(u64, Math.max(Math.floor(Math.max(.scrollPos.x - plotLeft, 0) / .pixelsPerTick), 0))
    }

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
    // plays on, its range of keys and its counts of notes.
    //
    // The lanes depend on the document alone, so they are gathered once when the roll is created:
    // walking every note again on each resize or zoom would cost a score of a million notes as
    // much as its loading did.
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
            range.lowKey    = Math.min(range.lowKey, note.key)
            range.highKey   = Math.max(range.highKey, note.key)
            range.noteCount += 1
            if note.isHit() do
                range.hitCount += 1
        }

        .lanes.clear()
        .laneOfTrack.clear()
        .laneOfTrack.reserve(ranges.count)
        for range in ranges
        {
            if range.lowKey > range.highKey
            {
                .laneOfTrack.add(Swag.U32.Max)
                continue
            }

            .laneOfTrack.add(cast(u32, .lanes.count))
            .lanes.add(range)
        }
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

        // The rows span the keys of the notes shown: a chosen track has its own range, so a drum
        // track fills the view rather than a sliver of the range of the whole piece.
        var low  = .document.minKey
        var high = .document.maxKey
        for lane in .lanes where lane.track == .selectedTrack and lane.lowKey <= lane.highKey
        {
            low  = lane.lowKey
            high = lane.highKey
        }

        .lowKey  = cast(u8, Math.max(cast(s32, low) - 2, 0))
        .highKey = cast(u8, Math.min(cast(s32, high) + 2, 127))
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
        .refreshLayout()
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

    // Reports whether every note the roll shows is a percussion hit, so its keys name drums rather
    // than pitches. A selected drum track does; all tracks do only when the piece holds nothing else.
    mtd showsPercussion()->bool
    {
        var notes, hits: u64
        for lane in .lanes where .selectedTrack == Swag.U32.Max or lane.track == .selectedTrack
        {
            notes += lane.noteCount
            hits  += lane.hitCount
        }

        return notes and hits == notes
    }

    mtd applyZoom(value: f32)
    {
        .fit  = false
        .zoom = Math.clamp(value, MinZoom, MaxZoom)
        .refreshLayout()
    }

    // Zooms to `target`, one step from the scale shown, unless the step heads past a limit the
    // timeline already stands at. A step that changes nothing must leave the fit alone, or a score
    // fitted at the smallest zoom would stop following the window.
    mtd stepZoom(target: f32)
    {
        if target > .zoom ? .canZoomIn() : .canZoomOut() do
            .applyZoom(target)
    }

    mtd zoomIn()  => .stepZoom(.zoom * ZoomStep)
    mtd zoomOut() => .stepZoom(.zoom / ZoomStep)

    // Report whether a zoom step still widens or narrows the timeline, so the commands that take
    // one can read as unavailable at the limits instead of doing nothing.
    mtd canZoomIn()  => .zoom < MaxZoom
    mtd canZoomOut() => .zoom > MinZoom

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

        // The notes are sorted by start, so one pass over them all, whatever their lane, begins at
        // the first one that can reach the left edge and stops at the first one past the right
        // edge. The lanes stand apart, so the order they are painted in does not show.
        let leftEdge = .scrollPos.x + left
        let right    = .scrollPos.x + .clientRect().width
        for noteIndex in .firstNoteReaching(left, leftEdge, NoteHeight) until .document.notes.count
        {
            let note = &.document.notes[noteIndex]
            if note.track >= .laneOfTrack.count do
                continue
            let x = left + cast(f32, note.startTick) * .pixelsPerTick
            if x > right do
                break
            let width = note.isHit() ? NoteHeight : Math.max(cast(f32, note.endTick - note.startTick) * .pixelsPerTick, 2)
            if x + width < leftEdge do
                continue

            let index  = cast(u64, .laneOfTrack[note.track])
            let lane   = &.lanes[index]
            let band   = .laneRect(index)
            let range  = Math.max(cast(f32, lane.highKey - lane.lowKey), 1)
            let spread = Math.max(band.height - 2 * LanePadding - NoteHeight, 0)
            var color  = colors.series[index % colors.series.count]
            if .selectedTrack != Swag.U32.Max and .selectedTrack != lane.track do
                color = Color.lerp(colors.ground, color, 0.35)
            let y = band.y + LanePadding + (cast(f32, lane.highKey - note.key) / range) * spread
            painter.fillRoundRect(Math.Rectangle{x, y, width, NoteHeight}, NoteHeight * 0.5, NoteHeight * 0.5, color)
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
        }

        .paintScaleBands(painter, plotLeft, plotRight)

        for row in .keyCount()
        {
            let y = .plotTop + cast(f32, row) * .rowHeight
            painter.drawLine(plotLeft, y, plotRight, y, colors.line, 1)
        }

        painter.drawLine(plotLeft, plotBottom, plotRight, plotBottom, colors.line, 1)

        .paintBeats(painter, .plotTop, plotBottom, false)
    }

    // Tints in-scale key rows in bounded horizontal bands. A key change starts a new band, so a
    // long score does not need a precomputed per-tick scale map.
    mtd paintScaleBands(painter: *Painter, plotLeft, plotRight: f32)
    {
        if not .scaleHighlight or .mode != .Pitches or .showsPercussion() do
            return
        if not .pixelsPerTick or not .document.keySignatures.count do
            return

        let visibleLeft  = Math.max(plotLeft, .scrollPos.x)
        let visibleRight = Math.min(plotRight, .scrollPos.x + .clientRect().width)
        if visibleRight <= visibleLeft do
            return

        let firstTick = .visibleFirstTick(plotLeft)
        let lastTick  = cast(u64, Math.min(Math.ceil((visibleRight - plotLeft) / .pixelsPerTick), cast(f64, .document.durationTicks)))
        if lastTick <= firstTick do
            return

        var signatureAt = 0'u64
        var after       = .document.keySignatures.count
        while signatureAt < after
        {
            let middle = signatureAt + (after - signatureAt) / 2
            if .document.keySignatures[middle].tick <= firstTick do
                signatureAt = middle + 1
            else do
                after = middle
        }

        var mask = signatureAt ? keyPitchMask(&.document.keySignatures[signatureAt - 1]) : 0'u16
        var tick = firstTick
        while tick < lastTick
        {
            let nextTick = signatureAt < .document.keySignatures.count ?
                           Math.min(lastTick, .document.keySignatures[signatureAt].tick) : lastTick
            if nextTick <= tick
            {
                mask        = keyPitchMask(&.document.keySignatures[signatureAt])
                signatureAt += 1
                continue
            }

            let left  = Math.max(visibleLeft, plotLeft + cast(f32, tick) * .pixelsPerTick)
            let right = Math.min(visibleRight, plotLeft + cast(f32, nextTick) * .pixelsPerTick)
            .paintScaleMask(painter, mask, left, right - left)
            tick = nextTick
            if signatureAt < .document.keySignatures.count and .document.keySignatures[signatureAt].tick == tick
            {
                mask        = keyPitchMask(&.document.keySignatures[signatureAt])
                signatureAt += 1
            }
        }
    }

    mtd paintScaleMask(painter: *Painter, mask: u16, left, width: f32)
    {
        if mask == 0 or width <= 0 do
            return

        let colors = .themeColors()
        for row in .keyCount()
        {
            let key = .keyAtRow(row)
            if mask & (1'u16 << (key % 12)) == 0 do
                continue
            let y    = .plotTop + cast(f32, row) * .rowHeight
            let base = isBlackKey(key) ? colors.edit_Bk : colors.view_Bk
            painter.fillRect(Math.Rectangle{left, y, width, .rowHeight}, Color.lerp(base, colors.highlight, 0.35))
        }
    }

    // Paints the numbered beat lines from `top` to `bottom`, with their numbers when `numbered`.
    // The beats are thinned until two numbers stand far enough apart to read.
    mtd paintBeats(painter: *Painter, top, bottom: f32, numbered: bool)
    {
        let colors    = .themeColors()
        let plotLeft  = .keyboardWidth + ContentInset
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
            painter.drawLine(x, top, x, bottom, colors.line, 1)
            if numbered do
                painter.drawString(x + 5, top + 6, Format.toString("%", beat + 1), .codeFont, colors.label_TextFaint)
            beat += stride
        }
    }

    // Paints the band under the header that names the roll and numbers the beats. It stays at the
    // top of the view as the keys scroll under it, as the header does.
    mtd paintAxis(painter: *Painter)
    {
        let colors = .themeColors()
        let top    = .scrollPos.y + HeaderHeight
        painter.fillRect(.scrollPos.x, top, .clientRect().width, AxisHeight, colors.view_Bk)
        .paintBeats(painter, top, top + AxisHeight, true)
        painter.fillRect(.scrollPos.x, top, .keyboardWidth + ContentInset, AxisHeight, colors.view_Bk)
        painter.drawString(.scrollPos.x + ContentInset, top + 6, texts().ui_PianoRoll, .labelFont, colors.label_TextFaint)
    }

    // Returns the index of the first note that can reach `edge` when the notes start at `left` and
    // a hit is drawn `hitWidth` wide. The notes are sorted by start, and none is wider than the
    // longest one or a hit, so a note that starts that far left of the edge ends before it, as
    // does every note before it.
    mtd firstNoteReaching(left, edge, hitWidth: f32)->u64
    {
        let widest = Math.max(cast(f32, .document.longestNote) * .pixelsPerTick, 2, hitWidth)
        var first  = 0'u64
        var last   = .document.notes.count
        while first < last
        {
            let middle = first + (last - first) / 2
            if left + cast(f32, .document.notes[middle].startTick) * .pixelsPerTick + widest < edge do
                first = middle + 1
            else do
                last = middle
        }

        return first
    }

    // Paints the visible notes of the selected track, or of every track, shading each track
    // differently. Notes are sorted by start, so painting begins at the first one that can reach
    // the left edge and stops at the first one past the right edge.
    mtd paintNotes(painter: *Painter)
    {
        let colors    = .themeColors()
        let plotLeft  = .keyboardWidth + ContentInset
        let alternate = .theme().palette.alternate.mark
        let height    = Math.max(.rowHeight - 2, 1)
        let leftEdge  = .scrollPos.x + .keyboardWidth

        for index in .firstNoteReaching(plotLeft, leftEdge, height) until .document.notes.count
        {
            let note = &.document.notes[index]
            if .selectedTrack != Swag.U32.Max and note.track != .selectedTrack do
                continue
            let x = plotLeft + cast(f32, note.startTick) * .pixelsPerTick
            if x > .scrollPos.x + .clientRect().width do
                break
            let width = note.isHit() ? height : Math.max(cast(f32, note.endTick - note.startTick) * .pixelsPerTick, 2)
            if x + width < leftEdge do
                continue
            let y        = .plotTop + cast(f32, .highKey - note.key) * .rowHeight + 1
            let strength = 0.58'f32 + cast(f32, note.track % 4) * 0.09
            let color    = Color.lerp(colors.view_Bk, alternate, strength)
            painter.fillRoundRect(Math.Rectangle{x, y, width, height}, 2, 2, color)
        }
    }

    // Paints the keyboard column pinned to the left of the scrolled view, shading black keys and
    // labelling each C when rows are tall enough. Over drums, every row tall enough for a line of
    // text names the sound its key plays, cut to the keyboard's width.
    mtd paintKeyboard(painter: *Painter)
    {
        let colors     = .themeColors()
        let left       = .scrollPos.x
        let percussion = .showsPercussion()
        let drumFont   = .theme().createDefaultFont(11)
        painter.fillRect(left, .scrollPos.y + HeaderHeight, .keyboardWidth + ContentInset, .clientRect().height - HeaderHeight, colors.view_Bk)

        for row in .keyCount()
        {
            let key = .keyAtRow(row)
            let y   = .plotTop + cast(f32, row) * .rowHeight
            if isBlackKey(key) do
                painter.fillRect(left + ContentInset, y, .keyboardWidth, .rowHeight, colors.edit_Bk)
            if .scaleHighlightMaskAt(.visibleFirstTick(.keyboardWidth + ContentInset)) & (1'u16 << (key % 12)) != 0
            {
                let base = isBlackKey(key) ? colors.edit_Bk : colors.view_Bk
                painter.fillRect(left + ContentInset, y, .keyboardWidth, .rowHeight, Color.lerp(base, colors.highlight, 0.35))
            }

            painter.drawLine(left + ContentInset, y, left + ContentInset + .keyboardWidth, y, colors.line, 1)
            let labelTop = y + Math.max((.rowHeight - .codeFont.height) * 0.5, 0)
            if percussion
            {
                let name = percussionName(key)
                if name.count and .rowHeight >= drumFont.height
                {
                    let label = Painter.elideString(name, drumFont, .keyboardWidth - 12, .deviceScale())
                    painter.drawString(left + ContentInset + 6, y + Math.max((.rowHeight - drumFont.height) * 0.5, 0), label, drumFont, colors.label_TextLight)
                }

                continue
            }

            let showLabel = .pitchLabelMode == .MidiNumber ? .rowHeight >= 14 : key % 12 == 0 and .rowHeight >= 7
            if showLabel
            {
                let label = .pitchLabel(key)
                painter.drawString(left + ContentInset + 8, labelTop, label, .codeFont, colors.label_TextLight)
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

        if evt.modifiers == (.Control | .Shift)
        {
            switch evt.key
            {
            case .Add, .OemPlus:       .applyPitchZoom(.pitchZoom * ZoomStep)
            case .Subtract, .OemMinus: .applyPitchZoom(.pitchZoom / ZoomStep)
            default: evt.accepted = false
            }

            return
        }

        switch evt.key
        {
        case .Add, .OemPlus where evt.modifiers == .Control:       .zoomIn()
        case .Subtract, .OemMinus where evt.modifiers == .Control: .zoomOut()
        case .D0 where evt.modifiers == .Control:                  .applyZoom(1)
        case .PageUp:                                              .scroll.setScrollPos(.scrollPos.x, .scrollPos.y - .clientRect().height)
        case .PageDown:                                            .scroll.setScrollPos(.scrollPos.x, .scrollPos.y + .clientRect().height)
        case .F:                                                   .zoomToFit()
        case .Left:                                                .scroll.setScrollPos(.scrollPos.x - 96, .scrollPos.y)
        case .Right:                                               .scroll.setScrollPos(.scrollPos.x + 96, .scrollPos.y)
        case .Home:                                                .scroll.setScrollPos(0, .scrollPos.y)
        case .End:                                                 .scroll.setScrollPos(.timelineWidth, .scrollPos.y)
        default:                                                   evt.accepted = false
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .Wheel and evt.modifiers == .Control
        {
            if evt.delta.y > 0 do
                .stepZoom(.zoom * WheelZoomStep)
            elif evt.delta.y < 0 do
                .stepZoom(.zoom / WheelZoomStep)
            return
        }

        if evt.kind == .Wheel and evt.modifiers == (.Control | .Shift)
        {
            if evt.delta.y > 0 do
                .applyPitchZoom(.pitchZoom * WheelZoomStep)
            elif evt.delta.y < 0 do
                .applyPitchZoom(.pitchZoom / WheelZoomStep)
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
        .paintAxis(painter)
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
            .collectLanes()
            .refreshFonts()
            .refreshLayout()
        }

        return result
    }
}
