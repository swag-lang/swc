#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

func midiViewerFixturePath()->String => scopeTestDataPath("viewer.mid")

#test
{
    let fileName = midiViewerFixturePath()

    let document = expect Midi.loadDocument(fileName)
    Swag.require(document.format == 0 and document.division == 480)
    Swag.require(document.tracks.count == 1 and document.tracks[0].name == "Piano Roll")
    Swag.require(document.notes.count == 7 and document.tracks[0].noteCount == 7)
    Swag.require(document.minKey == 60 and document.maxKey == 72)
    Swag.require(document.tempos.count == 1 and document.bpm() == 120)
    Swag.require(document.timeSignatures.count == 1 and document.meterText() == "4/4")
    Swag.require(document.keySignatures.count == 1 and document.keyText() == "C major")
    Swag.require(Math.abs(document.durationSeconds - 2.25) < 0.001)
}

// The empty-score fallback must not replace the highest pitch of an actual score.
#test
{
    for key in [0'u8, 36, 100, 127]
    {
        var bytes: Array'u8
        bytes.add(cast(const [..] u8, "MThd"))
        bytes.add([0'u8, 0, 0, 6, 0, 0, 0, 1, 1, 0xE0])
        bytes.add(cast(const [..] u8, "MTrk"))
        bytes.add([0'u8, 0, 0, 13, 0, 0x90, key, 100, 0x83, 0x60, 0x80, key, 0, 0, 0xFF, 0x2F, 0])
        let fileName = Gui.Testing.tempFilePath("scope-midi-pitch-", ".mid")
        defer discard catch File.delete(fileName)
        expect File.writeAllBytes(fileName, bytes.toSlice())
        var document = expect Midi.loadDocument(fileName)
        Swag.require(document.notes.count == 1 and document.minKey == key and document.maxKey == key)

        var host: Testing.HeadlessHost
        host.setup(640, 360)
        let roll = Midi.RollView.create(&host.root, #move document)
        roll.refreshLayout()
        Swag.require(roll.lowKey <= key and roll.highKey >= key and roll.highKey >= roll.lowKey)
        let image = host.render(&host.root)
        Swag.require(image.isValid())
    }
}

// The score loads in the background, offers its tracks and its presentations, and zooms.
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    host.theme.setDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let foot     = createTestViewerFoot(&host.root)
    let fileName = midiViewerFixturePath()
    var result   = openTestViewer(Midi.viewerPlugin(), &host.root, fileName, commandParent: foot.commands, infoParent: foot.readings)
    Swag.require(result.view != null and result.commands == null and result.info != null)

    let viewer = assume cast(*Midi.Panel, result.view)
    completeViewerBackgroundLoad(&host, &viewer.load)
    Swag.require(result.info.preferredSize.x == Viewer.InfoOptionsWidth + Viewer.ZoomSlotWidth)
    Swag.require(Utf8.contains(viewer.details.toSlice(), "7 notes"))
    viewer.dockStyle = .Center
    var options: OptionSheet.Page
    viewer.describeOptions(&options)
    var tracks: OptionSheet.Page
    options.rows[0].buildLink(&tracks)
    Swag.require(options.rows[0].value == Midi.texts().ui_AllTracks and tracks.rows.count == 2)

    host.activateOptionRowWhenShown(Midi.texts().ui_Track)
    host.thenActivateOptionRow(tracks.rows[1].label.text)
    viewer.showOptions()
    Swag.require(viewer.roll.selectedTrack == 0 and viewer.roll.selectedNoteCount() == 7)
    viewer.roll.setTrack(Swag.U32.Max)
    let fitZoom = viewer.roll.zoom
    viewer.roll.zoomIn()
    Swag.require(not viewer.roll.fit and viewer.roll.zoom > fitZoom)
    viewer.roll.zoomToFit()

    host.root.applyLayout()
    Swag.require(viewer.optionsButton.parent == viewer.info and viewer.zoomLabel.parent == viewer.info)
    viewer.roll.refreshLayout()
    Swag.require(viewer.roll.mode == .Tracks and viewer.roll.lanes.count == 1)

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    host.root.applyLayout()
    discard host.render(&host.root)
    var translated: OptionSheet.Page
    viewer.describeOptions(&translated)
    Swag.require(translated.rows[0].value == "Toutes les pistes")
    Swag.require(viewer.zoomLabel.toolTip == Midi.texts().ui_ZoomMenu)
    Testing.assertContentFits(viewer.info)
}

#test
{
    let fileName = Gui.Testing.tempFilePath("scope-midi-bad-", ".mid")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "not MIDI")

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var result = openTestViewer(Midi.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.require(result.view != null and result.commands == null and result.info != null)
    let viewer = assume cast(*Midi.Panel, result.view)
    completeViewerBackgroundLoad(&host, &viewer.load)
    Swag.require(not viewer.failureReason.isEmpty())
}

// The tenth channel is percussion: its notes are hits drawn where they strike, whatever their
// note-off says; every other channel holds its pitch for its length.
#test
{
    var drum: Midi.Note
    drum.channel = 9
    var piano: Midi.Note
    piano.channel = 0
    Swag.require(drum.isHit() and not piano.isHit())
}

// The information sheet gives the tempo, the meter and the key of the whole file: the range a
// tempo moves through, and how many times each of them changes.
#test
{
    var bytes: Array'u8
    bytes.add(cast(const [..] u8, "MThd"))
    bytes.add([0'u8, 0, 0, 6, 0, 0, 0, 1, 1, 0xE0])
    bytes.add(cast(const [..] u8, "MTrk"))
    bytes.add([0'u8, 0, 0, 66])
    bytes.add([0x00'u8, 0xC0, 0x18, 0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20, 0x00, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08,
               0x00, 0xFF, 0x59, 0x02, 0x00, 0x00, 0x00, 0x90, 0x3C, 0x64, 0x83, 0x60, 0xFF, 0x51, 0x03,
               0x06, 0x1A, 0x80, 0x00, 0xFF, 0x58, 0x04, 0x03, 0x02, 0x18, 0x08, 0x83, 0x60, 0xFF, 0x51,
               0x03, 0x07, 0xA1, 0x20, 0x00, 0xFF, 0x59, 0x02, 0x01, 0x00, 0x00, 0x80, 0x3C, 0x00, 0x00,
               0xFF, 0x2F, 0x00])
    let fileName = Gui.Testing.tempFilePath("scope-midi-changes-", ".mid")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, bytes.toSlice())

    let document = expect Midi.loadDocument(fileName)
    Swag.require(document.tempos.count == 3 and document.bpm() == 120)
    Swag.require(document.tempoText() == "120–150 BPM · 2 changes", document.tempoText())
    Swag.require(document.meterChangesText() == "4/4 · 1 change", document.meterChangesText())
    Swag.require(document.keyChangesText() == "C major · 1 change", document.keyChangesText())

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var result = openTestViewer(Midi.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    let view   = assume cast(*Midi.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)

    let sheet = InfoSheet.create(&host.root)
    view.describeInformation(sheet)
    let text = sheet.text()
    Swag.require(Utf8.contains(text, "Tempo\n120–150 BPM · 2 changes"), text)
    Swag.require(Utf8.contains(text, "Time signature\n4/4 · 1 change"), text)
    Swag.require(Utf8.contains(text, "Key\nC major · 1 change"), text)

    // The track lists its channel, the General MIDI instrument it selects and its notes.
    Swag.require(document.tracks[0].program == 24 and Midi.instrumentName(24) == "Acoustic Guitar (nylon)")
    Swag.require(Utf8.contains(text, "channel 1 · Acoustic Guitar (nylon) · 1 note"), text)
}
