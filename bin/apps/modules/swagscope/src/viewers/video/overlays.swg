#global internal
#global namespace Viewers.Film

using Core, Pixel, Gui, Video, Audio

private
{
    const SeekOverlaySize    = Math.Point{112, 64}
    const SeekOverlayOffsetY = 56.0
    const SeekOverlayLifetime: Time.Duration = 650'ms

    // Subtitle readability effects are proportional to the text, so every text size keeps the
    // same look. Widths are distance-field units (0.1 is 4% of the em); offsets and paddings
    // are fractions of the font size.
    const SubtitleLineGap        = 4'f32
    const SubtitleEdgeColor      = 0xE6000000'u32
    const SubtitleBackdropColor  = 0xA6000000'u32
    const SubtitleOutlineWidth   = 0.18'f32
    const SubtitleShadowOffset   = 0.06'f32
    const SubtitleShadowDilate   = 0.08'f32
    const SubtitleShadowSoftness = 0.3'f32
    const SubtitleBackdropPadX   = 0.3'f32
    const SubtitleBackdropPadY   = 0.1'f32
}

private func subtitleFontSize(size: SubtitleSize)->u32
{
    switch #complete size
    {
    case .Small:     return 20
    case .Normal:    return 27
    case .Large:     return 36
    case .VeryLarge: return 46
    }
}

// Outlines the backdrop of subtitle `lines`, drawn from `top` and centered on `centerX`.
//
// Each line gets its own box, as wide as its text, and the boxes of consecutive lines meet
// halfway across the gap between them. The whole block is one contour, so a translucent fill
// covers every pixel once: separate boxes would darken the band where they overlap or touch.
private func subtitleBackdrop(lines: const [..] string, font: *Font, centerX, top: f32)->LinePath
{
    let padX    = Math.round(cast(f32, font.size) * SubtitleBackdropPadX)
    let padY    = Math.round(cast(f32, font.size) * SubtitleBackdropPadY)
    let advance = font.height + SubtitleLineGap

    var rows: Array'f32
    rows.add(top - padY)
    for index in 1 until lines.count do
        rows.add(Math.round(top + cast(f32, index) * advance - SubtitleLineGap * 0.5))
    rows.add(Math.round(top + cast(f32, lines.count - 1) * advance + font.height + padY))

    var lefts:  Array'f32
    var rights: Array'f32
    for line in lines
    {
        let width = Painter.measureString(line, font).width
        let left  = Math.floor(centerX - width * 0.5) - padX
        lefts.add(left)
        rights.add(left + width + 2 * padX)
    }

    var result: retval
    result.start(rights[0], rows[0])
    for index in lines.count
    {
        result.lineTo(rights[index], rows[index])
        result.lineTo(rights[index], rows[index + 1])
    }

    for index in reversed(lines.count)
    {
        result.lineTo(lefts[index], rows[index + 1])
        result.lineTo(lefts[index], rows[index])
    }

    result.close()
    return result
}

// Draws `text` in `color` at the eight positions `offset` pixels around (`x`, `y`).
//
// Painted under the text itself, the ring is a keyline that keeps the text legible over both
// bright and dark pictures.
private func drawStringKeyline(painter: *Painter, x, y: f32, text: string, font: *Font, color: Color, offset: f32)
{
    for row in 3
    {
        for column in 3 where row != 1 or column != 1 do
            painter.drawString(x + (cast(f32, column) - 1) * offset, y + (cast(f32, row) - 1) * offset, text, font, color)
    }
}

// Timed text painted over the picture without taking part in input or layout.
struct SubtitleOverlay
{
    using wnd: Wnd

    text:     String
    sidecars: Array'*Subtitle.Track
}

private impl IWnd for SubtitleOverlay
{
    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        for track in .sidecars do
            Subtitle.Track.destroy(track)
        .sidecars.clear()
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        if .text.isEmpty() do
            return

        let painter = evt.paintContext.painter
        let rect    = .clientRect()
        let font    = unwrap .font().regular
        let lines   = Tokenize.splitLines(.text)
        if lines.isEmpty() do
            return

        let height = cast(f32, lines.count) * font.height + cast(f32, lines.count - 1) * SubtitleLineGap
        let inset  = Math.max(24'f32, rect.height * 0.06)
        var y: f32
        switch g_SubtitleSettings.position
        {
        case .Bottom: y = rect.height - inset - height
        case .Center: y = (rect.height - height) * 0.5
        case .Top:    y = inset
        }

        y = Math.floor(Math.max(y, 0))

        // The outline and the shadow come from the glyph distance field: they keep their
        // proportions at every size and stay round, where copies of the text offset by a few
        // pixels thin to a hairline on large text and leave notches between their directions.
        let ink = g_SubtitleSettings.color == .Yellow ? Color.fromArgb(0xFFFFE66D) : Color.fromArgb(Argb.White)
        var effect: TextEffect
        painter.setAntialiased(true)
        switch #complete g_SubtitleSettings.effect
        {
        case .Outline:
            effect.outlineWidth = SubtitleOutlineWidth
            effect.outlineColor = Color.fromArgb(SubtitleEdgeColor)

        case .Shadow:
            let offset = Math.round(cast(f32, font.size) * SubtitleShadowOffset)
            effect.shadowColor    = Color.fromArgb(SubtitleEdgeColor)
            effect.shadowOffset   = {offset, offset}
            effect.shadowDilate   = SubtitleShadowDilate
            effect.shadowSoftness = SubtitleShadowSoftness

        case .Background:
            var backdrop = subtitleBackdrop(lines.toSlice(), font, rect.horzCenter(), y)
            painter.fillPolygon(&backdrop, Color.fromArgb(SubtitleBackdropColor))

        case .None:
            break
        }

        for line in lines
        {
            let width = Painter.measureString(line, font).width
            painter.drawString(Math.floor(rect.horzCenter() - width * 0.5), y, line, font, ink, effect)
            y += font.height + SubtitleLineGap
        }
    }
}

