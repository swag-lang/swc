#global internal
#global namespace Viewers.Midi

using Core, Pixel, Gui

// Offers the score surface for a Standard MIDI File, whatever it is called.
private func pluginProbe(content: Viewer.ProbeContent)->bool => content.startsWith("MThd")

// Describes the MIDI viewer to the host.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
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

private const CommandWidth = 64.0

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
        commands:      *Wnd
        info:          *Wnd
        optionsButton: *IconButton
        zoomLabel:     *IconButton
        roll:          *RollView
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

    mtd retranslate()
    {
        .optionsButton.toolTip = appStrings().ui_Options
        .zoomLabel.toolTip     = texts().ui_ZoomMenu
        if .isLoading() do
            return
        .roll.invalidate()
    }

    mtd publishDocument(document: *Document)
    {
        .roll = RollView.create(me, #move document[])
        .roll.setPitchLabelMode(.pitchLabelMode)
        .roll.setKeyboardWidth(.keyboardWidthMode == 0 ? 56 : .keyboardWidthMode == 1 ? 72 : 112)
        .roll.sigZoomChanged += func|view = me|(_) { view.refreshZoom() }
        .applyLayout()
        .roll.refreshLayout()
        .refreshZoom()
        .setInitialFocus(.roll)
        .refreshDetails()
    }

    // Rebuilds the host summary in the active language and reports it.
    mtd refreshDetails()
    {
        .details = Format.toString(texts().ui_Details, .roll.document.format, trackCountText(.roll.document.tracks.count), noteCountText(.roll.document.notes.count), Viewer.durationText(.roll.document.durationSeconds))
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
    // Opens what the roll shows and how: the track, the names of the pitches, the keyboard width.
    // Gives the lens the options and the zoom of the score.
    mtd describeLens(entries: *Viewer.LensEntries)
    {
        entries.add(appStrings().cmd_Options, func|view = me|() { view.showOptions() })
        entries.add(appStrings().cmd_ZoomMenu, func|view = me|() { view.showZoomMenu() })
    }

    mtd showOptions()
    {
        let sheet = OptionSheet.View.create(.optionsButton, func|view = me|(page) { view.describeOptions(page) }, owner: me)
        sheet.doModal(.optionsButton, autoDestroy: true)
    }

    mtd describeOptions(page: *OptionSheet.Page)
    {
        let strings = texts()
        if not .isLoading() and .failureReason.isEmpty()
        {
            let selected = .roll.selectedTrack
            let current  = selected == Swag.U32.Max ? strings.ui_AllTracks : .roll.document.tracks[selected].name.toString()
            page.addLink(strings.ui_Track, current, func|view = me|(tracks)
            {
                tracks.addChoice(texts().ui_AllTracks, view.roll.selectedTrack == Swag.U32.Max, func|view|() { view.roll.setTrack(Swag.U32.Max) })
                for track, index in view.roll.document.tracks
                {
                    tracks.addChoice(track.name,
                                     view.roll.selectedTrack == index,
                                     func|view, index|()
                                     {
                                         view.roll.setTrack(cast(u32, index))
                                     },
                                     detail: noteCountText(track.noteCount))
                }
            })
        }

        page.addLink(strings.ui_PitchLabels, pitchLabelText(.pitchLabelMode), func|view = me|(labels)
        {
            for mode in [PitchLabelMode.Scientific, .MidiNumber] do
                labels.addChoice(pitchLabelText(mode), mode == view.pitchLabelMode, func|view, mode|() { view.setPitchLabelMode(mode) })
        })

        page.addLink(strings.ui_KeyboardWidth, keyboardWidthText(.keyboardWidthMode), func|view = me|(widths)
        {
            for index in 3'u32 do
                widths.addChoice(keyboardWidthText(index), index == view.keyboardWidthMode, func|view, index|() { view.setKeyboardWidthMode(index) })
        })
    }

    // Names each pitch by its note and octave, or by its MIDI number; the choice is remembered.
    mtd setPitchLabelMode(mode: PitchLabelMode)
    {
        .pitchLabelMode = mode
        g_ViewerSettings.pitchLabelMode = mode
        if not .isLoading() and .failureReason.isEmpty() do
            .roll.setPitchLabelMode(mode)
    }

    // Draws the piano keyboard compact, standard or wide; the choice is remembered.
    mtd setKeyboardWidthMode(index: u32)
    {
        Swag.assert(index < 3)
        .keyboardWidthMode = index
        g_ViewerSettings.keyboardWidthMode = index
        if not .isLoading() and .failureReason.isEmpty() do
            .roll.setKeyboardWidth(index == 0 ? 56 : index == 1 ? 72 : 112)
    }

    // Builds the MIDI panel: the options button and the zoom button. Loads the file in the
    // background; the piano roll is created when the document arrives.
    func create(host: Viewer.Host)->*Panel
    {
        let services = host.services()
        let commands = host.createCommandGroup(CommandWidth)
        let info     = host.createInfoGroup(Viewer.ZoomSlotWidth)

        with let result = Wnd.create'Panel(host.contentParent(), "scope.midi")
        {
            .backgroundStyle   = .View
            .services          = services
            .commands          = commands
            .info              = info
            .pitchLabelMode    = g_ViewerSettings.pitchLabelMode
            .keyboardWidthMode = g_ViewerSettings.keyboardWidthMode
        }

        with result.optionsButton = Viewer.createOptionsButton(result.commands)
        {
            .dockStyle  = .Left
            .sigPressed += func|view = result|(_) { view.showOptions() }
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
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })

    with var lifecycle: Viewer.LifecycleApi
    {
        .isLoading = func|view|()->bool => view.isLoading()
        .needsLoadingOverlay = func|view|()->bool => view.isLoading()
        .retire    = func|view|()->bool => view.retire()
    }

    host.setLifecycle(lifecycle)
}
