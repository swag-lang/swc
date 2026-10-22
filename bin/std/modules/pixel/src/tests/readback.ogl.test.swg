#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Ogl

// A bounded readback preserves top-left cropping, BGRA row order and caller-owned GL bindings.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    var window  = expect Env.createWindow({identifier: "pixel-readback-test", title: "Pixel readback test", width: 64, height: 48})
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
    gpu.draw(&painter)
    let expected = gpu.readRenderTarget(&target, 3, 5, 21, 29)
    var actual   = Image.create(21, 29, .BGRA8)
    var readback: RenderOglReadback
    defer readback.release()
    for 3
    {
        let submitted = readback.submit(&target, 3, 5, 21, 29)
        Swag.assert(submitted and readback.isPending() and not readback.hasFailed())
        var copied: bool
        var watch:  Time.Stopwatch
        watch.start()
        while not copied and watch.elapsedMilliseconds() < 2000
        {
            copied = readback.tryCopyTo(actual.pixels.toSlice())
            if not copied do
                Threading.Thread.sleep(1'ms)
        }

        Swag.assert(copied and not readback.isPending() and not readback.hasFailed())
        Swag.assert(Slice.equals(actual.pixels.toSlice(), expected.pixels.toSlice()))
        var buffer, framebuffer: GLint
        glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &buffer)
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &framebuffer)
        Swag.assert(buffer == 0 and framebuffer == 0)
    }

    var padded: Array'u8
    padded.resize(128 * 29)
    let strided = readback.submit(&target, 3, 5, 21, 29)
    Swag.assert(strided)
    var copiedRows: bool
    var rowWatch:   Time.Stopwatch
    rowWatch.start()
    while not copiedRows and rowWatch.elapsedMilliseconds() < 2000
    {
        copiedRows = readback.tryCopyTo(padded.toSlice(), rowStride: 128)
        if not copiedRows do
            Threading.Thread.sleep(1'ms)
    }

    Swag.assert(copiedRows)
    for row in 29'u64
    {
        Swag.assert(Slice.equals(padded.toSlice()[row * 128 until row * 128 + 84],
                                 expected.pixels.toSlice()[row * 84 until (row + 1) * 84]))
        for byte in padded.toSlice()[row * 128 + 84 until (row + 1) * 128] do
            Swag.assert(byte == 0)
    }

    let submitted = readback.submit(&target, 3, 5, 21, 29)
    Swag.assert(submitted)
    readback.cancel()
    Swag.assert(not readback.isPending())
    let copied = readback.tryCopyTo(actual.pixels.toSlice())
    Swag.assert(not copied)
}
