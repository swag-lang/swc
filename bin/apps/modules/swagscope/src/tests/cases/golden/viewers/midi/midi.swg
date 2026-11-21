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

// A drum track read by pitch names each key by the General MIDI sound it plays, not by a pitch no
// drum has, over rows fitted to the keys it strikes; the whole piece, which also holds pitched
// tracks, keeps its pitch names.
#[Swag.TestTag("golden")]
#test
{
    Swag.require(Midi.percussionName(36) == "Bass Drum 1" and Midi.percussionName(42) == "Closed Hi-Hat")
    Swag.require(Midi.percussionName(34) == "" and Midi.percussionName(82) == "")

    let fileName = scopeTestDataPath("viewer.groove.mid")
    var host: Testing.HeadlessHost
    let window   = framedViewerWindow(&host, fileName.toString(), false)
    let view     = assume cast(*Midi.Panel, window.instances[window.activeChoiceIndex].view)
    view.roll.setMode(.Pitches)
    Swag.require(not view.roll.showsPercussion())

    var drums = Swag.U32.Max
    for lane in view.roll.lanes where lane.channel == 9 do
        drums = lane.track
    Swag.require(drums != Swag.U32.Max)
    view.roll.setTrack(drums)
    Swag.require(view.roll.showsPercussion())

    // The rows span the drums' own keys, tall enough for their names without a zoom.
    Swag.require(view.roll.lowKey >= 33 and view.roll.highKey <= 83)

    var image = host.render(&host.surfaceWnd)
    assertScopeImageGolden(&image, "viewer.midi.drums.encre")
}

// Key-signature highlighting is visible on pitched rows, while the multi-key score keeps its
// changes separated into musical-time segments.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.ensemble.mid"), true)
    let view   = assume cast(*Midi.Panel, window.instances[window.activeChoiceIndex].view)
    view.roll.setMode(.Pitches)
    view.setScaleHighlight(true)
    Swag.require(view.roll.scaleHighlightMaskAt(0) != 0)
    Swag.require(view.roll.scaleHighlightMaskAt(view.roll.document.durationTicks) != 0)

    var image = host.render(&host.surfaceWnd)
    assertScopeImageGolden(&image, "viewer.midi.scale-highlight.paper")
}
