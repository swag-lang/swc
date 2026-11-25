#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel, Audio

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()

    workspace.openDocument(scopeTestDataPath("comprehensive.txt"))
    openViews(&host, workspace)
    host.paint(&host.surfaceWnd)
    workspace.openDocument(scopeTestDataPath("sample.cpp"))
    openViews(&host, workspace)
    host.paint(&host.surfaceWnd)
    workspace.cycleSwitcher(false)
    let image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "scene.switcher.encre")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host, light: true)
    defer host.shutdown()

    let files = [scopeTestDataPath("comprehensive.txt"), scopeTestDataPath("sample.cpp")]
    workspace.openScene(files, .SideBySide, compare: true)
    openViews(&host, workspace)
    let comparison = unwrap workspace.comparison
    comparison.operation.task.wait()
    host.pump()
    Swag.require(workspace.comparisonVisible())
    let image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "scene.text.paper")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    workspace.openDocument(scopeTestDataPath("viewer.srt"))
    openViews(&host, workspace)
    let files = [scopeTestDataPath("comprehensive.txt"), scopeTestDataPath("sample.cpp")]
    workspace.openScene(files, .SideBySide, compare: true)
    openViews(&host, workspace)
    let comparison = unwrap workspace.comparison
    comparison.operation.task.wait()
    host.pump()
    workspace.selectView(1)
    host.keyPress(.F, .Control)
    let document = workspace.activeDocument()
    document.searchBox.setText("value")
    Swag.require(document.searchMatches.count > 0)
    let image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "scene.tabs.find.encre")
}

// A selected empty cell teaches its two local open commands and leaves the other readers in place.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host, light: true, width: 800, height: 540)
    defer host.shutdown()
    workspace.openScene([scopeTestDataPath("sample.cpp"), scopeTestDataPath("viewer.png"), scopeTestDataPath("viewer.srt")], .Grid2)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    var point = workspace.localToSurface(workspace.gridCellRect(scene, 3).center())
    host.surface.surfaceToScreen(&point)
    host.click(point)
    Swag.require(workspace.vacancy and workspace.vacantCell == 3 and scene.views.count == 3)
    let image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "scene.vacant.paper")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host, width: 760, height: 480)
    defer host.shutdown()
    workspace.openScene([scopeTestDataPath("sample.cpp"), scopeTestDataPath("viewer.png")], .Grid2)
    openViews(&host, workspace)
    let strip = host.surfaceWnd.captionContentRect()
    var point = host.surfaceWnd.localToSurface(strip.center())
    host.surface.surfaceToScreen(&point)
    host.click(point)
    Swag.require(workspace.focusOnGrid and not workspace.activeDocument().informationCaptionButton.isEnabled())
    let image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "scene.unselected.encre")
}

func pictureComparisonGolden(mode: PictureComparisonMode, name: string, light: bool)
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host, light: light)
    defer host.shutdown()

    let files = [scopeTestDataPath("viewer.png"), scopeTestDataPath("viewer.progressive.jpg")]
    workspace.openScene(files, .SideBySide, compare: true)
    openViews(&host, workspace)
    let comparison = unwrap workspace.comparison
    comparison.setPictureMode(mode)
    comparison.pointer = {503, 288}
    let image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, name)
}

#[Swag.TestTag("golden")]
#test { pictureComparisonGolden(.Curtain, "scene.curtain.paper", light: true) }

#[Swag.TestTag("golden")]
#test { pictureComparisonGolden(.SideBySide, "scene.pictures.encre", light: false) }

#[Swag.TestTag("golden")]
#test { pictureComparisonGolden(.OnionSkin, "scene.onionskin.encre", light: false) }

#[Swag.TestTag("golden")]
#test { pictureComparisonGolden(.Difference, "scene.difference.paper", light: true) }

