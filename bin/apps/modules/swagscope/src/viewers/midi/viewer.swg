#global internal
#global namespace Viewers.Midi

using Core, Pixel, Gui

// Offers the score surface for a Standard MIDI File, whatever it is called.
private func pluginProbe(content: Viewer.ProbeContent)->bool => content.startsWith("MThd")

// Describes the MIDI viewer to the host.
func viewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "midi"
        .staticName   = "MIDI"
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Midi)
        .create       = &createViewer
        .probe        = &pluginProbe
        .smokeFixture = "viewer.mid"
        .addSelectors(".mid;.midi")
    }

    return result
}

private const CommandWidth = 224.0

// Presents a Standard MIDI File as a piano roll, with a track filter and a zoom menu.
struct Panel
{
    using wnd: Wnd

    late
    {
        commands:   *Wnd
        info:       *Wnd
        trackCombo: *ComboBox
        zoomLabel:  *IconButton
        roll:       *RollView
    }

    details:              String
    load:                 Viewer.BackgroundLoad'Document
    loadTimer:            *Timer?
    reportFailure:        Viewer.ReportFailure?
    reportDetails:        Viewer.ReportDetails?
    reportLoadingChanged: Viewer.ReportLoadingChanged?
    failureReason:        String
}

private impl Panel
{
    mtd refreshZoom()
    {
        .zoomLabel.setText(Format.toString("% %%", cast(u32, Math.round(.roll.zoom * 100))))
    }

    mtd fillTracks()
    {
        let selected = .trackCombo.selectedIndex
        .trackCombo.clear()
        .trackCombo.addItem(texts().ui_AllTracks)
        for track in .roll.document.tracks
        {
            let label = Format.toString(texts().ui_TrackChoice, track.name, track.noteCount)
            .trackCombo.addItem(label)
        }

        .trackCombo.setSelectedIndex(selected == Swag.U32.Max ? 0 : selected, notify: false)
    }

    mtd retranslate()
    {
        .trackCombo.toolTip = texts().ui_AllTracks
        .zoomLabel.toolTip  = texts().ui_ZoomMenu
        if .isLoading() do
            return
        .fillTracks()
        .roll.invalidate()
    }

    mtd publishDocument(document: *Document)
    {
        .roll = RollView.create(me, #move document[])
        .roll.sigZoomChanged += func|view = me|(?) { view.refreshZoom() }
        .fillTracks()
        .trackCombo.setSelectedIndex(0, notify: false)
        .applyLayout()
        .roll.refreshLayout()
        .refreshZoom()
        .setInitialFocus(.roll)
        .refreshDetails()
    }

    // Rebuilds the host summary in the active language and reports it.
    mtd refreshDetails()
    {
        .details = Format.toString(texts().ui_Details, .roll.document.format, .roll.document.tracks.count, .roll.document.notes.count, Viewer.durationText(.roll.document.durationSeconds))
        if .reportDetails do
            .reportDetails(me, .details.toString())
    }

    mtd showZoomMenu()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem("25%", "scope.midi.zoom25")
        menu.addItem("50%", "scope.midi.zoom50")
        menu.addItem("100%", "scope.midi.zoom100")
        menu.addItem("200%", "scope.midi.zoom200")
        menu.addSeparator()
        menu.addItem(texts().ui_Fit, "scope.midi.zoomFit", .theme().icon(.FitView, themeRowIconSize(.themeMetrics())), rightName: "F")
        switch menu.doModal(.zoomLabel, autoDestroy: true) orelse ""
        {
        case "scope.midi.zoom25":  .roll.applyZoom(0.25)
        case "scope.midi.zoom50":  .roll.applyZoom(0.5)
        case "scope.midi.zoom100": .roll.applyZoom(1)
        case "scope.midi.zoom200": .roll.applyZoom(2)
        case "scope.midi.zoomFit": .roll.zoomToFit()
        }
    }

    // Reports whether the document is still being read in the background.
    mtd isLoading()->bool => .loadTimer != null

    // Requests teardown, and reports whether deferred GUI destruction may release this view.
    mtd retire()->bool
    {
        if not .load.retire() do
            return false
        if .loadTimer
        {
            .removeTimer(.loadTimer)
            .loadTimer = null
        }

        return true
    }
}

private impl IWnd for Panel
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .loadTimer
        {
            evt.accepted = false
            return
        }

        if not .load.isDone() do
            return

        .removeTimer(evt.timer)
        .loadTimer = null
        var document: Document
        .failureReason = .load.finish(&document)
        if not .failureReason.isEmpty()
        {
            if .reportFailure do
                .reportFailure(me, .failureReason.toString())
            return
        }

        .publishDocument(&document)
        if .reportLoadingChanged do
            .reportLoadingChanged(me)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        else do
            evt.accepted = false
    }
}

impl Panel
{
    func create(host: Viewer.Host)->*Panel
    {
        let services = host.services()
        let commands = host.createCommandGroup(CommandWidth)
        let info     = host.createInfoGroup(ViewerZoomSlotWidth)

        with let result = Wnd.create'Panel(host.contentParent(), "scope.midi")
        {
            .backgroundStyle      = .View
            .reportFailure        = services.reportFailure
            .reportDetails        = services.reportDetails
            .reportLoadingChanged = services.reportLoadingChanged
            .commands             = commands
            .info                 = info
        }

        with result.trackCombo = ComboBox.create(result.commands, {0, 0, CommandWidth, 36})
        {
            .dockStyle  = .Left
            .toolTip    = texts().ui_AllTracks
            .sigChanged += func|view = result|(?, index) { view.roll.setTrack(index ? index - 1 : Swag.U32.Max) }
        }

        with result.zoomLabel = IconButton.create(result.info, {}, {0, 0, ViewerZoomButtonWidth, 32}, "scope.midi.zoom", .CenterContent)
        {
            .dockStyle = .Center
            .margin    = {ViewerInfoControlInset, 0, ViewerInfoControlInset, 0}
            .setText("100%")
            .setArrowPosition(.RightDownward)
            .setForm(.Rectangle)
            .style.setFont(result.theme().createDefaultFontFs(11), .Regular)
            .toolTip    = texts().ui_ZoomMenu
            .sigPressed += func|view = result|(?) { view.showZoomMenu() }
        }

        result.applyLayout()
        result.load.start(host.fileName(), &loadDocument)
        result.loadTimer = result.addTimer(Viewer.BackgroundPollInterval)
        return result
    }
}

// Creates the integrated MIDI score view and connects it to the host.
func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)
    host.attachView(view)

    with var lifecycle: Viewer.LifecycleApi
    {
        .isLoading = func|view|()->bool => view.isLoading()
        .needsLoadingOverlay = func|view|()->bool => view.isLoading()
        .retire    = func|view|()->bool => view.retire()
    }

    host.setLifecycle(lifecycle)
}
