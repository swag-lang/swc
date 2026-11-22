#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Resizing a retained shadowed layer must match scaling its whole composite, including
// margins and offsets. Compare images so a misplaced coloured body cannot hide in a shadow.
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
        expect renderer.draw(&painter)
        return renderer.readRenderTarget(&target, 0, 0, 240, 160)
    }

    var expected = renderScaledLayer(true)
    var actual   = renderScaledLayer(false)
    Testing.assertImagesNear(&expected, &actual, "layer.scaled-shadow", {maxChannelDelta: 2})
}

// An opaque retained layer can replace destination colors without a second alpha blend.
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
    Swag.require(sawCopy and sawRelease and layer.contentTarget == null)
}

// A retained layer rebuilds its shadow when the draw-time shadow configuration changes.
#test
{
    func renderLayerShadow(reuseShadow: bool)->Image
    {
        var cpu:      RenderCpu
        let renderer: IRenderer = &cpu
        renderer.init()
        var target = renderer.createRenderTarget(96, 64)
        defer renderer.deleteRenderTarget(&target)
        var painter = Painter.create(renderer)
        painter.begin()
        painter.bindRenderTarget(&target)
        painter.setColorMaskFull()
        painter.clear(Color.fromArgb(Argb.Black))

        var layer: Layer
        layer.begin(&painter, {width: 48, height: 32})
        painter.fillRoundRect({12, 8, 24, 16}, 4, 4, Color.fromArgb(Argb.White))
        layer.end()

        var draw: LayerDrawInfo
        draw.dstRect = {20, 16, 48, 32}
        draw.releaseAfterDraw = false
        if reuseShadow
        {
            draw.shadow = {enabled: true, margin: 3, radius: 2, offsetX: 1, offsetY: 1,
                           color: Color.fromArgb(Argb.Blue)}
            layer.draw(draw)
            painter.clear(Color.fromArgb(Argb.Black))
        }

        draw.shadow = {enabled: true, margin: 10, radius: 7, offsetX: 5, offsetY: -3,
                       color: Color.fromArgb(Argb.Red)}
        layer.draw(draw)
        painter.unbindRenderTarget()
        painter.end()
        expect renderer.draw(&painter)
        let image = renderer.readRenderTarget(&target, 0, 0, 96, 64)
        layer.releaseImmediate()
        return image
    }

    let expected = renderLayerShadow(false)
    let actual   = renderLayerShadow(true)
    Swag.require(Slice.equals(expected.pixels.toSlice(), actual.pixels.toSlice()))
}

// Releasing a retained layer between painter recordings returns its targets before the next begin.
#test
{
    var cpu: RenderCpu
    cpu.begin(16, 16)
    let renderer: IRenderer = &cpu
    var painter = Painter.create(renderer)
    var layer:    Layer

    painter.begin()
    layer.begin(&painter, {width: 8, height: 8})
    layer.end()
    painter.end()
    discard expect renderer.draw(&painter)
    renderer.end()

    let releasedTarget = unwrap layer.contentTarget
    layer.release()
    Swag.require(layer.painter == null and layer.renderer == null)

    // A fresh recording used to discard the queued release before it reached the renderer.
    painter.begin()
    painter.end()

    let reusedTarget = renderer.acquireRenderTarget(releasedTarget.colorBuffer.width,
                                                    releasedTarget.colorBuffer.height)
    Swag.require(reusedTarget == releasedTarget)
    renderer.releaseRenderTarget(reusedTarget)
}

// Starting a new recording abandons the old stream and still releases its queued targets.
#test
{
    var cpu: RenderCpu
    cpu.begin(16, 16)
    let renderer: IRenderer = &cpu
    var painter = Painter.create(renderer)
    var layer:    Layer

    painter.begin()
    layer.begin(&painter, {width: 8, height: 8})
    layer.end()
    painter.end()

    let releasedTarget = unwrap layer.contentTarget
    layer.release()
    painter.begin()
    painter.end()

    let reusedTarget = renderer.acquireRenderTarget(releasedTarget.colorBuffer.width,
                                                    releasedTarget.colorBuffer.height)
    Swag.require(reusedTarget == releasedTarget)
    renderer.releaseRenderTarget(reusedTarget)
    renderer.end()
}

// A released layer can outlive its renderer and then bind to a new one safely.
#test
{
    var firstCpu: RenderCpu
    firstCpu.begin(16, 16)
    let firstRenderer: IRenderer = &firstCpu
    var firstPainter = Painter.create(firstRenderer)

    var secondCpu: RenderCpu
    secondCpu.begin(16, 16)
    let secondRenderer: IRenderer = &secondCpu
    var secondPainter = Painter.create(secondRenderer)

    var layer: Layer
    firstPainter.begin()
    layer.begin(&firstPainter, {width: 8, height: 8})
    layer.end()
    firstPainter.end()
    discard expect firstRenderer.draw(&firstPainter)
    firstRenderer.end()
    layer.releaseImmediate()

    Swag.require(layer.painter == null and layer.renderer == null)

    secondPainter.begin()
    layer.begin(&secondPainter, {width: 8, height: 8})
    layer.end()
    secondPainter.end()
    discard expect secondRenderer.draw(&secondPainter)
    secondRenderer.end()
    layer.release()
}

// Releasing after painter.end still waits until the pending command stream unbinds the layer.
#test
{
    var cpu: RenderCpu
    cpu.begin(16, 16)
    let renderer: IRenderer = &cpu
    var painter = Painter.create(renderer)
    var layer:    Layer

    painter.begin()
    layer.begin(&painter, {width: 8, height: 8})
    painter.fillRect(0, 0, 8, 8, Color.fromArgb(Argb.Red))
    layer.end()
    painter.end()

    let releasedTarget = unwrap layer.contentTarget
    layer.release()
    var sawUnbind: bool
    var sawReleaseAfterUnbind: bool
    for command in painter.commandBuffer
    {
        if command.op is .UnbindRenderTarget do
            sawUnbind = true
        elif sawUnbind and
             command.op is .ReleaseRenderTarget and
             command.renderTgt.tgt == releasedTarget do
            sawReleaseAfterUnbind = true
    }

    Swag.require(sawReleaseAfterUnbind)

    discard expect renderer.draw(&painter)
    renderer.end()
    let reusedTarget = renderer.acquireRenderTarget(releasedTarget.colorBuffer.width,
                                                    releasedTarget.colorBuffer.height)
    Swag.require(reusedTarget == releasedTarget)
    renderer.releaseRenderTarget(reusedTarget)
}
