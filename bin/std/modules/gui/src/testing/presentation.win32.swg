#global public
#global namespace Testing
#global if #os == Swag.TargetOs.Windows

using Core, Pixel, Ogl

// Compares the WGL front buffer with its completed OpenGL render target.
//
// Call on the window thread between event-loop frames. Returns false until a frame has
// appeared in the front buffer. Fails if the surface has no OpenGL renderer or rendering
// or pixel inspection fails.
//
// This reads the GPU synchronously and is intended for smoke checkpoints. For composition
// effects such as translucency over other windows, inspect the desktop separately.
func verifyNativePresentation(surface: *Surface)->bool fail
{
    if not (surface.app.renderer is RenderOgl) do
        fail Errors.InvalidFormatError{Errors.mkString("presentation verification needs an OpenGL surface")}
    if not surface.renderFailure.isEmpty() do
        fail Errors.InvalidFormatError{Errors.mkString(surface.renderFailure.toString())}
    if not surface.presentedFrame do
        return false

    surface.app.renderer.setCurrentContext(surface.renderingContext())
    let tinted   = (surface.isDisabled and surface.app.fadeDisabledSurface) or surface.opacity < 1
    let target   = tinted ? &surface.presentationTarget : &surface.rt
    let width    = surface.rc.width
    let height   = surface.rc.height
    let expected = surface.app.renderer.readRenderTarget(target, 0, 0, width, height)
    if not expected.isValid() do
        fail Errors.InvalidFormatError{Errors.mkString("cannot read the GPU target for presentation verification")}

    var actual = Image.create(width, height, .BGRA8)
    var readFramebuffer, readBuffer: GLint
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &readFramebuffer)
    glBindFramebuffer(GL_READ_FRAMEBUFFER, 0)
    glGetIntegerv(GL_READ_BUFFER, &readBuffer)
    defer
    {
        glReadBuffer(cast(GLenum, readBuffer))
        glBindFramebuffer(GL_READ_FRAMEBUFFER, cast(GLuint, readFramebuffer))
    }

    glReadBuffer(GL_FRONT)
    glReadPixels(0, 0, width, height, GL_BGRA, GL_UNSIGNED_BYTE, actual.pixels.storage())
    if glGetError() != GL_NO_ERROR do
        fail Errors.InvalidFormatError{Errors.mkString("cannot read the WGL front buffer")}

    for index in expected.byteCount
    {
        if Math.abs(cast(s32, actual.pixels[index]) - expected.pixels[index]) > 1 do
            return false
    }

    return true
}
