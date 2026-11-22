#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Ogl

// Nested render targets cannot grow the clipping-mask cache past its documented bound.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var renderer: RenderOgl
    renderer.setOffscreen()
    let gpu: IRenderer = &renderer
    var context        = expect gpu.createContext(null, 16, 16)
    defer gpu.deleteContext(&context)
    gpu.begin(context)
    gpu.init()

    var targets: [4] RenderTarget
    for index in targets.count do
        targets[index] = gpu.createRenderTarget(16, 16)
    defer
    {
        for index in targets.count do
            gpu.deleteRenderTarget(&targets[index])
    }

    var painter = Painter.create(gpu)
    painter.begin()
    for index in targets.count
    {
        painter.startClippingRegion()
        painter.fillRect({0, 0, 16, 16}, Argb.White)
        painter.bindRenderTarget(&targets[index])
    }

    painter.startClippingRegion()
    painter.fillRect({0, 0, 16, 16}, Argb.White)
    painter.end()

    var failed = false
    catch gpu.draw(&painter)
    {
        failed = true
        Swag.require(Errors.message(Swag.err) == "OpenGL cannot allocate a clipping mask while all cached masks are in use")
    }

    Swag.require(failed)
    gpu.end()
}
