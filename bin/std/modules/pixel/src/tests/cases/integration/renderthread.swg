#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Math

#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var window = expect Env.createWindow({identifier: "render-worker-test", title: "Render worker test", width: 64, height: 64})
    expect window.showOffScreen()
    var backend: RenderOgl
    var worker:  RenderThread
    worker.start(&backend)
    defer worker.close()
    let renderer: IRenderer = &worker
    var context = expect renderer.createContext(window.nativeRenderHandle(), 64, 64)
    defer renderer.deleteContext(&context)
    renderer.setCurrentContext(context)
    renderer.init()
    renderer.begin(context)
    var target = renderer.createRenderTarget(32, 32)
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
    let actual   = renderer.readRenderTarget(&target, 0, 0, 32, 32)
    var expected = Image.create(32, 32, .BGRA8)
    expected.fill(Color.fromArgb(Argb.Red))
    Testing.assertImagesNear(&expected, &actual, "renderthread.ogl")
    renderer.end()
    worker.wait()
    Swag.require(worker.isReady())
}
