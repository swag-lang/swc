#global public
using Core, Ogl, Core.Math

enum DefaultShaderId
{
    Default
    Blur
}

// Antialiasing fringe half-width, in (untransformed) path-space pixels.
// The fringe band is centered on the shape contour (AAHalf inside / AAHalf
// outside), giving a 1px transition with 50% coverage on the true edge.
const AAHalf = 0.5'f32

#[Swag.Pack(1)]
struct VertexLayout
{
    pos:       Vector2
    uv:        Vector2
    color:     u32
    cov:       f32     // antialiasing coverage: 1 = solid, 0 = outer fringe edge
}

enum CommandId
{
    Clear
    ColorMask
    Transform
    DrawTriangles
    BindTexture0
    ResetTexture0
    StartFont
    StartMsdfFont
    EndFont
    BindTextureFont
    ResetTextureFont
    SetClippingRect
    ResetClippingRect
    StartClippingRegion
    EndClippingRegion
    ResetClippingRegion
    SetClippingRegionMode
    UpdateFont
    StartNoOverlap
    StopNoOverlap
    SetBlendingMode
    BindRenderTarget
    UnbindRenderTarget
    ReleaseRenderTarget
    SetShader
    SetShaderParam
    SetFontEffect
}

#[Swag.EnumFlags]
enum PaintParams
{
    Zero
    Antialiased
    Default     = Antialiased
}

enum PaintQuality
{
    Draft
    Normal
}

enum ClippingMode
{
    Set
    Clear
}

enum BlendingMode
{
    Copy
    Alpha
    Add
    Sub
    SubDst
    Min
    Max
}

struct PaintState
{
    paintParams:           PaintParams = Default
    paintQuality:          PaintQuality = Normal
    transform:             Transform2
    blendingMode:          BlendingMode = Alpha
    interpolationMode:     InterpolationMode = .Pixel
    clippingRect:          Math.Rectangle
    stackClipRect:         Array'Math.Rectangle
    clippingRectOn:        bool
    colorMask:             ColorMask
}

struct ColorMask { r, g, b, a: bool }

// Resolved MSDF font-effect uniforms (see TextEffect / font_msdf.frag). Colors are
// kept as Color (not Vector4) and expanded to vec4 at the GL layer.
struct FontEffectParams
{
    enabled:       f32
    faceDilate:    f32
    faceSoftness:  f32
    outlineWidth:  f32
    outlineColor:  Color
    glowColor:     Color
    glowOffset:    f32
    glowInner:     f32
    glowOuter:     f32
    glowPower:     f32
    bevel:         f32
}

struct Command
{
    id:  CommandId = undefined

    using params: union
    {
        clear:              struct{ color: Color }
        drawTriangles:      struct{ start: u32, count: u32 }
        transform:          struct{ tr: Transform2 }
        clippingRect:       struct{ rect: Math.Rectangle }
        clippingRegion:     struct{ mode: ClippingMode = undefined }
        font:               struct{ fontRef: *Font }
        blendingMode:       struct{ mode: BlendingMode = undefined }
        textureFont:        struct{ font: *Font, atlasIndex: s32 }
        colorMask:          ColorMask
        renderTgt:          struct{ tgt: *RenderTarget, paintAlpha: bool }
        shader:             struct{ shader: *ShaderBase }

        shaderParam: struct
        {
            param:     ShaderParamHandle
            type:      typeinfo
            _f32:      f32
            _s32:      s32
        }

        fontEffect: FontEffectParams

        texture0: struct
        {
            boundRect:             Vector4
            textureRect:           Vector4
            type:                  BrushType = undefined
            hatch:                 HatchStyle = undefined
            uvMode:                UVMode = undefined
            interpolationMode:     InterpolationMode = undefined
            texture:               Texture
            gradientStart:         Vector2
            gradientEnd:           Vector2
            gradientRadius0:       f32
            gradientRadius1:       f32
            gradientAngle0:        f32
            gradientAngle1:        f32
            gradientSpread:        GradientSpread = undefined
            gradientStops:         [MaxGradientStops] GradientStop
            gradientStopCount:     u8
        }
    }
}

