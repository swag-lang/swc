#global public

using Core

// Configures an off-screen layer recording scope.
struct LayerBeginInfo
{
    width:        s32                                          // Logical layer width, in pixels.
    height:       s32                                          // Logical layer height, in pixels.
    renderScale:  s32          = 1                             // Supersampling factor; values below `1` become `1`.
    paintAlpha:   bool         = true                          // Preserve alpha through a separate resolve when needed.
    clearColor:   Color        = Color.fromArgb(Argb.Zero)     // Initial straight-alpha color.
    antialiased:  bool         = true                          // Enable antialiasing while recording.
    blendingMode: BlendingMode = .Alpha                        // Initial blend mode.
}

// Configures the blurred shadow generated for an off-screen layer.
struct LayerShadowInfo
{
    enabled: bool                                        // Generate and draw a shadow when true.
    margin:  s32   = 8                                   // Extra pixels reserved around the layer for blur.
    radius:  f32   = 8                                   // Separable blur radius, in pixels.
    offsetX: f32                                         // Horizontal shadow offset, in pixels.
    offsetY: f32                                         // Vertical shadow offset, in pixels.
    color:   Color = Color.fromArgb(150, Argb.Black)     // Shadow tint and opacity.
}

// Configures compositing an off-screen layer into the current painter target.
struct LayerDrawInfo
{
    dstRect:           Math.Rectangle                                     // Destination rectangle in painter path space.
    color:             Color             = Color.fromArgb(Argb.White)     // Multiplicative tint.
    interpolationMode: InterpolationMode = .Linear                        // Sampling used while scaling.
    writeAlpha:        bool              = true                           // Composite the layer alpha channel separately.
    alphaBlendingMode: BlendingMode      = .Max                           // Blend operation for the alpha-only pass.
    releaseAfterDraw:  bool              = true                           // Queue layer targets for release after drawing.
    shadow:            LayerShadowInfo                                    // Optional blurred shadow.
}

// Records painter commands into an off-screen render target and composites the result.
//
// A layer owns renderer targets until [[Layer.release]] or a draw configured with
// `releaseAfterDraw`. Calls must follow `begin`, drawing, `end`, then optional
// `resolve`/`buildShadow`/`draw`.
struct Layer
{
    renderer:      #null *RenderOgl        // Borrowed renderer used to allocate targets.
    painter:       #null *Painter          // Borrowed painter receiving layer commands.
    paintTarget:   #null *RenderTarget     // Supersampled recording target, if allocated.
    contentTarget: #null *RenderTarget     // Resolved content target, if allocated.
    shadowTarget:  #null *RenderTarget     // Shadow-composited target, if allocated.
    width:         s32                     // Logical content width, in pixels.
    height:        s32                     // Logical content height, in pixels.
    renderScale:   s32 = 1                 // Active supersampling factor.
    active:        bool                    // Whether recording is between `begin` and `end`.
    resolved:      bool                    // Whether content is at logical resolution.
}

impl Layer
{
    // Begins recording into a newly acquired off-screen target.
    //
    // `renderer` and `painter` are borrowed until release. Dimensions must be positive.
    mtd begin(renderer: *RenderOgl, painter: *Painter, info: LayerBeginInfo)
    {
        Debug.assert(!.active)
        Debug.assert(renderer != null)
        Debug.assert(painter != null)
        Debug.assert(info.width > 0 and info.height > 0)

        .release()
        .renderer      = renderer
        .painter       = painter
        .width         = info.width
        .height        = info.height
        .renderScale   = Math.max(info.renderScale, 1)
        .paintTarget   = renderer.getRenderTarget(.width * .renderScale, .height * .renderScale)
        .contentTarget = .paintTarget
        .active        = true
        .resolved      = .renderScale == 1

        let paintTarget = .paintTarget
        with painter
        {
            .bindRenderTarget(paintTarget, info.paintAlpha)
            .setAntialiased(info.antialiased)
            .setColorMaskFull()
            .clear(info.clearColor)
            .setColorMaskColor()
            .setBlendingMode(info.blendingMode)
        }
    }

    // Ends the active off-screen recording scope.
    mtd end()
    {
        Debug.assert(.active)
        let painter = notnull .painter
        painter.unbindRenderTarget()
        .active = false
    }

    // Downsamples supersampled content to logical layer dimensions.
    //
    // Calling this more than once is harmless.
    mtd resolve()
    {
        Debug.assert(!.active)
        if .resolved do
            return

        let renderer       = notnull .renderer
        let painter        = notnull .painter
        let paintTarget    = notnull .paintTarget
        let renderScale    = .renderScale
        let resolvedTarget = renderer.getRenderTarget(.width, .height)
        let srcRect        = Math.Rectangle{0, 0, .width * renderScale, .height * renderScale}
        let dstRect        = Math.Rectangle{0, 0, .width, .height}

        with painter
        {
            .bindRenderTarget(resolvedTarget)
            .setShader(&renderer.shaderResolve)
            .setShaderParam(renderer.shaderResolve.factor, renderScale)
            .setColorMaskFull()
            .setBlendingMode(.Copy)
            .clear(Argb.Zero)
            .drawTexture(dstRect, srcRect, paintTarget.colorBuffer)
            .setShader()
            .unbindRenderTarget()
            .releaseRenderTarget(paintTarget)
        }

        .paintTarget   = null
        .contentTarget = resolvedTarget
        .resolved      = true
    }

