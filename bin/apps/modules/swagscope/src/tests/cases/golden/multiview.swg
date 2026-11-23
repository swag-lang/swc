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
    let transport = unwrap workspace.transport
    let sheet     = transport.createLinkSheet(transport.linkButton)
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

    sheet.doModal(transport.linkButton, autoDestroy: true)
    host.app.sigFrame.clear()
    Swag.require(captured)
    assertScopeImageGolden(&image, "scene.grid.encre")
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
    workspace.transport!.lastPointerAt = 0
    workspace.playScene()
    Swag.require(not workspace.mediaChromeVisible())
    let image = host.renderSettled(&host.surfaceWnd)
    assertScopeImageGolden(&image, "scene.playing.encre")
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