struct Painter
{
    commandBuffer:          Array'Command
    vertexBuffer:           Array'VertexLayout
    triangulateIdx:         Array's32
    fake:                   bool

    sharedLinePath:         LinePath
    sharedLinePathList:     LinePathList
    sharedRoundTmp:         Array'{ factor: f32, pos: Vector2 }

    curState:               PaintState
    stackState:             Array'PaintState
    stackTransform:         Array'Transform2
    lastTexture0Type:       BrushType = SolidColor
    tess:                   Poly2Tri.Tessellate

    stackRT:                Array'*RenderTarget
    curRT:                  *RenderTarget

    lastTexture0Handle:     TextureHandle
    hasTextureFont:         bool

    // Last MSDF font-effect uniforms emitted this frame, to skip redundant
    // SetFontEffect commands (most text shares the same -- usually empty -- effect).
    lastFontEffect:         FontEffectParams
    hasFontEffect:          bool

    // Currently bound glyph atlas, to skip redundant per-glyph BindTextureFont commands
    // (consecutive glyphs of a run share an atlas); this keeps their triangles in one batch.
    curTextureFont:         *Font
    curTextureFontAtlas:    s32 = -1

    // Reusable shaped run for the immediate drawString path, so per-frame text drawing
    // shapes without allocating a fresh glyph buffer on every call.
    scratchShaped:          ShapedRun

    drawingBegin:           bool
    overlapMode:            bool
    canSetTexture0:         bool = true
}

impl Painter
{
    fileprivate func getTextureSize(brush: Brush)->{ w: s32, h: s32 }
    {
        var result: retval

        // For a hatch brush, texture size is always 8x8
        if brush.type == .Hatch
        {
            result.w, result.h = 8
        }
        else
        {
            result.w = brush.texture.width
            result.h = brush.texture.height
        }

        return result
    }

    fileprivate mtd resetTexture0()
    {
        if .lastTexture0Handle or .lastTexture0Type != .SolidColor
        {
            .lastTexture0Handle = cast(TextureHandle) 0
            .lastTexture0Type   = .SolidColor
            discard .newCommand(.ResetTexture0, true)
        }
    }

    fileprivate mtd setTexture0(bvMin, bvMax: Vector2, brush: Brush)
    {
        if !.canSetTexture0 do
            return
        if brush.type == .SolidColor
        {
            .resetTexture0()
            return
        }

        let cmd    = .newCommand(.BindTexture0, true)
        let params = &cmd.texture0

        params.boundRect.x = bvMin.x
        params.boundRect.y = bvMin.y
        params.boundRect.z = bvMax.x
        params.boundRect.w = bvMax.y

        let (wt, ht) = getTextureSize(brush)
        if brush.uvMode == .FillSubRect
        {
            params.textureRect.x = brush.uvRect.x / wt
            params.textureRect.y = brush.uvRect.y / ht
            params.textureRect.z = brush.uvRect.right() / wt
            params.textureRect.w = brush.uvRect.bottom() / ht
            params.textureRect.x += 0.5 / wt
            params.textureRect.y += 0.5 / ht
            params.textureRect.z -= 0.5 / wt
            params.textureRect.w -= 0.5 / ht
        }
        else
        {
            params.textureRect.x = 0
            params.textureRect.y = 0
            params.textureRect.z = wt
            params.textureRect.w = ht
        }

        params.type    = brush.type
        params.hatch   = brush.hatch
        params.texture = brush.texture
        params.uvMode  = brush.uvMode
        params.gradientStart     = brush.gradientStart
        params.gradientEnd       = brush.gradientEnd
        params.gradientRadius0   = brush.gradientRadius0
        params.gradientRadius1   = brush.gradientRadius1
        params.gradientAngle0    = brush.gradientAngle0
        params.gradientAngle1    = brush.gradientAngle1
        params.gradientSpread    = brush.gradientSpread
        params.gradientStops     = brush.gradientStops
        params.gradientStopCount = brush.gradientStopCount
        if brush.type == .Hatch do
            params.interpolationMode = .Pixel
        else do
            params.interpolationMode = .curState.interpolationMode

        .lastTexture0Handle = brush.texture.handle
        .lastTexture0Type   = brush.type
    }

