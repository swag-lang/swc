#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Video, Audio, Viewers

// Playback options and track settings each open above their own control; direct lens commands
// still reach the sound and subtitle choices without a duplicate readout on the veil.
#[Swag.TestTag("golden")]
#test
{
    let savedHints = Film.g_PlaybackHintUses
    defer Film.g_PlaybackHintUses = savedHints
    Film.g_PlaybackHintUses = 3
    Swag.require(Sound.acquireEngine(.NoSound))
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

#[Swag.TestTag("golden")]
#test
{
    let savedHints = Film.g_PlaybackHintUses
    defer Film.g_PlaybackHintUses = savedHints
    Film.g_PlaybackHintUses = 3
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, videoMatroskaFixturePath(), true)
    let view   = assume cast(*Film.Panel, window.currentView)
    waitForVideoAudio(view, 2)
    pinVideoFrame(view, 5)

    assertScopeAnchoredMenuWith(&host, window, "menus.video.frame.paper", func|view, host = &host|()
    {
        var point = view.imageView.surfaceRect().center()
        host.surface.surfaceToScreen(&point)
        host.click(point, .Right)
    })
}
