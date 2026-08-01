#global public

using Core, Core.Math

impl IRenderer for RenderCpu
{
    mtd const impl needsNativeWindow()->bool => false

    mtd impl createContext(nativeWindow: #null const *void, width, height: s32, shared: #null *RenderContext = null)->RenderContext fail
    {
        Debug.assert(nativeWindow == null, "CPU renderer contexts do not use a native window")
        Debug.assert(width > 0 and height > 0, "renderer context dimensions must be positive")
        discard shared
        return {nativeWindow, null, width, height}
    }

    mtd impl deleteContext(context: *RenderContext)
    {
        dref context = {}
    }

    mtd impl fontCache()->*FontCache => &.fonts

    mtd impl init() {}

    mtd impl setCurrentContext(rc: RenderContext)
    {
        RenderCpu.begin(me, rc.width, rc.height)
    }

    mtd impl begin(rc: RenderContext)
    {
        RenderCpu.begin(me, rc.width, rc.height)
    }

    mtd impl end()
    {
        .endImpl()
    }

    mtd impl clear()
    {
        .clearImpl()
    }

    mtd impl targetSize()->{ width, height: s32 }
    {
        return .targetSizeImpl()
    }

    mtd impl setScissorRect(rect: Math.Rectangle)
    {
        .setScissorRectImpl(rect)
    }

    mtd impl resetScissorRect()
    {
        .resetScissorRectImpl()
    }

    mtd impl draw(painter: *Painter)
    {
        .drawImpl(painter)
    }

    mtd impl bindRenderTarget(target: *RenderTarget, vp: #null *Math.Rectangle = null)
    {
        .bindRenderTargetImpl(target)
    }

    mtd impl readRenderTarget(target: const *RenderTarget, x, y, width, height: s32)->Image
    {
        return .readRenderTargetImpl(target, x, y, width, height)
    }

    mtd impl unbindRenderTargetToImage(x, y, width, height: s32)->Image
    {
        return .unbindRenderTargetToImageImpl(x, y, width, height)
    }

    mtd impl unbindRenderTarget()
    {
        .unbindRenderTargetImpl()
    }

    mtd impl createRenderTarget(width, height: s32)->RenderTarget
    {
        return .createRenderTargetImpl(width, height)
    }

    mtd impl deleteRenderTarget(target: *RenderTarget)
    {
        .deleteRenderTargetImpl(target)
    }

    mtd impl addImage(fullName: string)->Texture fail
    {
        return try .addImageImpl(fullName)
    }

    mtd impl addImage(image: Image)->Texture
    {
        return .addImageImpl(&image)
    }

    mtd impl updateTexture(texture: Texture, pixels: const *u8)
    {
        .updateTextureImpl(texture, pixels)
    }

    mtd impl readTexturePixels(texture: Texture, pixelFormat: PixelFormat)->Array'u8
    {
        return .readTexturePixelsImpl(texture, pixelFormat)
    }

    mtd impl removeTexture(texture: *Texture)
    {
        .removeTextureImpl(texture)
    }

    mtd impl translateTransform(x, y: f32)
    {
        .translateTransformImpl(x, y)
    }

    mtd impl rotateTransform(angle: Math.Angle)
    {
        .rotateTransformImpl(angle)
    }

    mtd impl rotateTransform(angle: Math.Angle, centerX, centerY: f32)
    {
        .rotateTransformImpl(angle, centerX, centerY)
    }

    mtd impl scaleTransform(x, y: f32)
    {
        .scaleTransformImpl(x, y)
    }

    mtd impl scaleTransform(scale: f32)
    {
        .scaleTransformImpl(scale)
    }

    mtd impl resetTransform()
    {
        .resetTransformImpl()
    }

    mtd impl acquireRenderTarget(width, height: s32)->*RenderTarget
    {
        return .acquireRenderTargetImpl(width, height)
    }

    mtd impl releaseRenderTarget(target: #null *RenderTarget)
    {
        .releaseRenderTargetImpl(target)
    }
}
