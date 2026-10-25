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

private const CommandWidth = 560.0

// Display preferences of the MIDI viewer, persisted with the main window.
struct ViewerSettings
{
    pitchLabelMode:    PitchLabelMode = .Scientific
    keyboardWidthMode: u32 = 1
}

impl ViewerSettings
{
    mtd sanitize()
    {
        if cast(u32, .pitchLabelMode) > cast(u32, PitchLabelMode.MidiNumber) do
            .pitchLabelMode = .Scientific
        .keyboardWidthMode = Math.min(.keyboardWidthMode, 2)
    }
}

var g_ViewerSettings: ViewerSettings

// Presents a Standard MIDI File as a piano roll, with a track filter and a zoom menu.
struct Panel
{
    using wnd: Wnd

    late
    {
        commands:           *Wnd
        info:               *Wnd
        trackCombo:         *ComboBox
        pitchLabelCombo:    *ComboBox
        keyboardWidthCombo: *ComboBox
        zoomLabel:          *IconButton
        roll:               *RollView
    }

    details:           String
    pitchLabelMode:    PitchLabelMode = .Scientific
    keyboardWidthMode: u32 = 1
    load:              Viewer.BackgroundLoad'Document
    services:          Viewer.HostServices
    failureReason:     String
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

    mtd fillPitchLabels()
    {
        let selected = .pitchLabelCombo.selectedIndex
        .pitchLabelCombo.clear()
        .pitchLabelCombo.addItem(texts().ui_PitchScientific)
        .pitchLabelCombo.addItem(texts().ui_PitchMidiNumber)
        .pitchLabelCombo.setSelectedIndex(selected == Swag.U32.Max ? 0 : selected, notify: false)
    }

    mtd fillKeyboardWidths()
    {
        let selected = .keyboardWidthCombo.selectedIndex
        .keyboardWidthCombo.clear()
        .keyboardWidthCombo.addItem(texts().ui_KeyboardCompact)
        .keyboardWidthCombo.addItem(texts().ui_KeyboardStandard)
        .keyboardWidthCombo.addItem(texts().ui_KeyboardWide)
        .keyboardWidthCombo.setSelectedIndex(selected == Swag.U32.Max ? .keyboardWidthMode : selected, notify: false)
    }

    mtd retranslate()
    {
        .trackCombo.toolTip         = texts().ui_AllTracks
        .pitchLabelCombo.toolTip    = texts().ui_PitchLabels
        .keyboardWidthCombo.toolTip = texts().ui_KeyboardWidth
        .zoomLabel.toolTip          = texts().ui_ZoomMenu
        if .isLoading() do
            return
        .fillTracks()
        .fillPitchLabels()
        .fillKeyboardWidths()
        .roll.invalidate()
    }

    mtd publishDocument(document: *Document)
    {
        .roll = RollView.create(me, #move document[])
        .roll.setPitchLabelMode(.pitchLabelMode)
        .roll.setKeyboardWidth(.keyboardWidthMode == 0 ? 56 : .keyboardWidthMode == 1 ? 72 : 112)
        .roll.sigZoomChanged += func|view = me|(_) { view.refreshZoom() }
        .fillTracks()
        .fillPitchLabels()
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
        .services.showDetails(me, .details)
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
    mtd isLoading()->bool => .load.isPending()

    // Requests teardown, and reports whether deferred GUI destruction may release this view.
    mtd retire()->bool
    {
        return .load.retire()
    }
}

private impl IWnd for Panel
{
    mtd impl onTaskEvent(evt: *TaskEvent)
    {
        if not .load.claim(evt)
        {
            evt.accepted = false
            return
        }

        var document: Document
        .failureReason = .load.finish(&document)
        if not .failureReason.isEmpty()
        {
            .services.failed(me, .failureReason)
            return
        }

        .publishDocument(&document)
        .services.loadingChanged(me)
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
    // Builds the MIDI panel: the track selector and the zoom button. Loads the file in the
    // background; the piano roll is created when the document arrives.
    func create(host: Viewer.Host)->*Panel
    {
        let services = host.services()
        let commands = host.createCommandGroup(CommandWidth)
        let info     = host.createInfoGroup(Viewer.ZoomSlotWidth)

        with let result = Wnd.create'Panel(host.contentParent(), "scope.midi")
        {
            .backgroundStyle = .View
            .services        = services
            .commands        = commands
            .info            = info
            .pitchLabelMode    = g_ViewerSettings.pitchLabelMode
            .keyboardWidthMode = g_ViewerSettings.keyboardWidthMode
        }

        with result.trackCombo = ComboBox.create(result.commands, {0, 0, 224, 36})
        {
            .dockStyle  = .Left
            .toolTip    = texts().ui_AllTracks
            .sigChanged += func|view = result|(_, index) { view.roll.setTrack(index ? index - 1 : Swag.U32.Max) }
        }

        with result.pitchLabelCombo = ComboBox.create(result.commands, {0, 0, 160, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = texts().ui_PitchLabels
            .addItem(texts().ui_PitchScientific)
            .addItem(texts().ui_PitchMidiNumber)
            .setSelectedIndex(result.pitchLabelMode == .MidiNumber ? 1 : 0, notify: false)
            .sigChanged += func|view = result|(_, index)
            {
                view.pitchLabelMode = index ? .MidiNumber : .Scientific
                g_ViewerSettings.pitchLabelMode = view.pitchLabelMode
                if not view.isLoading() and view.failureReason.isEmpty() do
                    view.roll.setPitchLabelMode(view.pitchLabelMode)
            }
        }

        with result.keyboardWidthCombo = ComboBox.create(result.commands, {0, 0, 150, 36})
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = texts().ui_KeyboardWidth
            .addItem(texts().ui_KeyboardCompact)
            .addItem(texts().ui_KeyboardStandard)
            .addItem(texts().ui_KeyboardWide)
            .setSelectedIndex(result.keyboardWidthMode, notify: false)
            .sigChanged += func|view = result|(_, index)
            {
                view.keyboardWidthMode = index
                g_ViewerSettings.keyboardWidthMode = index
                if not view.isLoading() and view.failureReason.isEmpty()
                    do
                    view.roll.setKeyboardWidth(index == 0 ? 56 : index == 1 ? 72 : 112)
            }
        }

        result.zoomLabel = Viewer.createZoomButton(result.info, "scope.midi.zoom", texts().ui_ZoomMenu)
        result.zoomLabel.sigPressed += func|view = result|(_) { view.showZoomMenu() }

        result.applyLayout()
        result.load.start(host.fileName(), &loadDocument, result)
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
