#global public
using Core

struct LayerBeginInfo
{
    width:          s32
    height:         s32
    renderScale:    s32 = 1
    paintAlpha:     bool = true
    clearColor:     Color = Color.fromArgb(Argb.Zero)
    antialiased:    bool = true
    blendingMode:   BlendingMode = .Alpha
}

struct LayerShadowInfo
{
    enabled:        bool
    margin:         s32 = 8
    radius:         f32 = 8
    offsetX:        f32
    offsetY:        f32
    color:          Color = Color.fromArgb(150, Argb.Black)
}

struct LayerDrawInfo
{
    dstRect:            Math.Rectangle
    color:              Color = Color.fromArgb(Argb.White)
    interpolationMode:  InterpolationMode = .Linear
    writeAlpha:         bool = true
    alphaBlendingMode:  BlendingMode = .Max
    releaseAfterDraw:   bool = true
    shadow:             LayerShadowInfo
}

struct Layer
{
    renderer:       #null *RenderOgl
    painter:        #null *Painter
    paintTarget:    #null *RenderTarget
    contentTarget:  #null *RenderTarget
    shadowTarget:   #null *RenderTarget
    width:          s32
    height:         s32
    renderScale:    s32 = 1
    active:         bool
    resolved:       bool
}

impl Layer
{
    mtd begin(renderer: #nonull *RenderOgl, painter: #nonull *Painter, info: LayerBeginInfo)
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

        let paintTarget = .paintTarget orelse cast(#nonull *RenderTarget) 1'u64
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

    mtd end()
    {
        Debug.assert(.active)
        .painter.unbindRenderTarget()
        .active = false
    }

    mtd resolve()
    {
        Debug.assert(!.active)
        if .resolved do
            return

        let renderer       = .renderer
        let painter        = .painter
        let paintTarget    = .paintTarget
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
        let renderer     = .renderer
        let painter      = .painter
        let content      = .contentTarget
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
            srcRect = Math.Rectangle{0, 0, .width + 2 * margin, .height + 2 * margin}
            texture = .shadowTarget.colorBuffer
        }
        else do
            .resolve()

        let painter = .painter
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

    mtd texture()->Texture
    {
        .resolve()
        return .contentTarget.colorBuffer
    }

    mtd sourceRect()->Math.Rectangle
    {
        return Math.Rectangle{0, 0, .width, .height}
    }

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

        .paintTarget    = null
        .contentTarget  = null
        .shadowTarget   = null
        .active         = false
        .resolved       = false
    }
}