    fileprivate mtd startFont()
    {
        discard .newCommand(.StartFont, true)
    }

    fileprivate mtd startMsdfFont()
    {
        discard .newCommand(.StartMsdfFont, true)
    }

    fileprivate mtd endFont()
    {
        discard .newCommand(.EndFont, true)
    }

    // Set the MSDF font-effect uniforms for the following glyph runs. Emitted only
    // when the effect changes (most runs share the same one), and must follow a
    // StartMsdfFont so the uniforms land on the MSDF font program.
    fileprivate mtd setFontEffect(fx: FontEffectParams)
    {
        if .hasFontEffect
           and .lastFontEffect.enabled      == fx.enabled
           and .lastFontEffect.faceDilate   == fx.faceDilate
           and .lastFontEffect.faceSoftness == fx.faceSoftness
           and .lastFontEffect.outlineWidth == fx.outlineWidth
           and .lastFontEffect.outlineColor.argb == fx.outlineColor.argb
           and .lastFontEffect.glowColor.argb == fx.glowColor.argb
           and .lastFontEffect.glowOffset   == fx.glowOffset
           and .lastFontEffect.glowInner    == fx.glowInner
           and .lastFontEffect.glowOuter    == fx.glowOuter
           and .lastFontEffect.glowPower    == fx.glowPower
           and .lastFontEffect.bevel        == fx.bevel do
            return

        .lastFontEffect = fx
        .hasFontEffect  = true

        let cmd = .newCommand(.SetFontEffect, true)
        cmd.fontEffect = fx
    }

    fileprivate mtd resetTextureFont()
    {
        .curTextureFont      = null
        .curTextureFontAtlas = -1
        if !.hasTextureFont do
            return
        .hasTextureFont = false
        discard .newCommand(.ResetTextureFont, true)
    }

    fileprivate mtd setTextureFont(font: *Font, atlasIndex: s32)
    {
        // Already bound to this atlas: nothing to emit, so the following glyph
        // triangles extend the current DrawTriangles batch instead of starting a new one.
        if .hasTextureFont and .curTextureFont == font and .curTextureFontAtlas == atlasIndex do
            return

        let cmd    = .newCommand(.BindTextureFont, true)
        let params = &cmd.textureFont
        params.font       = font
        params.atlasIndex = atlasIndex
        .hasTextureFont      = true
        .curTextureFont      = font
        .curTextureFontAtlas = atlasIndex
    }

    fileprivate mtd pushTriangleCmd()->*Command
    {
        var cmd: *Command
        if .commandBuffer.count
        {
            let last = .commandBuffer.buffer + .commandBuffer.count - 1
            if last.id == CommandId.DrawTriangles do
                cmd = last
        }

        if !cmd
        {
            cmd                     = .newCommand(.DrawTriangles)
            cmd.drawTriangles.start = cast(u32) .vertexBuffer.count
            cmd.drawTriangles.count = 0
        }

        return cmd
    }

    fileprivate mtd pushTriangle(p1, p2, p3: Vector2, uv1, uv2, uv3: Vector2, color: Color)->u64
    {
        let cmd = .pushTriangleCmd()
        cmd.drawTriangles.count += 3

        var ptr = .vertexBuffer.emplaceAddress(3)
        ptr.pos   = p1
        ptr.color = color.argb
        ptr.cov   = 1
        ptr.uv    = uv1
        ptr += 1
        ptr.pos   = p2
        ptr.color = color.argb
        ptr.cov   = 1
        ptr.uv    = uv2
        ptr += 1
        ptr.pos   = p3
        ptr.color = color.argb
        ptr.cov   = 1
        ptr.uv    = uv3

        return .vertexBuffer.count - 3
    }

