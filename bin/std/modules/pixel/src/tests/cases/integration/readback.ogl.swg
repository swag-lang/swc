#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Ogl

// A bounded readback preserves top-left cropping, BGRA row order and caller-owned GL bindings.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var window = expect Env.createWindow({identifier: "pixel-readback-test", title: "Pixel readback test", width: 64, height: 48})
    expect window.showOffScreen()
    var renderer: RenderOgl
    let gpu:      IRenderer = &renderer
    var context = expect gpu.createContext(window.nativeRenderHandle(), 64, 48)
    defer gpu.deleteContext(&context)
    gpu.setCurrentContext(context)
    gpu.init()
    var target = gpu.createRenderTarget(64, 48)
    defer gpu.deleteRenderTarget(&target)
    var painter = Painter.create(gpu)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.clear(Argb.Black)
    painter.fillRect({3, 5, 21, 13}, Color.fromArgb(255'u8, 23'u8, 71'u8, 119'u8))
    painter.fillRect({7, 18, 15, 16}, Color.fromArgb(255'u8, 151'u8, 87'u8, 41'u8))
    painter.unbindRenderTarget()
    painter.end()
    expect gpu.draw(&painter)
    let expected = gpu.readRenderTarget(&target, 3, 5, 21, 29)
    var actual   = Image.create(21, 29, .BGRA8)
    var readback: RenderOglReadback
    defer readback.release()
    for width in [21's32, 32's32, 21's32]
    {
        let cropped   = gpu.readRenderTarget(&target, 3, 5, width, 29)
        var image     = Image.create(width, 29, .BGRA8)
        let submitted = readback.submit(&target, 3, 5, width, 29)
        Swag.require(submitted and readback.isPending() and not readback.hasFailed())
        var copied: bool
        var watch:  Time.Stopwatch
        watch.start()
        while not copied and watch.elapsedMilliseconds() < 2000
        {
            copied = readback.tryCopyTo(image.pixels.toSlice())
            if not copied do
                Threading.Thread.sleep(1'ms)
        }

        Swag.require(copied and not readback.isPending() and not readback.hasFailed())
        Swag.require(Slice.equals(image.pixels.toSlice(), cropped.pixels.toSlice()))
        var buffer, framebuffer: GLint
        glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &buffer)
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &framebuffer)
        Swag.require(buffer == 0 and framebuffer == 0)
    }

    var padded: Array'u8
    padded.resize(128 * 29)
    let strided = readback.submit(&target, 3, 5, 21, 29)
    Swag.require(strided)
    var copiedRows: bool
    var rowWatch:   Time.Stopwatch
    rowWatch.start()
    while not copiedRows and rowWatch.elapsedMilliseconds() < 2000
    {
        copiedRows = readback.tryCopyTo(padded.toSlice(), rowStride: 128)
        if not copiedRows do
            Threading.Thread.sleep(1'ms)
    }

    Swag.require(copiedRows)
    for row in 29'u64
    {
        Swag.require(Slice.equals(padded.toSlice()[row * 128 until row * 128 + 84],
                                  expected.pixels.toSlice()[row * 84 until (row + 1) * 84]))
        for byte in padded.toSlice()[row * 128 + 84 until (row + 1) * 128] do
            Swag.require(byte == 0)
    }

    let submitted = readback.submit(&target, 3, 5, 21, 29)
    Swag.require(submitted)
    readback.cancel()
    Swag.require(not readback.isPending())
    let copied = readback.tryCopyTo(actual.pixels.toSlice())
    Swag.require(not copied)

    // A target whose attachment disappeared represents a driver-side readback failure.
    glBindFramebuffer(GL_FRAMEBUFFER, cast(GLuint, target.handle))
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, 0, 0)
    glBindFramebuffer(GL_FRAMEBUFFER, 0)
    let invalid = gpu.readRenderTarget(&target, 0, 0, 1, 1)
    Swag.require(not invalid.isValid() and glGetError() == GL_NO_ERROR)

    let accepted = readback.submit(&target, 0, 0, 1, 1)
    if accepted
    {
        var failureWatch: Time.Stopwatch
        failureWatch.start()
        while not readback.hasFailed() and failureWatch.elapsedMilliseconds() < 2000
        {
            discard readback.tryCopyTo(actual.pixels.toSlice())
            if not readback.hasFailed() do
                Threading.Thread.sleep(1'ms)
        }
    }

    Swag.require(readback.hasFailed())
    glBindFramebuffer(GL_FRAMEBUFFER, cast(GLuint, target.handle))
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, cast(GLuint, target.colorBuffer.handle), 0)
    glBindFramebuffer(GL_FRAMEBUFFER, 0)
}

