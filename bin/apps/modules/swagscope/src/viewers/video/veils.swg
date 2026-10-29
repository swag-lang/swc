#global internal
#global namespace Viewers.Film

using Core, Pixel, Gui

// The veils are drawn over the picture, which is dark whatever palette the window wears: their
// ground is black fading out, their words white, so they read the same on Encre and on Papier.
private
{
    const VeilInk:      Color = 0xFFFFFFFF     // Words and glyphs written on a veil.
    const VeilSoftInk:  Color = 0x99FFFFFF     // What a veil writes second: a length, a fact.
    const VeilTrack:    Color = 0x38FFFFFF     // The part of the timeline still to come.
    const VeilBuffered: Color = 0x66FFFFFF     // The part of the timeline already read.
    const VeilTick:     Color = 0x99FFFFFF     // The mark of a chapter on the timeline.
    // A chip's ground and words, at rest, under the pointer, pressed.
    const ChipColors       = "btnIcon_Bk 0x24FFFFFF\nbtnIcon_HotBk 0x3DFFFFFF\nbtnIcon_PressedBk 0x52FFFFFF\nbtnIcon_Text 0xFFFFFFFF\nbtnIcon_HotText 0xFFFFFFFF\nbtnIcon_PressedText 0xFFFFFFFF"
    const VeilTipBk: Color = 0xE0101114     // Ground of the time read under the pointer.
    const VeilShade: Color = 0xB8000000     // Darkest end of a veil's shade.
    const VeilClear: Color = 0x00000000     // Clear end of a veil's shade.
}

// Measures of the veils, after `scope.video`.
const VeilInset      = 28.0       // Air between a veil's words and the edges of the window.
const TopVeilHeight  = 120.0      // Height of the top veil's shade.
const TitleY         = 32.0       // Centre of the title's line, from the top of the window.
const TitleX         = 52.0       // Where the title starts: after the glyph of the application, which the strip keeps.
const TitleSize      = 16'u32     // Size of the title.
const FactsGap       = 14.0       // Air between the title and the facts after it.
const BottomHeight   = 140.0      // Height of the bottom veil's shade.
const TimelineBottom = 83.0       // Distance from the bottom of the window to the timeline's centre.
const TimelineHeight = 24.0       // Height the timeline takes for the pointer.
const RowBottom      = 38.0       // Distance from the bottom of the window to the centre of the row.
const RowGap         = 12.0       // Air between two parts of the row.
const ChipHeight     = 24.0       // Height of a chip.
const ChipPadding    = 10.0       // Air at each end of a chip's words.
const TrackSize      = 3.0        // Thickness of the timeline.
const KnobSize       = 14.0       // Diameter of the timeline's knob.
const KnobInset      = KnobSize * 0.5 + 1     // Room for the knob and its outline at either endpoint.
const TickHeight     = 9.0        // Height of a chapter mark.
const TipGap         = 16.0       // Air between the timeline and the time read under the pointer.

// Fills `rect` with a veil's shade, from `dark` at the edge it stands against to clear inside.
private func paintShade(painter: *Painter, rect: Math.Rectangle, fromTop: bool)
{
    let top    = fromTop ? VeilShade : VeilClear
    let bottom = fromTop ? VeilClear : VeilShade
    painter.fillRect(rect, Brush.createLinearGradient(rect.x, rect.y, rect.x, rect.bottom(), top, bottom))
}

/*
The timeline of a film, as the bottom veil draws it.

The part to come is a faint track, the part already read is lighter, the part played is Arc, and
a white knob stands at the play position. A chapter is a short mark across the track. Under the
pointer, the time it points at reads in mono in a dark tip above the track. A press moves the knob
there and a drag follows it; the film seeks once the hand lets go.
*/
struct VideoTimeline
{
    using wnd: Wnd

    sigStartChange: SigArray'func||(*VideoTimeline)     // Emitted when a press starts moving the knob.
    sigEndChange:   SigArray'func||(*VideoTimeline)     // Emitted when the knob is let go, or set by a call.

