using Core, Pixel

// The recording controls stand beside the frame, outside the recorded area. Their readouts,
// progress and choices use GUI widgets so one theme and event model owns the whole bar.
const RecordHudHeight     = 40.0     // Logical height of the pill.
const RecordHudLeft       = 7.0      // Air before the recording mark.
const RecordHudRight      = 6.0      // Air after the last command.
const RecordHudMark       = 26.0     // Side of the recording mark's cell.
const RecordHudTextMargin = 8.0      // Air on each side of the time.
const RecordHudRuleHeight = 20.0     // Height of the rule before the commands.
const RecordHudButton     = 28.0     // Side of one command.
const RecordHudButtonGap  = 4.0      // Air between two commands.
const RecordHudGap        = 8.0      // Air between the frame and the pill.
const AllScreensChoiceId  = "record.screen.all"

struct RecordHud
{
    using wnd: Wnd

    late recorder:     *Recorder
    late pauseButton:  *IconButton
    late stopButton:   *IconButton
    late cancelButton: *IconButton
    late recordMark:   *Label
    late timeLabel:    *Label
    late limitLabel:   *Label
    late droppedLabel: *Label
    late targetLabel:  *Label
    late progress:     *ProgressBar
    late separator:    *Separator
    screenButton:      *IconButton?     // Screen source chooser during video preparation.
    screenChoices:     *RecordScreenChoices?
    shownState:        RecorderState = .Stopped
    shownTargetPause:  bool
    hasShownState:     bool
    hasCommands:       bool     // The commands exist; the window is resized before they do.
    prepOptions:       Array'(*IconButton) // Choices shown only before a video starts.
}

impl IWnd for RecordHud
{
    mtd impl onDestroyEvent(_: *DestroyEvent)
    {
        .screenChoices?.close()
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        // The screen below can be as light or dark as either palette. Keep the floating
        // controls legible against both with a full-contrast outline around their surface.
        let painter = evt.paintContext.painter
        painter.setParams(.Antialiased)
        painter.drawRoundRect(.clientRect(), .themeMetrics().corner_Floating,
                              .themeMetrics().corner_Floating, .themeColors().text,
                              .themeMetrics().separator_HairlineSize)
    }

    mtd impl onThemeEvent(evt: *ThemeEvent)
    {
        .wnd.IWnd.onThemeEvent(evt)
        if not .hasCommands do
            return
        .droppedLabel.setTextColor(.themeColors().critical)
        .hasShownState = false
        .refresh()
    }

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

        .layoutReadout()

