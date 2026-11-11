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
    shownState:        RecorderState = .Stopped
    shownTargetPause:  bool
    hasCommands:       bool     // The commands exist; the window is resized before they do.
    prepOptions:       Array'(*OptionChip) // Choices shown only before a video starts.
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
        let preparing = .recorder.state == .Preparing
        let top    = (preparing ? RecordHudHeight * 0.5 : client.vertCenter()) - RecordHudButton * 0.5
        var right  = client.right() - RecordHudRight
        for button in [.cancelButton, .stopButton, .pauseButton]
        {
            right -= RecordHudButton
            button.setPosition(Math.Rectangle{right, top, RecordHudButton, RecordHudButton})
            right -= RecordHudButtonGap
        }

        if preparing
        {
            var x = RecordHudLeft
            let rowTop = RecordHudHeight + (client.height - RecordHudHeight - .themeMetrics().miniBar_ButtonSize) * 0.5
            for option in .prepOptions
            {
                option[].move(x, rowTop)
                x += option[].position.width + .themeMetrics().miniBar_Padding
            }
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        if not .hasCommands do
            return

        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let client  = .clientRect()
        let preparing = .recorder.state == .Preparing
        let elapsed = .recorder.elapsed()
        let limit   = .recorder.limit

        // The ground of a floating surface; the sheet rounds its corners and casts its shadow.
        painter.fillRect(client, colors.surface)
        painter.setParams(.Antialiased)

        // The ring fills towards the limit; without one, it turns once a minute. During the
        // countdown, it empties towards the first frame.
        let cx       = RecordHudLeft + RecordHudRing * 0.5
        let cy       = preparing ? RecordHudHeight * 0.5 : client.vertCenter()
        let counting = .recorder.state == .Counting
        let left     = .recorder.countdownLeft()
        var fraction = limit ? Math.min(cast(f32, elapsed) / cast(f32, limit), 1) : cast(f32, elapsed % 60_000_000) / 60_000_000
        if counting do
            fraction = cast(f32, left) / cast(f32, RecordCountdown)
        painter.drawCircle(cx, cy, RecordHudRingRadius, colors.raised, RecordHudRingWidth)
        if fraction > 0 do
            painter.drawArc(cx, cy, RecordHudRingRadius, Math.Angle.fromDegrees(0), Math.Angle.fromDegrees(360 * fraction), colors.arc, RecordHudRingWidth)

        // A paused recording keeps its dot, without the colour of a recording.
        let dotColor = preparing or .recorder.state == .Paused or counting ? colors.faintText : colors.critical
        painter.fillCircle(cx, cy, RecordHudDotRadius, dotColor)

        // The time recorded, then the limit, fainter.
        let font = timeFont(me)
        let top  = font.opticalLineTop(cy)
        var x    = RecordHudLeft + RecordHudRing + RecordHudTextMargin
        if preparing
        {
            painter.drawString(x, top, appStrings().ui_AimReady, font, colors.text)
        }
        elif counting
        {
            // The whole seconds left, counted down to the first frame.
            let seconds = (left + 999_999) / 1_000_000
            var shown   = String.from("-")
            shown += Capture.clockText(seconds * 1_000_000)
            painter.drawString(x, top, shown, font, colors.text)
        }
        else
        {
            let shown = Capture.clockText(elapsed)
            painter.drawString(x, top, shown, font, colors.text)
            x += Painter.measureString(shown, font).width
        }

        if limit and not counting
        {
            var rest = String.from(" / ")
            rest += Capture.clockText(limit)
            painter.drawString(x, top, rest, font, colors.faintText)
            x += Painter.measureString(rest, font).width
        }

        if .recorder.dropped and not counting
        {
            x += RecordHudTextMargin
            painter.drawString(x, top, Format.toString(appStrings().ui_DroppedCount, .recorder.dropped),
                               font, colors.critical)
        }

        // The rule before the commands.
        let ruleX = .pauseButton.position.x - RecordHudButtonGap - 1
        let target = captureTargetLabel()
        let targetFont = .theme().createDefaultFontFs(.themeMetrics().defaultFontSize - 1)
        let targetWidth = Painter.measureString(target, targetFont).width
        painter.drawString(ruleX - RecordHudTextMargin - targetWidth,
                           targetFont.opticalLineTop(cy), target, targetFont, colors.softText)
        painter.fillRect({ruleX, cy - RecordHudRuleHeight * 0.5, 1, RecordHudRuleHeight}, colors.line)

        if .shownState != .recorder.state or .shownTargetPause != .recorder.pausedForTarget
        {
            .shownState = .recorder.state
            .shownTargetPause = .recorder.pausedForTarget
            .pauseButton.setIcon(.theme().icon(preparing or .recorder.state == .Paused ? .Play : .Pause))
            .pauseButton.toolTip = preparing ? appStrings().ui_AimRecord :
                                   .recorder.pausedForTarget ? appStrings().tip_WaitingForWindow :
                                   .recorder.state == .Paused ? appStrings().tip_ResumeRecording : appStrings().tip_PauseRecording
            .pauseButton.enable(preparing or (not .recorder.pausedForTarget and not .recorder.videoMode))
            .stopButton.show(not preparing)
            if .recorder.videoMode and not preparing do
                .pauseButton.toolTip = appStrings().tip_VideoPauseUnavailable
        }
    }
}

