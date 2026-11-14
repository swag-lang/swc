#global internal
#global namespace Viewers.Film

using Core, Pixel, Gui

// The timeline and controls follow the host's palette and bottom action panel.
private const VeilInk:   Color = 0xFFFFFFFF
private const VeilTipBk: Color = 0xE0101114

// Geometry of the shared two-row media panel.
const VeilInset      = 12.0     // Air between a veil's words and the edges of the window.
const BottomHeight   = 72.0     // Height of the bottom veil's shade.
const TimelineBottom = 56.0     // Distance from the bottom of the window to the timeline's centre.
const TimelineHeight = 24.0     // Height the timeline takes for the pointer.
const RowBottom      = 18.0     // Distance from the bottom of the window to the centre of the row.
const RowGap         = 12.0     // Air between two parts of the row.
const TrackSize      = 3.0      // Thickness of the timeline.
const KnobSize       = 14.0     // Diameter of the timeline's knob.
const VolumeWidth    = 88.0
const KnobInset      = KnobSize * 0.5 + 1     // Room for the knob and its outline at either endpoint.
const TickHeight     = 9.0      // Height of a chapter mark.
const TipGap         = 16.0     // Air between the timeline and the time read under the pointer.

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
        painter.fillRoundRect(track, TrackSize * 0.5, TrackSize * 0.5, .themeColors().line)
        if .buffered >= .minimum
        {
            let right = .positionOf(.buffered)
            painter.fillRoundRect(Math.Rectangle{track.x, track.y, right - track.x, TrackSize}, TrackSize * 0.5, TrackSize * 0.5, .themeColors().softText)
        }

        let knobX = .positionOf(.current)
        painter.fillRoundRect(Math.Rectangle{track.x, track.y, knobX - track.x, TrackSize}, TrackSize * 0.5, TrackSize * 0.5, .themeColors().arc)

        for chapter in .chapters
        {
            let x = Math.round(.positionOf(chapter))
            painter.fillRect(Math.Rectangle{x, centerY - TickHeight * 0.5, 1, TickHeight}, .themeColors().faintText)
        }

        painter.fillCircle(knobX, centerY, KnobSize * 0.5 + 1, .themeColors().faintText)
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

/*
The veil at the bottom of the picture: the timeline, then a row of the play button, the time in
mono and the chapter on the left, and on the right the options, tracks, sound and full screen.
*/
struct BottomVeil
{
    using wnd: Wnd

    late
    {
        timeline:         *VideoTimeline
        playButton:       *IconButton
        optionsButton:    *IconButton
        tracksButton:     *IconButton
        muteButton:       *IconButton
        volumeSlider:     *Slider
        fullScreenButton: *IconButton
    }

    elapsed: String     // Time played, written first and strong.
    length:  String     // Length of the film, written after it.
    chapter: String     // The chapter played, or empty.
}

impl BottomVeil
{
    // Creates a themed action button, matching the other viewers.
    private func createGlyph(parent: *Wnd, icon: ThemeIcons, id: WndId, flags = IconButtonFlags.None)->*IconButton
    {
        let button = Viewer.createActionButton(parent, icon, flags)
        button.id = id
        return button
    }

    func create(parent: *Wnd)->*BottomVeil
    {
        with let result = Wnd.create'BottomVeil(parent, "scope.video.controls", Math.Rectangle{0, 0, 0, BottomHeight})
        {
            .backgroundStyle = .Transparent
            .wndFlags        |= .TopMost
        }

        result.timeline      = Wnd.create'VideoTimeline(result, "scope.video.timeline", Math.Rectangle{0, 0, 0, TimelineHeight})
        result.playButton    = createGlyph(result, .Play, "scope.video.play")
        result.optionsButton = createGlyph(result, .Settings, "scope.video.options")
        result.tracksButton  = createGlyph(result, .AudioTracks, "scope.video.tracks")
        result.muteButton    = createGlyph(result, .Volume, "scope.video.mute", .Toggle)
        with result.volumeSlider = Slider.create(result, Math.Rectangle{0, 0, VolumeWidth, parent.themeMetrics().slider_Height}, "scope.video.volume")
        {
            .setBounds(0, 1, 0.05)
            .setValueWithoutGesture(1)
            .enable(false)
        }

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
        .volumeSlider.show(width >= 580)
        .fullScreenButton.show(width >= 360)
        let lineY = room.bottom() - RowBottom
        let glyph = .playButton.position.width
        .timeline.setPosition(Math.Rectangle{room.x + VeilInset - KnobInset,
                                             room.bottom() - TimelineBottom - TimelineHeight * 0.5,
                                             width + 2 * KnobInset,
                                             TimelineHeight})
        .playButton.setPosition(Math.Rectangle{room.x + VeilInset - glyph * 0.25, lineY - glyph * 0.5, glyph, glyph})

        // The right end of the row reads from the edge inwards: full screen, volume, mute, tracks and options.
        var right = room.right() - VeilInset + glyph * 0.25
        if .fullScreenButton.isLocallyVisible()
        {
            right -= glyph
            .fullScreenButton.setPosition(Math.Rectangle{right, lineY - glyph * 0.5, glyph, glyph})
        }

        if .volumeSlider.isLocallyVisible()
        {
            right -= RowGap + VolumeWidth
            .volumeSlider.setPosition(Math.Rectangle{right, lineY - .volumeSlider.position.height * 0.5, VolumeWidth, .volumeSlider.position.height})
        }

        right -= glyph + RowGap * 0.5
        .muteButton.setPosition(Math.Rectangle{right, lineY - glyph * 0.5, glyph, glyph})
        right -= glyph + RowGap
        .tracksButton.setPosition(Math.Rectangle{right, lineY - glyph * 0.5, glyph, glyph})
        right -= glyph + RowGap * 0.5
        .optionsButton.setPosition(Math.Rectangle{right, lineY - glyph * 0.5, glyph, glyph})
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

        let metrics = .themeMetrics()
        let mono    = .theme().createDefaultFontFs(metrics.defaultFixedFontSize)
        let words   = .theme().createDefaultFont(metrics.defaultFontSize)
        let lineY   = room.bottom() - RowBottom

        var x = .playButton.position.right() + RowGap
        painter.drawString(x, mono.opticalLineTop(lineY), .elapsed, mono, .themeColors().softText)
        x += Painter.measureString(.elapsed, mono).width
        let length = Format.toString(" / %", .length)
        painter.drawString(x, mono.opticalLineTop(lineY), length, mono, .themeColors().faintText)
        x += Painter.measureString(length, mono).width + 2 * RowGap
        let textEnd = .optionsButton.position.x
        if not .chapter.isEmpty() and x + Painter.measureString(.chapter, words).width + RowGap < textEnd do
            painter.drawString(x, words.opticalLineTop(lineY), .chapter, words, .themeColors().faintText)

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
