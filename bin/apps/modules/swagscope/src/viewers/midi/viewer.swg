#global internal
#global namespace Viewers.Midi

using Core, Pixel, Gui

// Offers the score surface for a Standard MIDI File, whatever it is called.
private func pluginProbe(content: Viewer.ProbeContent)->bool => content.startsWith("MThd")

// Draws the notes of a MIDI file as a small piano roll, time across and pitch up, its drums apart
// in a softer tone, within `maxSide`.
private func loadThumbnail(fileName: string, maxSide: u32)->Image fail
{
    let document = try loadDocument(fileName)
    let width    = cast(s32, Math.max(Math.min(maxSide, 256'u32), 64'u32))
    let height   = width / 2
    var canvas   = try ImageCanvas.create(width, height)
    canvas.clear(Color.fromRgb(248, 249, 250))
    if document.notes.isEmpty() or not document.durationTicks do
        return try canvas.toImage()

    const Margin = 8.0
    let painter = &canvas.painter
    let span    = cast(f32, document.durationTicks)
    let keys    = cast(f32, document.maxKey - document.minKey + 1)
    let room    = Math.Rectangle{Margin, Margin, cast(f32, width) - Margin * 2, cast(f32, height) - Margin * 2}
    let pitch   = Math.max(room.height / keys, 1)
    for &note in document.notes
    {
        let end = note.endTick == Swag.U64.Max ? document.durationTicks : note.endTick
        let x   = room.x + room.width * cast(f32, note.startTick) / span
        let w   = Math.max(room.width * cast(f32, end - note.startTick) / span, 1)
        let y   = room.bottom() - cast(f32, note.key - document.minKey + 1) * room.height / keys
        let ink = note.channel == 9 ? Color.fromRgb(150, 165, 177) : Color.fromRgb(48, 80, 104)
        painter.fillRect({x, y, w, Math.min(pitch, 3)}, ink)
    }

    return try canvas.toImage()
}

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
        .options      = &addViewerOptions
        .probe        = &pluginProbe
        .thumbnail    = &loadThumbnail
        .smokeFixture = "viewer.mid"
        .addSelectors(".mid;.midi")
    }

    return result
}

// Display preferences of the MIDI viewer, persisted with the main window.
struct ViewerSettings
{
    #[Properties.Name("Pitch Labels")]
    pitchLabelMode: PitchLabelMode = .Scientific
    #[Properties.Name("Keyboard Width"), Properties.MinMax(0, 2)]
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

// Widths of the piano keyboard, in pixels, for each `keyboardWidthMode`: compact, standard, wide.
private const KeyboardWidths: [3] f32 = [56, 72, 112]

private func addViewerOptions(grid: *PropertiesCtrl, section: string) => grid.addStruct(g_ViewerSettings, section)

// Presents a Standard MIDI File as a piano roll, with a track filter and a zoom menu.
struct Panel
{
    using wnd: Wnd

