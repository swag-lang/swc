#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

using Core

// Deleting the first drawable keeps the renderer's context and offscreen objects alive.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var firstWindow  = expect Env.createWindow({identifier: "pixel-shared-first", title: "First Pixel drawable", width: 32, height: 32})
    var secondWindow = expect Env.createWindow({identifier: "pixel-shared-second", title: "Second Pixel drawable", width: 32, height: 32})
    var backend: RenderOgl
    let renderer: IRenderer = &backend
    var first = expect renderer.createContext(firstWindow.nativeRenderHandle(), 32, 32)
    defer renderer.deleteContext(&first)
    renderer.setCurrentContext(first)
    renderer.init()
    var second = expect renderer.createContext(secondWindow.nativeRenderHandle(), 32, 32, &first)
    defer renderer.deleteContext(&second)
    renderer.setCurrentContext(first)
    var target = renderer.createRenderTarget(16, 16)
    defer renderer.deleteRenderTarget(&target)
    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.clear(Argb.Red)
    painter.unbindRenderTarget()
    painter.end()
    expect renderer.draw(&painter)
    renderer.setCurrentContext(second)
    renderer.deleteContext(&first)
    expect firstWindow.close()
    let actual = renderer.readRenderTarget(&target, 0, 0, 16, 16)
    var expected = Image.create(16, 16, .BGRA8)
    expected.fill(Color.fromArgb(Argb.Red))
    Testing.assertImagesNear(&expected, &actual, "context.linux.shared")
}
