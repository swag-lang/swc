#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Core, Ogl

// A mask being written must not also be available to the fragment shader as a texture.
// A uniform branch that skips sampling does not make an OpenGL feedback loop defined.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var window = expect Env.createWindow({identifier: "pixel-clip-feedback-test", title: "Pixel clipping test", width: 96, height: 64})
    expect window.showOffScreen()
    var renderer: RenderOgl
    let gpu:      IRenderer = &renderer
    var context = expect gpu.createContext(window.nativeRenderHandle(), 96, 64)
    defer gpu.deleteContext(&context)
    gpu.setCurrentContext(context)
    gpu.init()
    var target = gpu.createRenderTarget(96, 64)
    defer gpu.deleteRenderTarget(&target)
    gpu.bindRenderTarget(&target)
    defer gpu.unbindRenderTarget()
    var painter = Painter.create(gpu)

    // Inspect both allocation and reuse, before finishing the region rebinds the color target.
    for 2
    {
        painter.begin()
        painter.startClippingRegion()
        painter.fillRect({8, 8, 32, 24}, Argb.White)
        painter.end()
        gpu.draw(&painter)

        var attachment, sampled: GLint
        glGetFramebufferAttachmentParameteriv(GL_DRAW_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_FRAMEBUFFER_ATTACHMENT_OBJECT_NAME, &attachment)
        glActiveTexture(GL_TEXTURE5)
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &sampled)
        glActiveTexture(GL_TEXTURE0)
        Swag.require(attachment != 0 and attachment != sampled,
                     "the clipping mask is both a render target and a shader input")

        painter.begin()
        painter.endClippingRegion()
        painter.resetClippingRegion()
        painter.end()
        gpu.draw(&painter)
    }

    // The completed mask becomes readable again and still clips ordinary drawing.
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Argb.Black)
    painter.startClippingRegion()
    painter.fillRect({8, 8, 32, 24}, Argb.White)
    painter.endClippingRegion()
    painter.fillRect({0, 0, 96, 64}, Argb.Red)
    painter.resetClippingRegion()
    painter.end()
    gpu.draw(&painter)
    let result = gpu.readRenderTarget(&target, 0, 0, 96, 64)
    Swag.require(result.pixelColor(16, 16) == Color.fromArgb(Argb.Red))
    Swag.require(result.pixelColor(64, 48) == Color.fromArgb(Argb.Black))
    Swag.require(glGetError() == GL_NO_ERROR)
}