        if preparing
        {
            var x = RecordHudLeft
            let rowTop = RecordHudHeight + (client.height - RecordHudHeight - .themeMetrics().miniBar_ButtonSize) * 0.5
            if let screenButton = .screenButton
            {
                screenButton.move(x, rowTop)
                x += screenButton.position.width + .themeMetrics().miniBar_Padding
            }
            for option in .prepOptions
            {
                option[].move(x, rowTop)
                x += option[].position.width + .themeMetrics().miniBar_Padding
            }
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
        let logicalWidth = widthFor(recorder.limit, recorder.captureLabel(), preparing,
                                    recorder.screenSelection ? screenChoiceWidth(recorder.main) : 0)
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
        let logicalWidth = widthFor(recorder.limit, recorder.captureLabel(), preparing,
                                    recorder.screenSelection ? screenChoiceWidth(recorder.main) : 0)
        let logicalHeight = preparing ? RecordHudHeight + g_App.theme.metrics.miniBar_ButtonSize + g_App.theme.metrics.miniBar_Padding : RecordHudHeight
        var monitor      = Env.monitorForPoint({frame.horzCenter(), frame.vertCenter()})
        var otherScreen: bool
        var nearest = Swag.F32.Max
        if recorder.screenSelection and recorder.screenIndex != Swag.U64.Max
        {
            let selected = recorder.screenIndex
            for candidate, index in recorder.main.monitors where index != selected
            {
                let candidateScale = candidate.scaleFactor
                let margin = Math.ceil(g_App.theme.floatingShadowMargin() * candidateScale)
                let neededWidth = Math.ceil(logicalWidth * candidateScale) +
                                  2 * margin + Math.ceil(RecordHudGap * candidateScale)
                let neededHeight = Math.ceil(logicalHeight * candidateScale) +
                                   2 * margin + Math.ceil(RecordHudGap * candidateScale)
                if candidate.physicalWorkArea.width < neededWidth or
                   candidate.physicalWorkArea.height < neededHeight do
                    continue
                let work = candidate.physicalWorkArea
                let dx = frame.horzCenter() - Math.clamp(frame.horzCenter(), work.x, work.right())
                let dy = frame.vertCenter() - Math.clamp(frame.vertCenter(), work.y, work.bottom())
                let distance = dx * dx + dy * dy
                if distance >= nearest do
                    continue
                nearest = distance
                monitor = candidate
                otherScreen = true
            }
        }
        let barScale     = recorder.screenSelection ? monitor.scaleFactor : scale
        let width        = Math.ceil(logicalWidth * barScale)
        let height       = Math.ceil(logicalHeight * barScale)
        let gap          = Math.ceil(RecordHudGap * barScale)
        let workArea     = monitor.physicalWorkArea

        if otherScreen
        {
            let margin = Math.ceil(g_App.theme.floatingShadowMargin() * barScale)
            let inset = gap + margin
            let x = Math.clamp(frame.horzCenter() - width * 0.5,
                               workArea.x + inset, workArea.right() - width - inset)
            let y = Math.clamp(frame.vertCenter() - height * 0.5,
                               workArea.y + inset, workArea.bottom() - height - inset)
            return {x - margin, y - margin, width + 2 * margin, height + 2 * margin}
        }

        var place = Math.Rectangle{frame.right() - width, frame.bottom() + gap, width, height}
        if place.bottom() > workArea.bottom() do
            place.y = frame.y - gap - height
        if place.y < workArea.y
        {
            // A nearly full-height area has no vertical room. Try either side, keeping the
            // controls clear of the recorded pixels even on an X11 root capture.
            place.y = Math.clamp(frame.bottom() - height, workArea.y, workArea.bottom() - height)
            place.x = frame.right() + gap
            if place.right() > workArea.right() do
                place.x = frame.x - gap - width
        }
        else do
            place.x = Math.max(place.x, workArea.x)

        // A whole-screen recording leaves no outside edge for the pill. On Windows the
        // recording surface's display affinity excludes this control from the video.
        if place.x < workArea.x or place.right() > workArea.right()
        {
            place.x = workArea.right() - width - gap
            place.y = workArea.y + gap
        }

        // A sheet casts the floating shadow into a margin around its body: the window is the pill
        // grown by that margin. It is created where it stands, so it takes the scale of that
        // monitor from the start.
        let margin  = Math.ceil(g_App.theme.floatingShadowMargin() * barScale)
        return {place.x - margin, place.y - margin, place.width + 2 * margin, place.height + 2 * margin}
    }

    // Creates the pill of `recorder` in `parent`, with its commands.
    func create(parent: *Wnd, recorder: *Recorder)->*RecordHud
    {
        with let result = Wnd.create'RecordHud(parent)
        {
            .recorder        = recorder
            .toolTip         = g_CaptureWindow.title
            .backgroundStyle = .Surface
            .createCommands()
            .createReadout()
            if recorder.state == .Preparing
            {
                if recorder.screenSelection do
                    .createScreenChoice()
                .createPrepOptions()
            }
            .hasCommands = true
            .refresh()
        }

        return result
    }

    // Returns the font of the time: a measure, in the fixed-width family.
    func timeFont(wnd: *Wnd)->*Font => wnd.theme().createDefaultFontFs(wnd.themeMetrics().defaultFontSize - 1)

    // Returns the logical width of a pill whose recording has `limit` microseconds at most, zero
    // for none: room for the longest time it can show, so the pill never changes size.
    func widthFor(limit: u64, targetLabel: string = "", preparing: bool = false,
                  screenWidth: f32 = 0)->f32
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
        let targetWidth = Math.max(Painter.measureString(targetLabel, font).width, screenWidth)
        let readyWidth = Painter.measureString(appStrings().ui_AimReady, font).width
        let contentWidth = preparing ? Math.max(Painter.measureString(widest, font).width, readyWidth) :
                           Painter.measureString(widest, font).width
        let normalWidth = RecordHudLeft + RecordHudMark + 3 * RecordHudTextMargin + contentWidth +
                          targetWidth + commands + RecordHudRight
        if not preparing do
            return Math.ceil(normalWidth)

