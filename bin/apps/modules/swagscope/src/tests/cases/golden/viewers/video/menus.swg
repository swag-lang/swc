#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Video, Audio, Viewers

// Opens a track choice through the command a reader can use from the lens.
func openVideoLensChoice(host: *Testing.HeadlessHost, view: *Film.Panel, title: string)
{
    var results: Lens.Results
    var entries = Viewer.LensEntries.create(&results, "Video", host.theme)
    view.describeLens(&entries)
    for &entry in results.sections[0]!.entries where entry.title == title
    {
        entry.run!()
        return
    }
    Swag.require(false, title)
}

// Playback options and track settings each open above their own control; direct lens commands
// still reach the sound and subtitle choices without a duplicate readout on the veil.
#[Swag.TestTag("golden")]
#test
{
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, videoMatroskaFixturePath(), false)
    let view   = assume cast(*Film.Panel, window.currentView)
    waitForVideoFrame(view)
    waitForVideoAudio(view, 2)
    view.veilsHeld = true
    pinVideoFrame(view, 5)
    view.timeline.setValueWithoutGesture(cast(f32, view.elapsed))
    host.moveMouse(view.timeline.surfaceRect().center())
    host.finishAnimations()
    assertScopeAnchoredMenu(&host, window, view.optionsButton, "menus.video.options")
    view.subtitleOverlay.sidecars.add(expect Video.Subtitle.Track.loadOwned(scopeTestDataPath("viewer.srt")))
    view.finishSubtitles()
    assertScopeAnchoredMenu(&host, window, view.tracksButton, "menus.video.tracks")
    assertScopeAnchoredMenuWith(&host, window, "menus.video.audio", func|view, host = &host|() { openVideoLensChoice(host, view, Film.texts().cmd_AudioTrack) })
    assertScopeAnchoredMenuWith(&host, window, "menus.video.subtitles", func|view, host = &host|() { openVideoLensChoice(host, view, Film.texts().cmd_Subtitles) })
}