#[Swag.TestTag("golden")]
#test { pictureComparisonGolden(.Flip, "scene.flip.encre", light: false) }

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    let files = [scopeTestDataPath("viewer.avi"), scopeTestDataPath("viewer.mp4"),
                 scopeTestDataPath("viewer.h264.mp4"), scopeTestDataPath("ffmpeg-h264-baseline.mp4")]
    workspace.openScene(files, .Grid2)
    let scene = unwrap workspace.scene()
    scene.linked = false
    openViews(&host, workspace)
    for &view in scene.views
    {
        let film = assume cast(*Viewers.Film.Panel, view.document!.currentView)
        pinVideoFrame(film, 0)
    }

    scene.linked = true
    workspace.alignSceneHere()
    workspace.synchronizeMedia()
    workspace.updateMedia()
    let sheet = workspace.createMediaLinkSheet()
    var image:    Image
    var captured: bool
    host.app.sigFrame += func|host = &host, sheet, image = &image, captured = &captured|(_)
    {
        if captured[] do
            return
        captured[] = true
        image[]    = host.renderSettled(&host.surfaceWnd)
        sheet.close()
    }

    sheet.doModal(&workspace.mediaLinks.button, autoDestroy: true)
    host.app.sigFrame.clear()
    Swag.require(captured)
    assertScopeImageGolden(&image, "scene.grid.encre")
}

#[Swag.TestTag("golden")]
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host, light: true)
    defer host.shutdown()
    let files = [scopeTestDataPath("viewer.png"), scopeTestDataPath("viewer.wav"), scopeTestDataPath("sample.cpp")]
    workspace.openScene(files, .Grid2)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    let picture = unwrap scene.views[0].document
    picture.revealViewerBar()
    Swag.require(picture.cellCaption.isVisible())

    var image: Image
    var captured: bool
    host.app.sigFrame += func|host = &host, image = &image, captured = &captured|(_)
    {
        let sheet = host.capturedOptionSheet()
        if captured[] or not sheet do
            return
        captured[] = true
        image[]    = host.renderSettled(&host.surfaceWnd)
        sheet.close()
    }
    host.clickWnd(workspace.mediaTransport)
    host.app.sigFrame.clear()
    Swag.require(captured)
    assertScopeImageGolden(&image, "scene.controls.paper")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host, light: true, width: ViewerWindow.MinWidth)
    defer host.shutdown()

    let files = [scopeTestDataPath("comprehensive.txt"), scopeTestDataPath("sample.cpp")]
    workspace.openScene(files, .SideBySide)
    openViews(&host, workspace)
    workspace.activeDocument().lens.open(">grid")
    let image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "scene.layouts.paper")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()

    let files = [scopeTestDataPath("sample.cpp"), scopeTestDataPath("comprehensive.txt"),
                 scopeTestDataPath("viewer.png"), scopeTestDataPath("viewer.srt")]
    workspace.openScene(files, .Grid2)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    var point = workspace.localToSurface(workspace.viewRect(scene, 3).center())
    host.surface.surfaceToScreen(&point)
    Swag.require(host.dragFilesOver(point, [scopeTestDataPath("comprehensive.md").toString()]) == .Copy)
    let image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "scene.drop.encre")
}

#[Swag.TestTag("golden")]
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host, light: true)
    defer host.shutdown()

    let files = [scopeTestDataPath("glint-aac-mjpeg.mp4"), scopeTestDataPath("ffmpeg-h264-baseline.mp4")]
    workspace.openScene(files, .SideBySide, compare: true)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    for &view in scene.views
    {
        let film = unwrap ScenePlayer.from(view.document).film
        pinVideoFrame(film, 0)
        view.document?.revealViewerBar()
    }

    workspace.activeDocument().toggleInformation()
    Swag.require(workspace.comparisonSheet!.facts.count > 4)
    let image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "scene.sheet.paper")
}