    minimum:  f32
    maximum:  f32 = 1
    current:  f32
    buffered: f32 = -1      // Position read so far, or a negative value when unknown.
    chapters: Array'f32     // Start of each chapter.
    pointerX: f32 = -1      // Where the pointer stands over the timeline, or a negative value.
    dragging: bool
}

impl VideoTimeline
{
    // The knob and its outline stay inside the timeline's paint bounds, even at either endpoint.
    private mtd trackRoom()->Math.Rectangle
    {
        var room  = .clientRect()
        let inset = Math.min(KnobInset, room.width * 0.5)
        room.x     += inset
        room.width = Math.max(room.width - 2 * inset, 0)
        return room
    }

    // Sets the range of the timeline; the step is accepted for the slider it replaces.
    mtd setBounds(minimum, maximum, _: f32)
    {
        .minimum = minimum
        .maximum = Math.max(maximum, minimum)
        .invalidate()
    }

    mtd value()->f32 => .current

    // Moves the knob without telling anyone, as the clock does while the film plays.
    mtd setValueWithoutGesture(value: f32)
    {
        if .dragging do
            return
        .current = Math.clamp(value, .minimum, .maximum)
        .invalidate()
    }

    // Moves the knob as a hand would, and tells who listens that it was let go there.
    mtd setValue(value: f32)
    {
        .current = Math.clamp(value, .minimum, .maximum)
        .invalidate()
        .sigEndChange.call(me)
    }

    // Says how far the film has been read, so the timeline can show it apart from what is to come.
    mtd setBuffered(value: f32)
    {
        if .buffered == value do
            return
        .buffered = value
        .invalidate()
    }

    // Returns where `value` stands across the timeline.
    mtd positionOf(value: f32)->f32
    {
        let room = .trackRoom()
        let span = Math.max(.maximum - .minimum, 0.0001)
        return room.x + room.width * Math.clamp((value - .minimum) / span, 0, 1)
    }

    // Returns the value at the horizontal position `x`.
    mtd valueAt(x: f32)->f32
    {
        let room = .trackRoom()
        return .minimum + (.maximum - .minimum) * Math.clamp((x - room.x) / Math.max(room.width, 1), 0, 1)
    }
}

impl IWnd for VideoTimeline
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let room    = .clientRect()
        let rail    = .trackRoom()
        let centerY = room.vertCenter()
        let track   = Math.Rectangle{rail.x, centerY - TrackSize * 0.5, rail.width, TrackSize}

        painter.setParams(.Antialiased)
        painter.fillRoundRect(track, TrackSize * 0.5, TrackSize * 0.5, VeilTrack)
        if .buffered >= .minimum
        {
            let right = .positionOf(.buffered)
            painter.fillRoundRect(Math.Rectangle{track.x, track.y, right - track.x, TrackSize}, TrackSize * 0.5, TrackSize * 0.5, VeilBuffered)
        }

        let knobX = .positionOf(.current)
        painter.fillRoundRect(Math.Rectangle{track.x, track.y, knobX - track.x, TrackSize}, TrackSize * 0.5, TrackSize * 0.5, .themeColors().arc)

        for chapter in .chapters
        {
            let x = Math.round(.positionOf(chapter))
            painter.fillRect(Math.Rectangle{x, centerY - TickHeight * 0.5, 1, TickHeight}, VeilTick)
        }

        painter.fillCircle(knobX, centerY, KnobSize * 0.5 + 1, VeilShade)
        painter.fillCircle(knobX, centerY, KnobSize * 0.5, VeilInk)
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let x = .surfaceToLocal(evt.surfacePos).x
        switch evt.kind
        {
        case .Pressed where evt.button == .Left and .isEnabled():
            .dragging = true
            .captureMouse()
            .current = .valueAt(x)
            .sigStartChange.call(me)
            .invalidate()

        case .Move:
            .pointerX = x
            if .dragging do
                .current = .valueAt(x)
            .parent?.invalidate()

        case .Released where .dragging:
            .dragging = false
            .releaseMouse()
            .current = .valueAt(x)
            .invalidate()
            .sigEndChange.call(me)

        case .Leave:
            .pointerX = -1
            .parent?.invalidate()

        default:
            evt.accepted = false
        }
    }
}

