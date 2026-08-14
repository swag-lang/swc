#global public

using Core

// Configures an off-screen layer recording scope.
struct LayerBeginInfo
{
    public
    {
        width:        s32                                          // Logical layer width, in pixels.
        height:       s32                                          // Logical layer height, in pixels.
        renderScale:  s32          = 1                             // Supersampling factor, clamped to the range `1` through `8`.
        paintAlpha:   bool         = true                          // Preserve alpha through a separate resolve when needed.
        clearColor:   Color        = Color.fromArgb(Argb.Zero)     // Initial straight-alpha color.
        antialiased:  bool         = true                          // Enable antialiasing while recording.
        blendingMode: BlendingMode = .Alpha                        // Initial blend mode.
    }
}

// Configures the blurred shadow generated for an off-screen layer.
struct LayerShadowInfo
{
    public
    {
        enabled: bool                                        // Generate and draw a shadow when true.
        margin:  s32   = 8                                   // Extra pixels reserved around the layer for blur.
        radius:  f32   = 8                                   // Separable blur radius, in pixels.
        offsetX: f32                                         // Horizontal shadow offset, in pixels.
        offsetY: f32                                         // Vertical shadow offset, in pixels.
        color:   Color = Color.fromArgb(150, Argb.Black)     // Shadow tint and opacity.
    }
}

// Configures compositing an off-screen layer into the current painter target.
struct LayerDrawInfo
{
    public
    {
        dstRect:           Math.Rectangle                                     // Destination rectangle in painter path space.
        color:             Color             = Color.fromArgb(Argb.White)     // Multiplicative tint.
        interpolationMode: InterpolationMode = .Linear                        // Sampling used while scaling.
        writeAlpha:        bool              = true                           // Composite the layer alpha channel separately.
        alphaBlendingMode: BlendingMode      = .Max                           // Blend operation for the alpha-only pass.
        releaseAfterDraw:  bool              = true                           // Queue layer targets for release after drawing.
        shadow:            LayerShadowInfo                                    // Optional blurred shadow.
    }
}

// Records painter commands into an off-screen render target and composites the result.
//
// A layer owns renderer targets until [[Layer.release]] or a draw configured with
// `releaseAfterDraw`. Calls must follow `begin`, drawing, `end`, then optional
// `resolve`/`buildShadow`/`draw`.
struct Layer
{
    public
    {
        renderer:      #null IRenderer         // Borrowed renderer used to allocate targets.
        painter:       #null *Painter          // Borrowed painter receiving layer commands.
        paintTarget:   #null *RenderTarget     // Supersampled recording target, if allocated.
        contentTarget: #null *RenderTarget     // Resolved content target, if allocated.
        shadowTarget:  #null *RenderTarget     // Shadow-composited target, if allocated.
        width:         s32                     // Logical content width, in pixels.
        height:        s32                     // Logical content height, in pixels.
        renderScale:   s32 = 1                 // Active supersampling factor.
        deviceScale:   f32 = 1                 // Painter content scale captured at `begin`.
        active:        bool                    // Whether recording is between `begin` and `end`.
        resolved:      bool                    // Whether content is at logical resolution.
    }
}

impl Layer
{
    // Begins recording into a newly acquired off-screen target.
    //
    // The painter and its selected renderer are borrowed until release. Dimensions must be positive.
    mtd begin(painter: *Painter, info: LayerBeginInfo)
    {
        Debug.assert(!.active)
        Debug.assert(info.width > 0 and info.height > 0)

        .release()
        let renderer = painter.renderer()
        .renderer    = renderer
        .painter     = painter
        .width       = info.width
        .height      = info.height
        .renderScale = Math.clamp(info.renderScale, 1, 8)

        // Dimensions are logical: the renderer maps recorded drawing to device
        // pixels, so the targets hold width x deviceScale texels per logical unit.
        .deviceScale   = painter.contentScale()
        .paintTarget   = renderer.acquireRenderTarget(.deviceWidth() * .renderScale, .deviceHeight() * .renderScale)
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
        let painter = .painter!
        painter.unbindRenderTarget()
        .active = false
    }

    // Returns the allocation width of the resolved layer content, in whole device texels.
    private mtd const deviceWidth()->s32 => cast(s32) Math.ceil(.width * .deviceScale)

    // Returns the allocation height of the resolved layer content, in whole device texels.
    private mtd const deviceHeight()->s32 => cast(s32) Math.ceil(.height * .deviceScale)

    // Content extents in device texels, kept exact: rendering fills width x deviceScale
    // texels, so a ceil'ed source rectangle would minify the content into its logical
    // footprint and blend the cleared padding texels into the last column and row.
    private mtd const contentDeviceWidth()->f32 => .width * .deviceScale

    private mtd const contentDeviceHeight()->f32 => .height * .deviceScale

