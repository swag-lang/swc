#global internal
#global namespace Viewers.Film

using Core, Pixel, Gui, Video, Audio

private
{
    const SeekOverlaySize    = Math.Point{112, 64}
    const SeekOverlayOffsetY = 56.0
    const SeekOverlayLifetime: Time.Duration = 650'ms
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
    mtd impl onDestroyEvent(?: *DestroyEvent)
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
        let font    = .font().regular!
        let lines   = Tokenize.splitLines(.text)
        if lines.isEmpty() do
            return

        let lineGap = 4'f32
        let height  = cast(f32, lines.count) * font.height + cast(f32, lines.count - 1) * lineGap
        let inset   = Math.max(24'f32, rect.height * 0.06)
        var y: f32
        switch g_SubtitleSettings.position
        {
        case .Bottom: y = rect.height - inset - height
        case .Center: y = (rect.height - height) * 0.5
        case .Top:    y = inset
        }

        y = Math.max(y, 0)

        let ink  = g_SubtitleSettings.color == .Yellow ? Color.fromArgb(0xFFFFE66D) : Color.fromArgb(Argb.White)
        let edge = Color.fromArgb(0xE6000000)
        painter.setAntialiased(true)
        for line in lines
        {
            let size = Painter.measureString(line, font)
            let x    = Math.floor(rect.horzCenter() - size.width * 0.5)
            switch #complete g_SubtitleSettings.effect
            {
            case .Background: painter.fillRect(x - 8, y - 3, size.width + 16, font.height + 6, Color.fromArgb(0xA6000000))
            case .Shadow:     painter.drawString(x + 2, y + 2, line, font, edge)
            case .Outline:    drawStringKeyline(painter, x, y, line, font, edge, 1.5)
            case .None:       break
            }

            painter.drawString(x, y, line, font, ink)
            y += font.height + lineGap
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
        let size = subtitleFontSize(g_SubtitleSettings.size)
        let font = g_SubtitleSettings.font == .Monospace ? .theme().createDefaultFontFs(size, .Bold) : .theme().createDefaultFont(size, .Bold)
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
        let font     = .font().regular!
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

    mtd impl onDestroyEvent(?: *DestroyEvent)
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
