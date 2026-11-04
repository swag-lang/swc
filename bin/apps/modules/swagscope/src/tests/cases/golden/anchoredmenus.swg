#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// Exercise the shipped opener and modal path, keeping the surrounding view in the image.
internal func assertScopeAnchoredMenu(host: *Testing.HeadlessHost, window: *ViewerWindow, button: *IconButton, golden: string)
{
    window.revealViewerBar()
    window.applyLayout()
    host.finishAnimations()
    Swag.require(button.isVisible())
    var captured: bool
    host.app.sigFrame += func|host, golden, captured = &captured|(_)
    {
        if captured[] do
            return
        let menu  = host.capturedPopupMenu()
        let sheet = host.capturedOptionSheet()
        Swag.require(menu != null or sheet != null)
        host.finishAnimations()
        var image = host.render(&host.surfaceWnd)
        assertScopeImageGolden(&image, golden)
        captured[] = true
        if menu do
            Swag.require(host.dismissPopupMenu())
        else do
            sheet!.close()
    }

    button.sigPressed.call(cast(*Button, button))
    host.app.sigFrame.clear()
    Swag.require(captured)
    host.pump()
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window   = boardWindow(&host, false, films: true, width: 960, height: 600)
    let explorer = unwrap window.explorer
    explorer.entries.add({name: "Illustrations", path: "Illustrations", directory: true, attempted: true})
    explorer.entries.add({name: "Notes.txt", path: "Notes.txt", attempted: true})
    showBoard(&host, window, "Projects", "Documents")
    assertScopeAnchoredMenu(&host, window, explorer.modeMenu, "menus.explorer.mode")
    assertScopeAnchoredMenu(&host, window, explorer.sortMenu, "menus.explorer.sort")
    assertScopeAnchoredMenu(&host, window, explorer.kindMenu, "menus.explorer.kind")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("title.png"), false)
    let view   = assume cast(*Picture.Panel, window.currentView)
    assertScopeAnchoredMenu(&host, window, view.transformButton, "menus.image.transform")
    assertScopeAnchoredMenu(&host, window, view.zoomLabel, "menus.image.zoom")
    assertScopeAnchoredMenu(&host, window, &view.playModeButton.button, "menus.image.playback")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("segoeui.ttf"), true)
    let view   = assume cast(*Typeface.Panel, window.currentView)
    assertScopeAnchoredMenu(&host, window, view.pageLabel, "menus.font.range.paper")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.groove.mid"), true)
    let view   = assume cast(*Midi.Panel, window.currentView)
    assertScopeAnchoredMenu(&host, window, view.zoomLabel, "menus.midi.zoom.paper")
    assertScopeAnchoredMenu(&host, window, view.optionsButton, "menus.midi.options.paper")
}

#[Swag.TestTag("golden")]
#test
{
    let file = createPdfFixture()
    defer discard catch File.delete(file)
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, file, false)
    host.surface.setTitle("viewer.pdf")
    let view = assume cast(*PdfDocument.Panel, window.currentView)
    assertScopeAnchoredMenu(&host, window, view.zoomLabel, "menus.pdf.zoom")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.page.html"), true)
    let view   = assume cast(*Html.Panel, window.currentView)
    assertScopeAnchoredMenu(&host, window, view.zoomLabel, "menus.html.zoom.paper")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("comprehensive.txt"), false)
    let view   = assume cast(*PlainText.Panel, window.currentView)
    assertScopeAnchoredMenu(&host, window, view.zoomLabel, "menus.text.zoom")
    assertScopeAnchoredMenu(&host, window, view.optionsButton, "menus.text.options")
    window.showSearch()
    assertScopeAnchoredMenu(&host, window, window.searchOptionsButton, "menus.search.options")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("sample.cpp"), true)
    let view   = assume cast(*Code.Panel, window.currentView)
    assertScopeAnchoredMenu(&host, window, unwrap view.zoomLabel, "menus.code.zoom.paper")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("title.png"), false)
    for choice, index in window.choices where choice.key == "hex"
    {
        window.selectViewer(cast(u32, index))
        break
    }

    completeQueuedViewerFile(&host, window)
    let view = assume cast(*Hex.Panel, window.currentView)
    assertScopeAnchoredMenu(&host, window, unwrap view.zoomLabel, "menus.hex.zoom")
    assertScopeAnchoredMenu(&host, window, view.optionsButton, "menus.hex.options")
}

#[Swag.TestTag("golden")]
#test
{
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, videoMatroskaFixturePath(), false)
    let view   = assume cast(*Film.Panel, window.currentView)
    waitForVideoFrame(view)
    waitForVideoAudio(view, 2)
    pinVideoFrame(view, 5)
    view.timeline.setValueWithoutGesture(cast(f32, view.elapsed))
    host.moveMouse(view.timeline.surfaceRect().center())
    host.finishAnimations()
    assertScopeAnchoredMenu(&host, window, view.speedChip, "menus.video.speed")
    assertScopeAnchoredMenu(&host, window, view.audioChip, "menus.video.audio")
    view.subtitleOverlay.sidecars.add(expect Video.Subtitle.Track.loadOwned(scopeTestDataPath("viewer.srt")))
    view.finishSubtitles()
    assertScopeAnchoredMenu(&host, window, view.subtitleChip, "menus.video.subtitles")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window   = boardWindow(&host, true, films: true)
    let explorer = unwrap window.explorer
    showBoard(&host, window, "Projects", "Films")
    assertScopeAnchoredMenu(&host, window, explorer.artworkMenu, "menus.explorer.artwork.paper")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = homeWindow(&host, false)
    assertScopeAnchoredMenu(&host, window, window.home.clearButton, "menus.home.clear")
}
