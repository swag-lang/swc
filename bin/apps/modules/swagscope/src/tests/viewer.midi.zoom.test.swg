#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

func midiZoomFixturePath()->String => Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/viewer.mid")

#test
{
    var document = expect Midi.loadDocument(midiZoomFixturePath())
    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

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
    roll.scroll.setScrollPos(0, 120)
    Swag.assert(roll.scroll.scrollPosition().y > 0)

    roll.applyPitchZoom(0)
    Swag.assert(roll.pitchZoom == 0.5)
    roll.zoomToFit()
    Swag.assert(roll.pitchZoom == 1 and roll.scroll.scrollPosition().y == 0)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 520)
    defer
    {
        discard catch host.app.setLanguage(ReferenceLanguage)
        host.shutdown()
    }

    var session = openTestViewer(Midi.viewerPlugin(), &host.root, midiZoomFixturePath())
    let viewer  = assume cast(*Midi.Panel, session.view)
    completeViewerBackgroundLoad(&host, &viewer.load)
    Swag.assert(viewer.pitchLabelCombo.items.count == 2 and viewer.roll.pitchLabel(60) == "C4")
    Swag.assert(viewer.keyboardWidthCombo.items.count == 3 and viewer.roll.keyboardWidth == 72)

    viewer.pitchLabelCombo.setSelectedIndex(1)
    Swag.assert(viewer.roll.pitchLabelMode == .MidiNumber and viewer.roll.pitchLabel(60) == "60")
    viewer.keyboardWidthCombo.setSelectedIndex(0)
    Swag.assert(viewer.roll.keyboardWidth == 56)
    viewer.keyboardWidthCombo.setSelectedIndex(2)
    Swag.assert(viewer.roll.keyboardWidth == 112)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.assert(viewer.pitchLabelCombo.selectedIndex == 1)
    Swag.assert(viewer.keyboardWidthCombo.selectedIndex == 2)
    Swag.assert(viewer.keyboardWidthCombo.items[2]!.name.raw == "Large")
    expect host.app.setLanguage(ReferenceLanguage)
}

#[Swag.TestTag("golden")]
#test
{
    var document = expect Midi.loadDocument(midiZoomFixturePath())
    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let roll = Midi.RollView.create(&host.root, #move document)
    host.root.applyLayout()
    roll.refreshLayout()
    roll.applyPitchZoom(2)
    roll.scroll.setScrollPos(0, 120)
    host.settleAnimations(&host.root, 4)
    let image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.midi.vertical-zoom")
}
