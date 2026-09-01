#global public

using Core, Ogl, Core.Math

// Identifies a renderer-independent program understood by every painter backend.
enum DefaultShaderId
{
    Default     // Standard antialiased shape, texture, and text rendering.
    Simple      // Non-antialiased textured rendering.
    Blur        // Separable blur pass used by layers and effects.
    Resolve     // Supersampling resolve pass used by layers.
}

// Antialiasing fringe half-width, in (untransformed) path-space pixels.
//
// The fringe band is centered on the shape contour (AAHalf inside / AAHalf
// outside), giving a 1px transition with 50% coverage on the true edge.
const AAHalf = 0.5'f32

// Defines the packed vertex format consumed by [[Pixel.RenderOgl]] and [[Pixel.RenderCpu]].
#[Swag.Pack(1)]
struct VertexLayout
{
    public
    {
        pos:   Vector2     // Position in painter path-space pixels.
        uv:    Vector2     // Normalized or tiled texture coordinates.
        color: u32         // Vertex color packed for the renderer.
        cov:   f32         // Antialiasing coverage: `1` is solid and `0` is the outer fringe edge.
    }
}

// Identifies one command in the painter's deferred command stream.
enum CommandId
{
    Clear                     // Clear the active rendering surface.
    ColorMask                 // Change writable color channels.
    Transform                 // Change the current two-dimensional transform.
    DrawTriangles             // Draw a contiguous vertex-buffer range.
    BindTexture0              // Bind the current brush texture or gradient.
    ResetTexture0             // Restore the default brush texture.
    ReleaseTexture            // Release a transient renderer-owned texture.
    StartFont                 // Begin bitmap-font rendering.
    StartMsdfFont             // Begin multi-channel signed-distance-field text rendering.
    EndFont                   // End the current font batch.
    BindTextureFont           // Bind one font-atlas texture.
    ResetTextureFont          // Unbind the current font atlas.
    SetClippingRect           // Enable a rectangular scissor region.
    ResetClippingRect         // Disable the rectangular scissor region.
    StartClippingRegion       // Begin writing a stencil clipping region.
    EndClippingRegion         // Finish writing a stencil clipping region.
    ResetClippingRegion       // Clear stencil clipping.
    SetClippingRegionMode     // Change how subsequent shapes affect stencil clipping.
    UpdateFont                // Upload pending font-atlas changes.
    StartNoOverlap            // Begin overlap-safe alpha rendering.
    StopNoOverlap             // Finish overlap-safe alpha rendering.
    SetBlendingMode           // Change the framebuffer blend operation.
    BindRenderTarget          // Redirect drawing to an off-screen target.
    UnbindRenderTarget        // Restore the previous rendering target.
    ReleaseRenderTarget       // Release a renderer-owned target.
    SetDefaultShader          // Select a renderer-independent built-in program.
    SetShader                 // Select a custom shader.
    SetShaderParam            // Update one custom-shader uniform.
    SetFontEffect             // Update MSDF font-effect uniforms.
}

// Controls optional painter behaviors.
#[Swag.EnumFlags]
enum PaintParams
{
    Zero                      // Disable every optional behavior.
    Antialiased               // Generate coverage fringes along vector edges.
    Default = Antialiased     // Use the normal antialiased configuration.
}

// Selects the geometric approximation quality used for curved paths.
enum PaintQuality
{
    Draft      // Favor fewer segments and lower tessellation cost.
    Normal     // Balance visual quality and cost.
    High       // Favor smoother curves at additional tessellation cost.
}

// Selects how newly drawn geometry changes the stencil clipping region.
enum ClippingMode
{
    Set       // Add drawn coverage to the clipping region.
    Clear     // Remove drawn coverage from the clipping region.
}

// Selects how source and destination colors are combined.
enum BlendingMode
{
    Copy           // Replace the destination with the source.
    Alpha          // Composite using source alpha.
    Add            // Add source and destination components.
    Sub            // Subtract destination components from the source.
    SubDst         // Subtract source components from the destination.
    Min            // Keep the minimum raw source/destination component.
    Max            // Keep the maximum raw source/destination component.
    DstIn          // Multiply the destination by the source alpha, ignoring the source color.
    Multiply       // Multiply source and backdrop colors, producing a darker result.
    Screen         // Multiply inverted colors, producing a lighter result.
    Overlay        // Multiply or screen according to the backdrop color.
    Darken         // Select the darker source/backdrop color before compositing.
    Lighten        // Select the lighter source/backdrop color before compositing.
    ColorDodge     // Brighten the backdrop to reflect the source color.
    ColorBurn      // Darken the backdrop to reflect the source color.
    HardLight      // Multiply or screen according to the source color.
    SoftLight      // Apply a soft source-controlled highlight or shadow.
    Difference     // Use the absolute difference between source and backdrop colors.
    Exclusion      // Apply a lower-contrast difference between source and backdrop colors.
    Hue            // Use the source hue with backdrop saturation and luminosity.
    Saturation     // Use the source saturation with backdrop hue and luminosity.
    Color          // Use the source hue and saturation with backdrop luminosity.
    Luminosity     // Use the source luminosity with backdrop hue and saturation.
}

internal impl BlendingMode
{
    mtd usesAdvancedBlending()->bool
    {
        switch me
        {
        case .Multiply, .Screen, .Overlay, .Darken, .Lighten, .ColorDodge, .ColorBurn, .HardLight, .SoftLight, .Difference, .Exclusion, .Hue, .Saturation, .Color, .Luminosity: return true
        default: return false
        }
    }

    mtd isSeparable()->bool
    {
        switch me
        {
        case .Multiply, .Screen, .Overlay, .Darken, .Lighten, .ColorDodge, .ColorBurn, .HardLight, .SoftLight, .Difference, .Exclusion: return true
        default: return false
        }
    }
}

