#global if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    func renderScaledLayer(transformed: bool)->Image
    {
        var cpu:      RenderCpu
        let renderer: IRenderer = &cpu
        renderer.init()
        var target = renderer.createRenderTarget(240, 160)
        defer renderer.deleteRenderTarget(&target)
        var painter = Painter.create(renderer)
        painter.begin()
        painter.bindRenderTarget(&target)
        painter.setColorMaskFull()
        painter.clear(Color.fromArgb(Argb.White))

        var layer: Layer
        layer.begin(&painter, {width: 64, height: 32})
        painter.fillRoundRect({8, 4, 48, 24}, 4, 4, Color.fromArgb(Argb.Red))
        layer.end()
        var draw: LayerDrawInfo
        draw.dstRect = transformed ? Math.Rectangle{20, 20, 64, 32} : Math.Rectangle{40, 60, 128, 96}
        draw.shadow  = {enabled: true, radius: 4, offsetX: 3, offsetY: 5}
        if transformed do
            painter.scaleTransform(2, 3)
        layer.draw(draw)
        painter.unbindRenderTarget()
        painter.end()
        renderer.draw(&painter)
        return renderer.readRenderTarget(&target, 0, 0, 240, 160)
    }

    var expected = renderScaledLayer(true)
    var actual   = renderScaledLayer(false)
    Testing.assertImagesNear(&expected, &actual, "layer.scaled-shadow", {maxChannelDelta: 2})
}
#test
{
    var cpu:   RenderCpu
    var painter = Painter.create(&cpu)
    var layer: Layer
    var draw:  LayerDrawInfo

    draw.dstRect          = {10, 10, 64, 32}
    draw.blendingMode     = .Copy
    draw.releaseAfterDraw = false

    painter.begin()
    layer.begin(&painter, {width: 64, height: 32})
    painter.fillRect(0, 0, 64, 32, Color.fromArgb(Argb.Red))
    layer.end()
    layer.draw(draw)
    layer.releaseImmediate()
    painter.end()

    var sawCopy:    bool
    var sawRelease: bool
    for cmd in painter.commandBuffer where cmd.op is .SetBlendingMode and cmd.blendingMode.mode == .Copy do
        sawCopy = true
    for cmd in painter.commandBuffer where cmd.op is .ReleaseRenderTarget do
        sawRelease = true
    Swag.assert(sawCopy and sawRelease and layer.contentTarget == null)
}
