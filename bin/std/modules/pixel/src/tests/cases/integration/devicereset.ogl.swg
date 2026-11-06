#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Draws the same text and fills into `target`, and returns what it holds.
func paintProbe(gpu: IRenderer, target: *RenderTarget, font: *Font, texture: Texture)->Image
{
    var painter = Painter.create(gpu)
    painter.begin()
    painter.bindRenderTarget(target)
    painter.setColorMaskFull()
    painter.clear(Argb.Black)
    painter.fillRect({2, 2, 12, 10}, Argb.Red)
    painter.drawTexture({20, 2, 8, 8}, texture)
    painter.drawString(2, 18, "AV", font, Argb.White)
    painter.unbindRenderTarget()
    painter.end()
    expect gpu.draw(&painter)
    return gpu.readRenderTarget(target, 0, 0, 64, 48)
}

// A device reset caused by the renderer's own work is reported, retires what the lost device
// held, and leaves a renderer that draws text, textures and readbacks exactly as before.
//
// This resets the graphics device for real. Run it on its own: displays driven through a USB
// graphics adapter can go dark for a few seconds while the driver recovers.
#[Swag.TestTag("integration.renderer.reset")]
#test
{
    var window = expect Env.createWindow({identifier: "pixel-device-reset-test", title: "Pixel device reset test", width: 64, height: 48})
    expect window.showOffScreen()
    var renderer: RenderOgl
    let gpu:      IRenderer = &renderer
    var context = expect gpu.createContext(window.nativeRenderHandle(), 64, 48)
    defer gpu.deleteContext(&context)
    gpu.setCurrentContext(context)
    gpu.init()
    Swag.require(not expect renderer.recoverLostDevice(), "a healthy device reported a reset")

    var image = Image.create(8, 8, .BGRA8)
    image.fill(Argb.Lime)
    let font    = makeTextTestFont(gpu.fontCache(), 18, .Bitmap)
    var texture = gpu.addImage(image)
    var target  = gpu.createRenderTarget(64, 48)
    let before  = paintProbe(gpu, &target, font, texture)
    Swag.require(before.pixelColor(24, 6).argb == Argb.Lime)

    // Wait for the system to reset the device the hang stalls.
    Testing.submitDeviceHang()
    var recovered: bool
    var watch:     Time.Stopwatch
    watch.start()
    while not recovered and watch.elapsedMilliseconds() < 30000
    {
        recovered = catch renderer.recoverLostDevice()
        if not recovered do
            Threading.Thread.sleep(50'ms)
    }

    Swag.require(recovered and renderer.deviceResets == 1, "the device reset was never reported")
    Swag.require(not texture.isValid() and not target.colorBuffer.isValid())

    // Releasing what the lost device held touches nothing of the replacement.
    let stale = texture
    gpu.removeTexture(&texture)
    gpu.deleteRenderTarget(&target)
    Swag.require(not target.colorBuffer.isValid())

    // The replacement draws the same picture; a lost texture draws nothing.
    var fresh = gpu.addImage(image)
    defer gpu.removeTexture(&fresh)
    var replacement = gpu.createRenderTarget(64, 48)
    defer gpu.deleteRenderTarget(&replacement)
    let after = paintProbe(gpu, &replacement, font, fresh)
    Swag.require(Slice.equals(after.pixels.toSlice(), before.pixels.toSlice()), "the restored renderer draws a different picture")
    let lost = paintProbe(gpu, &replacement, font, stale)
    Swag.require(lost.pixelColor(24, 6).argb == Argb.Black)

    // An asynchronous readback of the replacement delivers the pixels just drawn.
    var readback: RenderOglReadback
    defer readback.release()
    var copy = Image.create(64, 48, .BGRA8)
    discard paintProbe(gpu, &replacement, font, fresh)
    Swag.require(readback.submit(&replacement, 0, 0, 64, 48))
    var copied:    bool
    var copyWatch: Time.Stopwatch
    copyWatch.start()
    while not copied and copyWatch.elapsedMilliseconds() < 2000
    {
        copied = readback.tryCopyTo(copy.pixels.toSlice())
        if not copied do
            Threading.Thread.sleep(1'ms)
    }

    Swag.require(copied and Slice.equals(copy.pixels.toSlice(), before.pixels.toSlice()))
}
