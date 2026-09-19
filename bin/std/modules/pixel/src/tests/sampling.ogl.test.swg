#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Swag, Core

// A hidden native drawable exercises the real shaders; CPU goldens cannot catch a GPU sampler
// crossing the edge of a source rectangle into its brightly colored atlas neighbors.
func renderSamplingScene(renderer: IRenderer, scale: f32)->Image
{
    var source = Image.create(8, 8, .BGRA8)
    for y in source.height
    {
        for x in source.width
        {
            let pixel  = source.pixels.storage() + cast(u64) ((source.height - y - 1) * source.rowStride + x * 4)
            let border = x == 0 or y == 0 or x == 7 or y == 7
            pixel[0] = border ? 255'u8 : cast(u8) (x * 28)
            pixel[1] = border ? 0'u8 : cast(u8) (y * 28)
            pixel[2] = border ? 255'u8 : cast(u8) ((x + y) * 14)
            pixel[3] = cast(u8) (64 + x * 20)
        }
    }

    var texture = renderer.addImage(source)
    defer renderer.removeTexture(&texture)
    var target = renderer.createRenderTarget(192, 160)
    defer renderer.deleteRenderTarget(&target)
    var painter = Painter.create(renderer)
    painter.begin()
    painter.setContentScale(scale)
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.clear(Argb.Black)
    painter.setInterpolationMode(.Linear)

    // Magnification, minification, fractional source edges, and a one-texel-wide strip.
    painter.drawTexture({4, 4, 31, 23}, {1, 1, 6, 6}, texture)
    painter.drawTexture({40, 4, 3, 4}, {1, 1, 6, 6}, texture)
    painter.drawTexture({48, 4, 27, 23}, {2, 1, 1, 6}, texture)
    painter.drawTexture({4, 32, 31, 23}, {1.25, 1.25, 5.5, 5.5}, texture)

    // Texture state must not leak into a subsequent solid fill, including transparent RGB.
    painter.fillRect({40, 32, 35, 23}, Color.fromArgb(0'u8, 80'u8, 120'u8, 160'u8))
    painter.setBlendingMode(.Alpha)
    painter.fillRect({4, 60, 31, 16}, Color.fromArgb(128'u8, 120'u8, 80'u8, 40'u8))
    painter.drawTexture({40, 60, 35, 16}, {1, 1, 6, 6}, texture)
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)
    return renderer.readRenderTarget(&target, 0, 0, 192, 160)
}

#[Swag.TestTag("gpu")]
#test
{
    var window         = expect Env.createWindow({identifier: "pixel-sampling-test", title: "Pixel sampling test", width: 192, height: 160})
    var ogl: RenderOgl
    let gpu: IRenderer = &ogl
    var context        = expect gpu.createContext(window.nativeRenderHandle(), 192, 160)
    defer gpu.deleteContext(&context)
    gpu.setCurrentContext(context)
    gpu.init()

    var cpu:       RenderCpu
    let reference: IRenderer = &cpu
    reference.init()
    for scale in [1.0'f32, 1.25, 1.5, 2.0]
    {
        let expected = renderSamplingScene(reference, scale)
        let actual   = renderSamplingScene(gpu, scale)

        // Interpolation and alpha blending round on both backends. The existing four-fetch
        // shader differs by up to three channel levels; no outlier pixels are allowed.
        Testing.assertImagesNear(&expected, &actual, "sampling.ogl", {maxChannelDelta: 3})
    }
}
