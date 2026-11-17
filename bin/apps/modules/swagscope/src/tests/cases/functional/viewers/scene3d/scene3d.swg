#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

func scene3dFixturePath()->String => scopeTestDataPath("viewer.obj")

private func scene3dTestFile(fileName: string)
{
    let path = scopeTestDataPath(fileName)
    let registry = createViewerPluginRegistry()
    let choices = registry.choices(path)
    Swag.require(not choices.isEmpty() and choices[0].key == "scene3d", fileName)

    var host: Testing.HeadlessHost
    host.setup(640, 480)
    let foot = createTestViewerFoot(&host.root)
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
    let foot = createTestViewerFoot(&host.root)
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

// The app routes both ASCII and binary STL files to the reusable scene codecs and draws their facets.
#test
{
    scene3dTestFile("viewer.ascii.stl")
    scene3dTestFile("viewer.binary.stl")
}
