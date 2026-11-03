#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var ogl: RenderOgl
    ogl.setOffscreen()
    let gpu: IRenderer = &ogl
    var context        = expect gpu.createContext(null, 144, 96)
    defer gpu.deleteContext(&context)
    gpu.setCurrentContext(context)
    gpu.init()

    // Temporary color targets need no depth/stencil plane and must not survive an idle frame.
    gpu.begin(context)
    let first = gpu.acquireRenderTarget(1025, 513)
    Swag.assert(first.colorBuffer.width >= 1025 and first.colorBuffer.width < 1089)
    Swag.assert(first.colorBuffer.height >= 513 and first.colorBuffer.height < 577)
    Swag.assert(first.depthStencil == InvalidRenderTargetSurfaceHandle)
    let texture = first.colorBuffer.handle
    gpu.releaseRenderTarget(first)
    gpu.end()

    gpu.begin(context)
    let again = gpu.acquireRenderTarget(1025, 513)
    Swag.assert(again.colorBuffer.handle == texture)
    gpu.releaseRenderTarget(again)
    gpu.end()

    gpu.begin(context)
    gpu.end()
    Swag.assert(Ogl.glIsTexture(cast(Ogl.GLuint, texture)) == Ogl.GL_FALSE)

    var cpu:       RenderCpu
    let reference: IRenderer = &cpu
    reference.init()
    for algorithm in [BackdropBlur.Gaussian, .DualKawase]
    {
        for scale in [1.0'f32, 1.5]
        {
            for 2
            {
                reference.begin({width: 144, height: 96})
                gpu.begin(context)
                let expected = renderBackdropScene(reference, algorithm, scale)
                let actual   = renderBackdropScene(gpu, algorithm, scale)
                Testing.assertImagesNear(&expected, &actual, "backdrop.ogl", {maxChannelDelta: 4})
                reference.end()
                gpu.end()
            }
        }
    }
}