// Captures the complete mutable drawing state of a [[Pixel.Painter]].
struct PaintState
{
    public
    {
        paintParams:       PaintParams       = Default     // Enabled painter behaviors.
        paintQuality:      PaintQuality      = Normal      // Curve tessellation quality.
        transform:         Transform2                      // Current path-to-surface transform.
        blendingMode:      BlendingMode      = Alpha       // Current color blend operation.
        interpolationMode: InterpolationMode = .Pixel      // Current texture sampler mode.
        clippingRect:      Math.Rectangle                  // Active surface-space clipping rectangle.
        stackClipRect:     Array'Math.Rectangle            // Saved nested clipping rectangles.
        clippingRectOn:    bool                            // Whether `clippingRect` is active.
        colorMask:         ColorMask                       // Channels currently writable by the renderer.
    }
}

// Selects which framebuffer color channels may be written.
struct ColorMask
{
    public
    {
        r: bool     // Allow writes to the red channel.
        g: bool     // Allow writes to the green channel.
        b: bool     // Allow writes to the blue channel.
        a: bool     // Allow writes to the alpha channel.
    }
}

// Contains resolved MSDF font-effect values sent to the text shader.
//
// Applications normally configure [[Pixel.TextEffect]]; the painter derives this
// low-level representation for the renderer.
struct FontEffectParams
{
    public
    {
        enabled:      f32       // Nonzero when at least one effect is active.
        faceDilate:   f32       // Signed expansion of the glyph face in distance-field units.
        faceSoftness: f32       // Width of the softened face edge.
        outlineWidth: f32       // Outline thickness in distance-field units.
        outlineColor: Color     // Straight-alpha outline color.
        glowColor:    Color     // Straight-alpha glow color.
        glowOffset:   f32       // Signed glow displacement in distance-field units.
        glowInner:    f32       // Inner glow boundary.
        glowOuter:    f32       // Outer glow boundary.
        glowPower:    f32       // Glow falloff exponent.
        bevel:        f32       // Bevel intensity.
    }
}

// Stores one deferred painter command and its command-specific payload.
//
// This is the transport format consumed by Pixel renderers. Applications
// should use `Painter` methods instead of constructing commands directly.
struct Command
{
    public
    {
        id: CommandId = undefined     // Operation represented by the active union payload.

        using params: union     // Command-specific payload selected by `id`; inactive members must not be read.
        {
            clear:          struct{ color: Color }
            drawTriangles:  struct{ start: u32, count: u32, bbMin: Vector2, bbMax: Vector2 }
            transform:      struct{ tr: Transform2 }
            clippingRect:   struct{ rect: Math.Rectangle }
            clippingRegion: struct{ mode: ClippingMode = undefined }
            font:           struct{ fontRef: *Font }
            blendingMode:   struct{ mode: BlendingMode = undefined }
            textureFont:    struct{ font: *Font, atlasIndex: s32 }
            colorMask:      ColorMask
            renderTgt:      struct{ tgt: *RenderTarget, paintAlpha: bool }
            defaultShader:  struct{ id: DefaultShaderId = undefined, axis: s32, radius: f32, factor: s32 }
            shader:         struct{ shader: #null *ShaderBase }

            shaderParam: struct
            {
                param: ShaderParamHandle
                type:  typeinfo = undefined
                _f32:  f32
                _s32:  s32
            }

            fontEffect: FontEffectParams

            texture0: struct
            {
                boundRect:         Vector4
                textureRect:       Vector4
                type:              BrushType         = undefined
                hatch:             HatchStyle        = undefined
                uvMode:            UVMode            = undefined
                interpolationMode: InterpolationMode = undefined
                texture:           Texture
                gradientStart:     Vector2
                gradientEnd:       Vector2
                gradientRadius0:   f32
                gradientRadius1:   f32
                gradientAngle0:    f32
                gradientAngle1:    f32
                gradientSpread:    GradientSpread    = undefined
                gradientStopStart: u64
                gradientStopCount: u64
            }
        }
    }
}

// Records drawing operations as a deferred command and vertex stream.
//
// Create it with an [[Pixel.IRenderer]], call [[Painter.begin]], issue drawing
// operations, call [[Painter.end]], then call [[Painter.render]]. Coordinates are
// in path-space pixels and are transformed by the current [[Core.Math.Transform2]].
//
// ## Example
//
// ```swag
// var cpu: RenderCpu
// let renderer: IRenderer = &cpu
// var painter = Painter.create(renderer)
// painter.begin()
// painter.clear(Color.fromRgb(24, 32, 48))
// painter.fillCircle(48, 48, 24, Color.fromRgb(72, 149, 239))
// painter.end()
// ```
struct Painter
{
    // Optional backend selected for [[Painter.render]]. It is borrowed and may
    // remain unset when the painter is used only to inspect recorded commands.
    private rendererItf: #null IRenderer
    public
    {
        // The recorded frame. A renderer, a golden test or a bounds pass reads it; only the
        // drawing methods append to it.
        readonly
        {
            commandBuffer: Array'Command          // Deferred renderer command stream.
            vertexBuffer:  Array'VertexLayout     // Packed vertices referenced by draw commands.
        }
    }

    // Gradient stops referenced by command ranges. Keeping them beside the command stream
    // makes every recorded brush independent of the caller's lifetime without imposing a cap.
    gradientStops: Array'GradientStop

