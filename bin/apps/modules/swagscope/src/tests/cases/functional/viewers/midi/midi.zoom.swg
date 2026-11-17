#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

internal func midiZoomFixturePath()->String => scopeTestDataPath("viewer.mid")

#test
{
    var document = expect Midi.loadDocument(midiZoomFixturePath())
    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let roll = Midi.RollView.create(&host.root, #move document)
    host.root.applyLayout()
    roll.refreshLayout()
    let fittedRowHeight = roll.rowHeight
    Swag.require(roll.pitchLabel(60) == "C4")
    Swag.require(roll.pitchZoom == 1 and roll.scroll.scrollSize.y <= roll.clientRect().height + 1)

    var zoomIn = KeyEvent{kind: .Pressed, key: .OemPlus, modifiers: .Control | .Shift}
    roll.sendEvent(&zoomIn)
    Swag.require(roll.pitchZoom == 1.25 and roll.rowHeight > fittedRowHeight)
    Swag.require(roll.scroll.scrollSize.y > roll.clientRect().height)

    // A wheel notch scales the pitch by an eighth, as it scales the timeline.
    host.mouseWheel(roll.surfaceRect().center(), 120, .Control | .Shift)
    Swag.require(Math.isEqualEpsilon(roll.pitchZoom, 1.25 * 1.12, 0.0001))
    var pageDown = KeyEvent{kind: .Pressed, key: .PageDown}
    roll.sendEvent(&pageDown)
    let pageDownPosition = roll.scroll.scrollPosition().y
    Swag.require(pageDown.accepted and pageDownPosition > 0)
    var pageUp = KeyEvent{kind: .Pressed, key: .PageUp}
    roll.sendEvent(&pageUp)
    Swag.require(pageUp.accepted and roll.scroll.scrollPosition().y == 0)

    roll.applyPitchZoom(0)
    Swag.require(roll.pitchZoom == 0.5)
    roll.zoomToFit()
    Swag.require(roll.pitchZoom == 1 and roll.scroll.scrollPosition().y == 0)
}

#test
{
    let previousSettings = Midi.g_ViewerSettings
    defer Midi.g_ViewerSettings = previousSettings
    Midi.g_ViewerSettings = {}
    var host: Testing.HeadlessHost
    host.setup(800, 520)
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    var session = openTestViewer(Midi.viewerPlugin(), &host.root, midiZoomFixturePath())
    let viewer  = assume cast(*Midi.Panel, session.view)
    completeViewerBackgroundLoad(&host, &viewer.load)
    Swag.require(viewer.roll.pitchLabel(60) == "C4" and viewer.roll.keyboardWidth == 72)
    Swag.require(viewer.zoomLabel.toolTip == Midi.texts().ui_ZoomMenu)

    viewer.setPitchLabelMode(.MidiNumber)
    Swag.require(viewer.roll.pitchLabelMode == .MidiNumber and viewer.roll.pitchLabel(60) == "60")
    Swag.require(Midi.g_ViewerSettings.pitchLabelMode == .MidiNumber)
    host.activateOptionRowWhenShown(Midi.texts().ui_KeyboardWidth)
    host.thenActivateOptionRow(Midi.texts().ui_KeyboardCompact)
    viewer.showOptions()
    Swag.require(viewer.roll.keyboardWidth == 56)
    viewer.setKeyboardWidthMode(2)
    Swag.require(viewer.roll.keyboardWidth == 112 and Midi.g_ViewerSettings.keyboardWidthMode == 2)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    var options: OptionSheet.Page
    viewer.describeOptions(&options)
    Swag.require(options.rows[2].value == "Nombres MIDI" and options.rows[3].value == "Large")
    Swag.require(viewer.zoomLabel.toolTip == Midi.texts().ui_ZoomMenu)
    expect host.app.setLanguage(ReferenceLanguage)
}

// A score too long to fit even at the smallest zoom stays fitted when a zoom-out step at that
// limit changes nothing, so the roll keeps following the window instead of freezing its scale.
#test
{
    var bytes: Array'u8
    bytes.add(cast(const [..] u8, "MThd"))
    bytes.add([0'u8, 0, 0, 6, 0, 0, 0, 1, 1, 0xE0])
    bytes.add(cast(const [..] u8, "MTrk"))
    bytes.add([0'u8, 0, 0, 15])
    bytes.add([0'u8, 0x90, 60, 100])
    bytes.add([0x81'u8, 0x80, 0x80, 0x00, 0x80, 60, 0])
    bytes.add([0'u8, 0xFF, 0x2F, 0])
    let fileName = Gui.Testing.tempFilePath("scope-midi-long-", ".mid")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, bytes.toSlice())
    var document = expect Midi.loadDocument(fileName)

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    let roll = Midi.RollView.create(&host.root, #move document)
    host.root.applyLayout()
    roll.refreshLayout()
    Swag.require(roll.fit and not roll.canZoomOut())
    let smallest = roll.zoom

    roll.zoomOut()
    Swag.require(roll.fit and roll.zoom == smallest)
    host.mouseWheel(roll.surfaceRect().center(), -120, .Control)
    Swag.require(roll.fit and roll.zoom == smallest)

    // A key step and a wheel notch scale the timeline as the picture and PDF views scale theirs.
    roll.zoomIn()
    Swag.require(not roll.fit and Math.isEqualEpsilon(roll.zoom, smallest * 1.25, 0.0001))
    host.mouseWheel(roll.surfaceRect().center(), 120, .Control)
    Swag.require(Math.isEqualEpsilon(roll.zoom, smallest * 1.25 * 1.12, 0.0001))
}
