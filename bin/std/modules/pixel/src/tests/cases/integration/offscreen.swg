#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core

// Invisible drawables share resources and survive deletion of the first context.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var renderer: RenderOgl
    renderer.setOffscreen()
    let gpu: IRenderer = &renderer
    Swag.require(not gpu.needsNativeWindow())
    var first  = expect gpu.createContext(null, 64, 48)
    var second = expect gpu.createContext(null, 32, 24, &first)
    gpu.setCurrentContext(first)
    gpu.init()
    var target = gpu.createRenderTarget(32, 24)
    for context in [first, second]
    {
        gpu.begin(context)
        var painter = Painter.create(gpu)
        painter.begin()
        painter.bindRenderTarget(&target)
        painter.setColorMaskFull()
        painter.clear(Argb.Red)
        painter.unbindRenderTarget()
        painter.end()
        gpu.draw(&painter)
        let pixels = gpu.readRenderTarget(&target, 0, 0, 32, 24)
        Swag.require(pixels.pixelColor(17, 13).argb == Argb.Red)
        gpu.end()
    }

    gpu.deleteContext(&first)
    gpu.begin(second)
    let retained = gpu.readRenderTarget(&target, 0, 0, 32, 24)
    Swag.require(retained.pixelColor(17, 13).argb == Argb.Red)
    gpu.deleteRenderTarget(&target)
    gpu.end()
    gpu.deleteContext(&second)
}