    // Builds the optional blurred shadow and composites the layer content into it.
    //
    // Recording must have ended. A disabled shadow leaves the layer unchanged.
    mtd buildShadow(info: LayerShadowInfo)
    {
        Debug.assert(!.active)
        if !info.enabled do
            return

        .resolve()
        if .shadowTarget do
            return

        let margin       = Math.max(info.margin, 0)
        let shadowWidth  = .width + 2 * margin
        let shadowHeight = .height + 2 * margin
        let sourceRect   = Math.Rectangle{0, 0, .width, .height}
        let targetRect   = Math.Rectangle{margin, margin, .width, .height}
        let fullRect     = Math.Rectangle{0, 0, shadowWidth, shadowHeight}
        let renderer     = notnull .renderer
        let painter      = notnull .painter
        let content      = notnull .contentTarget
        let target1      = renderer.getRenderTarget(shadowWidth, shadowHeight)
        let target2      = renderer.getRenderTarget(shadowWidth, shadowHeight)

        with painter
        {
            .bindRenderTarget(target1)
            .setShader(&renderer.shaderSimple)
            .setBlendingMode(.Copy)
            .setColorMaskFull()
            .clear(Argb.Zero)
            .drawTexture(targetRect, sourceRect, content.colorBuffer)
            .unbindRenderTarget()
        }

        with painter
        {
            .bindRenderTarget(target2)
            .setShader(&renderer.shaderBlur)
            .setShaderParam(renderer.shaderBlur.axis, 0's32)
            .setShaderParam(renderer.shaderBlur.radius, info.radius)
            .setBlendingMode(.Copy)
            .setColorMaskFull()
            .clear(Argb.Zero)
            .drawTexture(fullRect, fullRect, target1.colorBuffer)
            .setShader()
            .unbindRenderTarget()
        }

        var imageRect = targetRect
        imageRect.offset(-info.offsetX, -info.offsetY)

        with painter
        {
            .bindRenderTarget(target1)
            .setShader(&renderer.shaderBlur)
            .setShaderParam(renderer.shaderBlur.axis, 1's32)
            .setShaderParam(renderer.shaderBlur.radius, info.radius)
            .setBlendingMode(.Copy)
            .setColorMaskFull()
            .drawTexture(fullRect, fullRect, target2.colorBuffer, info.color)
            .setShader(&renderer.shaderSimple)
            .setBlendingMode(.Alpha)
            .drawTexture(imageRect, sourceRect, content.colorBuffer)
            .setShader()
            .unbindRenderTarget()
            .releaseRenderTarget(target2)
        }

        .shadowTarget = target1
    }

    // Composites the resolved layer into the painter.
    //
    // The layer is released afterward when `info.releaseAfterDraw` is true.
    mtd draw(info: LayerDrawInfo)
    {
        Debug.assert(!.active)

        var dstRect = info.dstRect
        var srcRect = Math.Rectangle{0, 0, .width, .height}
        var texture = .texture()

        if info.shadow.enabled
        {
            .buildShadow(info.shadow)
            let margin = Math.max(info.shadow.margin, 0)
            dstRect.offset(info.shadow.offsetX - cast(f32) margin, info.shadow.offsetY - cast(f32) margin)
            dstRect.width, dstRect.height += cast(f32) (2 * margin)
            srcRect                       = Math.Rectangle{0, 0, .width + 2 * margin, .height + 2 * margin}
            texture                       = (notnull .shadowTarget).colorBuffer
        }
        else do
            .resolve()

        let painter = notnull .painter
        with painter
        {
            .pushState()
            .setShader()
            .setAntialiased(false)
            .setInterpolationMode(info.interpolationMode)
            .setColorMaskColor()
            .setBlendingMode(.Alpha)
            .drawTexture(dstRect, srcRect, texture, info.color)

            if info.writeAlpha
            {
                .setBlendingMode(info.alphaBlendingMode)
                .setColorMaskAlpha()
                .drawTexture(dstRect, srcRect, texture, info.color)
            }

            .popState()
        }

        if info.releaseAfterDraw do
            .release()
    }

    // Returns the resolved layer texture.
    //
    // Supersampled content is resolved on demand. The texture remains renderer-owned
    // and valid until the layer is released.
    mtd texture()->Texture
    {
        .resolve()
        let contentTarget = notnull .contentTarget
        return contentTarget.colorBuffer
    }

    // Returns the logical layer rectangle with origin `(0, 0)`.
    mtd sourceRect()->Math.Rectangle
    {
        return Math.Rectangle{0, 0, .width, .height}
    }

    // Queues every owned render target for release and resets the layer.
    //
    // Calling `release` on an empty layer is harmless.
    mtd release()
    {
        if .painter
        {
            let paintTarget   = .paintTarget
            let contentTarget = .contentTarget
            .painter.releaseRenderTarget(.paintTarget)
            if contentTarget != paintTarget do
                .painter.releaseRenderTarget(.contentTarget)
            if .shadowTarget do
                .painter.releaseRenderTarget(.shadowTarget)
        }

        .paintTarget   = null
        .contentTarget = null
        .shadowTarget  = null
        .active        = false
        .resolved      = false
    }
}
