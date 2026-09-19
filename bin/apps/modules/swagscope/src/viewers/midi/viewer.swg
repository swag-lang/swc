#global internal

using Core, Pixel, Gui

// Offers the score surface for a Standard MIDI File, whatever it is called.
private func midiPluginProbe(content: Viewer.ProbeContent)->bool => content.startsWith("MThd")

// Describes the MIDI viewer to the host.
func midiViewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "midi"
        .staticName   = "MIDI"
        .attach       = &registerMidiStrings
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32) ViewerIcons.Midi
        .create       = &createMidiViewer
        .probe        = &midiPluginProbe
        .smokeFixture = "viewer.mid"
        .addSelectors(".mid;.midi")
    }

    return result
}

private const MidiCommandWidth = 224.0

// Presents a Standard MIDI File as a piano roll, with a track filter and a zoom menu.
struct MidiViewer
{
    using wnd: Wnd

    late
    {
        commands:   *Wnd
        info:       *Wnd
        trackCombo: *ComboBox
        zoomLabel:  *IconButton
        roll:       *MidiRollView
    }

    details:              String
    load:                 Viewer.BackgroundLoad'MidiDocument
    loadTimer:            *Timer?
    reportFailure:        Viewer.ReportFailure?
    reportDetails:        Viewer.ReportDetails?
    reportLoadingChanged: Viewer.ReportLoadingChanged?
    failureReason:        String
}

private impl MidiViewer
{
    mtd refreshZoom()
    {
        .zoomLabel.setText(Format.toString("% %%", cast(u32) Math.round(.roll.zoom * 100)))
    }

    mtd fillTracks()
    {
        let selected = .trackCombo.selectedIndex
        .trackCombo.clear()
        .trackCombo.addItem(midiStrings().ui_AllTracks)
        for track in .roll.document.tracks
        {
            let label = Format.toString(midiStrings().ui_TrackChoice, track.name, track.noteCount)
            .trackCombo.addItem(label.toString())
        }

        .trackCombo.setSelectedIndex(selected == Swag.U32.Max ? 0 : selected, notify: false)
    }

    mtd retranslate()
    {
        .trackCombo.toolTip = midiStrings().ui_AllTracks
        .zoomLabel.toolTip  = midiStrings().ui_ZoomMenu
        if .isLoading() do
            return
        .fillTracks()
        .roll.invalidate()
    }

    mtd publishDocument(document: *MidiDocument)
    {
        .roll = MidiRollView.create(me, #move document[])
        .roll.sigZoomChanged += func|view = me|(roll)
        {
            discard roll
            view.refreshZoom()
        }

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
        .details = Format.toString(midiStrings().ui_Details, .roll.document.format, .roll.document.tracks.count, .roll.document.notes.count, Viewer.durationText(.roll.document.durationSeconds))
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
        menu.addItem(midiStrings().ui_Fit, "scope.midi.zoomFit", .theme().icon(.FitView, themeRowIconSize(.themeMetrics())), rightName: "F")
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

private impl IWnd for MidiViewer
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
        var document: MidiDocument
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

impl MidiViewer
{
    func create(host: Viewer.Host)->*MidiViewer
    {
        let services    = host.services()
        let commands    = host.createCommandGroup(MidiCommandWidth)
        let info        = host.createInfoGroup(ViewerZoomSlotWidth)
        with let result = Wnd.create'MidiViewer(host.contentParent(), "scope.midi")
        {
            .backgroundStyle      = .View
            .reportFailure        = services.reportFailure
            .reportDetails        = services.reportDetails
            .reportLoadingChanged = services.reportLoadingChanged
            .commands             = commands
            .info                 = info
        }

        with result.trackCombo = ComboBox.create(result.commands, {0, 0, MidiCommandWidth, 36})
        {
            .dockStyle  = .Left
            .toolTip    = midiStrings().ui_AllTracks
            .sigChanged += func|view = result|(combo, index)
            {
                discard combo
                view.roll.setTrack(index ? index - 1 : Swag.U32.Max)
            }
        }

        with result.zoomLabel = IconButton.create(result.info, {}, {0, 0, ViewerZoomButtonWidth, 32}, "scope.midi.zoom", .CenterContent)
        {
            .dockStyle = .Center
            .margin    = {ViewerInfoControlInset, 0, ViewerInfoControlInset, 0}
            .setText("100%")
            .setArrowPosition(.RightDownward)
            .setForm(.Rectangle)
            .style.setFont(result.theme().createDefaultFontFs(11), .Regular)
            .toolTip    = midiStrings().ui_ZoomMenu
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.showZoomMenu()
            }
        }

        result.applyLayout()
        result.load.start(host.fileName(), &loadMidiDocument)
        result.loadTimer = result.addTimer(Viewer.BackgroundPollInterval)
        return result
    }
}

// Creates the integrated MIDI score view and connects it to the host.
func createMidiViewer(host: Viewer.Host)
{
    host.attachView(MidiViewer.create(host))
    host.setLifecycle({
        isLoading: func(wnd)->bool => (cast #assume (*MidiViewer) wnd).isLoading(),
        needsLoadingOverlay: func(wnd)->bool => (cast #assume (*MidiViewer) wnd).isLoading(),
        retire: func(wnd)->bool => (cast #assume (*MidiViewer) wnd).retire()})
}
