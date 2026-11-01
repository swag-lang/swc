#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Audio, Viewers

// The recording in the window, against `scope.sound`: the cover, the name and who made it, the
// wave as bars played in Arc up to the play head, and the times under it.
#[Swag.TestTag("golden")]
#test
{
    let fileName = Path.combine(Env.getSpecialDirectory(.Temp), "viewer.sound.preview.wav")
    defer discard catch File.delete(fileName)
    let wav = previewWav()
    expect File.writeAllBytes(fileName, wav.toSlice())

    Swag.assert(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    for light in [false, true]
    {
        var host: Testing.HeadlessHost
        let window = framedViewerWindow(&host, fileName.toString(), light)
        let view   = assume cast(*Sound.Panel, window.instances[window.activeChoiceIndex].view)
        waitForSoundOpen(&host, view)
        finishWaveform(view)

        // Photographed mid-playback, with the tags a recording carries.
        view.tags.title  = "Harbour Lights"
        view.tags.artist = "The Quiet Pier"
        view.tags.album  = "Night Ferries"
        view.tags.year   = "2026"
        view.elapsed     = view.duration * 0.38
        view.refreshTransport()
        view.invalidate()
        host.settleAnimations(window, 4)

        var image = host.render(&host.surfaceWnd)
        Pixel.Testing.assertImageGolden(&image, light ? "viewer.sound.paper" : "viewer.sound.ink")
    }
}
