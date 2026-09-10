#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

func midiTestFixture()->String
{
    return Path.combine(Path.combine(Path.directoryName(#curlocation.fileName)!, "datas"), "viewer.mid")
}

#test
{
    let fileName = midiTestFixture()

    let document = expect loadMidiDocument(fileName.toString())
    Swag.assert(document.format == 0 and document.division == 480)
    Swag.assert(document.tracks.count == 1 and document.tracks[0].name == "Piano Roll")
    Swag.assert(document.notes.count == 7 and document.tracks[0].noteCount == 7)
    Swag.assert(document.minKey == 60 and document.maxKey == 72)
    Swag.assert(document.tempos.count == 1 and midiBpm(&document) == 120)
    Swag.assert(document.timeSignatures.count == 1 and midiMeterText(&document) == "4/4")
    Swag.assert(document.keySignatures.count == 1 and midiKeyText(&document) == "C major")
    Swag.assert(Math.abs(document.durationSeconds - 2.25) < 0.001)
}

// The empty-score fallback must not replace the highest pitch of an actual score.
#test
{
    for key in [0'u8, 36, 100, 127]
    {
        var bytes: Array'u8
        bytes.add(cast(const [..] u8) "MThd")
        bytes.add([0'u8, 0, 0, 6, 0, 0, 0, 1, 1, 0xE0])
        bytes.add(cast(const [..] u8) "MTrk")
        bytes.add([0'u8, 0, 0, 13, 0, 0x90, key, 100, 0x83, 0x60, 0x80, key, 0, 0, 0xFF, 0x2F, 0])
        let fileName = Gui.Testing.tempFilePath("scope-midi-pitch-", ".mid")
        defer discard catch File.delete(fileName)
        expect File.writeAllBytes(fileName, bytes.toSlice())
        var document = expect loadMidiDocument(fileName)
        Swag.assert(document.notes.count == 1 and document.minKey == key and document.maxKey == key)

        var host: Testing.HeadlessHost
        host.setup(640, 360)
        defer host.shutdown()
        let roll = MidiRollView.create(&host.root, #move document)
        roll.refreshLayout()
        Swag.assert(roll.lowKey <= key and roll.highKey >= key and roll.highKey >= roll.lowKey)
        let image = host.render(&host.root)
        Swag.assert(image.isValid())
    }
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let commandBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 52})
    commandBar.dockStyle       = .Bottom
    commandBar.backgroundStyle = .Window
    commandBar.padding         = {16, 8, 16, 8}
    let infoBar = Wnd.create'ViewerActionBar(&host.root, {0, 0, 0, 40})
    infoBar.dockStyle       = .Top
    infoBar.backgroundStyle = .InformationBar
    infoBar.padding         = {16, 4, 16, 4}

    let fileName = midiTestFixture()
    var result   = openTestViewer(midiViewerPlugin(), &host.root, fileName.toString(), commandParent: commandBar, infoParent: infoBar)
    Swag.assert(result.view != null and result.commands != null)
    commandBar.centerGroup = result.commands
    infoBar.centerGroup    = result.info

    let viewer = cast(*MidiViewer) result.view!
    completeViewerBackgroundLoad(&host, &viewer.load, viewer.loadTimer)
    assertViewerInfoButton(viewer.zoomLabel)
    Swag.assert(result.info!.preferredSize.x == ViewerZoomSlotWidth)
    Swag.assert(Utf8.contains(viewer.details.toSlice(), "7 notes"))
    viewer.dockStyle          = .Center
    viewer.commands.dockStyle = .None
    result.info!.dockStyle    = .None
    Swag.assert(viewer.trackCombo.items.count == 2)
    viewer.trackCombo.setSelectedIndex(1)
    Swag.assert(viewer.roll.selectedTrack == 0 and viewer.roll.selectedNoteCount() == 7)
    viewer.trackCombo.setSelectedIndex(0)
    let fitZoom = viewer.roll.zoom
    viewer.roll.zoomIn()
    Swag.assert(not viewer.roll.fit and viewer.roll.zoom > fitZoom)
    viewer.roll.zoomToFit()

    host.root.applyLayout()
    viewer.roll.refreshLayout()
    host.settleAnimations(&host.root, 4)
    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.midi.document")

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    host.root.applyLayout()
    var french = host.render(&host.root)
    discard french
    Swag.assert(viewer.trackCombo.selectedItem()!.name.raw == "Toutes les pistes")
    Swag.assert(viewer.zoomLabel.toolTip == "Options de zoom")
    Testing.assertContentFits(viewer.commands)
}

#test
{
    let fileName = Gui.Testing.tempFilePath("scope-midi-bad-", ".mid")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "not MIDI")

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    var result = openTestViewer(midiViewerPlugin(), &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view != null and result.commands != null)
    let viewer = cast(*MidiViewer) result.view!
    completeViewerBackgroundLoad(&host, &viewer.load, viewer.loadTimer)
    Swag.assert(not viewer.failureReason.isEmpty())
}