    fileprivate mtd pushTriangle(p1, p2, p3: Vector2, color: Color)->u64
    {
        let cmd = .pushTriangleCmd()
        cmd.drawTriangles.count += 3

        var ptr = .vertexBuffer.emplaceAddress(3)
        ptr.pos   = p1
        ptr.color = color.argb
        ptr.cov   = 1
        ptr += 1
        ptr.pos   = p2
        ptr.color = color.argb
        ptr.cov   = 1
        ptr += 1
        ptr.pos   = p3
        ptr.color = color.argb
        ptr.cov   = 1

        return .vertexBuffer.count - 3
    }

    // Emit a fringe quad: the (innerA, innerB) edge sits at full coverage and the
    // (outerA, outerB) edge fades to zero. Two triangles are appended to the
    // current draw command, reusing the given color.
    #[Swag.Safety(.All, false)]
    fileprivate mtd pushFringeQuad(innerA, outerA, innerB, outerB: Vector2, color: u32)
    {
        let cmd = .pushTriangleCmd()
        cmd.drawTriangles.count += 6

        var ptr = .vertexBuffer.emplaceAddress(6)
        ptr.pos = innerA; ptr.color = color; ptr.cov = 1
        ptr += 1
        ptr.pos = innerB; ptr.color = color; ptr.cov = 1
        ptr += 1
        ptr.pos = outerA; ptr.color = color; ptr.cov = 0
        ptr += 1
        ptr.pos = innerB; ptr.color = color; ptr.cov = 1
        ptr += 1
        ptr.pos = outerB; ptr.color = color; ptr.cov = 0
        ptr += 1
        ptr.pos = outerA; ptr.color = color; ptr.cov = 0
    }

    // Emit a centered antialiasing fringe along the edge (startx,starty)-(endx,endy)
    // of the triangle 'tri'. The band straddles the edge (AAHalf inside / AAHalf
    // outside), the outside direction being the one pointing away from the
    // triangle centroid. Used by stroke geometry, where overlap on the inner half
    // is handled by the no-overlap blending pass (or is harmless for opaque pens).
    #[Swag.Safety(.All, false)]
    fileprivate mtd addEdgeAA(tri: u64, startx, starty, endx, endy: f32)
    {
        let v0 = .vertexBuffer.buffer + tri
        let p  = Vector2{startx, starty}
        let q  = Vector2{endx, endy}

        // Outward normal: perpendicular to the edge, pointing away from the centroid.
        let centroid = (v0[0].pos + v0[1].pos + v0[2].pos) * (1.0 / 3.0)
        var n        = Vector2{q.y - p.y, p.x - q.x}
        n.normalizeSafe()
        let mid = (p + q) * 0.5
        if n.dot(mid - centroid) < 0 do
            n = -n

        let off = n * AAHalf
        .pushFringeQuad(p - off, p + off, q - off, q + off, v0.color)
    }

    #[Swag.Inline]
    fileprivate mtd addEdgeAA(tri: u64, start, end: Vector2)
    {
        .addEdgeAA(tri, start.x, start.y, end.x, end.y)
    }

    #[Swag.Inline]
    fileprivate mtd newCommand(cmd: CommandId, replaceLast = false)->*Command
    {
        Debug.assert(.drawingBegin, "begin() not called before")

        // Take the previous command if it's the same
        if replaceLast and .commandBuffer.count and .commandBuffer.buffer[.commandBuffer.count - 1].id == cmd do
            return .commandBuffer.buffer + .commandBuffer.count - 1

        let ptr = .commandBuffer.emplaceAddress(1)
        ptr.id = cmd
        return ptr
    }

    fileprivate mtd updateFont(fontRef: *Font)
    {
        if !fontRef.cache.dirty do
            return
        let cmd = .newCommand(.UpdateFont, false)
        cmd.font.fontRef = fontRef
    }

