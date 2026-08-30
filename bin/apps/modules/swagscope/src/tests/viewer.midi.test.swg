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

    let commandBar = Wnd.create'Wnd(&host.root, {0, 0, 0, 52})
    commandBar.dockStyle       = .Top
    commandBar.backgroundStyle = .Window
    commandBar.padding         = {16, 8, 16, 8}

    let fileName = midiTestFixture()
    var result   = openTestViewer(&createMidiViewer, &host.root, fileName.toString(), commandParent: commandBar)
    Swag.assert(result.view != null and result.commands != null)

    let viewer = cast(*MidiViewer) result.view!
    completeViewerBackgroundLoad(&host, &viewer.load, viewer.loadTimer)
    Swag.assert(Utf8.contains(viewer.details.toSlice(), "7 notes"))
    viewer.dockStyle          = .Center
    viewer.commands.dockStyle = .Right
    Swag.assert(viewer.trackCombo.items.count == 2)
    viewer.trackCombo.setSelectedIndex(1)
    Swag.assert(viewer.roll.selectedTrack == 0 and viewer.roll.selectedNoteCount() == 7)
    viewer.trackCombo.setSelectedIndex(0)
    let fitZoom = viewer.roll.zoom
    viewer.roll.zoomIn()
    Swag.assert(!viewer.roll.fit and viewer.roll.zoom > fitZoom)
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
    Swag.assert(viewer.zoomOutButton.toolTip == "Réduire le zoom")
    Swag.assert(viewer.fitButton.toolTip == "Ajuster la partition complète")
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
    var result = openTestViewer(&createMidiViewer, &host.root, fileName, commandParent: &host.root)
    Swag.assert(result.view != null and result.commands != null)
    let viewer = cast(*MidiViewer) result.view!
    completeViewerBackgroundLoad(&host, &viewer.load, viewer.loadTimer)
    Swag.assert(!viewer.failureReason.isEmpty())
}
