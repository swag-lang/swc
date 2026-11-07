using Core, Pixel

// The recording pill: a dot of something running now, the time recorded against the limit, and
// the commands of the recording. It stands beside the frame, outside the recorded area.
const RecordHudWidth   = 236.0     // Logical width of the pill.
const RecordHudHeight  = 40.0      // Logical height of the pill.
const RecordHudPadding = 12.0      // Air before the dot and after the last command.
const RecordHudDot     = 8.0       // Diameter of the running dot.
const RecordHudButton  = 30.0      // Side of one command.
const RecordHudGap     = 8.0       // Air between the frame and the pill.

struct RecordHud
{
    using wnd: Wnd

    late recorder:    *Recorder
    late pauseButton: *IconButton
    shownState:       RecorderState
}

impl IWnd for RecordHud
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let metrics = .themeMetrics()
        let colors  = .themeColors()
        let client  = .clientRect()

        painter.fillRect(client, colors.surface)

        // A paused recording keeps its dot, without the colour of something running.
        painter.setParams(.Antialiased)
        let dotColor = .recorder.state == .Paused ? colors.faintText : colors.live
        painter.fillCircle(RecordHudPadding + RecordHudDot * 0.5, client.vertCenter(), RecordHudDot * 0.5, dotColor)

        let font = .theme().createDefaultFontFs(metrics.defaultFontSize)
        var text = clockText(.recorder.elapsed())
        text += " / "
        text += clockText(AnimationMaxDuration)
        let textX = RecordHudPadding + RecordHudDot + 8
        painter.drawString(textX, font.opticalLineTop(client.vertCenter()), text, font, colors.text)

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
        let surface = catch g_App.createSurface(0, 0, 16, 16, .ToolWindow | .TopMost | .Sheet)
        {
            return null
        }

        with let result = Wnd.create'RecordHud(surface.wnd)
        {
            .recorder        = recorder
            .backgroundStyle = .Transparent
            .dockStyle       = .Center
            .createCommands()
        }

        surface.setView(result)

        let width   = Math.ceil(RecordHudWidth * scale)
        let height  = Math.ceil(RecordHudHeight * scale)
        let gap     = Math.ceil(RecordHudGap * scale)
        let monitor = Env.monitorForPoint({frame.horzCenter(), frame.vertCenter()}).physicalWorkArea

        var place = Math.Rectangle{frame.right() - width, frame.bottom() + gap, width, height}
        if place.bottom() > monitor.bottom() do
            place.y = frame.y - gap - height
        if place.y < monitor.y do
            place.y = frame.bottom() - gap - height
        place.x = Math.max(place.x, monitor.x)

        surface.setPosition(place)
        surface.show()
        return result
    }

    // Writes `time`, in microseconds, as minutes and seconds.
    func clockText(time: u64)->String
    {
        let seconds = time / 1_000_000
        return Format.toString("%:%%", seconds / 60, (seconds % 60) / 10, seconds % 10)
    }

    // Creates the commands of the recording, right-aligned in the pill.
    private mtd createCommands()
    {
        var right = RecordHudWidth - RecordHudPadding * 0.5

        func place(hud: *RecordHud, right: *f32, icon: Icon, tip: string)->*IconButton
        {
            right[] -= RecordHudButton
            with let button = IconButton.create(hud, icon, {right[], (RecordHudHeight - RecordHudButton) * 0.5, RecordHudButton, RecordHudButton}, flags: .Flat)
            {
                .toolTip = tip
            }

            return button
        }

        let cancel = place(me, &right, .theme().icon(.WndClose), appStrings().tip_CancelRecording)
        cancel.sigPressed += func|hud = me|(_) { hud.recorder.cancel() }

        let stop = place(me, &right, .theme().icon(.Stop), appStrings().tip_StopRecording)
        stop.sigPressed += func|hud = me|(_) { hud.recorder.stop() }

        .pauseButton = place(me, &right, .theme().icon(.Pause), appStrings().tip_PauseRecording)
        .pauseButton.sigPressed += func|hud = me|(_)
        {
            if hud.recorder.state == .Paused do
                hud.recorder.resume()
            else do
                hud.recorder.pause()
        }
    }
}