    fileprivate mtd startOverlapMode(pen: Pen)
    {
        var alpha = false
        if !pen.brush.isOpaque() do
            alpha = true
        if .curRT and .curRT.paintAlpha and .curState.paintParams & .Antialiased do
            alpha = true
        if alpha and .curState.blendingMode == .Alpha
        {
            .overlapMode = true
            discard .newCommand(.StartNoOverlap, true)
        }
    }

    fileprivate mtd stopOverlapMode()
    {
        if .overlapMode
        {
            .overlapMode = false
            discard .newCommand(.StopNoOverlap, true)
        }
    }

    // Call this before drawing
    mtd begin()
    {
        Debug.assert(.drawingBegin == false)

        .commandBuffer.clear()
        .vertexBuffer.clear()

        .drawingBegin   = true
        .canSetTexture0 = true
        .overlapMode    = false
        .hasFontEffect  = false
        .curRT          = null
        .stackRT.clear()

        .resetState()
    }

    // Call this after drawing
    mtd end()
    {
        Debug.assert(.drawingBegin)
        .drawingBegin = false
    }

    // Clear the rendering surface
    mtd clear(color: Color)
    {
        let cmd = .newCommand(.Clear)
        cmd.clear.color = color
    }

    // Reset the current painting state
    mtd resetState()
    {
        with me.curState
        {
            .paintParams  = .Default
            .paintQuality = .Normal
            .transform.setIdentity()
            .interpolationMode = .Pixel
            .blendingMode      = .Alpha
            .colorMask.r, .colorMask.g, .colorMask.b = true
            .colorMask.a = false
        }

        .resetClippingRect()
        .resetTexture0()
        .resetTextureFont()
        .setState(.curState)
    }

    // Set the current painting state
    mtd setState(state: PaintState)
    {
        .curState = state
        .setTransform(.curState.transform)
        .setBlendingMode(.curState.blendingMode)
        .setColorMask(.curState.colorMask)

        if .curState.clippingRectOn
        {
            .curState.clippingRectOn = false
            .setClippingRect(.curState.clippingRect)
        }
    }

    // Save the current paint state
    mtd pushState()
    {
        .stackState.add(.curState)
    }

    // Restore the last paint state
    mtd popState()
    {
        let state = .stackState.popBack()
        .setState(state)
    }

    // Set the paint parameters
    mtd setParams(add: PaintParams, remove: PaintParams = .Zero)
    {
        .curState.paintParams |= add
        .curState.paintParams &= ~remove
    }

    mtd addParams(add: PaintParams)
    {
        .curState.paintParams |= add
    }

    mtd removeParams(remove: PaintParams)
    {
        .curState.paintParams &= ~remove
    }

    // Set antialiased mode on/off
    mtd setAntialiased(aa = true)
    {
        if aa do
            .curState.paintParams |= .Antialiased
        else do
            .curState.paintParams &= ~.Antialiased
    }

    #[Swag.Inline]
    mtd getParams() => .curState.paintParams
    #[Swag.Inline]
    mtd getQuality() => .curState.paintQuality

    // Set the paint quality
    mtd setQuality(quality: PaintQuality)
    {
        .curState.paintQuality = quality
    }

    // Set the paint position
    mtd translateTransform(x, y: f32)
    {
        if isZeroEpsilon(x) and isZeroEpsilon(y) do
            return
        let tr = Transform2.createTranslation(x, y)
        .curState.transform.multiply(tr)
        .setTransform(.curState.transform)
    }

    // Set the paint rotation
    mtd rotateTransform(angle: Math.Angle)
    {
        if isZeroEpsilon(angle.rad) do
            return
        let tr = Transform2.createRotation(angle.rad, 0, 0)
        .curState.transform.multiply(tr)
        .setTransform(.curState.transform)
    }

    // Set the paint rotation
    mtd rotateTransform(angle: Math.Angle, centerX, centerY: f32)
    {
        if isZeroEpsilon(angle.rad) do
            return
        let tr = Transform2.createRotation(angle.rad, centerX, centerY)
        .curState.transform.multiply(tr)
        .setTransform(.curState.transform)
    }