    // Reusable workspaces. They only hold intermediate results of the call in progress.
    private
    {
        triangulateIdx:     Array's32                               // Reusable tessellation index workspace.
        sharedLinePath:     LinePath                                // Reusable single-path workspace.
        sharedLinePathList: LinePathList                            // Reusable multi-path workspace.
        sharedIsland:       Array'(*LinePath)                       // Contours of the region being filled.
        sharedDirections:   HashTable'(u64, Vector2)                // Outward direction of each contour point of that region.
        sharedOffsetDirs:   Array'Vector2                           // Outward direction of each point of the contour being banded.
        sharedRoundTmp:     Array'{ factor: f32, pos: Vector2 }     // Reusable stroke-rounding workspace.
        tess:               Poly2Tri.Tessellate                     // Reusable polygon tessellator.

        // Reusable shaped run for the immediate drawString path, so per-frame text drawing
        // shapes without allocating a fresh glyph buffer on every call.
        scratchShaped:     ShapedRun                 // Reusable shaping result for immediate text drawing.
        transientTextures: Array'Texture             // Renderer-owned images released after the recorded frame.
        transientTargets:  Array'(*RenderTarget)     // Off-screen targets released after nested alpha replay.
    }

    // Recording state: the saved-state stacks, the render-target stack, and the emitted-uniform
    // memos that keep the command stream free of redundant state changes.
    private
    {
        stackState:     Array'PaintState     // States saved by [[Painter.pushState]].
        stackTransform: Array'Transform2     // Transforms saved by [[Painter.pushTransform]].

        stackRT: Array'#null *RenderTarget     // Nested off-screen render targets.
        curRT:   #null *RenderTarget           // Active off-screen target, or `null` for the surface.

        // Whether the bound target rebuilds its alpha by replaying the recording, as the caller
        // asked when it bound. The target carries the same answer, but only once the renderer has
        // executed that bind: while a frame is being recorded, this is the one that is true.
        stackPaintAlpha: Array'bool
        curPaintAlpha:   bool

        lastTexture0Type:   BrushType = SolidColor     // Last brush type emitted to the command stream.
        lastTexture0Handle: TextureHandle              // Last brush texture handle emitted.
        hasTextureFont:     bool                       // Whether a glyph atlas is currently bound.

        // The paintType / gradient uniforms live per shader program, but texture0 state
        // is tracked once. Switching program (AA <-> font <-> MSDF font) leaves the new
        // program's paint uniforms stale, so a program switch forces the next texture0
        // setup to re-emit. 0 = AA/non-text, 1 = bitmap font, 2 = MSDF font.
        texture0Dirty:  bool     // Whether brush uniforms must be re-emitted.
        curTextProgram: s32      // Active text program: `0` none, `1` bitmap, `2` MSDF.

        // Last MSDF font-effect uniforms emitted this frame, to skip redundant
        // SetFontEffect commands (most text shares the same -- usually empty -- effect).
        lastFontEffect: FontEffectParams     // Last emitted MSDF effect values.
        hasFontEffect:  bool                 // Whether `lastFontEffect` is initialized.

        // Currently bound glyph atlas, to skip redundant per-glyph BindTextureFont commands
        // (consecutive glyphs of a run share an atlas); this keeps their triangles in one batch.
        curTextureFont:      #null *Font     // Font owning the currently bound glyph atlas.
        curTextureFontAtlas: s32 = -1        // Zero-based bound atlas index, or `-1`.

        drawingBegin:   bool            // Whether a `begin`/`end` recording scope is active.
        layoutOnly:     bool            // Whether text layout skips rendering commands.
        overlapMode:    bool            // Whether overlap-safe alpha rendering is active.
        canSetTexture0: bool = true     // Whether drawing operations may change the brush texture.
        curState:       PaintState      // Current mutable drawing state.

        // Physical device pixels per painter path-space unit. The renderer multiplies
        // every recorded coordinate by it at draw time, so the whole stream stays in
        // logical units; the painter itself only consults it for antialiasing fringes,
        // text resolution, and device-grid snapping.
        curContentScale: f32 = 1     // Device pixels per logical unit for this stream.

        // Device pixels one path-space unit covers for the purpose of curve flattening,
        // quantized by [[Pixel.Painter.setFlattenScale]]. Kept apart from the content
        // scale: flattening tolerances were calibrated against it, and folding it in
        // would re-flatten every cached path of every consumer on a scaled display.
        curFlattenScale: f32 = 1     // Flattening scale for subsequent path draws.
    }
}

impl Painter
{
    // Creates a painter that borrows `renderer` for resource ownership and submission.
    //
    // The concrete renderer must outlive this painter and every resource referenced
    // by its command stream.
    func create(renderer: IRenderer)->Painter
    {
        var result: retval
        result.rendererItf = renderer
        return result
    }

    // Selects the renderer used by [[Painter.render]].
    //
    // Change it only when no recording is active and no renderer-owned resource is
    // referenced by the painter.
    mtd setRenderer(renderer: IRenderer)
    {
        Debug.assert(!.drawingBegin)
        .rendererItf = renderer
    }

    // Sets the number of physical device pixels per painter path-space unit.
    //
    // Drawing keeps using logical units: the renderer scales every recorded
    // coordinate at draw time, while antialiasing fringes, text resolution, and
    // device-grid snapping account for the real on-screen pixel size. `1`, the
    // default, draws one path-space unit per device pixel. The value survives
    // [[Pixel.Painter.begin]]; set it once per owner, or per pass when a frame mixes
    // logical and physical passes.
    mtd setContentScale(scale: f32)
    {
        Debug.assert(scale > 0)
        .curContentScale = scale
    }

    // Returns the number of physical device pixels per painter path-space unit.
    #[Swag.Inline]
    mtd const contentScale() => .curContentScale

