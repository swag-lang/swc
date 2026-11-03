#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Ogl

// A region outside the surface has no pixels. Passing a negative extent to OpenGL must not
// poison the next submission with GL_INVALID_VALUE or clear pixels outside the empty region.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var window = expect Env.createWindow({identifier: "pixel-scissor-test", title: "Pixel scissor test", width: 32, height: 24})
    expect window.showOffScreen()
    var renderer: RenderOgl
    let gpu:      IRenderer = &renderer
    var context = expect gpu.createContext(window.nativeRenderHandle(), 32, 24)
    defer gpu.deleteContext(&context)
    gpu.setCurrentContext(context)
    gpu.init()
    var target = gpu.createRenderTarget(32, 24)
    defer gpu.deleteRenderTarget(&target)
    gpu.bindRenderTarget(&target)
    defer gpu.unbindRenderTarget()
    gpu.resetScissorRect()
    gpu.clear()
    var painter = Painter.create(gpu)
    painter.begin()
    painter.setColorMaskFull()
    painter.fillRect({0, 0, 32, 24}, Color.fromRgb(23, 71, 119))
    painter.end()
    expect gpu.draw(&painter)
    let before = gpu.readRenderTarget(&target, 0, 0, 32, 24)
    Swag.require(before.isValid())

    for rect in [Math.Rectangle{12, 8, -4, 6}, Math.Rectangle{12, 8, 4, -6}, Math.Rectangle{12, 8, 0, 6}]
    {
        gpu.setScissorRect(rect)
        let error = glGetError()
        Swag.require(error == GL_NO_ERROR, "an empty scissor leaves an OpenGL error")
        gpu.clear()
        let after = gpu.readRenderTarget(&target, 0, 0, 32, 24)
        Swag.require(after.isValid() and Slice.equals(before.pixels.toSlice(), after.pixels.toSlice()))
    }

    // An error left by native code is recoverable and cannot be blamed on vertex allocation.
    glScissor(0, 0, 1, -1)
    var failed = false
    catch gpu.draw(&painter)
    {
        failed = true
        Swag.require(Errors.message(Swag.err) == "OpenGL has an error before painter submission")
    }

    Swag.require(failed and glGetError() == GL_NO_ERROR)
    gpu.resetScissorRect()
    expect gpu.draw(&painter)
    let recovered = gpu.readRenderTarget(&target, 0, 0, 32, 24)
    Swag.require(Slice.equals(before.pixels.toSlice(), recovered.pixels.toSlice()))

    // A refused nested layer releases its queued resources and restores the outer target.
    var limit: GLint
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, &limit)
    painter.begin()
    var layer: Layer
    layer.begin(&painter, {width: limit + 1, height: 1})
    layer.end()
    layer.draw({dstRect: {0, 0, 1, 1}})
    painter.end()
    failed = false
    catch gpu.draw(&painter) { failed = true }
    Swag.require(failed and glGetError() == GL_NO_ERROR)
    var binding: GLint
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &binding)
    Swag.require(binding == cast(GLint, target.handle))
    painter.begin()
    painter.setColorMaskFull()
    painter.fillRect({0, 0, 32, 24}, Color.fromRgb(23, 71, 119))
    painter.end()
    expect gpu.draw(&painter)
    let afterFailure = gpu.readRenderTarget(&target, 0, 0, 32, 24)
    Swag.require(Slice.equals(before.pixels.toSlice(), afterFailure.pixels.toSlice()))
}

// Glyph and gradient uploads own their CPU pointers even when a caller left an unpack PBO bound.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var renderer: RenderOgl
    renderer.setOffscreen()
    let gpu: IRenderer = &renderer
    var context        = expect gpu.createContext(null, 64, 32)
    defer gpu.deleteContext(&context)
    gpu.begin(context)
    gpu.init()
    var target = gpu.createRenderTarget(64, 32)
    defer gpu.deleteRenderTarget(&target)
    gpu.bindRenderTarget(&target)
    defer gpu.unbindRenderTarget()
    var buffer: GLuint
    glGenBuffers(1, &buffer)
    defer glDeleteBuffers(1, &buffer)
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, buffer)
    glBufferData(GL_PIXEL_UNPACK_BUFFER, 4, null, GL_STREAM_DRAW)
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 19)
    glPixelStorei(GL_UNPACK_SKIP_ROWS, 2)
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, 3)

    let font     = gpu.fontCache().createFont(expect fallbackTestFace(false), 18, .Bitmap)
    var gradient = Brush.createLinearGradient(0, 0, 64, 0, Argb.Red, Argb.Blue)
    for index in 12 do
        gradient.addGradientStop(cast(f32, index) / 12, Argb.Lime)
    var painter = Painter.create(gpu)
    painter.begin()
    painter.setColorMaskFull()
    painter.fillRect({0, 0, 64, 32}, gradient)
    painter.drawString(2, 2, "AV", font, Argb.White)
    painter.end()
    expect gpu.draw(&painter)
    Swag.require(glGetError() == GL_NO_ERROR)
    var binding, rowLength, skipRows, skipPixels: GLint
    glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &binding)
    glGetIntegerv(GL_UNPACK_ROW_LENGTH, &rowLength)
    glGetIntegerv(GL_UNPACK_SKIP_ROWS, &skipRows)
    glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &skipPixels)
    Swag.require(binding == cast(GLint, buffer) and rowLength == 19 and skipRows == 2 and skipPixels == 3)
    let first = gpu.readRenderTarget(&target, 0, 0, 64, 32)
    Swag.require(first.isValid() and first.pixelColor(32, 28).a != 0)
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 0)
    glPixelStorei(GL_UNPACK_SKIP_ROWS, 0)
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0)
}