    // Set the paint rotation.
    // Will rotate around the current transformation position.
    mtd rotateTransformInPlace(angle: Math.Angle)
    {
        if isZeroEpsilon(angle.rad) do
            return
        let tr = Transform2.createRotation(angle.rad, .curState.transform.tx, .curState.transform.ty)
        .curState.transform.multiply(tr)
        .setTransform(.curState.transform)
    }

    // Set the paint scale
    mtd scaleTransform(x, y: f32)
    {
        if isZeroEpsilon(x) and isZeroEpsilon(y) do
            return
        let tr = Transform2.createScale(x, y, 0, 0)
        .curState.transform.multiply(tr)
        .setTransform(.curState.transform)
    }

    // Set the paint scale
    mtd scaleTransform(x: f32)
    {
        if isZeroEpsilon(x) do
            return
        let tr = Transform2.createScale(x, x, 0, 0)
        .curState.transform.multiply(tr)
        .setTransform(.curState.transform)
    }

    // Push the current transformation
    mtd pushTransform()
    {
        .stackTransform.add(.curState.transform)
    }

    // Restore the pushed transformation
    mtd popTransform()
    {
        .setTransform(.stackTransform.popBack())
    }

    // Reset the paint position, rotation, scale
    mtd resetTransform()
    {
        .curState.transform.setIdentity()
        .setTransform(.curState.transform)
    }

    // Set the paint transformation
    mtd setTransform(tr: Transform2)
    {
        .curState.transform = tr
        let cmd = .newCommand(.Transform, true)
        cmd.transform.tr = tr
    }

    // Returns the current tranformation
    mtd getTransform()->Transform2
    {
        var result: retval = .curState.transform
        return result
    }

    // Set the texture interpolation mode
    mtd setInterpolationMode(mode: InterpolationMode)
    {
        .curState.interpolationMode = mode
    }

    #[Swag.Inline]
    mtd getInterpolationMode() => .curState.interpolationMode

    // Set the current clipping rectangle
    mtd setClippingRect(x, y, width, height: f32)
    {
        .setClippingRect({x, y, width, height})
    }

    // Set the current clipping rectangle
    mtd setClippingRect(rect: Math.Rectangle)
    {
        if .curState.clippingRect == rect and .curState.clippingRectOn do
            return
        .curState.clippingRect   = rect
        .curState.clippingRectOn = true
        let cmd = .newCommand(.SetClippingRect, true)
        cmd.clippingRect.rect = .curState.clippingRect
    }

    // Reset the current clipping rectangle
    mtd resetClippingRect()
    {
        if .curState.clippingRectOn
        {
            .curState.clippingRectOn = false
            .curState.stackClipRect.clear()
            discard .newCommand(.ResetClippingRect, true)
        }
    }

    // Interface the given rectangle with the current clipping rectangle
    mtd pushClippingSurfaceRect(rect: Math.Rectangle)
    {
        .pushClippingRect(rect, true)
    }

    // Interface the given rectangle with the current clipping rectangle
    mtd pushClippingRect(rect: Math.Rectangle, isSurfacePos = false)
    {
        var rrect = rect
        if !isSurfacePos do
            rrect.offset(.curState.transform.tx, .curState.transform.ty)
        rrect.round()

        if .curState.clippingRectOn
        {
            .curState.stackClipRect.add(.curState.clippingRect)
            var newRect = .curState.clippingRect
            newRect.intersect(rrect)
            .setClippingRect(newRect)
        }
        else
        {
            .setClippingRect(rrect)
        }
    }

    // Restore the original clipping rectangle
    mtd popClippingRect()
    {
        if .curState.stackClipRect.isEmpty()
        {
            .resetClippingRect()
        }
        else
        {
            let clipRect = .curState.stackClipRect.popBack()
            .setClippingRect(clipRect)
        }
    }