impl RecordHud
{
    // Opens the pill of `recorder` beside the frame `frame`, in physical screen pixels, on a
    // monitor of scale `scale`: under the frame, over it, or beside it when vertical room is tight.
    func open(recorder: *Recorder, frame: Math.Rectangle, scale: f32)->*RecordHud?
    {
        let preparing = recorder.state == .Preparing
        let logicalWidth = widthFor(recorder.limit, captureTargetLabel(), preparing)
        let logicalHeight = preparing ? RecordHudHeight + recorder.main.themeMetrics().miniBar_ButtonSize + recorder.main.themeMetrics().miniBar_Padding : RecordHudHeight
        let outer        = placement(recorder, frame, scale)

        // A sheet casts the floating shadow into a margin around its body: the window is the pill
        // grown by that margin. It is created where it stands, so it takes the scale of that
        // monitor from the start.
        let surface = catch g_App.createSurface(cast(s32, outer.x), cast(s32, outer.y), cast(s32, logicalWidth), cast(s32, logicalHeight), .ToolWindow | .TopMost | .Sheet)
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

    // Moves the pill with an attached recording area.
    mtd follow(frame: Math.Rectangle, scale: f32)
    {
        .surface?.setPosition(placement(.recorder, frame, scale))
    }

    // Places the pill beside the frame, or inside the monitor when the frame fills it.
    private func placement(recorder: *Recorder, frame: Math.Rectangle, scale: f32)->Math.Rectangle
    {
        let preparing    = recorder.state == .Preparing
        let logicalWidth = widthFor(recorder.limit, captureTargetLabel(), preparing)
        let width        = Math.ceil(logicalWidth * scale)
        let logicalHeight = preparing ? RecordHudHeight + g_App.theme.metrics.miniBar_ButtonSize + g_App.theme.metrics.miniBar_Padding : RecordHudHeight
        let height       = Math.ceil(logicalHeight * scale)
        let gap          = Math.ceil(RecordHudGap * scale)
        let monitor      = Env.monitorForPoint({frame.horzCenter(), frame.vertCenter()}).physicalWorkArea

        var place = Math.Rectangle{frame.right() - width, frame.bottom() + gap, width, height}
        if place.bottom() > monitor.bottom() do
            place.y = frame.y - gap - height
        if place.y < monitor.y
        {
            // A nearly full-height area has no vertical room. Try either side, keeping the
            // controls clear of the recorded pixels even on an X11 root capture.
            place.y = Math.clamp(frame.bottom() - height, monitor.y, monitor.bottom() - height)
            place.x = frame.right() + gap
            if place.right() > monitor.right() do
                place.x = frame.x - gap - width
        }
        else do
            place.x = Math.max(place.x, monitor.x)

        // A whole-screen recording leaves no outside edge for the pill. On Windows the
        // recording surface's display affinity excludes this control from the video.
        if place.x < monitor.x or place.right() > monitor.right()
        {
            place.x = monitor.right() - width - gap
            place.y = monitor.y + gap
        }

        // A sheet casts the floating shadow into a margin around its body: the window is the pill
        // grown by that margin. It is created where it stands, so it takes the scale of that
        // monitor from the start.
        let margin  = Math.ceil(g_App.theme.floatingShadowMargin() * scale)
        return {place.x - margin, place.y - margin, place.width + 2 * margin, place.height + 2 * margin}
    }

    // Creates the pill of `recorder` in `parent`, with its commands.
    func create(parent: *Wnd, recorder: *Recorder)->*RecordHud
    {
        with let result = Wnd.create'RecordHud(parent)
        {
            .recorder        = recorder
            .toolTip         = g_CaptureWindow.title
            .backgroundStyle = .Transparent
            .createCommands()
            if recorder.state == .Preparing do
                .createPrepOptions()
        }

        return result
    }

    // Returns the font of the time: a measure, in the fixed-width family.
    func timeFont(wnd: *Wnd)->*Font => wnd.theme().createDefaultFontFs(wnd.themeMetrics().defaultFontSize - 1)

    // Returns the logical width of a pill whose recording has `limit` microseconds at most, zero
    // for none: room for the longest time it can show, so the pill never changes size.
    func widthFor(limit: u64, targetLabel: string = "", preparing: bool = false)->f32
    {
        var widest = limit ? Capture.clockText(limit) : String.from("0:00:00")
        if limit
        {
            widest += " / "
            widest += Capture.clockText(limit)
        }

        widest += " "
        widest += Format.toString(appStrings().ui_DroppedCount, 1200)

        let font     = g_App.theme.createDefaultFontFs(g_App.theme.metrics.defaultFontSize - 1)
        let commands = 3 * RecordHudButton + 3 * RecordHudButtonGap + 1
        let targetWidth = Painter.measureString(targetLabel, font).width
        let readyWidth = Painter.measureString(appStrings().ui_AimReady, font).width
        let contentWidth = preparing ? Math.max(Painter.measureString(widest, font).width, readyWidth) :
                           Painter.measureString(widest, font).width
        let normalWidth = RecordHudLeft + RecordHudRing + 3 * RecordHudTextMargin + contentWidth +
                          targetWidth + commands + RecordHudRight
        if not preparing do
            return Math.ceil(normalWidth)

        let texts = appStrings()
        let labels = [texts.ui_AimCursor, texts.ui_AimCountdown, texts.ui_AimMicrophone, texts.ui_AimSystemSound]
        let optionFont = g_App.theme.createDefaultFont(g_App.theme.metrics.defaultFontSize)
        var optionsWidth = RecordHudLeft + RecordHudRight
        for label in labels
        {
            optionsWidth += 2 * OptionChipInset + OptionChipIcon + OptionChipGap +
                            Painter.measureString(label, optionFont).width + g_App.theme.metrics.miniBar_Padding
        }
        return Math.ceil(Math.max(normalWidth, optionsWidth))
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
            if hud.recorder.state == .Preparing
            {
                hud.recorder.recordRequested = true
                return
            }
            if hud.recorder.pausedForTarget do
                return
            if hud.recorder.state == .Paused do
                hud.recorder.resume()
            else do
                hud.recorder.pause()
        }

        .hasCommands = true
    }

