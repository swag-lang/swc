#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

func midiZoomFixturePath()->String => Path.combine(unwrap Path.directoryName(#curlocation.fileName), "datas/viewer.mid")

#test
{
    var document = expect Midi.loadDocument(midiZoomFixturePath())
    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let roll = Midi.RollView.create(&host.root, #move document)
    host.root.applyLayout()
    roll.refreshLayout()
    let fittedRowHeight = roll.rowHeight
    Swag.assert(roll.pitchLabel(60) == "C4")
    Swag.assert(roll.pitchZoom == 1 and roll.scroll.scrollSize.y <= roll.clientRect().height + 1)

    var zoomIn = KeyEvent{kind: .Pressed, key: .OemPlus, modifiers: .Control}
    roll.sendEvent(&zoomIn)
    Swag.assert(roll.pitchZoom == 1.25 and roll.rowHeight > fittedRowHeight)
    Swag.assert(roll.scroll.scrollSize.y > roll.clientRect().height)

    host.mouseWheel(roll.surfaceRect().center(), 120, .Control)
    Swag.assert(roll.pitchZoom == 1.5625)
    var pageDown = KeyEvent{kind: .Pressed, key: .PageDown}
    roll.sendEvent(&pageDown)
    let pageDownPosition = roll.scroll.scrollPosition().y
    Swag.assert(pageDown.accepted and pageDownPosition > 0)
    var pageUp = KeyEvent{kind: .Pressed, key: .PageUp}
    roll.sendEvent(&pageUp)
    Swag.assert(pageUp.accepted and roll.scroll.scrollPosition().y == 0)

    roll.applyPitchZoom(0)
    Swag.assert(roll.pitchZoom == 0.5)
    roll.zoomToFit()
    Swag.assert(roll.pitchZoom == 1 and roll.scroll.scrollPosition().y == 0)
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
    Swag.assert(viewer.roll.pitchLabel(60) == "C4" and viewer.roll.keyboardWidth == 72)
    Swag.assert(viewer.zoomLabel.toolTip.contains("Page Up/Down"))

    viewer.setPitchLabelMode(.MidiNumber)
    Swag.assert(viewer.roll.pitchLabelMode == .MidiNumber and viewer.roll.pitchLabel(60) == "60")
    Swag.assert(Midi.g_ViewerSettings.pitchLabelMode == .MidiNumber)
    host.activateOptionRowWhenShown(Midi.texts().ui_KeyboardWidth)
    host.thenActivateOptionRow(Midi.texts().ui_KeyboardCompact)
    viewer.showOptions()
    Swag.assert(viewer.roll.keyboardWidth == 56)
    viewer.setKeyboardWidthMode(2)
    Swag.assert(viewer.roll.keyboardWidth == 112 and Midi.g_ViewerSettings.keyboardWidthMode == 2)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    var options: OptionSheet.Page
    viewer.describeOptions(&options)
    Swag.assert(options.rows[2].value == "Nombres MIDI" and options.rows[3].value == "Large")
    Swag.assert(viewer.zoomLabel.toolTip.contains("Page précédente/suivante"))
    expect host.app.setLanguage(ReferenceLanguage)
}

#[Swag.TestTag("golden")]
#test
{
    var document = expect Midi.loadDocument(midiZoomFixturePath())
    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let roll = Midi.RollView.create(&host.root, #move document)
    host.root.applyLayout()
    roll.refreshLayout()
    roll.applyPitchZoom(2)
    roll.scroll.setScrollPos(0, 120)
    host.settleAnimations(&host.root, 4)
    let image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.midi.vertical-zoom")
}