#[Swag.TestTag("golden")]
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host)
    defer host.shutdown()

    let files = [scopeTestDataPath("viewer.avi"), scopeTestDataPath("viewer.mp4"),
                 scopeTestDataPath("viewer.h264.mp4"), scopeTestDataPath("ffmpeg-h264-baseline.mp4")]
    workspace.openScene(files, .Grid2)
    let scene = unwrap workspace.scene()
    openViews(&host, workspace)
    for &view in scene.views do
        pinVideoFrame(unwrap ScenePlayer.from(view.document).film, 0)
    workspace.playScene()
    Swag.require(workspace.anyMediaPlaying())
    var pointer = workspace.localToSurface(workspace.viewRect(scene, 1).center())
    host.surface.surfaceToScreen(&pointer)
    host.moveMouse(pointer)
    let image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "scene.playing.encre")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host, light: true)
    defer host.shutdown()
    host.setReducedMotion(false)
    let files = [scopeTestDataPath("viewer.mp4"), scopeTestDataPath("viewer.png")]
    workspace.openScene(files, .Stacked)
    openViews(&host, workspace)
    let document = workspace.activeDocument()
    let film = unwrap ScenePlayer.from(document).film
    pinVideoFrame(film, 0)
    document.revealViewerBar()
    host.finishAnimations()
    document.concealViewerBar()
    host.advanceAnimations(document.themeMetrics().motion_PanelSeconds * 0.4)
    Swag.require(not document.viewerBar.isVisible() and document.viewerBar.presentationOpacity > 0)
    let image = host.render(&host.surfaceWnd)
    assertScopeImageGolden(&image, "scene.chrome.fading.paper")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host, light: true)
    defer host.shutdown()

    let files = [scopeTestDataPath("sample.cpp"), scopeTestDataPath("comprehensive.txt"), scopeTestDataPath("viewer.srt")]
    workspace.openScene(files, .Grid3)
    openViews(&host, workspace)
    workspace.selectView(1)
    workspace.toggleMaximized()
    let image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "scene.maximized.paper")
}

#[Swag.TestTag("golden")]
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host, width: ViewerWindow.MinWidth, height: 480)
    defer host.shutdown()
    workspace.openScene([scopeTestDataPath("pacman_beginning.wav"), scopeTestDataPath("viewer.png"),
                         scopeTestDataPath("sample.cpp"), scopeTestDataPath("viewer.mp4")], .Grid2)
    openViews(&host, workspace)
    let scene = unwrap workspace.scene()
    let audio = unwrap scene.views[0].document
    finishWaveform(unwrap ScenePlayer.from(audio).sound)
    pinVideoFrame(unwrap ScenePlayer.from(scene.views[3].document).film, 0)
    audio.concealViewerBar()
    let image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "scene.mixed.compact.encre")
    audio.revealViewerBar()
    let controls = host.renderSettled(&host.surfaceWnd)
    let sound = unwrap ScenePlayer.from(audio).sound
    Swag.require(sound.waveform.surfaceRect().bottom() <= audio.viewerBar.surfaceRect().y)
    assertScopeImageGolden(&controls, "scene.sound.controls.encre")
}

#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let workspace = testWorkspace(&host, light: true, width: ViewerWindow.MinWidth, height: 480)
    defer host.shutdown()
    let root = Testing.tempFilePath("scope-folder-pane-", "")
    let folder = Path.combine(root, "Notes")
    expect Directory.create(folder, recurse: true)
    defer discard catch Directory.delete(root, recurse: true)
    workspace.openScene([scopeTestDataPath("sample.cpp"), scopeTestDataPath("viewer.png")], .SideBySide)
    openViews(&host, workspace)
    let document = workspace.activeDocument()
    document.openExplorer(folder)
    let explorer = unwrap document.explorer
    completeExplorer(&host, explorer)
    explorer.entries.add({name: "Brief.txt", attempted: true})
    explorer.entries.add({name: "Draft.md", attempted: true})
    showBoard(&host, document, "Projects", "Notes")
    explorer.listing.path = "Z:/Projects/Notes"
    explorer.updateBreadcrumb()
    explorer.setMode(.Names)
    workspace.scene()!.split = 0.22
    workspace.layoutScene()
    let image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "scene.folder.narrow.paper")
}