        let texts = appStrings()
        let labels = [texts.ui_AimCursor, texts.ui_AimCountdown, texts.ui_AimMicrophone, texts.ui_AimSystemSound]
        var optionsWidth = RecordHudLeft + RecordHudRight +
                           (screenWidth != 0 ? screenWidth + g_App.theme.metrics.miniBar_Padding : 0)
        for label in labels
        {
            optionsWidth += recordOptionWidth(g_App.theme, label) + g_App.theme.metrics.miniBar_Padding
        }
        return Math.ceil(Math.max(normalWidth, optionsWidth))
    }

    // Fits the screen choice to every connected monitor and the all-screens wording.
    func screenChoiceWidth(main: *MainWnd)->f32
    {
        let metrics = main.themeMetrics()
        let font    = main.theme().createDefaultFont(metrics.defaultFontSize)
        var widest  = Painter.measureString(appStrings().ui_AimAllScreens, font).width
        for index in main.monitors.count do
            widest = Math.max(widest, Painter.measureString(Format.toString(appStrings().ui_AimScreen, index + 1), font).width)
        return Math.ceil(2 * metrics.btnIcon_Padding + metrics.menuPopup_IconSize +
                         metrics.btnIcon_SpacingTextH + widest + metrics.btnIcon_ArrowSize +
                         metrics.btnIcon_SpacingArrowH)
    }

    private mtd createScreenChoice()
    {
        let metrics = .themeMetrics()
        let recorder = .recorder
        with .screenButton = IconButton.create(me, .recorder.main.icon(.Monitor),
                                               {0, 0, screenChoiceWidth(.recorder.main), metrics.miniBar_ButtonSize},
                                               flags: .Flat | .CenterContent)
        {
            .setIconSize(metrics.menuPopup_IconSize, metrics.menuPopup_IconSize)
            .setTextPosition(.Right)
            .setArrowPosition(.RightDownward)
            .setText(recorder.captureLabel())
            .sigPressed += func|hud = me|(_) { hud.chooseScreen() }
        }
    }

    private mtd chooseScreen()
    {
        discard RecordScreenChoices.open(me, unwrap .screenButton)
    }

    mtd refreshScreenChoice()
    {
        .screenButton?.setText(.recorder.captureLabel())
        .refresh()
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

    }

    // The readout is composed from the same labels, progress and separator as other GUI views.
    private mtd createReadout()
    {
        let font = timeFont(me)
        with .recordMark = Label.create(me, "")
        {
            .setIcon(.theme().icon(.Dot, .themeMetrics().menuPopup_IconSize))
        }
        with .timeLabel = Label.create(me, "")
        {
            .style.setFont(font, .Regular)
            .setTextAlignment(.Left, .Center)
        }
        with .limitLabel = Label.create(me, "", flags: .SecondaryText)
        {
            .style.setFont(font, .Regular)
            .setTextAlignment(.Left, .Center)
        }
        with .droppedLabel = Label.create(me, "")
        {
            .style.setFont(font, .Regular)
            .setTextAlignment(.Left, .Center)
            .setTextColor(.themeColors().critical)
        }
        with .targetLabel = Label.create(me, .recorder.captureLabel(), flags: .SecondaryText)
        {
            .style.setFont(font, .Regular)
            .setTextAlignment(.Left, .Center)
        }
        .progress  = ProgressBar.create(me)
        .separator = Separator.create(me, .Left)
        .separator.dockStyle = .None
    }

    // Keep labels at their measured width while the timer and dropped-frame count change.
    private mtd layoutReadout()
    {
        let preparing = .recorder.state == .Preparing
        let cy        = preparing ? RecordHudHeight * 0.5 : .clientRect().vertCenter()
        let font      = timeFont(me)
        let rowTop    = cy - RecordHudHeight * 0.5
        let textX     = RecordHudLeft + RecordHudMark + RecordHudTextMargin
        let timeWidth = Painter.measureString(.timeLabel.text(), font).width
        let limitWidth = Painter.measureString(.limitLabel.text(), font).width
        let targetWidth = Painter.measureString(.targetLabel.text(), font).width
        let ruleX     = .pauseButton.position.x - RecordHudButtonGap - .themeMetrics().separator_HairlineSize

        .recordMark.setPosition({RecordHudLeft, cy - RecordHudMark * 0.5, RecordHudMark, RecordHudMark})
        .timeLabel.setPosition({textX, rowTop, timeWidth, RecordHudHeight})
        .limitLabel.setPosition({textX + timeWidth, rowTop, limitWidth, RecordHudHeight})
        .droppedLabel.setPosition({textX + timeWidth + limitWidth + RecordHudTextMargin, rowTop,
                                   Painter.measureString(.droppedLabel.text(), font).width, RecordHudHeight})
        .targetLabel.setPosition({ruleX - RecordHudTextMargin - targetWidth, rowTop, targetWidth, RecordHudHeight})
        .separator.setPosition({ruleX, cy - RecordHudRuleHeight * 0.5,
                                .themeMetrics().separator_HairlineSize, RecordHudRuleHeight})
        .progress.setPosition({textX, rowTop + RecordHudHeight - .themeMetrics().progressBar_Height,
                               Math.max(timeWidth + limitWidth, RecordHudMark), .themeMetrics().progressBar_Height})
    }

    // Synchronize widget state with the recorder after each capture or state transition.
    mtd refresh()
    {
        let preparing = .recorder.state == .Preparing
        let counting  = .recorder.state == .Counting
        let elapsed   = .recorder.elapsed()
        let limit     = .recorder.limit
        let left      = .recorder.countdownLeft()

        var shown = preparing ? String.from(appStrings().ui_AimReady) : Capture.clockText(elapsed)
        if counting
        {
            let seconds = (left + 999_999) / 1_000_000
            shown = "-"
            shown += Capture.clockText(seconds * 1_000_000)
        }
        var limitText: String
        if limit and not counting
        {
            limitText = " / "
            limitText += Capture.clockText(limit)
        }
        var droppedText: String
        if .recorder.dropped and not counting do
            droppedText = Format.toString(appStrings().ui_DroppedCount, .recorder.dropped)
        let targetText = .recorder.captureLabel()
        let needsLayout = .timeLabel.text() != shown or .limitLabel.text() != limitText or
                          .droppedLabel.text() != droppedText or .targetLabel.text() != targetText
        .timeLabel.setText(shown)
        .limitLabel.setText(limitText)
        .droppedLabel.setText(droppedText)
        .targetLabel.setText(targetText)
        .targetLabel.show(not preparing or not .recorder.screenSelection)

        .progress.show((limit != 0 or counting) and not preparing)
        .progress.setValue(counting ? cast(f32, left) / cast(f32, RecordCountdown) :
                           limit ? cast(f32, elapsed) / cast(f32, limit) : 0)
        if not .hasShownState or .shownState != .recorder.state or .shownTargetPause != .recorder.pausedForTarget
        {
            .shownState       = .recorder.state
            .shownTargetPause = .recorder.pausedForTarget
            .hasShownState    = true
            .recordMark.setIconColor(preparing or counting or .recorder.state == .Paused ?
                                      .themeColors().faintText : .themeColors().critical)
            .pauseButton.setIcon(.theme().icon(preparing or .recorder.state == .Paused ? .Play : .Pause))
            .pauseButton.toolTip = preparing ? appStrings().ui_AimRecord :
                                   .recorder.pausedForTarget ? appStrings().tip_WaitingForWindow :
                                   .recorder.state == .Paused ? appStrings().tip_ResumeRecording : appStrings().tip_PauseRecording
            .pauseButton.enable(preparing or (not .recorder.pausedForTarget and not .recorder.videoMode))
            .stopButton.show(not preparing)
            if .recorder.videoMode and not preparing do
                .pauseButton.toolTip = appStrings().tip_VideoPauseUnavailable
        }
        if needsLayout do
            .layoutReadout()
    }

    // Keeps capture inputs beside the live target until the recording is started.
    private mtd createPrepOptions()
    {
        let options = &.recorder.main.captureOptions
        let texts   = appStrings()
        with let cursor = createRecordOption(me, .recorder.main.icon(.Select), texts.ui_AimCursor, options.captureCursor)
        {
            .sigCheckedChanged += func|options, cursor|(_) { options.captureCursor = cursor.isChecked }
        }
        .prepOptions.add(cursor)

        with let countdown = createRecordOption(me, .theme().icon(.HourGlass), texts.ui_AimCountdown, options.recordCountdown)
        {
            .sigCheckedChanged += func|options, countdown|(_) { options.recordCountdown = countdown.isChecked }
        }
        .prepOptions.add(countdown)

        #static if #os == Swag.TargetOs.Windows
        {
            with let microphone = createRecordOption(me, .theme().icon(.AudioTracks), texts.ui_AimMicrophone, options.recordMicrophone)
            {
                .sigCheckedChanged += func|options, microphone|(_) { options.recordMicrophone = microphone.isChecked }
            }
            .prepOptions.add(microphone)

            with let system = createRecordOption(me, .theme().icon(.Volume), texts.ui_AimSystemSound, options.recordSystemSound)
            {
                .sigCheckedChanged += func|options, system|(_) { options.recordSystemSound = system.isChecked }
            }
            .prepOptions.add(system)
        }
        else do
            .prepOptions.add(createRecordOption(me, .theme().icon(.Volume), texts.ui_AimSoundUnavailable, false, enabled: false))
    }
}