// Creates a chip of the bottom veil: a choice of the film named in a word or two, on a faint
// ground. Its words are written with [[Gui.IconButton.setQuietText]], which fits it to them; a
// press opens the page of the options it names, joined to it.
func createChip(parent: *Wnd, id: WndId)->*IconButton
{
    with let result = IconButton.create(parent, {}, Math.Rectangle{0, 0, 0, ChipHeight}, id, flags: .CenterContent)
    {
        .setForm(.RoundedRectangle)
        .setTextPosition(.Right)
        .padding = Math.Vector4{ChipPadding, 0, ChipPadding, 0}
        .style.addStyleSheetColors(ChipColors)
        .style.setFont(parent.theme().createDefaultFont(parent.themeMetrics().defaultFontSize - 1), .Regular)
    }

    return result
}

/*
The veil at the top of the picture: the name of the film and its facts in mono, on a shade that
keeps them legible over any picture.
*/
struct TopVeil
{
    using wnd: Wnd

    title: String
    facts: String
}

impl IWnd for TopVeil
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let room    = .clientRect()
        paintShade(painter, room, fromTop: true)

        let title = .theme().createDefaultFont(TitleSize, .Bold)
        let mono  = .theme().createDefaultFontFs(.themeMetrics().defaultFixedFontSize - 1)
        painter.drawString(room.x + TitleX, title.opticalLineTop(room.y + TitleY), .title, title, VeilInk)
        let x = room.x + TitleX + Painter.measureString(.title, title).width + FactsGap
        painter.drawString(x, mono.opticalLineTop(room.y + TitleY), .facts, mono, VeilSoftInk)
    }
}

/*
The veil at the bottom of the picture: the timeline, then a row of the play button, the time in
mono and the chapter on the left, and on the right the chips of the subtitles, the sound track
and the speed, the sound and full screen.
*/
struct BottomVeil
{
    using wnd: Wnd

    late
    {
        timeline:         *VideoTimeline
        playButton:       *IconButton
        subtitleChip:     *IconButton
        audioChip:        *IconButton
        speedChip:        *IconButton
        muteButton:       *IconButton
        fullScreenButton: *IconButton
    }

    elapsed: String     // Time played, written first and strong.
    length:  String     // Length of the film, written after it.
    chapter: String     // The chapter played, or empty.
}

impl BottomVeil
{
    // Creates a glyph button of the row, its glyph white over the veil.
    private func createGlyph(parent: *Wnd, icon: ThemeIcons, id: WndId, flags = IconButtonFlags.None)->*IconButton
    {
        let metrics = parent.themeMetrics()
        let size    = themeActionButtonSize(metrics)
        let glyph   = parent.theme().icon(icon, themeActionIconSize(metrics))
        let button  = IconButton.create(parent, glyph, Math.Rectangle{0, 0, size, size}, id, flags: flags | .Flat)
        button.setIconColor(VeilInk)
        return button
    }

    func create(parent: *Wnd)->*BottomVeil
    {
        with let result = Wnd.create'BottomVeil(parent, "scope.video.controls", Math.Rectangle{0, 0, 0, BottomHeight})
        {
            .backgroundStyle = .Transparent
            .wndFlags        |= .TopMost
        }

        result.timeline         = Wnd.create'VideoTimeline(result, "scope.video.timeline", Math.Rectangle{0, 0, 0, TimelineHeight})
        result.playButton       = createGlyph(result, .Play, "scope.video.play")
        result.subtitleChip     = createChip(result, "scope.video.subtitles")
        result.audioChip        = createChip(result, "scope.video.audio")
        result.speedChip        = createChip(result, "scope.video.speed")
        result.muteButton       = createGlyph(result, .Volume, "scope.video.mute", .Toggle)
        result.fullScreenButton = createGlyph(result, .FullScreen, "scope.video.fullScreen")
        result.muteButton.setCheckIndicator(.Ink)
        return result
    }