    // Sets how many device pixels one path-space unit covers for curve flattening.
    //
    // Flattening tolerances are expressed in path units, so a consumer that zooms vector
    // geometry through its transform — a document viewer scaling a page — declares the zoom
    // here and curves stay as smooth on screen as they are at scale one. The value is
    // quantized to the power of two below it, between a sixty-fourth and sixty-four, so the
    // derived caches re-key on zoom *buckets* rather than on every wheel step. `1`, the
    // default, keeps the calibrated path-space tolerances untouched. Set it per pass and
    // restore it, the way [[Pixel.Painter.setContentScale]] is managed.
    //
    // Below one it declares a *minified* pass, where a path unit covers less than a device
    // pixel: round joins and caps take fewer segments, and a stroke walks its contour in
    // steps of one tolerance rather than visiting points a shared pixel could not tell
    // apart. Curve flattening itself is never coarsened — a cached contour keeps the finest
    // tessellation anything asked of it, so the result cannot depend on the order two
    // consumers reached the same geometry.
    mtd setFlattenScale(scale: f32)
    {
        Debug.assert(scale > 0)
        var bucket = 1.0'f32
        while bucket * 2 <= scale and bucket < 64 do
            bucket *= 2
        while bucket > scale and bucket > 1.0 / 64 do
            bucket *= 0.5
        .curFlattenScale = bucket
    }

    // Returns the quantized flattening scale of subsequent path draws.
    #[Swag.Inline]
    mtd const flattenScale() => .curFlattenScale

    // Rounds a horizontal path-space position to the physical device-pixel grid.
    //
    // Valid under a translation-only transform; other transforms return the value
    // unchanged. Use it to keep hairlines and carets on whole device pixels.
    mtd const snapToDeviceX(x: f32)->f32
    {
        if !.curState.transform.isTranslationOnly() do
            return x
        let k = .curContentScale
        return Math.round((x + .curState.transform.tx) * k) / k - .curState.transform.tx
    }

    // Rounds a vertical path-space position to the physical device-pixel grid.
    //
    // See [[Pixel.Painter.snapToDeviceX]].
    mtd const snapToDeviceY(y: f32)->f32
    {
        if !.curState.transform.isTranslationOnly() do
            return y
        let k = .curContentScale
        return Math.round((y + .curState.transform.ty) * k) / k - .curState.transform.ty
    }

    // Returns a stroke thickness covering a whole number of device pixels.
    //
    // The result is at least one device pixel, so a one-unit hairline stays a crisp
    // single pixel on every display scale instead of a blurred fraction.
    mtd const hairline(thickness: f32 = 1)->f32
    {
        let k = .curContentScale
        return Math.max(1.0, Math.round(thickness * k)) / k
    }

    // Returns the renderer selected for this painter.
    //
    // The returned interface borrows the concrete renderer.
    mtd renderer()->IRenderer
    {
        Debug.assert(.rendererItf != null, "painter has no renderer")
        return .rendererItf!
    }

    // Queues a transient texture for release after every preceding command has consumed it.
    internal mtd releaseTexture(texture: Texture)
    {
        .transientTextures.add(texture)
    }

    // Submits the completed command stream to the selected renderer.
    //
    // Rendering is synchronous. Call [[Painter.end]] before this method.
    mtd render()
    {
        Debug.assert(!.drawingBegin)
        .renderer().draw(me)
    }

    private func getTextureSize(brush: Brush)->{ w: s32, h: s32 }
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

    private mtd resetTexture0()
    {
        if .texture0Dirty or .lastTexture0Handle or .lastTexture0Type != .SolidColor
        {
            .lastTexture0Handle = cast(TextureHandle) 0
            .lastTexture0Type   = .SolidColor
            .texture0Dirty      = false
            discard .newCommand(.ResetTexture0, true)
        }
    }

    private mtd setTexture0(bvMin, bvMax: Vector2, brush: Brush)
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

        let {wt, ht} = getTextureSize(brush)
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

        params.type              = brush.type
        params.hatch             = brush.hatch
        params.texture           = brush.texture
        params.uvMode            = brush.uvMode
        params.gradientStart     = brush.gradientStart
        params.gradientEnd       = brush.gradientEnd
        params.gradientRadius0   = brush.gradientRadius0
        params.gradientRadius1   = brush.gradientRadius1
        params.gradientAngle0    = brush.gradientAngle0
        params.gradientAngle1    = brush.gradientAngle1
        params.gradientSpread    = brush.gradientSpread
        params.gradientStopStart = .gradientStops.count
        params.gradientStopCount = brush.gradientStops.count
        .gradientStops.add(brush.gradientStops.toSlice())

        // Pixel mode keeps its meaning at every scale: the renderers sharpen it to
        // one device pixel of smoothing per texel edge when the content scale makes
        // the texel-to-pixel mapping fractional.
        if brush.type == .Hatch do
            params.interpolationMode = .Pixel
        else do
            params.interpolationMode = .curState.interpolationMode

        .lastTexture0Handle = brush.texture.handle
        .lastTexture0Type   = brush.type
        .texture0Dirty      = false
    }

    private mtd startFont()
    {
        if .curTextProgram != 1
        {
            .curTextProgram = 1
            .texture0Dirty  = true
        }

        discard .newCommand(.StartFont, true)
    }

    private mtd startMsdfFont()
    {
        if .curTextProgram != 2
        {
            .curTextProgram = 2
            .texture0Dirty  = true
        }

        discard .newCommand(.StartMsdfFont, true)
    }

    private mtd endFont()
    {
        if .curTextProgram != 0
        {
            .curTextProgram = 0
            .texture0Dirty  = true
        }

        discard .newCommand(.EndFont, true)
    }

