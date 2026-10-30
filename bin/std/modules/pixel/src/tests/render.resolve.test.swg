#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Full-target resolves must agree with the general shader, including translucent samples,
// transparent blocks, non-power-of-two factors and the first and last source rows.
func checkResolve(width, height: s32)
{
    for factor in 1 to 8
    {
        var source = Image.create(width * factor, height * factor, .BGRA8)
        for &value, index in source.pixels do
            value[] = cast(u8, (index * 37 + index / 11) % 256)
        Memory.clear(source.pixels.storage(), cast(u64, source.rowStride * factor))

        var cpu: RenderCpu
        cpu.begin(width, height)
        let renderer: IRenderer = &cpu
        defer renderer.end()
        var texture = renderer.addImage(source)
        defer renderer.removeTexture(&texture)
        var target = renderer.createRenderTarget(width, height)
        defer renderer.deleteRenderTarget(&target)

        var images: [2] Image
        for pass in 2
        {
            var painter = Painter.create(renderer)
            painter.begin()
            painter.bindRenderTarget(&target)
            painter.setColorMaskFull()
            painter.setBlendingMode(.Copy)
            painter.setResolveShader(factor)

            // A full-size scissor preserves the picture while selecting the general path.
            if pass do
                painter.setClippingRect({0, 0, width, height})
            painter.drawTexture({0, 0, width, height}, {0, 0, width * factor, height * factor}, texture)
            painter.resetClippingRect()
            painter.setDefaultShader()
            painter.unbindRenderTarget()
            painter.end()
            renderer.draw(&painter)
            images[pass] = renderer.readRenderTarget(&target, 0, 0, width, height)
        }

        for value, index in images[0].pixels do
            Swag.assert(value == images[1].pixels[index])
    }
}

#test
{
    checkResolve(13, 7)
}

// Cross the work threshold with two full bands and a partial final band.
#[Swag.TestTag("parallel")]
#test
{
    let workers = Swag.workerCount()
    Swag.setWorkerCount(4)
    defer Swag.setWorkerCount(workers)
    checkResolve(128, 35)
}