    // Keeps capture inputs beside the live target until the recording is started.
    private mtd createPrepOptions()
    {
        let options = &.recorder.main.captureOptions
        let texts   = appStrings()
        with let cursor = OptionChip.create(me, .recorder.main.icon(.Select), texts.ui_AimCursor, options.captureCursor)
        {
            .sigPressed += func|options|(chip)
            {
                options.captureCursor = not options.captureCursor
                chip.on = options.captureCursor
                chip.invalidate()
            }
        }
        .prepOptions.add(cursor)

        with let countdown = OptionChip.create(me, .theme().icon(.HourGlass), texts.ui_AimCountdown, options.recordCountdown)
        {
            .sigPressed += func|options|(chip)
            {
                options.recordCountdown = not options.recordCountdown
                chip.on = options.recordCountdown
                chip.invalidate()
            }
        }
        .prepOptions.add(countdown)

        #static if #os == Swag.TargetOs.Windows
        {
            with let microphone = OptionChip.create(me, .theme().icon(.AudioTracks), texts.ui_AimMicrophone, options.recordMicrophone)
            {
                .sigPressed += func|options|(chip)
                {
                    options.recordMicrophone = not options.recordMicrophone
                    chip.on = options.recordMicrophone
                    chip.invalidate()
                }
            }
            .prepOptions.add(microphone)

            with let system = OptionChip.create(me, .theme().icon(.Volume), texts.ui_AimSystemSound, options.recordSystemSound)
            {
                .sigPressed += func|options|(chip)
                {
                    options.recordSystemSound = not options.recordSystemSound
                    chip.on = options.recordSystemSound
                    chip.invalidate()
                }
            }
            .prepOptions.add(system)
        }
        else do
            .prepOptions.add(OptionChip.create(me, .theme().icon(.Volume), texts.ui_AimSoundUnavailable, false, inert: true))
    }
}
