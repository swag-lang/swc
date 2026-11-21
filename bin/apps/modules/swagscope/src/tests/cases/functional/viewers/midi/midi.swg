#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Errors, Pixel, Gui, Viewers

func midiViewerFixturePath()->String => scopeTestDataPath("viewer.mid")

// Writes small, deterministic SMF matrix fixtures from raw event bytes. They use only note-on,
// note-off and End-of-Track, so the corpus has no third-party source or licensing dependency.
private func appendMidiU32(bytes: *Array'u8, value: u32)
{
    bytes.add(cast(u8, value >> 24))
    bytes.add(cast(u8, value >> 16))
    bytes.add(cast(u8, value >> 8))
    bytes.add(cast(u8, value))
}

private func appendMidiTrack(bytes: *Array'u8, events: const [..] u8)
{
    bytes.add(cast(const [..] u8, "MTrk"))
    appendMidiU32(bytes, cast(u32, events.count))
    for event in events do
        bytes.add(event)
}

private func writeMidiMatrixFixture(format, division: u16)->String
{
    // One C4 note lasts exactly 1,000 ticks in each sequence.
    const Events: [13] u8 = [0, 0x90, 60, 100, 0x87, 0x68, 0x80, 60, 0, 0, 0xFF, 0x2F, 0]
    let tracks = format == 0 ? 1'u16 : 2'u16
    var bytes: Array'u8
    bytes.add(cast(const [..] u8, "MThd"))
    bytes.add([0'u8, 0, 0, 6])
    bytes.add(cast(u8, format >> 8))
    bytes.add(cast(u8, format))
    bytes.add(cast(u8, tracks >> 8))
    bytes.add(cast(u8, tracks))
    bytes.add(cast(u8, division >> 8))
    bytes.add(cast(u8, division))
    appendMidiTrack(&bytes, Events)
    if format != 0 do
        appendMidiTrack(&bytes, Events)

    let fileName = Gui.Testing.tempFilePath("scope-midi-matrix-", ".mid")
    expect File.writeAllBytes(fileName, bytes.toSlice())
    return fileName
}

private func requireMidiFormatFailure(fileName: string)
{
    var outcome: Swag.Error
    discard catch Midi.loadDocument(fileName) as outcome
    Swag.require(outcome.value() is Errors.InvalidFormatError)
}

// A generated Cartesian matrix covers SMF formats 0/1/2 under PPQN and each legal SMPTE rate.
#test
{
    const Formats: [3] u16 = [0, 1, 2]
    for format in Formats
    {
        let ppqnFile = writeMidiMatrixFixture(format, 1000)
        defer discard catch File.delete(ppqnFile)
        let ppqn = expect Midi.loadDocument(ppqnFile)
        Swag.require(ppqn.format == format and ppqn.division == 1000)
        Swag.require(ppqn.tracks.count == (format == 0 ? 1 : 2))
        Swag.require(ppqn.notes.count == ppqn.tracks.count)
        Swag.require(Math.abs(ppqn.durationSeconds - 0.5) < 0.00001, Format.toString("format % PPQN: %", format, ppqn.durationSeconds))

        const SmpteDivisions:  [4] u16 = [0xE828, 0xE728, 0xE328, 0xE228]
        const ExpectedSeconds: [4] f64 = [1.0416666667, 1.0, 0.8341675, 0.8333333333]
        for division, index in SmpteDivisions
        {
            let smpteFile = writeMidiMatrixFixture(format, division)
            defer discard catch File.delete(smpteFile)
            let smpte = expect Midi.loadDocument(smpteFile)
            Swag.require(smpte.format == format and smpte.division == division)
            Swag.require(smpte.tracks.count == (format == 0 ? 1 : 2))
            Swag.require(Math.abs(smpte.durationSeconds - ExpectedSeconds[index]) < 0.00001,
                         Format.toString("format % SMPTE division %{X4}: %", format, division, smpte.durationSeconds))
        }
    }
}

// Invalid timing divisions and a format-0 multi-track header are rejected as malformed SMF.
#test
{
    for division in [0'u16, 0xE628, 0xE700, 0xE200]
    {
        let fileName = writeMidiMatrixFixture(1, division)
        defer discard catch File.delete(fileName)
        requireMidiFormatFailure(fileName)
    }

    let fileName = writeMidiMatrixFixture(0, 480)
    defer discard catch File.delete(fileName)
    var bytes = expect File.readAllBytes(fileName)
    bytes[10] = 0
    bytes[11] = 2
    discard expect File.writeAllBytes(fileName, bytes.toSlice())
    requireMidiFormatFailure(fileName)
}

// A generated four-track score covers a named conductor, tempo changes and ensemble parts.
#test
{
    let document = expect Midi.loadDocument(scopeTestDataPath("viewer.ensemble.mid"))
    Swag.require(document.format == 1 and document.division == 480)
    Swag.require(document.tracks.count == 4 and document.tracks[0].name == "Conductor")
    Swag.require(document.tracks[1].name == "Piano" and document.tracks[1].program == 0)
    Swag.require(document.tracks[2].name == "Bass" and document.tracks[2].program == 32)
    Swag.require(document.tracks[3].name == "Drums" and document.tracks[3].program == 0)
    Swag.require(document.notes.count == 62 and document.minKey == 36 and document.maxKey == 72)
    Swag.require(document.tempos.count == 2 and document.timeSignatures.count == 1)
    Swag.require(document.keySignatures.count == 1 and document.keyText() == "C major")
}

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

    // While the score loads there is no roll yet: the information sheet says nothing of it, and
    // the lens offers the zoom of the roll disabled.
    Swag.require(viewer.load.isPending())
    viewer.describeInformation(InfoSheet.create(&host.root))
    var pending: Lens.Results
    var pendingEntries = Viewer.LensEntries.create(&pending, "MIDI", host.theme)
    viewer.describeLens(&pendingEntries)
    var zoomRows = 0
    for &entry in pending.sections[0]!.entries where entry.title == appStrings().cmd_ZoomIn
    {
        Swag.require(entry.disabled)
        zoomRows += 1
    }

    Swag.require(zoomRows == 1)

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

    // The lens fits the score back, as `F` does.
    var zoomed: Lens.Results
    var zoomedEntries = Viewer.LensEntries.create(&zoomed, "MIDI", host.theme)
    viewer.describeLens(&zoomedEntries)
    var fitRows = 0
    for &entry in zoomed.sections[0]!.entries where entry.title == Midi.texts().ui_Fit
    {
        Swag.require(not entry.checked and not entry.disabled)
        entry.run!()
        fitRows += 1
    }

    Swag.require(fitRows == 1 and viewer.roll.fit)

    // At the roll's limits, the step that cannot be taken reads as unavailable.
    for value in [1000.0'f32, 0.0'f32]
    {
        viewer.roll.applyZoom(value)
        var limit: Lens.Results
        var limitEntries = Viewer.LensEntries.create(&limit, "MIDI", host.theme)
        viewer.describeLens(&limitEntries)
        for &entry in limit.sections[0]!.entries
        {
            if entry.title == appStrings().cmd_ZoomIn do
                Swag.require(entry.disabled == (value > 1))
            elif entry.title == appStrings().cmd_ZoomOut do
                Swag.require(entry.disabled == (value < 1))
        }
    }

    // Actual size reads as chosen while the roll shows at it, as the readout's 100 %.
    viewer.roll.applyZoom(1)
    var actual: Lens.Results
    var actualEntries = Viewer.LensEntries.create(&actual, "MIDI", host.theme)
    viewer.describeLens(&actualEntries)
    var actualRows = 0
    for &entry in actual.sections[0]!.entries where entry.title == appStrings().cmd_ZoomReset
    {
        Swag.require(entry.checked)
        actualRows += 1
    }

    Swag.require(actualRows == 1 and viewer.zoomLabel.text() == Viewer.zoomText(100))
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

// A note held from the start of the piece still shows once the view scrolls far past where it
// started, beyond many shorter notes that it no longer reaches.
#test
{
    const ShortNotes = 64'u32
    var bytes: Array'u8
    bytes.add(cast(const [..] u8, "MThd"))
    bytes.add([0'u8, 0, 0, 6, 0, 0, 0, 1, 1, 0xE0])
    bytes.add(cast(const [..] u8, "MTrk"))
    let trackSize = 4 + ShortNotes * 9 + 4 + 4
    bytes.add([0'u8, 0, cast(u8, trackSize >> 8), cast(u8, trackSize & 0xFF)])
    bytes.add([0'u8, 0x90, 60, 100])
    for ShortNotes do
        bytes.add([0'u8, 0x90, 64, 100, 0x83, 0x60, 0x80, 64, 0])
    bytes.add([0'u8, 0x80, 60, 0])
    bytes.add([0'u8, 0xFF, 0x2F, 0])
    let fileName = Gui.Testing.tempFilePath("scope-midi-held-", ".mid")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, bytes.toSlice())
    var document = expect Midi.loadDocument(fileName)
    Swag.require(document.notes.count == ShortNotes + 1 and document.longestNote == ShortNotes * 480)

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let roll = Midi.RollView.create(&host.root, #move document)
    host.root.applyLayout()
    roll.applyZoom(1)
    roll.scroll.setScrollPos(roll.timelineWidth * 0.5, 0)
    Swag.require(roll.scrollPos.x > roll.clientRect().width)

    // The held key's row is painted across the view; the next white key, which no note plays, is not.
    func rowY(roll: *Midi.RollView, key: u8)->s32
    {
        let middle = roll.plotTop + (cast(f32, roll.highKey - key) + 0.5) * roll.rowHeight
        return cast(s32, roll.surfaceRect().y + middle)
    }

    let image = host.render(&host.root)
    let x     = cast(s32, roll.surfaceRect().x + roll.clientRect().width * 0.75)
    Swag.require(image.pixelColor(x, rowY(roll, 60)) != image.pixelColor(x, rowY(roll, 62)))
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

    // A file that failed has no roll to translate or describe.
    host.notify(.LanguageChanged)
    viewer.describeInformation(InfoSheet.create(&host.root))
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
    bytes.add([0'u8, 0, 0, 82])
    bytes.add([0x00'u8, 0xC0, 0x18, 0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20, 0x00, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08,
               0x00, 0xFF, 0x59, 0x02, 0x00, 0x00, 0x00, 0x90, 0x3C, 0x64, 0x83, 0x60, 0xFF, 0x51, 0x03,
               0x06, 0x1A, 0x80, 0x00, 0xFF, 0x58, 0x04, 0x03, 0x02, 0x18, 0x08, 0x83, 0x60, 0xFF, 0x51,
               0x03, 0x07, 0xA1, 0x20, 0x00, 0xFF, 0x59, 0x02, 0x01, 0x00, 0x00, 0x80, 0x3C, 0x00,
               0x83, 0x60, 0xFF, 0x59, 0x02, 0xFE, 0x01, 0x00, 0x90, 0x46, 0x64, 0x83, 0x60, 0x80,
               0x46, 0x00, 0x00, 0xFF, 0x2F, 0x00])
    let fileName = Gui.Testing.tempFilePath("scope-midi-changes-", ".mid")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, bytes.toSlice())

    let document = expect Midi.loadDocument(fileName)
    Swag.require(document.tempos.count == 3 and document.bpm() == 120)
    Swag.require(document.tempoText() == "120–150 BPM · 2 changes", document.tempoText())
    Swag.require(document.meterChangesText() == "4/4 · 1 change", document.meterChangesText())
    Swag.require(document.keyChangesText() == "C major · 2 changes", document.keyChangesText())
    Swag.require(document.keySignatures.count == 3 and
                 document.keySignatures[2].sharps == -2 and
                 document.keySignatures[2].minor)

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    var result = openTestViewer(Midi.viewerPlugin(), &host.root, fileName, commandParent: &host.root)
    let view   = assume cast(*Midi.Panel, result.view)
    completeViewerBackgroundLoad(&host, &view.load)

    view.roll.setMode(.Pitches)
    view.setScaleHighlight(true)
    Swag.require(view.roll.pitchIsHighlighted(0, 60) and not view.roll.pitchIsHighlighted(0, 61))
    Swag.require(view.roll.pitchIsHighlighted(960, 66) and not view.roll.pitchIsHighlighted(960, 65))
    Swag.require(view.roll.pitchIsHighlighted(1440, 70) and not view.roll.pitchIsHighlighted(1440, 71))

    // Channel 10 remains a percussion map and never receives key-signature colouring.
    for &note in view.roll.document.notes do
        note.channel = 9
    view.roll.collectLanes()
    Swag.require(view.roll.scaleHighlightMaskAt(1440) == 0)
    for &note in view.roll.document.notes do
        note.channel = 0
    view.roll.collectLanes()

    let sheet = InfoSheet.create(&host.root)
    view.describeInformation(sheet)
    let text = sheet.text()
    Swag.require(Utf8.contains(text, "Tempo\n120–150 BPM · 2 changes"), text)
    Swag.require(Utf8.contains(text, "Time signature\n4/4 · 1 change"), text)
    Swag.require(Utf8.contains(text, "Key\nC major · 2 changes"), text)

    // The track lists its channel, the General MIDI instrument it selects and its notes.
    Swag.require(document.tracks[0].program == 24 and Midi.instrumentName(24) == "Acoustic Guitar (nylon)")
    Swag.require(Utf8.contains(text, "channel 1 · Acoustic Guitar (nylon) · 2 notes"), text)
}

// The Explorer preview of a MIDI file is its notes as a small piano roll on a light ground.
#test
{
    let plugin = Midi.viewerPlugin()
    let image  = expect plugin.thumbnail!(midiViewerFixturePath(), 128)
    Swag.require(image.width == 128 and image.height == 64)

    // Some pixels carry the ink of the notes, the rest the ground.
    var ink = 0'u32
    for y in image.height
    {
        for x in image.width
        {
            let color = image.pixelColor(x, y)
            if color.r < 100 do
                ink += 1
        }
    }

    Swag.require(ink > 20 and ink < 128 * 64 / 2, Format.toString("%", ink))
}
