#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Command-stream goldens for the renderer configuration a drawing asks for: blending, color
// masks, texture sampling, overlap-safe stroking and custom shaders. None of it changes the
// geometry, so these goldens are the contract between the painter and the renderer.
// See [[Testing.assertGolden]].

private func makeTestTexture(handle: u64, w, h: s32)->Texture
{
    var result: retval
    result.attach(cast(TextureHandle) handle, .BGRA8, w, h)
    return result
}

// Every blending mode in order, each separating two fills. A mode that stopped being emitted, or
// that started coalescing with its neighbor, shows up as a missing line.
#test
{
    var painter: Painter
    painter.begin()
    painter.setBlendingMode(.Copy)
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Red))
    painter.setBlendingMode(.Alpha)
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Red))
    painter.setBlendingMode(.Add)
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Red))
    painter.setBlendingMode(.Sub)
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Red))
    painter.setBlendingMode(.SubDst)
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Red))
    painter.setBlendingMode(.Min)
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Red))
    painter.setBlendingMode(.Max)
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "blend.allmodes")
}

// Setting the same blending mode twice must collapse into a single command.
#test
{
    var painter: Painter
    painter.begin()
    painter.setBlendingMode(.Add)
    painter.setBlendingMode(.Add)
    painter.end()
    Testing.assertGolden(&painter, "blend.redundant")
}

// The sampler mode travels with the brush, not with the painter state, so it has to reach
// BindTexture0 for a texture but never for a hatch (which is always sampled per pixel).
#test
{
    var painter: Painter
    let texture = makeTestTexture(7, 64, 32)

    painter.begin()
    painter.setInterpolationMode(.Linear)
    painter.drawTexture(0, 0, 64, 32, texture)
    painter.setInterpolationMode(.Pixel)
    painter.drawTexture(0, 40, 64, 32, texture)
    painter.end()
    Testing.assertGolden(&painter, "blend.interpolation")
}

// A translucent thick stroke enters overlap-safe mode so that self-overlapping segments do not
// accumulate alpha. Losing the StartNoOverlap / StopNoOverlap pair is a visible regression on
// every dashed or joined translucent line.
#test
{
    var painter: Painter
    var path:    LinePath
    let pen = Pen.createSolid(Color.fromArgb(128'u8, Argb.Red), 8)

    path.start(10, 80)
    path.lineTo(50, 10)
    path.lineTo(90, 80)

    painter.begin()
    painter.drawPath(&path, pen)
    painter.end()
    Testing.assertGolden(&painter, "blend.nooverlap.translucent")
}

// An opaque, non-antialiased stroke needs no overlap pass at all.
#test
{
    var painter: Painter
    var path:    LinePath
    let pen = Pen.createSolid(Color.fromArgb(Argb.Red), 8)

    path.start(10, 80)
    path.lineTo(50, 10)
    path.lineTo(90, 80)

    painter.begin()
    painter.setAntialiased(false)
    painter.drawPath(&path, pen)
    painter.end()
    Testing.assertGolden(&painter, "blend.nooverlap.opaque")
}

#test
{
    var painter: Painter
    painter.begin()
    painter.setColorMask(true, false, false, true)
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Red))
    painter.setColorMask(false, true, false, false)
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Red))
    painter.end()
    Testing.assertGolden(&painter, "blend.colormask.channels")
}

// Shader handles and uniform locations are driver-assigned values; the dump remaps them so the
// golden records the sequence of shader switches, not the addresses of the day.
#test
{
    var painter: Painter
    var first:   ShaderBase
    var second:  ShaderBase

    painter.begin()
    painter.setShader(&first)
    painter.setShaderParam(cast(ShaderParamHandle) 17, 0.5'f32)
    painter.setShaderParam(cast(ShaderParamHandle) 42, 3's32)
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Red))
    painter.setShader(&second)
    painter.setShaderParam(cast(ShaderParamHandle) 17, 1.5'f32)
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Red))
    painter.setShader()
    painter.end()
    Testing.assertGolden(&painter, "blend.shader")
}

// Nested render targets must unwind in order, each restoring the state its bind saved.
#test
{
    var painter: Painter
    var outer:   RenderTarget
    var inner:   RenderTarget

    outer.attach(cast(RenderTargetHandle) 1, cast(TextureHandle) 21, .BGRA8, 128, 128)
    inner.attach(cast(RenderTargetHandle) 2, cast(TextureHandle) 22, .BGRA8, 64, 64)

    painter.begin()
    painter.bindRenderTarget(&outer)
    painter.setBlendingMode(.Add)
    painter.bindRenderTarget(&inner, paintAlpha: true)
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Red))
    painter.unbindRenderTarget()
    painter.fillRect(0, 0, 10, 10, Color.fromArgb(Argb.Green))
    painter.unbindRenderTarget()
    painter.end()
    Testing.assertGolden(&painter, "blend.target.nested")
}