    // Get the current clipping rectangle
    mtd getClippingRect()->Math.Rectangle
    {
        if .curState.clippingRectOn do
            return .curState.clippingRect
        return {0, 0, Swag.F32.Max, Swag.F32.Max}
    }

    // Returns true if the current clipping rectangle is empty (no drawing !)
    mtd isEmptyClippingRect()->bool
    {
        return .curState.clippingRectOn and .curState.clippingRect.isEmpty()
    }

    // Start painting in the clipping buffer
    mtd startClippingRegion(mode = ClippingMode.Set)
    {
        let cmd = .newCommand(.StartClippingRegion, true)
        cmd.clippingRegion.mode = mode
    }

    // Set the clipping region mode
    mtd setClippingRegionMode(mode: ClippingMode)
    {
        let cmd = .newCommand(.SetClippingRegionMode, true)
        cmd.clippingRegion.mode = mode
    }

    // Stop painting in the clipping buffer. Back to normal.
    mtd endClippingRegion()
    {
        discard .newCommand(.EndClippingRegion, true)
    }

    // Reset clipping buffer to its default value (no more clipping)
    mtd resetClippingRegion()
    {
        discard .newCommand(.ResetClippingRegion, true)
    }

    // Set the current blending mode
    mtd setBlendingMode(mode: BlendingMode)
    {
        let cmd = .newCommand(.SetBlendingMode, true)
        cmd.blendingMode.mode  = mode
        .curState.blendingMode = mode
    }

    // Set color mask
    mtd setColorMask(cm: ColorMask)
    {
        let cmd = .newCommand(.ColorMask, true)
        cmd.colorMask       = cm
        .curState.colorMask = cm
    }

    // Set color mask
    mtd setColorMask(r, g, b, a: bool)
    {
        let cmd = .newCommand(.ColorMask, true)
        cmd.colorMask.r     = r
        cmd.colorMask.g     = g
        cmd.colorMask.b     = b
        cmd.colorMask.a     = a
        .curState.colorMask = cmd.colorMask
    }

    mtd setColorMaskColor() => .setColorMask(true, true, true, false)
    mtd setColorMaskFull()  => .setColorMask(true, true, true, true)
    mtd setColorMaskAlpha() => .setColorMask(false, false, false, true)

    // Bind a render target
    mtd bindRenderTarget(tgt: *RenderTarget, paintAlpha = false)
    {
        .pushState()
        let cmd = .newCommand(.BindRenderTarget, true)
        cmd.renderTgt.tgt        = tgt
        cmd.renderTgt.paintAlpha = paintAlpha
        .resetState()

        if .curRT do
            .stackRT.add(.curRT)
        .curRT = tgt
    }

    // Bind a render target
    mtd unbindRenderTarget()
    {
        discard .newCommand(.UnbindRenderTarget, true)
        .popState()

        if .stackRT.count do
            .curRT = .stackRT.popBack()
        else
        {
            Debug.assert(.curRT != null)
            .curRT = null
        }
    }

    // Release the render target
    mtd releaseRenderTarget(tgt: *RenderTarget)
    {
        if !tgt do
            return
        let cmd = .newCommand(.ReleaseRenderTarget)
        cmd.renderTgt.tgt = tgt
    }

    // Set the current shader
    mtd setShader(shader: *ShaderBase = null)
    {
        let cmd = .newCommand(.SetShader, true)
        cmd.shader.shader = shader
    }

    // Set a shader parameter
    mtd setShaderParam(param: ShaderParamHandle, val: s32)
    {
        let cmd = .newCommand(.SetShaderParam)
        cmd.shaderParam.param = param
        cmd.shaderParam.type  = s32
        cmd.shaderParam._s32  = val
    }

    // Set a shader parameter
    mtd setShaderParam(param: ShaderParamHandle, val: f32)
    {
        let cmd = .newCommand(.SetShaderParam)
        cmd.shaderParam.param = param
        cmd.shaderParam.type  = f32
        cmd.shaderParam._f32  = val
    }
}
