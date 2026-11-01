#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Viewers

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