    // Set the MSDF font-effect uniforms for the following glyph runs. Emitted only
    // when the effect changes (most runs share the same one), and must follow a
    // StartMsdfFont so the uniforms land on the MSDF font program.
    private mtd setFontEffect(fx: FontEffectParams)
    {
        if .hasFontEffect and
           .lastFontEffect.enabled == fx.enabled and
           .lastFontEffect.faceDilate == fx.faceDilate and
           .lastFontEffect.faceSoftness == fx.faceSoftness and
           .lastFontEffect.outlineWidth == fx.outlineWidth and
           .lastFontEffect.outlineColor.argb == fx.outlineColor.argb and
           .lastFontEffect.glowColor.argb == fx.glowColor.argb and
           .lastFontEffect.glowOffset == fx.glowOffset and
           .lastFontEffect.glowInner == fx.glowInner and
           .lastFontEffect.glowOuter == fx.glowOuter and
           .lastFontEffect.glowPower == fx.glowPower and
           .lastFontEffect.bevel == fx.bevel do
            return

        .lastFontEffect = fx
        .hasFontEffect  = true

        let cmd = .newCommand(.SetFontEffect, true)
        cmd.fontEffect = fx
    }

    private mtd resetTextureFont()
    {
        .curTextureFont      = null
        .curTextureFontAtlas = -1
        if !.hasTextureFont do
            return
        .hasTextureFont = false
        discard .newCommand(.ResetTextureFont, true)
    }

    private mtd setTextureFont(font: *Font, atlasIndex: s32)
    {
        // Already bound to this atlas: nothing to emit, so the following glyph
        // triangles extend the current DrawTriangles batch instead of starting a new one.
        if .hasTextureFont and .curTextureFont == font and .curTextureFontAtlas == atlasIndex do
            return

        let cmd    = .newCommand(.BindTextureFont, true)
        let params = &cmd.textureFont
        params.font          = font
        params.atlasIndex    = atlasIndex
        .hasTextureFont      = true
        .curTextureFont      = font
        .curTextureFontAtlas = atlasIndex
    }

    private mtd pushTriangleCmd()->*Command
    {
        if .commandBuffer.count
        {
            let last = .commandBuffer.buffer! + .commandBuffer.count - 1
            if last.id == CommandId.DrawTriangles do
                return last
        }

        let cmd = .newCommand(.DrawTriangles)
        cmd.drawTriangles.start = cast(u32) .vertexBuffer.count
        cmd.drawTriangles.count = 0

        // An empty batch starts inverted, so the first point it takes in becomes both bounds.
        cmd.drawTriangles.bbMin = {Swag.F32.Max, Swag.F32.Max}
        cmd.drawTriangles.bbMax = {-Swag.F32.Max, -Swag.F32.Max}
        return cmd
    }

    // Grows a batch's bounds to hold one more point, in the space its vertices are recorded in.
    //
    // The bounds are what lets a backend touch only the part of the target a batch can reach.
    // The overlap-safe path is the one that needs them: it uses the destination alpha as a scratch
    // channel and has to start that channel from zero, which without bounds means clearing the
    // whole clipping rectangle once per batch — the cost of the window for the width of a stroke.
    #[Swag.Safety(.All, false)]
    private func expandBounds(cmd: *Command, pt: Vector2)
    {
        let bb = &cmd.drawTriangles
        bb.bbMin.x = Math.min(bb.bbMin.x, pt.x)
        bb.bbMin.y = Math.min(bb.bbMin.y, pt.y)
        bb.bbMax.x = Math.max(bb.bbMax.x, pt.x)
        bb.bbMax.y = Math.max(bb.bbMax.y, pt.y)
    }

    private mtd pushTriangle(p1, p2, p3: Vector2, uv1, uv2, uv3: Vector2, color: Color)->u64
    {
        let cmd = .pushTriangleCmd()
        cmd.drawTriangles.count += 3
        expandBounds(cmd, p1)
        expandBounds(cmd, p2)
        expandBounds(cmd, p3)

        var ptr = .vertexBuffer.emplaceAddress(3)
        ptr.pos   = p1
        ptr.color = color.argb
        ptr.cov   = 1
        ptr.uv    = uv1
        ptr       += 1
        ptr.pos   = p2
        ptr.color = color.argb
        ptr.cov   = 1
        ptr.uv    = uv2
        ptr       += 1
        ptr.pos   = p3
        ptr.color = color.argb
        ptr.cov   = 1
        ptr.uv    = uv3

        return .vertexBuffer.count - 3
    }

    private mtd pushTriangle(p1, p2, p3: Vector2, color: Color)->u64
    {
        let cmd = .pushTriangleCmd()
        cmd.drawTriangles.count += 3
        expandBounds(cmd, p1)
        expandBounds(cmd, p2)
        expandBounds(cmd, p3)

        // 'uv' is unused by the non-text shaders (they derive their texture coordinates from the
        // boundRect / textureRect uniforms), but the vertex storage is reused from frame to frame,
        // so leaving it alone would keep publishing stale bytes to anything that reads vertices
        // back.
        var ptr = .vertexBuffer.emplaceAddress(3)
        ptr.pos   = p1
        ptr.uv    = {0, 0}
        ptr.color = color.argb
        ptr.cov   = 1
        ptr       += 1
        ptr.pos   = p2
        ptr.uv    = {0, 0}
        ptr.color = color.argb
        ptr.cov   = 1
        ptr       += 1
        ptr.pos   = p3
        ptr.uv    = {0, 0}
        ptr.color = color.argb
        ptr.cov   = 1

        return .vertexBuffer.count - 3
    }

