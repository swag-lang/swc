#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// The score in the window, against `scope.midi`: one lane per track under the bar numbers, each
// track in its hue with its name and channel, the notes spread by pitch in the lane.
#[Swag.TestTag("golden")]
#test
{
    let fileName = scopeTestDataPath("viewer.groove.mid")
    var host: Testing.HeadlessHost
    let window   = framedViewerWindow(&host, fileName.toString(), true)
    let view     = assume cast(*Midi.Panel, window.instances[window.activeChoiceIndex].view)
    Swag.require(view.roll.mode == .Tracks and view.roll.lanes.count == 4)
    Swag.require(view.details.contains("4 tracks · 4/4"))

    var image = host.render(&host.surfaceWnd)
    assertScopeImageGolden(&image, "viewer.midi.paper")
}
