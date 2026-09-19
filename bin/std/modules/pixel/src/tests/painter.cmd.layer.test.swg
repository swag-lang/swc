#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Command-stream goldens for off-screen layers.
//
// A layer is the most command-heavy thing the painter does: it acquires render targets, redirects
// drawing into them, runs separable blur passes through a shader, and composites the result back.
// Every step is invisible to the other suites and reaches the renderer only as a command sequence,
// which is exactly what a golden records. See [[Testing.assertGolden]].
//
// The painter uses the CPU backend, so no graphics context is involved and resource handles are
// allocated in a deterministic order. Built-in effects remain explicit painter commands.

#[Swag.TestTag("golden")]
#test
{
    var cpu:   RenderCpu
    var painter = Painter.create(&cpu)
    var layer: Layer
    var begin: LayerBeginInfo

    begin.width  = 64
    begin.height = 32

    painter.begin()
    layer.begin(&painter, begin)
    painter.fillRect(0, 0, 64, 32, Color.fromArgb(Argb.Red))
    layer.end()
    layer.release()
    painter.end()
    Testing.assertGolden(&painter, "layer.record")
}

// A supersampled layer records into a larger target and needs a resolve pass back to the logical
// size; without renderScale the resolve is a no-op.
#[Swag.TestTag("golden")]
#test
{
    var cpu:   RenderCpu
    var painter = Painter.create(&cpu)
    var layer: Layer
    var begin: LayerBeginInfo

    begin.width       = 64
    begin.height      = 32
    begin.renderScale = 2

    painter.begin()
    layer.begin(&painter, begin)
    painter.fillRect(0, 0, 64, 32, Color.fromArgb(Argb.Red))
    layer.end()
    layer.resolve()
    layer.release()
    painter.end()
    Testing.assertGolden(&painter, "layer.supersampled")
}

// Compositing a layer binds its content texture and draws one quad.
#[Swag.TestTag("golden")]
#test
{
    var cpu:   RenderCpu
    var painter = Painter.create(&cpu)
    var layer: Layer
    var begin: LayerBeginInfo
    var draw:  LayerDrawInfo

    begin.width  = 64
    begin.height = 32
    draw.dstRect = {10, 10, 64, 32}

    painter.begin()
    layer.begin(&painter, begin)
    painter.fillRect(0, 0, 64, 32, Color.fromArgb(Argb.Red))
    layer.end()
    layer.resolve()
    layer.draw(draw)
    painter.end()
    Testing.assertGolden(&painter, "layer.draw")
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
    for cmd in painter.commandBuffer where cmd.id == .SetBlendingMode and cmd.blendingMode.mode == .Copy do
        sawCopy = true
    for cmd in painter.commandBuffer where cmd.id == .ReleaseRenderTarget do
        sawRelease = true
    Swag.assert(sawCopy and sawRelease and layer.contentTarget == null)
}

// A shadow adds the separable blur passes and a second composite. This is the only golden that
// exercises the built-in blur program and its parameters.
#[Swag.TestTag("golden")]
#test
{
    var cpu:   RenderCpu
    var painter = Painter.create(&cpu)
    var layer: Layer
    var begin: LayerBeginInfo
    var draw:  LayerDrawInfo

    begin.width         = 64
    begin.height        = 32
    draw.dstRect        = {10, 10, 64, 32}
    draw.shadow.enabled = true
    draw.shadow.radius  = 6
    draw.shadow.offsetX = 3
    draw.shadow.offsetY = 4

    painter.begin()
    layer.begin(&painter, begin)
    painter.fillRect(0, 0, 64, 32, Color.fromArgb(Argb.Red))
    layer.end()
    layer.resolve()
    layer.draw(draw)
    painter.end()
    Testing.assertGolden(&painter, "layer.shadow")
}