// The screen list lives on its own native surface, so a long list is not clipped to the HUD.
// It uses the same menu widget and floating surface pattern as the resident icon menu.
struct RecordScreenChoices
{
    using wnd: Wnd

    late hud:   *RecordHud
    late menu:  *MenuCtrl
    watch:      *Gui.Timer?
    wasActive:  bool
    armed:      bool
}

impl IWnd for RecordScreenChoices
{
    mtd impl onTimerEvent(_: *TimerEvent)
    {
        if PopupMenuSurface.shouldDismiss(me, .menu, &.wasActive, &.armed) do
            .close()
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        .menu.handleKeyboard(evt)
        if .menu.isModalEnded() do
            .close()
    }
}

impl RecordScreenChoices
{
    const WatchPeriod: Time.Duration = 30'ms

    func open(hud: *RecordHud, button: *IconButton)->*RecordScreenChoices?
    {
        hud.screenChoices?.close()
        let anchorSurface = unwrap hud.surface
        let buttonRect = button.surfaceRect()
        var corner = Math.Point{buttonRect.x, buttonRect.y}
        anchorSurface.surfaceToScreen(&corner)
        let anchor = Math.Rectangle{corner.x, corner.y,
                                    buttonRect.width * anchorSurface.dpiScale,
                                    buttonRect.height * anchorSurface.dpiScale}
        let surface = PopupMenuSurface.create(anchorSurface.app, {anchor.x, anchor.bottom()})
        if not surface do
            return null

        with let choices = Wnd.create'RecordScreenChoices(surface.wnd)
        {
            .dockStyle = .Center
            .backgroundStyle = .Window
            .focusPolicy = .Click
            .hud = hud
            .menu = Wnd.create'MenuCtrl(choices)
        }
        let selected = hud.recorder.screenIndex
        with choices.menu
        {
            for index in hud.recorder.main.monitors.count
            {
                .addRadioItem(Format.toString(appStrings().ui_AimScreen, index + 1),
                              Format.toString("record.screen.%", index), checked: selected == index)
            }
            .addRadioItem(appStrings().ui_AimAllScreens, AllScreensChoiceId,
                          checked: selected == Swag.U64.Max)
            .owner = choices
            .dockStyle = .Center
            .padding = 10
            .setFramePainting(true)
            .sigCommandSelected += func|choices|(_, id) { choices.select(id) }
        }

        hud.screenChoices = choices
        PopupMenuSurface.show(choices, choices.menu, anchor, .BelowAnchor,
                              {anchorSurface.position.horzCenter(), anchorSurface.position.vertCenter()})
        excludeCaptureChrome(surface)
        choices.watch = choices.addTimer(WatchPeriod)
        return choices
    }

    private mtd select(id: WndId)
    {
        let recorder = .hud.recorder
        if id == AllScreensChoiceId
        {
            recorder.selectScreen(Swag.U64.Max)
            return
        }
        for index in recorder.main.monitors.count where id == Format.toString("record.screen.%", index) do
            recorder.selectScreen(index)
    }

    mtd close()
    {
        .stopTimer(&.watch)
        .hud.screenChoices = null
        .surface?.destroy()
    }
}