    // Downsamples supersampled content to the layer's device resolution.
    //
    // Calling this more than once is harmless.
    mtd resolve()
    {
        Debug.assert(!.active)
        if .resolved do
            return

        let renderer       = .renderer!
        let painter        = .painter!
        let paintTarget    = .paintTarget!
        let renderScale    = .renderScale
        let resolvedTarget = renderer.acquireRenderTarget(.deviceWidth(), .deviceHeight())

        // Source rectangles address target texels, destination rectangles are
        // logical painter units mapped to device pixels at draw time.
        let srcRect = Math.Rectangle{0, 0, .contentDeviceWidth() * renderScale, .contentDeviceHeight() * renderScale}
        let dstRect = Math.Rectangle{0, 0, .width, .height}

        with painter
        {
            .bindRenderTarget(resolvedTarget)
            .setResolveShader(renderScale)
            .setColorMaskFull()
            .setBlendingMode(.Copy)
            .clear(Argb.Zero)
            .drawTexture(dstRect, srcRect, paintTarget.colorBuffer)
            .setDefaultShader()
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

        // Destination rectangles are logical, source rectangles address the texels
        // of the already device-resolution targets.
        let margin       = Math.max(info.margin, 0)
        let shadowWidth  = .width + 2 * margin
        let shadowHeight = .height + 2 * margin
        let devShadowW   = cast(s32) Math.ceil(shadowWidth * .deviceScale)
        let devShadowH   = cast(s32) Math.ceil(shadowHeight * .deviceScale)
        let sourceRect   = Math.Rectangle{0, 0, .contentDeviceWidth(), .contentDeviceHeight()}
        let targetRect   = Math.Rectangle{margin, margin, .width, .height}
        let fullDstRect  = Math.Rectangle{0, 0, shadowWidth, shadowHeight}
        let fullSrcRect  = Math.Rectangle{0, 0, shadowWidth * .deviceScale, shadowHeight * .deviceScale}
        let renderer     = .renderer!
        let painter      = .painter!
        let content      = .contentTarget!
        let target1      = renderer.acquireRenderTarget(devShadowW, devShadowH)
        let target2      = renderer.acquireRenderTarget(devShadowW, devShadowH)

        with painter
        {
            .bindRenderTarget(target1)
            .setDefaultShader(.Simple)
            .setBlendingMode(.Copy)
            .setColorMaskFull()
            .clear(Argb.Zero)
            .drawTexture(targetRect, sourceRect, content.colorBuffer)
            .unbindRenderTarget()
        }

        with painter
        {
            .bindRenderTarget(target2)
            .setBlurShader(0, info.radius)
            .setBlendingMode(.Copy)
            .setColorMaskFull()
            .clear(Argb.Zero)
            .drawTexture(fullDstRect, fullSrcRect, target1.colorBuffer)
            .setDefaultShader()
            .unbindRenderTarget()
        }

        var imageRect = targetRect
        imageRect.offset(-info.offsetX, -info.offsetY)

        with painter
        {
            .bindRenderTarget(target1)
            .setBlurShader(1, info.radius)
            .setBlendingMode(.Copy)
            .setColorMaskFull()
            .drawTexture(fullDstRect, fullSrcRect, target2.colorBuffer, info.color)
            .setDefaultShader(.Simple)
            .setBlendingMode(.Alpha)
            .drawTexture(imageRect, sourceRect, content.colorBuffer)
            .setDefaultShader()
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

        // The destination is logical; the source addresses device texels.
        var dstRect = info.dstRect
        var srcRect = Math.Rectangle{0, 0, .contentDeviceWidth(), .contentDeviceHeight()}
        var texture = .texture()

        if info.shadow.enabled
        {
            .buildShadow(info.shadow)
            let margin = Math.max(info.shadow.margin, 0)
            dstRect.offset(info.shadow.offsetX - cast(f32) margin, info.shadow.offsetY - cast(f32) margin)
            dstRect.width, dstRect.height += cast(f32) (2 * margin)
            srcRect = Math.Rectangle{0, 0, (.width + 2 * margin) * .deviceScale, (.height + 2 * margin) * .deviceScale}
            texture = .shadowTarget!.colorBuffer
        }
        else do
            .resolve()

        let painter = .painter!
        with painter
        {
            .pushState()
            .setDefaultShader()
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
        let contentTarget = .contentTarget!
        return contentTarget.colorBuffer
    }

    // Returns the logical layer rectangle with origin `(0, 0)`.
    //
    // Use it as a destination rectangle. When sampling the layer texture directly,
    // remember its texels are at device resolution: one logical unit covers the
    // painter content scale in texels.
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

    // Returns every owned render target straight to the renderer pool and resets the layer.
    //
    // [[Pixel.Layer.release]] records the release into the painter command stream, which is
    // right in the middle of a frame but wrong for a layer retained across frames:
    // [[Pixel.Painter.begin]] discards pending commands, so a release recorded between two
    // frames would be lost with them. Call this form instead when releasing a retained layer,
    // once no recorded frame still draws from its targets.
    mtd releaseImmediate()
    {
        if .renderer
        {
            let paintTarget   = .paintTarget
            let contentTarget = .contentTarget
            .renderer.releaseRenderTarget(.paintTarget)
            if contentTarget != paintTarget do
                .renderer.releaseRenderTarget(.contentTarget)
            if .shadowTarget do
                .renderer.releaseRenderTarget(.shadowTarget)
        }

        .paintTarget   = null
        .contentTarget = null
        .shadowTarget  = null
        .active        = false
        .resolved      = false
    }
}