    // Returns the time the row writes: played, then the length.
    mtd timeText()->String => Format.toString("% / %", .elapsed, .length)

    // Writes the time of the row.
    mtd setTime(elapsed, length: string)
    {
        if .elapsed == elapsed and .length == length do
            return
        .elapsed = elapsed
        .length  = length
        .invalidate()
    }

    // Places the timeline across the veil and the parts of the row along its line.
    mtd arrange()
    {
        let room  = .clientRect()
        let width = Math.max(room.width - 2 * VeilInset, 1)
        let lineY = room.bottom() - RowBottom
        let glyph = .playButton.position.width
        .timeline.setPosition(Math.Rectangle{room.x + VeilInset - KnobInset,
                                             room.bottom() - TimelineBottom - TimelineHeight * 0.5,
                                             width + 2 * KnobInset,
                                             TimelineHeight})
        .playButton.setPosition(Math.Rectangle{room.x + VeilInset - glyph * 0.25, lineY - glyph * 0.5, glyph, glyph})

        // The right end of the row reads from the edge inwards: full screen, the sound, then the chips.
        var right = room.right() - VeilInset + glyph * 0.25
        for button in [.fullScreenButton, .muteButton]
        {
            right -= glyph
            button.setPosition(Math.Rectangle{right, lineY - glyph * 0.5, glyph, glyph})
            right -= RowGap * 0.5
        }

        right -= RowGap
        for chip in [.speedChip, .audioChip, .subtitleChip] where chip.isLocallyVisible()
        {
            right -= chip.position.width
            chip.setPosition(Math.Rectangle{right, lineY - ChipHeight * 0.5, chip.position.width, ChipHeight})
            right -= RowGap
        }
    }
}

impl IWnd for BottomVeil
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .fullScreenButton != null do
            .arrange()
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let room    = .clientRect()
        paintShade(painter, room, fromTop: false)

        let metrics = .themeMetrics()
        let mono    = .theme().createDefaultFontFs(metrics.defaultFixedFontSize)
        let strong  = .theme().createDefaultFontFs(metrics.defaultFixedFontSize, .Bold)
        let words   = .theme().createDefaultFont(metrics.defaultFontSize)
        let lineY   = room.bottom() - RowBottom

        var x = .playButton.position.right() + RowGap
        painter.drawString(x, strong.opticalLineTop(lineY), .elapsed, strong, VeilInk)
        x += Painter.measureString(.elapsed, strong).width
        let length = Format.toString(" / %", .length)
        painter.drawString(x, mono.opticalLineTop(lineY), length, mono, VeilSoftInk)
        x += Painter.measureString(length, mono).width + 2 * RowGap
        if not .chapter.isEmpty() do
            painter.drawString(x, words.opticalLineTop(lineY), .chapter, words, VeilSoftInk)

        // The time under the pointer reads in a dark tip above the timeline.
        let timeline = .timeline
        if timeline.pointerX >= 0 and timeline.maximum > timeline.minimum
        {
            let text   = Viewer.timeText(timeline.valueAt(timeline.pointerX))
            let width  = Painter.measureString(text, mono).width + 2 * 8
            let height = mono.height + 8
            let center = timeline.position.x + timeline.pointerX
            let tip    = Math.Rectangle{Math.round(Math.clamp(center - width * 0.5, room.x, room.right() - width)), timeline.position.vertCenter() - TipGap - height, width, height}
            painter.setParams(.Antialiased)
            painter.fillRoundRect(tip, metrics.corner_Chip, metrics.corner_Chip, VeilTipBk)
            painter.drawString(tip.x + 8, mono.opticalLineTop(tip.vertCenter()), text, mono, VeilInk)
        }
    }
}
