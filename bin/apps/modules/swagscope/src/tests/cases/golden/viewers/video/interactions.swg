#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// The time prompt fits its French help and inline validation at the shared dialog measure.
#[Swag.TestTag("golden")]
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, videoMatroskaFixturePath(), true)
    let view   = assume cast(*Film.Panel, window.currentView)
    waitForVideoFrame(view)
    pinVideoFrame(view, 0)
    expect host.app.setLanguage("fr")
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    let dialog = view.createTimeDialog()
    dialog.setText("9:99")
    discard dialog.edit!.revalidate()
    dialog.applyLayout()
    var image = host.renderSurface(unwrap dialog.surface)
    Pixel.Testing.assertImageGolden(&image, "viewer.video.time.error.fr.paper")
}

// The first-use hints stay above the transport, then leave after three deliberate gestures.
#[Swag.TestTag("golden")]
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    let savedHints = Film.g_PlaybackHintUses
    defer Film.g_PlaybackHintUses = savedHints
    Film.g_PlaybackHintUses = 0
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, videoMatroskaFixturePath(), false)
    let view   = assume cast(*Film.Panel, window.currentView)
    waitForVideoFrame(view)
    pinVideoFrame(view, 0)
    view.showPlaybackHelp()
    Swag.require(view.helpLine != null and view.helpLine.isLocallyVisible())
    var image = host.renderSettled(&host.surfaceWnd)
    assertVideoRendererGolden(&image, "viewer.video.shortcuts.ink")
    for 3 do
        view.notePlaybackGesture()
    Swag.require(not view.helpLine.isLocallyVisible())
}

// French subtitle attachment and timing stay reachable at the minimum viewer width.
#[Swag.TestTag("golden")]
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    let savedHints = Film.g_PlaybackHintUses
    defer Film.g_PlaybackHintUses = savedHints
    Film.g_PlaybackHintUses = 3
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, videoMatroskaFixturePath(), true, ViewerWindow.MinWidth, 450)
    let view   = assume cast(*Film.Panel, window.currentView)
    waitForVideoFrame(view)
    pinVideoFrame(view, 0)
    view.subtitleOverlay.sidecars.add(expect Video.Subtitle.Track.loadOwned(scopeTestDataPath("viewer.srt")))
    view.finishSubtitles()
    expect host.app.setLanguage("fr")
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    assertScopeAnchoredMenuWith(&host, window, "menus.video.subtitles.fr.paper", func|view, host = &host|()
    {
        openVideoLensChoice(host, view, Film.texts().cmd_Subtitles)
    })
}