    // Emit a fringe quad: the (innerA, innerB) edge sits at full coverage and the
    // (outerA, outerB) edge fades to zero. Two triangles are appended to the
    // current draw command, reusing the given color.
    #[Swag.Safety(.All, false)]
    private mtd pushFringeQuad(innerA, outerA, innerB, outerB: Vector2, color: u32)
    {
        let cmd = .pushTriangleCmd()
        cmd.drawTriangles.count += 6
        expandBounds(cmd, innerA)
        expandBounds(cmd, outerA)
        expandBounds(cmd, innerB)
        expandBounds(cmd, outerB)

        var ptr = .vertexBuffer.emplaceAddress(6)
        ptr.pos   = innerA
        ptr.uv    = {0, 0}
        ptr.color = color
        ptr.cov   = 1
        ptr       += 1
        ptr.pos   = innerB
        ptr.uv    = {0, 0}
        ptr.color = color
        ptr.cov   = 1
        ptr       += 1
        ptr.pos   = outerA
        ptr.uv    = {0, 0}
        ptr.color = color
        ptr.cov   = 0
        ptr       += 1
        ptr.pos   = innerB
        ptr.uv    = {0, 0}
        ptr.color = color
        ptr.cov   = 1
        ptr       += 1
        ptr.pos   = outerB
        ptr.uv    = {0, 0}
        ptr.color = color
        ptr.cov   = 0
        ptr       += 1
        ptr.pos   = outerA
        ptr.uv    = {0, 0}
        ptr.color = color
        ptr.cov   = 0
    }

    private mtd aaHalfPathSpace()->f32
    {
        let tr = .curState.transform
        let sx = Math.sqrt(tr.m11 * tr.m11 + tr.m12 * tr.m12)
        let sy = Math.sqrt(tr.m21 * tr.m21 + tr.m22 * tr.m22)
        let sc = Math.min(sx, sy) * .curContentScale
        if sc <= 0.001 do
            return AAHalf
        return AAHalf / sc
    }

    private mtd aaHalfPathSpace(normal: Vector2)->f32
    {
        let tr = .curState.transform
        let tx = normal.x * tr.m11 + normal.y * tr.m21
        let ty = normal.x * tr.m12 + normal.y * tr.m22
        let sc = Math.sqrt(tx * tx + ty * ty) * .curContentScale
        if sc <= 0.001 do
            return AAHalf
        return AAHalf / sc
    }

    // Emit a centered antialiasing fringe along the edge (startx,starty)-(endx,endy)
    // of the triangle 'tri'. The band straddles the edge (AAHalf inside / AAHalf
    // outside), the outside direction being the one pointing away from the
    // triangle centroid. Used by stroke geometry, where overlap on the inner half
    // is handled by the no-overlap blending pass.
    #[Swag.Safety(.All, false)]
    private mtd addEdgeAA(tri: u64, startx, starty, endx, endy: f32)
    {
        let v0 = .vertexBuffer.buffer! + tri
        let p  = Vector2{startx, starty}
        let q  = Vector2{endx, endy}

        // Outward normal: perpendicular to the edge, pointing away from the centroid.
        let centroid = (v0[0].pos + v0[1].pos + v0[2].pos) * (1.0 / 3.0)
        var n        = Vector2{q.y - p.y, p.x - q.x}
        n.normalizeOrZero()
        let mid = (p + q) * 0.5
        if n.dot(mid - centroid) < 0 do
            n = -n

        let off = n * .aaHalfPathSpace(n)
        .pushFringeQuad(p - off, p + off, q - off, q + off, v0.color)
    }

    // Emits the same fringe for a silhouette edge whose outward side the caller already knows.
    //
    // `addEdgeAA` derives that side by reading the triangle back out of the vertex buffer and
    // comparing the edge against its centroid. A stroke does not need to be told: the quad it
    // just emitted has the pen normal for its two long edges, one on each side. Skipping the
    // derivation removes three vertex loads out of a buffer that is tens of megabytes on a
    // document of strokes, and it is that walk, rather than the arithmetic, that the recording
    // was spending its time on.
    //
    // `outward` is the unit direction the fringe extrudes toward, and must be perpendicular to
    // the edge for the band to sit square on it.
    #[Swag.Safety(.All, false)]
    private mtd addEdgeAAOutward(p, q, outward: Vector2, color: u32)
    {
        let off = outward * .aaHalfPathSpace(outward)
        .pushFringeQuad(p - off, p + off, q - off, q + off, color)
    }

    #[Swag.Inline]
    private mtd addEdgeAA(tri: u64, start, end: Vector2)
    {
        .addEdgeAA(tri, start.x, start.y, end.x, end.y)
    }

    #[Swag.Inline]
    private mtd newCommand(cmd: CommandId, replaceLast = false)->*Command
    {
        Debug.assert(.drawingBegin, "begin() not called before")

        // Take the previous command if it's the same
        if replaceLast and .commandBuffer.count
        {
            let cmdBuf = .commandBuffer.buffer!
            if cmdBuf[.commandBuffer.count - 1].id == cmd do
                return cmdBuf + .commandBuffer.count - 1
        }

        let ptr = .commandBuffer.emplaceAddress(1)
        ptr.id = cmd
        return ptr
    }

    private mtd updateFont(fontRef: *Font)
    {
        if !fontRef.cache.dirty do
            return
        let cmd = .newCommand(.UpdateFont, false)
        cmd.font.fontRef = fontRef
    }

    private mtd startOverlapMode(pen: Pen)
    {
        var alpha = false
        if .curState.paintParams & .Antialiased do
            alpha = true
        if !pen.brush.isOpaque() do
            alpha = true
        if .curPaintAlpha and .curState.paintParams & .Antialiased do
            alpha = true
        if alpha and .curState.blendingMode == .Alpha
        {
            .overlapMode = true
            discard .newCommand(.StartNoOverlap, true)
        }
    }

    private mtd stopOverlapMode()
    {
        if .overlapMode
        {
            .overlapMode = false
            discard .newCommand(.StopNoOverlap, true)
        }
    }

