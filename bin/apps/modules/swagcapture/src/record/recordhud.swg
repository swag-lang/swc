using Core, Pixel

// The recording pill, after the charter picture: a ring that fills towards the limit around the
// recording dot, the time recorded and the limit in the fixed-width family, a rule, then pause,
// stop and cancel. A recording without a limit shows the time alone, and its ring turns once a
// minute. The pill stands beside the frame, outside the recorded area.
const RecordHudHeight     = 40.0     // Logical height of the pill.
const RecordHudLeft       = 7.0      // Air before the ring.
const RecordHudRight      = 6.0      // Air after the last command.
const RecordHudRing       = 26.0     // Side of the square the ring is drawn in.
const RecordHudRingRadius = 10.5     // Radius of the ring.
const RecordHudRingWidth  = 2.5      // Weight of the ring.
const RecordHudDotRadius  = 4.5      // Radius of the recording dot.
const RecordHudTextMargin = 8.0      // Air on each side of the time.
const RecordHudRuleHeight = 20.0     // Height of the rule before the commands.
const RecordHudButton     = 28.0     // Side of one command.
const RecordHudButtonGap  = 4.0      // Air between two commands.
const RecordHudGap        = 8.0      // Air between the frame and the pill.

struct RecordHud
{
    using wnd: Wnd

    late recorder:     *Recorder
    late pauseButton:  *IconButton
    late stopButton:   *IconButton
    late cancelButton: *IconButton
    shownState:        RecorderState
    hasCommands:       bool     // The commands exist; the window is resized before they do.
}

impl IWnd for RecordHud
{
    // The commands stand against the right edge of the pill, whatever size its monitor gives it.
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        .wnd.IWnd.onResizeEvent(evt)
        if not .hasCommands do
            return

        let client = .clientRect()
        let top    = client.vertCenter() - RecordHudButton * 0.5
        var right  = client.right() - RecordHudRight
        for button in [.cancelButton, .stopButton, .pauseButton]
        {
            right -= RecordHudButton
            button.setPosition(Math.Rectangle{right, top, RecordHudButton, RecordHudButton})
            right -= RecordHudButtonGap
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        if not .hasCommands do
            return

        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let client  = .clientRect()
        let elapsed = .recorder.elapsed()
        let limit   = .recorder.limit

        // The ground of a floating surface; the sheet rounds its corners and casts its shadow.
        painter.fillRect(client, colors.surface)
        painter.setParams(.Antialiased)

        // The ring fills towards the limit; without one, it turns once a minute.
        let cx       = RecordHudLeft + RecordHudRing * 0.5
        let cy       = client.vertCenter()
        let fraction = limit ? Math.min(cast(f32, elapsed) / cast(f32, limit), 1) : cast(f32, elapsed % 60_000_000) / 60_000_000
        painter.drawCircle(cx, cy, RecordHudRingRadius, colors.raised, RecordHudRingWidth)
        if fraction > 0 do
            painter.drawArc(cx, cy, RecordHudRingRadius, Math.Angle.fromDegrees(0), Math.Angle.fromDegrees(360 * fraction), colors.arc, RecordHudRingWidth)

        // A paused recording keeps its dot, without the colour of a recording.
        let dotColor = .recorder.state == .Paused ? colors.faintText : colors.critical
        painter.fillCircle(cx, cy, RecordHudDotRadius, dotColor)

        // The time recorded, then the limit, fainter.
        let font  = timeFont(me)
        let top   = font.opticalLineTop(cy)
        var x     = RecordHudLeft + RecordHudRing + RecordHudTextMargin
        let shown = clockText(elapsed)
        painter.drawString(x, top, shown, font, colors.text)
        if limit
        {
            x += Painter.measureString(shown, font).width
            var rest = String.from(" / ")
            rest += clockText(limit)
            painter.drawString(x, top, rest, font, colors.faintText)
        }

        // The rule before the commands.
        let ruleX = .pauseButton.position.x - RecordHudButtonGap - 1
        painter.fillRect({ruleX, cy - RecordHudRuleHeight * 0.5, 1, RecordHudRuleHeight}, colors.line)

        if .shownState != .recorder.state
        {
            .shownState = .recorder.state
            .pauseButton.setIcon(.theme().icon(.recorder.state == .Paused ? .Play : .Pause))
            .pauseButton.toolTip = .recorder.state == .Paused ? appStrings().tip_ResumeRecording : appStrings().tip_PauseRecording
        }
    }
}

