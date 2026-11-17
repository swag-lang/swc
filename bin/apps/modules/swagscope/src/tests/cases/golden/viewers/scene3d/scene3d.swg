#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// The first imported tetrahedron shows one complete, framed scene in Encre.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.obj"), false)
    let viewer = assume cast(*Viewers.Scene.Panel, window.currentView)
    Swag.require(viewer.scene.meshes.count == 1 and viewer.scene.meshes[0].triangles.count == 4)

    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.scene3d.tetra.encre")
}

// A changed camera view remains clear on Papier.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, scopeTestDataPath("viewer.obj"), true)
    let viewer = assume cast(*Viewers.Scene.Panel, window.currentView)
    viewer.yaw += 0.9
    viewer.invalidate()

    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.scene3d.tetra.paper.orbit")
}