    // Starts a fresh recording scope and resets drawing state.
    //
    // A previous scope must have ended. Existing commands and vertices are discarded.
    // Set `layoutOnly` to compute layout without emitting text geometry.
    mtd begin(layoutOnly = false)
    {
        Debug.assert(.drawingBegin == false)

        .commandBuffer.clear()
        .vertexBuffer.clear()
        .gradientStops.clear()
        .transientTextures.clear()
        .transientTargets.clear()

        .drawingBegin   = true
        .layoutOnly     = layoutOnly
        .canSetTexture0 = true
        .overlapMode    = false
        .hasFontEffect  = false
        .texture0Dirty  = true
        .curTextProgram = 0
        .curRT          = null
        .curPaintAlpha  = false
        .stackRT.clear()
        .stackPaintAlpha.clear()

        .resetState()
    }

    // Ends the active recording scope.
    mtd end()
    {
        Debug.assert(.drawingBegin)
        for texture in .transientTextures
        {
            let cmd = .newCommand(.ReleaseTexture, true)
            cmd.texture0.texture = texture
        }

        for target in .transientTargets
        {
            let cmd = .newCommand(.ReleaseRenderTarget)
            cmd.renderTgt.tgt = target
        }

        .drawingBegin = false
    }

    // Records a clear of the active rendering surface.
    //
    // The current clipping rectangle and color mask apply. Enable alpha writes before clearing
    // when later blend equations need the cleared color to be an opaque backdrop.
    mtd clear(color: Color)
    {
        let cmd = .newCommand(.Clear)
        cmd.clear.color = color
    }