impl SubtitleOverlay
{
    func create(parent: *Wnd)->*SubtitleOverlay
    {
        with let result = Wnd.create'SubtitleOverlay(parent, "scope.video.subtitle")
        {
            .dockStyle       = .Center
            .wndFlags        |= .TopMost | .Disabled
            .backgroundStyle = .Transparent
            .applySettings()
        }

        return result
    }

    mtd applySettings()
    {
        // Only a distance-field font carries the outline and the shadow; the other effects keep
        // the crisper bitmap glyphs an automatic font draws at small sizes.
        let size = subtitleFontSize(g_SubtitleSettings.size)
        let mode = g_SubtitleSettings.effect == .Outline or g_SubtitleSettings.effect == .Shadow ? FontRenderMode.Msdf : .Auto
        let font = g_SubtitleSettings.font == .Monospace ? .theme().createDefaultFontFs(size, .Bold, mode) : .theme().createDefaultFont(size, .Bold, mode)
        .style.setFont(font, .Regular)
        .invalidate()
    }

    mtd setSubtitle(text: string)
    {
        if .text == text do
            return
        .text.clear()
        .text += text
        .invalidate()
    }
}

// Briefly reports a relative timeline jump over the picture itself.
//
// The Voltage mark carries an Ink keyline rather than a tile, so it remains legible over both
// bright and dark frames without covering the picture. Presentation transforms move the complete
// sign in the direction of travel without disturbing layout or hit testing.
struct SeekOverlay
{
    using wnd: Wnd

    text:       String
    direction:  s32
    fontReady:  bool
    timer:      *Timer?
    offsetAni:  AnimationHandle
    scaleAni:   AnimationHandle
    opacityAni: AnimationHandle
}

private impl IWnd for SeekOverlay
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter  = evt.paintContext.painter
        let rect     = .clientRect()
        let font     = unwrap .font().regular
        let textSize = Painter.measureString(.text, font)
        let textX    = Math.floor(rect.horzCenter() - textSize.width * 0.5)
        let textY    = Math.floor(rect.vertCenter() - font.height * 0.5)

        painter.setAntialiased(true)
        drawStringKeyline(painter, textX, textY, .text, font, Ink, 1)
        painter.drawString(textX, textY, .text, font, Voltage)
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .timer
        {
            evt.accepted = false
            return
        }

        .stopTimer(&.timer)
        .hide()
        .resetPresentation()
    }

    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .stopTimer(&.timer)
    }
}

impl SeekOverlay
{
    func create(parent: *Wnd)->*SeekOverlay
    {
        with let result = Wnd.create'SeekOverlay(parent, "scope.video.seek", {0, 0, SeekOverlaySize.x, SeekOverlaySize.y})
        {
            .wndFlags        |= .TopMost | .Disabled
            .backgroundStyle = .Transparent
            .hide()
        }

        return result
    }

    // Restarts the feedback for one signed jump in seconds.
    mtd showSeek(seconds: f64)
    {
        if seconds == 0 do
            return

        let animator = &.app().animator
        if animator.isActive(.offsetAni) do
            animator.cancel(.offsetAni)
        if animator.isActive(.scaleAni) do
            animator.cancel(.scaleAni)
        if animator.isActive(.opacityAni) do
            animator.cancel(.opacityAni)
        .stopTimer(&.timer)

        .direction = seconds < 0 ? -1 : 1
        .text      = Format.toString(seconds < 0 ? "-%" : "+%", cast(u64, Math.round(Math.abs(seconds))))
        if not .fontReady
        {
            .style.setFont(.theme().createDefaultFont(24, .Bold), .Regular)
            .fontReady = true
        }

        let rect = .parent!.clientRect()
        let size = .preferredSize
        let x    = Math.floor((rect.width - size.x) * 0.5)
        let y    = Math.floor(Math.clamp((rect.height - size.y) * 0.5 + SeekOverlayOffsetY, 0, Math.max(rect.height - size.y, 0)))
        .setPosition({x, y, size.x, size.y}, computeLayout: false)
        .resetPresentation()
        .show()
        .bringToFront()
        .timer = .addTimer(SeekOverlayLifetime)

        // Reduced motion keeps the information but removes its travel and zoom.
        if .app().isReducedMotion() do
            return

        let direction = cast(f32, .direction)
        .setPresentationOffset({-10 * direction, 0})
        .setPresentationScale({0.9, 0.9})

        .offsetAni  = animator.animatePoint(me, AnimationChannel.from("scope.VideoSeek.Offset"), {-10 * direction, 0}, {14 * direction, 0}, func(wnd, value) { wnd.setPresentationOffset(value) }, {duration: 600'ms, easing: .EaseOut})
        .scaleAni   = animator.animatePoint(me, AnimationChannel.from("scope.VideoSeek.Scale"), {0.9, 0.9}, {1, 1}, func(wnd, value) { wnd.setPresentationScale(value) }, {duration: 180'ms, easing: .EaseOut})
        .opacityAni = animator.animateF32(me, AnimationChannel.from("scope.VideoSeek.Opacity"), 1, 0, func(wnd, value) { wnd.setPresentationOpacity(value) }, {delay: 350'ms, duration: 250'ms, easing: .EaseIn})
    }
}
