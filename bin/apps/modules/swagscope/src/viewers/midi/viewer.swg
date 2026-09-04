#global internal

using Core, Pixel, Gui

// Describes the MIDI viewer to the host.
func midiViewerPlugin()->Viewer.Plugin
{
    var result: retval
    result.key          = "midi"
    result.staticName   = "MIDI"
    result.attach       = &registerMidiStrings
    result.iconAtlas    = viewerIcons()
    result.iconIndex    = cast(s32) ViewerIcons.Midi
    result.create       = &createMidiViewer
    result.smokeFixture = "viewer.mid"
    result.addSelectors(".mid;.midi")
    return result
}

private const MidiCommandWidth = 224.0

internal struct MidiViewer
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
        .zoomLabel.setText(Format.toString("% %", cast(u32) Math.round(.roll.zoom * 100), "%"))
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
        if !.loadTimer do
            .fillTracks()
        .trackCombo.toolTip = midiStrings().ui_AllTracks
        .zoomLabel.toolTip  = midiStrings().ui_ZoomMenu
        if !.loadTimer do
            .roll.invalidate()
    }

    mtd publishDocument(document: *MidiDocument)
    {
        .roll                = MidiRollView.create(me, #move document[])
        .roll.sigZoomChanged += func|view = me|(roll)
        {
            discard roll
            view.refreshZoom()
        }
        .fillTracks()
        .trackCombo.setSelectedIndex(0, notify: false)
        .details = Format.toString(midiStrings().ui_Details, .roll.document.format, .roll.document.tracks.count, .roll.document.notes.count, Viewer.durationText(.roll.document.durationSeconds))
        .applyLayout()
        .roll.refreshLayout()
        .refreshZoom()
        .setInitialFocus(.roll)
        if .reportDetails do
            .reportDetails!(me, .details.toString())
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

    mtd retire()->bool
    {
        if !.load.retire() do
            return false
        if .loadTimer
        {
            .removeTimer(.loadTimer!)
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

        if !.load.isDone() do
            return

        .removeTimer(evt.timer)
        .loadTimer = null
        var document: MidiDocument
        .failureReason = .load.finish(&document)
        if !.failureReason.isEmpty()
        {
            if .reportFailure do
                .reportFailure!(me, .failureReason.toString())
            return
        }

        .publishDocument(&document)
        if .reportLoadingChanged do
            .reportLoadingChanged!(me)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        else do
            evt.accepted = false
    }
}

internal impl MidiViewer
{
    func create(contentParent, commands, info: *Wnd, fileName: string, reportFailure: Viewer.ReportFailure?, reportDetails: Viewer.ReportDetails?, reportLoadingChanged: Viewer.ReportLoadingChanged?)->*MidiViewer
    {
        let result = Wnd.create'MidiViewer(contentParent, "scope.midi")
        result.backgroundStyle      = .View
        result.reportFailure        = reportFailure
        result.reportDetails        = reportDetails
        result.reportLoadingChanged = reportLoadingChanged

        result.commands = commands
        result.info     = info
        with result.trackCombo = ComboBox.create(result.commands, {0, 0, 224, 36})
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
            .style.setFont(result.theme().createDefaultFontFS(11), .Regular)
            .toolTip    = midiStrings().ui_ZoomMenu
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.showZoomMenu()
            }
        }

        result.applyLayout()
        result.load.start(fileName, &loadMidiDocument)
        result.loadTimer = result.addTimer(Viewer.BackgroundPollInterval)
        return result
    }
}

func createMidiViewer(host: Viewer.Host)
{
    let services = host.services()
    let view     = MidiViewer.create(host.contentParent(), host.createCommandGroup(MidiCommandWidth), host.createInfoGroup(ViewerZoomSlotWidth), host.fileName(), services.reportFailure, services.reportDetails, services.reportLoadingChanged)
    host.attachView(view)
    host.setLifecycle({
        isLoading: func(wnd)->bool { return (cast(*MidiViewer) wnd).loadTimer != null },
        needsLoadingOverlay: func(wnd)->bool { return (cast(*MidiViewer) wnd).loadTimer != null },
        retire: func(wnd)->bool { return (cast(*MidiViewer) wnd).retire() }})
}
