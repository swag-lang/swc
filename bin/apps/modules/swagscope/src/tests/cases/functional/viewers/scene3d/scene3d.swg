#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

func scene3dFixturePath()->String => scopeTestDataPath("viewer.obj")

private func scene3dTestFile(fileName: string)
{
    let path     = scopeTestDataPath(fileName)
    let registry = createViewerPluginRegistry()
    let choices  = registry.choices(path)
    Swag.require(not choices.isEmpty() and choices[0].key == "scene3d", fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 480)
    let foot    = createTestViewerFoot(&host.root)
    let session = openTestViewer(Viewers.Scene.viewerPlugin(),
                                 &host.root,
                                 path,
                                 commandParent: foot.commands,
                                 infoParent: foot.readings)
    let viewer = assume cast(*Viewers.Scene.Panel, session.view)
    completeViewerBackgroundLoad(&host, &viewer.load)
    Swag.require(viewer.scene.meshes.count == 1 and viewer.scene.meshes[0].triangles.count == 1, fileName)
    Swag.require(host.render(&host.root).isValid(), fileName)
}

// The host selects OBJ before the generic binary viewer and presents the decoded mesh.
#test
{
    let fileName = scene3dFixturePath()
    let registry = createViewerPluginRegistry()
    let choices  = registry.choices(fileName)
    Swag.require(not choices.isEmpty() and choices[0].key == "scene3d")

    var host: Testing.HeadlessHost
    host.setup(800, 600)
    host.theme.setDark()
    let foot    = createTestViewerFoot(&host.root)
    let session = openTestViewer(Viewers.Scene.viewerPlugin(),
                                 &host.root,
                                 fileName,
                                 commandParent: foot.commands,
                                 infoParent: foot.readings)
    let viewer = assume cast(*Viewers.Scene.Panel, session.view)
    completeViewerBackgroundLoad(&host, &viewer.load)

    Swag.require(viewer.scene.meshes.count == 1 and viewer.scene.nodes.count == 1)
    Swag.require(viewer.scene.meshes[0].triangles.count == 4 and viewer.scene.meshes[0].vertices.count == 12)
    Swag.require(viewer.radius > 0)
    Swag.require(viewer.zoomPercent == 100 and viewer.zoomLabel.text() == Viewer.zoomText(100))
    viewer.setZoomPercent(150)
    Swag.require(viewer.zoomPercent == 150 and viewer.zoomLabel.text() == Viewer.zoomText(150))

    let image = host.render(&host.root)
    Swag.require(image.isValid())
}

// Camera gestures and shortcuts arrive through the same window routing used by the application.
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scene3dFixturePath(), false, 800, 600)
    let viewer = assume cast(*Viewers.Scene.Panel, window.currentView)
    viewer.setFocus()

    let center = viewer.surfaceRect().center()
    host.mouseWheel(center, 120, .Control)
    Swag.require(viewer.zoomPercent == Viewer.zoomIn(100))

    host.mouseDown(center)
    host.moveMouse(center + Math.Point{18, 9})
    host.mouseUp(center + Math.Point{18, 9})
    Swag.require(viewer.yaw != 0.65 and viewer.pitch != 0.45)

    host.mouseDown(center, .Right)
    host.moveMouse(center + Math.Point{12, 7})
    host.mouseUp(center + Math.Point{12, 7}, .Right)
    Swag.require(viewer.pan.x != 0 and viewer.pan.y != 0)

    host.keyPress(Input.Key.F, .Control)
    Swag.require(viewer.zoomPercent == Viewer.zoomIn(100) and viewer.pan.x != 0)
    host.focus(viewer)
    host.keyPress(Input.Key.F)
    Swag.require(viewer.zoomPercent == 100)
    Swag.require(viewer.yaw == 0.65)
    Swag.require(viewer.pitch == 0.45)
    Swag.require(viewer.pan.x == 0 and viewer.pan.y == 0)
}

// Finite f32 vertices beyond the camera's safe range fail as a readable format error.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let foot    = createTestViewerFoot(&host.root)
    let session = openTestViewer(Viewers.Scene.viewerPlugin(),
                                 &host.root,
                                 scopeTestDataPath("viewer.extreme.obj"),
                                 commandParent: foot.commands,
                                 infoParent: foot.readings)
    let viewer = assume cast(*Viewers.Scene.Panel, session.view)
    completeViewerBackgroundLoad(&host, &viewer.load)
    Swag.require(not viewer.failureReason.isEmpty())
}

// The app routes both ASCII and binary STL files to the reusable scene codecs and draws their facets.
#test
{
    scene3dTestFile("viewer.ascii.stl")
    scene3dTestFile("viewer.binary.stl")
}