// Creating or reading another target must leave the active draw target in place.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var renderer: RenderOgl
    renderer.setOffscreen()
    let gpu: IRenderer = &renderer
    var context        = expect gpu.createContext(null, 32, 32)
    defer gpu.deleteContext(&context)
    gpu.begin(context)
    gpu.init()

    var active = gpu.createRenderTarget(16, 16)
    defer gpu.deleteRenderTarget(&active)
    gpu.bindRenderTarget(&active)

    var other = gpu.createRenderTarget(8, 8)
    defer gpu.deleteRenderTarget(&other)
    var readBinding, drawBinding: GLint
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &readBinding)
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &drawBinding)
    Swag.require(readBinding == cast(GLint, active.handle) and drawBinding == cast(GLint, active.handle))

    var maxTextureSize: GLint
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxTextureSize)
    let refused = gpu.createRenderTarget(maxTextureSize + 1, 1)
    Swag.require(not refused.colorBuffer.isValid() and glGetError() == GL_NO_ERROR)
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &readBinding)
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &drawBinding)
    Swag.require(readBinding == cast(GLint, active.handle) and drawBinding == cast(GLint, active.handle))

    discard gpu.readRenderTarget(&other, 0, 0, 8, 8)
    glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &readBinding)
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &drawBinding)
    Swag.require(readBinding == cast(GLint, active.handle) and drawBinding == cast(GLint, active.handle))

    gpu.clear()
    glClearColor(0, 1, 0, 1)
    glClear(GL_COLOR_BUFFER_BIT)
    gpu.unbindRenderTarget()
    let pixels = gpu.readRenderTarget(&active, 0, 0, 16, 16)
    Swag.require(pixels.pixelColor(7, 7).argb == Argb.Lime)

    var packBuffer: GLuint
    glGenBuffers(1, &packBuffer)
    glBindBuffer(GL_PIXEL_PACK_BUFFER, packBuffer)
    glBufferData(GL_PIXEL_PACK_BUFFER, 4, null, GL_STREAM_READ)
    glPixelStorei(GL_PACK_ALIGNMENT, 8)
    glPixelStorei(GL_PACK_ROW_LENGTH, 32)
    glPixelStorei(GL_PACK_SKIP_ROWS, 1)
    glPixelStorei(GL_PACK_SKIP_PIXELS, 2)
    let packed = gpu.readRenderTarget(&active, 0, 0, 16, 16)
    Swag.require(packed.pixelColor(7, 7).argb == Argb.Lime)
    var currentBuffer, alignment, rowLength, skipRows, skipPixels: GLint
    glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &currentBuffer)
    glGetIntegerv(GL_PACK_ALIGNMENT, &alignment)
    glGetIntegerv(GL_PACK_ROW_LENGTH, &rowLength)
    glGetIntegerv(GL_PACK_SKIP_ROWS, &skipRows)
    glGetIntegerv(GL_PACK_SKIP_PIXELS, &skipPixels)
    Swag.require(currentBuffer == cast(GLint, packBuffer) and
                 alignment == 8 and
                 rowLength == 32 and
                 skipRows == 1 and
                 skipPixels == 2)
    glBindBuffer(GL_PIXEL_PACK_BUFFER, 0)
    glDeleteBuffers(1, &packBuffer)
    gpu.end()
}

// CPU uploads and texture reads ignore ambient pixel-buffer and row-stride state.
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

    var unpackBuffer: GLuint
    glGenBuffers(1, &unpackBuffer)
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, unpackBuffer)
    glBufferData(GL_PIXEL_UNPACK_BUFFER, 4, null, GL_STREAM_DRAW)
    glPixelStorei(GL_UNPACK_ALIGNMENT, 8)
    glPixelStorei(GL_UNPACK_ROW_LENGTH, 32)
    glPixelStorei(GL_UNPACK_SKIP_ROWS, 1)
    glPixelStorei(GL_UNPACK_SKIP_PIXELS, 2)

    var target = gpu.createRenderTarget(2, 2)
    Swag.require(target.colorBuffer.isValid())
    gpu.deleteRenderTarget(&target)

    var image = Image.create(2, 2, .RGBA8)
    image.fill(Argb.Red)
    var texture = gpu.addImage(image)
    Swag.require(texture.isValid())
    image.fill(Argb.Blue)
    Swag.require(gpu.updateTexture(texture, image.pixels.storage()))

    var unpackBinding, alignment, rowLength, skipRows, skipPixels: GLint
    glGetIntegerv(GL_PIXEL_UNPACK_BUFFER_BINDING, &unpackBinding)
    glGetIntegerv(GL_UNPACK_ALIGNMENT, &alignment)
    glGetIntegerv(GL_UNPACK_ROW_LENGTH, &rowLength)
    glGetIntegerv(GL_UNPACK_SKIP_ROWS, &skipRows)
    glGetIntegerv(GL_UNPACK_SKIP_PIXELS, &skipPixels)
    Swag.require(unpackBinding == cast(GLint, unpackBuffer) and
                 alignment == 8 and
                 rowLength == 32 and
                 skipRows == 1 and
                 skipPixels == 2)

    var packBuffer: GLuint
    glGenBuffers(1, &packBuffer)
    glBindBuffer(GL_PIXEL_PACK_BUFFER, packBuffer)
    glBufferData(GL_PIXEL_PACK_BUFFER, 4, null, GL_STREAM_READ)
    glPixelStorei(GL_PACK_ALIGNMENT, 8)
    glPixelStorei(GL_PACK_ROW_LENGTH, 32)
    glPixelStorei(GL_PACK_SKIP_ROWS, 1)
    glPixelStorei(GL_PACK_SKIP_PIXELS, 2)
    let pixels = gpu.readTexturePixels(texture, .RGBA8)
    Swag.require(Slice.equals(pixels.toSlice(), image.pixels.toSlice()))
    glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &unpackBinding)
    glGetIntegerv(GL_PACK_ALIGNMENT, &alignment)
    glGetIntegerv(GL_PACK_ROW_LENGTH, &rowLength)
    glGetIntegerv(GL_PACK_SKIP_ROWS, &skipRows)
    glGetIntegerv(GL_PACK_SKIP_PIXELS, &skipPixels)
    Swag.require(unpackBinding == cast(GLint, packBuffer) and
                 alignment == 8 and
                 rowLength == 32 and
                 skipRows == 1 and
                 skipPixels == 2)

    gpu.removeTexture(&texture)
    glBindBuffer(GL_PIXEL_UNPACK_BUFFER, 0)
    glBindBuffer(GL_PIXEL_PACK_BUFFER, 0)
    glDeleteBuffers(1, &unpackBuffer)
    glDeleteBuffers(1, &packBuffer)
    gpu.end()
}
