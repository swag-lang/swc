#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// The reading list in the window, against `scope.subtitle`: the name and its mono line, the cues
// as rows of a number, a time range and the words, the current one on the selection ground.
#[Swag.TestTag("golden")]
#test
{
    let fileName = scopeTestDataPath("viewer.reading.srt")
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, fileName.toString(), false)
    let view   = assume cast(*Captions.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.assert(view.revealCue(1))
    window.applyLayout()
    host.settleAnimations(window, 4)

    var image = host.render(&host.surfaceWnd)
    assertScopeImageGolden(&image, "viewer.subtitle.ink")
}