    // Restores default transform, clipping, blending, interpolation, and color masks.
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
            .colorMask.a       = false
        }

        .resetClippingRect()
        .resetTexture0()
        .resetTextureFont()
        .setState(.curState)
    }

    // Replaces the current drawing state and emits its renderer-visible changes.
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

    // Returns a copy of the complete current drawing state.
    mtd const state()->PaintState
    {
        var result: retval = .curState
        return result
    }

    // Pushes a copy of the current drawing state.
    mtd pushState()
    {
        .stackState.add(.curState)
    }

    // Pops and restores the most recently pushed drawing state.
    mtd popState()
    {
        let state = .stackState.popBack()
        .setState(state)
    }

    // Adds and removes painter behavior flags atomically.
    mtd setParams(add: PaintParams, remove: PaintParams = .Zero)
    {
        .curState.paintParams |= add
        .curState.paintParams &= ~remove
    }

    // Enables the specified painter behavior flags.
    mtd addParams(add: PaintParams)
    {
        .curState.paintParams |= add
    }

    // Disables the specified painter behavior flags.
    mtd removeParams(remove: PaintParams)
    {
        .curState.paintParams &= ~remove
    }

    // Enables or disables antialiased path fringes.
    mtd setAntialiased(aa = true)
    {
        if aa do
            .curState.paintParams |= .Antialiased
        else do
            .curState.paintParams &= ~.Antialiased
    }

    // Returns the currently enabled painter behavior flags.
    #[Swag.Inline]
    mtd const params() => .curState.paintParams

    // Returns the current curve tessellation quality.
    #[Swag.Inline]
    mtd const quality() => .curState.paintQuality

    // Sets the curve tessellation quality for subsequent paths.
    mtd setQuality(quality: PaintQuality)
    {
        .curState.paintQuality = quality
    }

    // Appends a translation, in path-space pixels, to the current transform.
    mtd translateTransform(x, y: f32)
    {
        if isZeroEpsilon(x) and isZeroEpsilon(y) do
            return
        let tr = Transform2.createTranslation(x, y)
        .curState.transform.multiply(tr)
        .setTransform(.curState.transform)
    }

    // Appends a rotation around the path-space origin.
    mtd rotateTransform(angle: Math.Angle)
    {
        if isZeroEpsilon(angle.radians) do
            return
        let tr = Transform2.createRotation(angle.radians, 0, 0)
        .curState.transform.multiply(tr)
        .setTransform(.curState.transform)
    }

    // Appends a rotation around the specified path-space center.
    mtd rotateTransform(angle: Math.Angle, centerX, centerY: f32)
    {
        if isZeroEpsilon(angle.radians) do
            return
        let tr = Transform2.createRotation(angle.radians, centerX, centerY)
        .curState.transform.multiply(tr)
        .setTransform(.curState.transform)
    }

    // Set the paint rotation.
    // Will rotate around the current transformation position.
    mtd rotateTransformInPlace(angle: Math.Angle)
    {
        if isZeroEpsilon(angle.radians) do
            return
        let tr = Transform2.createRotation(angle.radians, .curState.transform.tx, .curState.transform.ty)
        .curState.transform.multiply(tr)
        .setTransform(.curState.transform)
    }

    // Appends independent horizontal and vertical scale factors.
    mtd scaleTransform(x, y: f32)
    {
        if isZeroEpsilon(x) and isZeroEpsilon(y) do
            return
        let tr = Transform2.createScale(x, y, 0, 0)
        .curState.transform.multiply(tr)
        .setTransform(.curState.transform)
    }

    // Appends a uniform scale factor.
    mtd scaleTransform(x: f32)
    {
        if isZeroEpsilon(x) do
            return
        let tr = Transform2.createScale(x, x, 0, 0)
        .curState.transform.multiply(tr)
        .setTransform(.curState.transform)
    }

    // Pushes a copy of the current transform.
    mtd pushTransform()
    {
        .stackTransform.add(.curState.transform)
    }

    // Pops and restores the most recently pushed transform.
    mtd popTransform()
    {
        .setTransform(.stackTransform.popBack())
    }

    // Restores the identity transform.
    mtd resetTransform()
    {
        .curState.transform.setIdentity()
        .setTransform(.curState.transform)
    }

    // Replaces the current path-to-surface transform.
    mtd setTransform(tr: Transform2)
    {
        .curState.transform = tr
        let cmd = .newCommand(.Transform, true)
        cmd.transform.tr = tr
    }

    // Returns the current path-to-surface transform.
    mtd const transform()->Transform2
    {
        var result: retval = .curState.transform
        return result
    }

    // Sets texture interpolation for subsequent textured and gradient draws.
    mtd setInterpolationMode(mode: InterpolationMode)
    {
        .curState.interpolationMode = mode
    }

    // Returns the current texture interpolation mode.
    #[Swag.Inline]
    mtd const interpolationMode() => .curState.interpolationMode

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

    // Pushes the intersection of a surface-space rectangle and the current clip.
    mtd pushClippingSurfaceRect(rect: Math.Rectangle)
    {
        .pushClippingRect(rect, true)
    }

    // Pushes the intersection of `rect` and the current clipping rectangle.
    //
    // By default `rect` is transformed to surface space using the current translation.
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

    // Returns the current clipping rectangle, or an unbounded rectangle when clipping is disabled.
    mtd const clippingRect()->Math.Rectangle
    {
        if .curState.clippingRectOn do
            return .curState.clippingRect
        return {0, 0, Swag.F32.Max, Swag.F32.Max}
    }

    // Reports whether rectangular clipping is currently enabled.
    mtd const hasClippingRect()->bool => .curState.clippingRectOn

    // Reports whether rectangular clipping currently rejects all drawing.
    mtd const isEmptyClippingRect()->bool
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

    // Sets the color blend operation used by subsequent drawing commands.
    //
    // The artistic modes blend non-premultiplied source and backdrop colors, then composite
    // the result with source-over coverage. [[Pixel.BlendingMode.Min]] and
    // [[Pixel.BlendingMode.Max]] remain raw component equations and therefore differ from
    // [[Pixel.BlendingMode.Darken]] and [[Pixel.BlendingMode.Lighten]] when alpha is partial.
    mtd setBlendingMode(mode: BlendingMode)
    {
        let cmd = .newCommand(.SetBlendingMode, true)
        cmd.blendingMode.mode  = mode
        .curState.blendingMode = mode
    }

    // Reports whether painting with `color` cannot change the destination.
    //
    // Both renderers drop a zero-alpha fragment under every blending mode except
    // [[Pixel.BlendingMode.Copy]], where the source replaces the destination whatever its
    // alpha: there a fully transparent fill is the erase operation, and must reach the
    // renderer instead of being culled at the recording boundary.
    internal mtd const isInvisible(color: Color)->bool
    {
        return color.a == 0 and .curState.blendingMode != .Copy
    }

    // Reports whether painting with `brush` cannot change the destination; see the color overload.
    internal mtd const isInvisible(brush: Brush)->bool
    {
        return !brush.hasVisibleAlpha() and .curState.blendingMode != .Copy
    }

    // Sets the writable framebuffer channels from a mask value.
    mtd setColorMask(cm: ColorMask)
    {
        let cmd = .newCommand(.ColorMask, true)
        cmd.colorMask       = cm
        .curState.colorMask = cm
    }

    // Sets the writable red, green, blue, and alpha channels.
    mtd setColorMask(r, g, b, a: bool)
    {
        let cmd = .newCommand(.ColorMask, true)
        cmd.colorMask.r     = r
        cmd.colorMask.g     = g
        cmd.colorMask.b     = b
        cmd.colorMask.a     = a
        .curState.colorMask = cmd.colorMask
    }

    // Enables writes to RGB and disables writes to alpha.
    mtd setColorMaskColor() => .setColorMask(true, true, true, false)

    // Enables writes to all color channels.
    mtd setColorMaskFull() => .setColorMask(true, true, true, true)

    // Enables writes only to alpha.
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
        .stackPaintAlpha.add(.curPaintAlpha)
        .curRT         = tgt
        .curPaintAlpha = paintAlpha
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

        .curPaintAlpha = .stackPaintAlpha.count ? .stackPaintAlpha.popBack() : false
    }

    // Release the render target
    mtd releaseRenderTarget(tgt: #null *RenderTarget)
    {
        if !tgt do
            return
        .transientTargets.add(tgt!)
    }

    // Set the current shader
    mtd setShader(shader: #null *ShaderBase = null)
    {
        let cmd = .newCommand(.SetShader, true)
        cmd.shader.shader = shader
    }

    // Selects the default antialiased or simple textured built-in program.
    //
    // Use [[Pixel.Painter.setBlurShader]] or [[Pixel.Painter.setResolveShader]]
    // for the parameterized programs.
    mtd setDefaultShader(shader: DefaultShaderId = .Default)
    {
        Debug.assert(shader == .Default or shader == .Simple)
        let cmd = .newCommand(.SetDefaultShader, true)
        cmd.defaultShader.id     = shader
        cmd.defaultShader.axis   = 0
        cmd.defaultShader.radius = 0
        cmd.defaultShader.factor = 0
    }

    // Selects one separable blur pass.
    //
    // `axis` is `0` for horizontal sampling and `1` for vertical sampling.
    // `radius` must be positive.
    mtd setBlurShader(axis: s32, radius: f32)
    {
        Debug.assert((axis == 0 or axis == 1) and radius > 0)
        let cmd = .newCommand(.SetDefaultShader, true)
        cmd.defaultShader.id     = .Blur
        cmd.defaultShader.axis   = axis
        cmd.defaultShader.radius = radius
        cmd.defaultShader.factor = 0
    }

    // Selects the supersampling resolve program.
    //
    // `factor` must be between `1` and `8`, inclusive.
    mtd setResolveShader(factor: s32)
    {
        Debug.assert(factor >= 1 and factor <= 8)
        let cmd = .newCommand(.SetDefaultShader, true)
        cmd.defaultShader.id     = .Resolve
        cmd.defaultShader.axis   = 0
        cmd.defaultShader.radius = 0
        cmd.defaultShader.factor = factor
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