impl RecordHud
{
    // Opens the pill of `recorder` beside the frame `frame`, in physical screen pixels, on a
    // monitor of scale `scale`: under the frame, or over it, or inside the area when the screen
    // has no room around it.
    func open(recorder: *Recorder, frame: Math.Rectangle, scale: f32)->*RecordHud?
    {
        let logicalWidth = widthFor(recorder.limit)
        let width        = Math.ceil(logicalWidth * scale)
        let height       = Math.ceil(RecordHudHeight * scale)
        let gap          = Math.ceil(RecordHudGap * scale)
        let monitor      = Env.monitorForPoint({frame.horzCenter(), frame.vertCenter()}).physicalWorkArea

        var place = Math.Rectangle{frame.right() - width, frame.bottom() + gap, width, height}
        if place.bottom() > monitor.bottom() do
            place.y = frame.y - gap - height
        if place.y < monitor.y do
            place.y = frame.bottom() - gap - height
        place.x = Math.max(place.x, monitor.x)

        // A sheet casts the floating shadow into a margin around its body: the window is the pill
        // grown by that margin. It is created where it stands, so it takes the scale of that
        // monitor from the start.
        let margin  = Math.ceil(g_App.theme.floatingShadowMargin() * scale)
        let outer   = Math.Rectangle{place.x - margin, place.y - margin, place.width + 2 * margin, place.height + 2 * margin}
        let surface = catch g_App.createSurface(cast(s32, outer.x), cast(s32, outer.y), cast(s32, logicalWidth), cast(s32, RecordHudHeight), .ToolWindow | .TopMost | .Sheet)
        {
            return null
        }

        with let result = create(surface.wnd, recorder)
        {
            .dockStyle = .Center
        }

        // The pill is smaller than the default minimum size of a surface.
        surface.minSize = {}
        surface.setView(result)
        surface.setPosition(outer)
        surface.show()
        surface.bringToFront()
        return result
    }

    // Creates the pill of `recorder` in `parent`, with its commands.
    func create(parent: *Wnd, recorder: *Recorder)->*RecordHud
    {
        with let result = Wnd.create'RecordHud(parent)
        {
            .recorder        = recorder
            .backgroundStyle = .Transparent
            .createCommands()
        }

        return result
    }

    // Returns the font of the time: a measure, in the fixed-width family.
    func timeFont(wnd: *Wnd)->*Font => wnd.theme().createDefaultFontFs(wnd.themeMetrics().defaultFontSize - 1)

    // Returns the logical width of a pill whose recording has `limit` microseconds at most, zero
    // for none: room for the longest time it can show, so the pill never changes size.
    func widthFor(limit: u64)->f32
    {
        var widest = limit ? clockText(limit) : String.from("0:00:00")
        if limit
        {
            widest += " / "
            widest += clockText(limit)
        }

        let font     = g_App.theme.createDefaultFontFs(g_App.theme.metrics.defaultFontSize - 1)
        let commands = 3 * RecordHudButton + 3 * RecordHudButtonGap + 1
        return Math.ceil(RecordHudLeft + RecordHudRing + 2 * RecordHudTextMargin + Painter.measureString(widest, font).width + commands + RecordHudRight)
    }

    // Writes `time`, in microseconds, as minutes and seconds, with the hours in front past an hour.
    func clockText(time: u64)->String
    {
        // `%%` is a literal percent sign in a format: two-digit fields are written digit by digit.
        func twoDigits(result: *String, value: u64)
        {
            result[] += Format.toString("%", value / 10)
            result[] += Format.toString("%", value % 10)
        }

        let seconds = time / 1_000_000
        var result: String
        if seconds >= 3600
        {
            result = Format.toString("%:", seconds / 3600)
            twoDigits(&result, (seconds / 60) % 60)
        }
        else
        {
            result = Format.toString("%", seconds / 60)
        }

        result += ":"
        twoDigits(&result, seconds % 60)
        return result
    }

    // Creates the commands of the recording; [[RecordHud.onResizeEvent]] places them.
    private mtd createCommands()
    {
        func command(hud: *RecordHud, icon: Icon, tip: string)->*IconButton
        {
            with let button = IconButton.create(hud, icon, {}, flags: .Flat)
            {
                .toolTip = tip
            }

            return button
        }

        .cancelButton = command(me, .theme().icon(.WndClose), appStrings().tip_CancelRecording)
        .cancelButton.sigPressed += func|hud = me|(_) { hud.recorder.cancel() }

        .stopButton = command(me, .theme().icon(.Stop), appStrings().tip_StopRecording)
        .stopButton.sigPressed += func|hud = me|(_) { hud.recorder.stop() }

        .pauseButton = command(me, .theme().icon(.Pause), appStrings().tip_PauseRecording)
        .pauseButton.sigPressed += func|hud = me|(_)
        {
            if hud.recorder.state == .Paused do
                hud.recorder.resume()
            else do
                hud.recorder.pause()
        }

        .hasCommands = true
    }
}
