#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Command-stream goldens for off-screen layers.
//
// A layer is the most command-heavy thing the painter does: it acquires render targets, redirects
// drawing into them, runs separable blur passes through a shader, and composites the result back.
// Every step is invisible to the other suites and reaches the renderer only as a command sequence,
// which is exactly what a golden records. See [[Testing.assertGolden]].
//
// The renderer runs in headless mode: its targets and textures are CPU-backed descriptors, so no
// GL context is involved and the handles are allocated in a deterministic order. No shader is
// linked either, so every uniform location is still zero and they all remap to the same 'p#0'; the
// type and value that follow are what tells two consecutive SetShaderParam apart.
private func makeLayerRenderer(renderer: *RenderOgl)
{
    renderer.setupHeadless()
}

#test
{
    var painter:  Painter
    var renderer: RenderOgl
    var layer:    Layer
    var begin:    LayerBeginInfo

    makeLayerRenderer(&renderer)
    begin.width  = 64
    begin.height = 32

    painter.begin()
    layer.begin(&renderer, &painter, begin)
    painter.fillRect(0, 0, 64, 32, Color.fromArgb(Argb.Red))
    layer.end()
    layer.release()
    painter.end()
    Testing.assertGolden(&painter, "layer.record")
}

// A supersampled layer records into a larger target and needs a resolve pass back to the logical
// size; without renderScale the resolve is a no-op.
#test
{
    var painter:  Painter
    var renderer: RenderOgl
    var layer:    Layer
    var begin:    LayerBeginInfo

    makeLayerRenderer(&renderer)
    begin.width       = 64
    begin.height      = 32
    begin.renderScale = 2

    painter.begin()
    layer.begin(&renderer, &painter, begin)
    painter.fillRect(0, 0, 64, 32, Color.fromArgb(Argb.Red))
    layer.end()
    layer.resolve()
    layer.release()
    painter.end()
    Testing.assertGolden(&painter, "layer.supersampled")
}

// Compositing a layer binds its content texture and draws one quad.
#test
{
    var painter:  Painter
    var renderer: RenderOgl
    var layer:    Layer
    var begin:    LayerBeginInfo
    var draw:     LayerDrawInfo

    makeLayerRenderer(&renderer)
    begin.width  = 64
    begin.height = 32
    draw.dstRect = {10, 10, 64, 32}

    painter.begin()
    layer.begin(&renderer, &painter, begin)
    painter.fillRect(0, 0, 64, 32, Color.fromArgb(Argb.Red))
    layer.end()
    layer.resolve()
    layer.draw(draw)
    painter.end()
    Testing.assertGolden(&painter, "layer.draw")
}

// A shadow adds the separable blur passes and a second composite. This is the only golden that
// exercises the blur shader and its parameters.
#test
{
    var painter:  Painter
    var renderer: RenderOgl
    var layer:    Layer
    var begin:    LayerBeginInfo
    var draw:     LayerDrawInfo

    makeLayerRenderer(&renderer)
    begin.width          = 64
    begin.height         = 32
    draw.dstRect         = {10, 10, 64, 32}
    draw.shadow.enabled  = true
    draw.shadow.radius   = 6
    draw.shadow.offsetX  = 3
    draw.shadow.offsetY  = 4

    painter.begin()
    layer.begin(&renderer, &painter, begin)
    painter.fillRect(0, 0, 64, 32, Color.fromArgb(Argb.Red))
    layer.end()
    layer.resolve()
    layer.draw(draw)
    painter.end()
    Testing.assertGolden(&painter, "layer.shadow")
}
