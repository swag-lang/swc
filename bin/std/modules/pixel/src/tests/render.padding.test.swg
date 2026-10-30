#global if #command == Swag.CompilerCommand.Test

using Core

// Fractional source bounds must select the same texels in a non-power-of-two texture.
func renderFractionalSourceScene(renderer: IRenderer)->Image
{
    var source = renderer.createRenderTarget(192, 192)
    defer renderer.deleteRenderTarget(&source)
    var target = renderer.createRenderTarget(2, 2)
    defer renderer.deleteRenderTarget(&target)
    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&source)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.setAntialiased(false)
    painter.clear(Argb.White)
    painter.fillRect(Math.Rectangle{0, 0, 1, 1}, Argb.Red)
    painter.fillRect(Math.Rectangle{1, 0, 1, 1}, Argb.Blue)
    painter.fillRect(Math.Rectangle{0, 1, 1, 1}, Argb.Green)
    painter.unbindRenderTarget()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.setAntialiased(false)
    painter.setInterpolationMode(.Pixel)
    painter.drawTexture({0, 0, 2, 2}, {0, 0, 1.5, 1.5}, source.colorBuffer)
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)
    return renderer.readRenderTarget(&target, 0, 0, 2, 2)
}

func assertFractionalSourceScene(image: Image)
{
    assertPixel(image, 0, 0, Argb.Red)
    assertPixel(image, 1, 0, Argb.Blue)
    assertPixel(image, 0, 1, Argb.Green)
    assertPixel(image, 1, 1, Argb.White)
}

#test
{
    var cpu: RenderCpu
    assertFractionalSourceScene(renderFractionalSourceScene(&cpu))
}

// The allocation need not be divisible by the resolve factor. Blocks start at the content origin.
func renderResolvePaddingScene(renderer: IRenderer, factor: s32)->Image
{
    var source = Image.create(128, 128, .BGRA8)
    for y in source.height
    {
        for x in source.width
        {
            let pixel = source.pixels.storage() + cast(u64, (127 - y) * source.rowStride + x * 4)
            pixel[0] = 64
            pixel[1] = cast(u8, ((y / factor) & 1) * 255)
            pixel[2] = cast(u8, ((x / factor) & 1) * 255)
            pixel[3] = 255
        }
    }

    var texture = renderer.addImage(source)
    defer renderer.removeTexture(&texture)
    var target = renderer.createRenderTarget(40, 40)
    defer renderer.deleteRenderTarget(&target)
    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.setAntialiased(false)
    painter.setResolveShader(factor)
    painter.drawTexture({0, 0, 40, 40}, {0, 0, 40 * factor, 40 * factor}, texture)
    painter.setDefaultShader()
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)
    return renderer.readRenderTarget(&target, 0, 0, 40, 40)
}

func assertResolvePaddingScene(image: Image)
{
    for y in 40
    {
        for x in 40 do
            assertPixel(image, x, y, Color.fromArgb(255'u8, cast(u8, (x & 1) * 255), cast(u8, (y & 1) * 255), 64'u8))
    }
}

#test
{
    var cpu: RenderCpu
    for factor in [2, 3] do
        assertResolvePaddingScene(renderResolvePaddingScene(&cpu, factor))
}
