#global internal

using Core, Pixel, Gui

private const MidiCommandWidth = 432.0
private const MidiGlyphSize    = 18.0

internal struct MidiViewer
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commands:      *ViewerCommandBar
        trackCombo:    *ComboBox
        zoomOutButton: *IconButton
        zoomInButton:  *IconButton
        fitButton:     *IconButton
        zoomLabel:     *Label
        roll:          *MidiRollView
    }

    details:              String
    load:                 ViewerBackgroundLoad'MidiDocument
    loadTimer:            #null *Timer
    reportFailure:        #null ViewerReportFailure
    reportDetails:        #null ViewerReportDetails
    reportLoadingChanged: #null ViewerReportLoadingChanged
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
        .trackCombo.toolTip    = midiStrings().ui_AllTracks
        .zoomOutButton.toolTip = midiStrings().ui_ZoomOut
        .zoomInButton.toolTip  = midiStrings().ui_ZoomIn
        .fitButton.toolTip     = midiStrings().ui_Fit
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
        .details = Format.toString(midiStrings().ui_Details, .roll.document.format, .roll.document.tracks.count, .roll.document.notes.count, mediaDurationText(.roll.document.durationSeconds))
        .applyLayout()
        .roll.refreshLayout()
        .refreshZoom()
        .setInitialFocus(.roll)
        if .reportDetails do
            .reportDetails!(me, .details.toString())
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
    func create(contentParent, commandParent: *Wnd, fileName: string, reportFailure: #null ViewerReportFailure, reportDetails: #null ViewerReportDetails, reportLoadingChanged: #null ViewerReportLoadingChanged)->*MidiViewer
    {
        registerMidiStrings(contentParent.app())
        let result = Wnd.create'MidiViewer(contentParent, "sFileScope.midi")
        result.backgroundStyle      = .View
        result.reportFailure        = reportFailure
        result.reportDetails        = reportDetails
        result.reportLoadingChanged = reportLoadingChanged

        result.commands = ViewerCommandBar.create(commandParent, MidiCommandWidth)
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

        with result.zoomOutButton = IconButton.create(result.commands, result.theme().icon(.ZoomOut, MidiGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = midiStrings().ui_ZoomOut
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.roll.zoomOut()
                view.refreshZoom()
            }
        }

        with result.zoomInButton = IconButton.create(result.commands, result.theme().icon(.ZoomIn, MidiGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .toolTip    = midiStrings().ui_ZoomIn
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.roll.zoomIn()
                view.refreshZoom()
            }
        }

        with result.fitButton = IconButton.create(result.commands, result.theme().icon(.FitView, MidiGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = midiStrings().ui_Fit
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.roll.zoomToFit()
                view.refreshZoom()
            }
        }

        with result.zoomLabel = Label.create(result.commands, "", {0, 0, 76, 36}, null, .SecondaryText)
        {
            .dockStyle = .Left
            .setTextAlignment(.Right, .Center)
            .style.setFont(result.theme().createDefaultFontFS(11), .Regular)
        }

        result.applyLayout()
        result.load.start(fileName, &loadMidiDocument)
        result.loadTimer = result.addTimer(ViewerBackgroundPollInterval)
        return result
    }
}

func createMidiViewer(request: const *ViewerRequest, result: *ViewerResult)
{
    registerMidiStrings(request.contentParent.app())
    let view = MidiViewer.create(request.contentParent, request.commandParent, request.fileName, request.reportFailure, request.reportDetails, request.reportLoadingChanged)
    result.view                = view
    result.commands            = view.commands
    result.isLoading           = func(wnd)->bool { return (cast(*MidiViewer) wnd).loadTimer != null }
    result.needsLoadingOverlay = func(wnd)->bool { return (cast(*MidiViewer) wnd).loadTimer != null }
    result.retire              = func(wnd)->bool { return (cast(*MidiViewer) wnd).retire() }
}
