#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

func midiTestPoke(bytes: *Array'u8, at, value, size: u64)
{
    for index in size do
        bytes[][at + index] = cast(u8) ((cast(u64) value >> cast(u32) ((size - index - 1) * 8)) & 0xFF)
}

func midiTestPokeText(bytes: *Array'u8, at: u64, text: string)
{
    for value, index in text do
        bytes[][at + index] = value
}

func midiTestFixture()->String
{
    var bytes: Array'u8
    bytes.resize(22)
    midiTestPokeText(&bytes, 0, "MThd")
    midiTestPoke(&bytes, 4, 6, 4)
    midiTestPoke(&bytes, 8, 0, 2)
    midiTestPoke(&bytes, 10, 1, 2)
    midiTestPoke(&bytes, 12, 480, 2)
    midiTestPokeText(&bytes, 14, "MTrk")

    const Track = [0'u8, 0xFF, 0x03, 10, 'P'u8, 'i'u8, 'a'u8, 'n'u8, 'o'u8, ' 'u8, 'R'u8, 'o'u8, 'l'u8, 'l'u8,
                   0, 0xFF, 0x51, 3, 0x07, 0xA1, 0x20,
                   0, 0xFF, 0x58, 4, 4, 2, 24, 8,
                   0, 0xFF, 0x59, 2, 0, 0,
                   0, 0x90, 60, 104, 0x81, 0x70, 0x80, 60, 0,
                   0, 0x90, 64, 96, 0x81, 0x70, 0x80, 64, 0,
                   0, 0x90, 67, 92, 0x81, 0x70, 0x80, 67, 0,
                   0, 0x90, 72, 112, 0x83, 0x60, 0x80, 72, 0,
                   0, 0x90, 67, 88, 0x81, 0x70, 0x80, 67, 0,
                   0, 0x90, 64, 92, 0x81, 0x70, 0x80, 64, 0,
                   0, 0x90, 60, 108, 0x83, 0x60, 0x80, 60, 0,
                   0, 0xFF, 0x2F, 0]
    midiTestPoke(&bytes, 18, @countof(Track), 4)
    bytes.add(Track)

    let fileName = Gui.Testing.tempFilePath("filescope-midi-", ".mid")
    expect File.writeAllBytes(fileName, bytes.toSlice())
    return fileName
}

#test
{
    let fileName = midiTestFixture()
    defer discard catch File.delete(fileName.toString())

    let document = expect loadMidiDocument(fileName.toString())
    @assert(document.format == 0 and document.division == 480)
    @assert(document.tracks.count == 1 and document.tracks[0].name == "Piano Roll")
    @assert(document.notes.count == 7 and document.tracks[0].noteCount == 7)
    @assert(document.minKey == 60 and document.maxKey == 72)
    @assert(document.tempos.count == 1 and midiBpm(&document) == 120)
    @assert(document.timeSignatures.count == 1 and midiMeterText(&document) == "4/4")
    @assert(document.keySignatures.count == 1 and midiKeyText(&document) == "C major")
    @assert(Math.abs(document.durationSeconds - 2.25) < 0.001)
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
    defer discard catch File.delete(fileName.toString())
    let request = ViewerRequest{&host.root, commandBar, fileName.toString()}
    var result: ViewerResult
    createMidiViewer(&request, &result)
    @assert(result.view != null and result.commands != null)
    @assert(Utf8.contains(result.details.toSlice(), "7 notes"))

    let viewer = cast(*MidiViewer) result.view!
    viewer.dockStyle          = .Center
    viewer.commands.dockStyle = .Right
    @assert(viewer.trackCombo.items.count == 2)
    viewer.trackCombo.setSelectedIndex(1)
    @assert(viewer.roll.selectedTrack == 0 and viewer.roll.selectedNoteCount() == 7)
    viewer.trackCombo.setSelectedIndex(0)
    let fitZoom = viewer.roll.zoom
    viewer.roll.zoomIn()
    @assert(!viewer.roll.fit and viewer.roll.zoom > fitZoom)
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
    @assert(viewer.trackCombo.selectedItem()!.name.raw == "Toutes les pistes")
    @assert(viewer.zoomOutButton.toolTip == "Réduire le zoom")
    @assert(viewer.fitButton.toolTip == "Ajuster la partition complète")
    Testing.assertContentFits(viewer.commands)
}

#test
{
    let fileName = Gui.Testing.tempFilePath("filescope-midi-bad-", ".mid")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "not MIDI")

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    let request = ViewerRequest{&host.root, &host.root, fileName}
    var result: ViewerResult
    createMidiViewer(&request, &result)
    @assert(result.view == null and result.commands == null and !result.failureReason.isEmpty())
}