    late
    {
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
    // Returns the horizontal scale of the roll in percent, as the zoom readout shows it: 100 % is
    // the timeline at its natural width, which a whole score fitted to the window never exceeds.
    mtd zoomPercent()->u32 => cast(u32, Math.round(.roll.zoom * 100))

    // Writes the horizontal scale, as a number even while the score is fitted, as every other
    // viewer's readout does.
    mtd refreshZoom()
    {
        .zoomLabel.setText(Viewer.zoomText(.zoomPercent()))
    }

    mtd retranslate()
    {
        .optionsButton.toolTip = appStrings().ui_Options
        .zoomLabel.toolTip     = texts().ui_ZoomMenu
        if .hasRoll() do
            .roll.invalidate()
    }

    mtd publishDocument(document: *Document)
    {
        .roll      = RollView.create(me, #move document[])
        .roll.mode = .Tracks
        .roll.setPitchLabelMode(.pitchLabelMode)
        .roll.setKeyboardWidth(KeyboardWidths[.keyboardWidthMode])
        .roll.sigZoomChanged += func|view = me|(_) { view.refreshZoom() }
        .applyLayout()
        .roll.refreshLayout()
        .refreshZoom()
        .refreshDetails()
    }

    // Rebuilds the host summary in the active language and reports it.
    mtd refreshDetails()
    {
        .details = Format.toString(texts().ui_Details, trackCountText(.roll.lanes.count), .roll.document.meterText(), noteCountText(.roll.document.notes.count), Viewer.durationText(.roll.document.durationSeconds))
        .services.showDetails(me, .details)
    }

    // Offers the zoom presets and the fit, with the level in use and the fit checked, as the lens
    // checks them. A score is often far wider than the window, so the levels reach down to 25 %, as
    // a picture's do.
    mtd showZoomMenu()
    {
        if not .hasRoll() do
            return
        let menu    = MenuCtrl.createPopup(me, owner: me)
        let percent = .zoomPercent()
        menu.addItem("25 %", "scope.midi.zoom25", checked: percent == 25)
        menu.addItem("50 %", "scope.midi.zoom50", checked: percent == 50)
        menu.addItem("100 %", "scope.midi.zoom100", checked: percent == 100)
        menu.addItem("200 %", "scope.midi.zoom200", checked: percent == 200)
        menu.addSeparator()
        menu.addItem(texts().ui_Fit,
                     "scope.midi.zoomFit",
                     .theme().icon(.FitView, themeRowIconSize(.themeMetrics())),
                     rightName: .keyShortcutName("scope.midi.fit", "F"),
                     checked: .roll.fit)
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

    // Reports whether the piano roll exists, which it does once the document has been read without
    // failure; until then everything that shows or zooms the score has nothing to act on.
    mtd hasRoll()->bool => not .isLoading() and .failureReason.isEmpty()

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
    // Gives the lens the options and the zoom of the score; the zoom waits for the roll.
    mtd describeLens(entries: *Viewer.LensEntries)
    {
        let missing = not .hasRoll()
        entries.add(appStrings().cmd_Options, .Settings, func|view = me|() { view.showOptions() }, bindId: "scope.midi.options")
        entries.add(appStrings().cmd_ZoomIn, .ZoomIn, func|view = me|() { view.roll.zoomIn() }, disabled: missing or not .roll.canZoomIn(), defaultKey: {modifiers: .Control, key: .OemPlus}, bindId: "scope.midi.zoomIn")
        entries.add(appStrings().cmd_ZoomOut, .ZoomOut, func|view = me|() { view.roll.zoomOut() }, disabled: missing or not .roll.canZoomOut(), defaultKey: {modifiers: .Control, key: .OemMinus}, bindId: "scope.midi.zoomOut")
        entries.add(appStrings().cmd_ZoomReset, .ActualSize, func|view = me|() { view.roll.applyZoom(1) }, checked: not missing and .zoomPercent() == 100, disabled: missing, defaultKey: {modifiers: .Control, key: .D0}, bindId: "scope.midi.zoomReset")
        entries.add(texts().ui_Fit, .FitView, func|view = me|() { view.roll.zoomToFit() }, checked: not missing and .roll.fit, disabled: missing, defaultKey: {modifiers: .None, key: .F}, bindId: "scope.midi.fit")
        entries.add(appStrings().cmd_ZoomMenu, .ZoomLevels, func|view = me|() { view.showZoomMenu() }, disabled: missing, bindId: "scope.midi.zoomMenu")
    }

    // Opens what the roll shows and how: the track, the presentation, the names of the pitches,
    // the keyboard width.
    mtd showOptions()
    {
        let sheet = OptionSheet.View.create(.optionsButton, func|view = me|(page) { view.describeOptions(page) }, owner: me)
        sheet.doModal(.optionsButton, autoDestroy: true)
    }

    mtd describeOptions(page: *OptionSheet.Page)
    {
        let strings = texts()
        if .hasRoll()
        {
            let selected = .roll.selectedTrack
            let current  = selected == Swag.U32.Max ? strings.ui_AllTracks : .roll.document.tracks[selected].name.toString()
            page.addLink(strings.ui_Track,
                         current,
                         func|view = me|(tracks)
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
                         },
                         icon: .theme().icon(.AudioTracks, themeRowIconSize(.themeMetrics())))
        }

        if .hasRoll()
        {
            let current = .roll.mode == .Tracks ? strings.ui_ByTrack : strings.ui_ByPitch
            page.addLink(strings.ui_Presentation,
                         current,
                         func|view = me|(modes)
                         {
                             modes.addChoice(texts().ui_ByTrack, view.roll.mode == .Tracks, func|view|() { view.roll.setMode(.Tracks) })
                             modes.addChoice(texts().ui_ByPitch, view.roll.mode == .Pitches, func|view|() { view.roll.setMode(.Pitches) })
                         },
                         icon: .theme().icon(.Outline, themeRowIconSize(.themeMetrics())))
        }

        page.addLink(strings.ui_PitchLabels,
                     pitchLabelText(.pitchLabelMode),
                     func|view = me|(labels)
                     {
                         for mode in [PitchLabelMode.Scientific, .MidiNumber] do
                             labels.addChoice(pitchLabelText(mode), mode == view.pitchLabelMode, func|view, mode|() { view.setPitchLabelMode(mode) }, detail: texts().ui_PitchReference)
                     },
                     icon: .theme().icon(.LineNumbers, themeRowIconSize(.themeMetrics())))

        page.addLink(strings.ui_KeyboardWidth,
                     keyboardWidthText(.keyboardWidthMode),
                     func|view = me|(widths)
                     {
                         for index in 3'u32 do
                             widths.addChoice(keyboardWidthText(index), index == view.keyboardWidthMode, func|view, index|() { view.setKeyboardWidthMode(index) })
                     },
                     icon: .theme().icon(.FitWidth, themeRowIconSize(.themeMetrics())))
    }

    // Names each pitch by its note and octave, or by its MIDI number; the choice is remembered.
    mtd setPitchLabelMode(mode: PitchLabelMode)
    {
        .pitchLabelMode = mode
        g_ViewerSettings.pitchLabelMode = mode
        if .hasRoll() do
            .roll.setPitchLabelMode(mode)
    }

    // Draws the piano keyboard compact, standard or wide; the choice is remembered.
    mtd setKeyboardWidthMode(index: u32)
    {
        Swag.assert(index < 3)
        .keyboardWidthMode = index
        g_ViewerSettings.keyboardWidthMode = index
        if .hasRoll() do
            .roll.setKeyboardWidth(KeyboardWidths[index])
    }

    // Builds the MIDI panel: the options button and the zoom button. Loads the file in the
    // background; the piano roll is created when the document arrives.
    func create(host: Viewer.Host)->*Panel
    {
        let services    = host.services()
        let info        = host.createInfoGroup(Viewer.InfoOptionsWidth + Viewer.ZoomSlotWidth)
        with let result = Wnd.create'Panel(host.contentParent(), "scope.midi")
        {
            .backgroundStyle   = .View
            .services          = services
            .info              = info
            .pitchLabelMode    = g_ViewerSettings.pitchLabelMode
            .keyboardWidthMode = g_ViewerSettings.keyboardWidthMode
        }

        with result.optionsButton = Viewer.createInfoOptionsButton(result.info)
        {
            .sigPressed += func|view = result|(_) { view.showOptions() }
        }

        with result.zoomLabel = Viewer.createZoomButton(result.info, "scope.midi.zoom", texts().ui_ZoomMenu)
        {
            .dockStyle  = .Right
            .sigPressed += func|view = result|(_) { view.showZoomMenu() }
        }

        result.applyLayout()
        result.load.start(host.fileName(), &loadDocument, result)
        return result
    }
}

impl Panel
{
    // Describes the score in the information sheet: its length, tracks and notes, then its meter.
    // A score still loading, or one that failed to load, has nothing to describe yet.
    mtd describeInformation(sheet: *InfoSheet)
    {
        if not .hasRoll() do
            return
        var data: MediaInfoData
        data.addFigure(.Duration, Viewer.durationText(.roll.document.durationSeconds))
        data.addFigure(.Custom, trackCountText(.roll.lanes.count))
        data.addFigure(.Custom, noteCountText(.roll.document.notes.count))

        // The tempo, the meter and the key, each with how often it changes.
        data.add(.Music, group: true)
        data.add(.Tempo, .roll.document.tempoText())
        data.add(.Meter, .roll.document.meterChangesText())
        data.add(.KeySignature, .roll.document.keyChangesText())

        // Each lane of the roll: its track, its channel, the instrument the track selects and the
        // notes the lane draws. The tenth channel is the drum kit whatever its program says.
        if .roll.lanes.count
        {
            data.add(.Tracks, Format.toString("%", .roll.lanes.count), group: true)
            for &lane, index in .roll.lanes
            {
                let track    = &.roll.document.tracks[lane.track]
                let name     = track.name.isEmpty() ? Format.toString(texts().ui_TrackName, lane.track + 1) : String.from(track.name)
                var measures = Format.toString(texts().ui_Channel, cast(u32, lane.channel) + 1)
                if lane.channel == 9 do
                    measures += Format.toString(" · %", texts().ui_Percussion)
                elif track.program >= 0 do
                    measures += Format.toString(" · %", instrumentName(cast(u8, track.program)))
                measures += Format.toString(" · %", noteCountText(lane.noteCount))
                data.addTrack(index + 1, name, measures)
            }
        }

        data.describe(sheet)
    }
}

// Creates the integrated MIDI score view and connects it to the host.
func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)
    host.attachView(view)
    host.setLensSource(func|view|(entries) { view.describeLens(entries) })
    host.setInformation(func|view|(sheet) { view.describeInformation(sheet) })

    with var lifecycle: Viewer.LifecycleApi
    {
        .isLoading = func|view|()->bool => view.isLoading()
        .needsLoadingOverlay = func|view|()->bool => view.isLoading()
        .retire    = func|view|()->bool => view.retire()
    }

    host.setLifecycle(lifecycle)
}
