#global public

using Core, Core.Math

impl IRenderer for RenderCpu
{
    mtd const impl needsNativeWindow()->bool => false

    mtd impl createContext(renderHandle: const *void?, width, height: s32, _: *RenderContext? = null)->RenderContext fail
    {
        Swag.assert(renderHandle == null, "CPU renderer contexts do not use a platform drawable")
        Swag.assert(width > 0 and height > 0, "renderer context dimensions must be positive")
        return RenderContext{renderHandle, null, width, height}
    }

    mtd impl deleteContext(context: *RenderContext)
    {
        context[] = {}
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

    mtd impl targetSize()->{ width, height: s32 } => .targetSizeImpl()

    mtd impl setScissorRect(rect: Math.Rectangle)
    {
        .setScissorRectImpl(rect)
    }

    mtd impl resetScissorRect()
    {
        .resetScissorRectImpl()
    }

    mtd impl draw(painter: *Painter) fail
    {
        try .drawImpl(painter)
        painter.markSubmitted()
    }

    mtd impl bindRenderTarget(target: *RenderTarget, _: *Math.Rectangle? = null)
    {
        .bindRenderTargetImpl(target)
    }

    mtd impl readRenderTarget(target: const *RenderTarget, x, y, width, height: s32)->Image => .readRenderTargetImpl(target, x, y, width, height)

    mtd impl unbindRenderTargetToImage(x, y, width, height: s32)->Image => .unbindRenderTargetToImageImpl(x, y, width, height)

    mtd impl unbindRenderTarget()
    {
        .unbindRenderTargetImpl()
    }

    mtd impl createRenderTarget(width, height: s32)->RenderTarget => .createRenderTargetImpl(width, height)

    mtd impl deleteRenderTarget(target: *RenderTarget)
    {
        .deleteRenderTargetImpl(target)
    }

    mtd impl addImage(view: const *YuvPlanarView)->Texture => .addImageImpl(view)

    mtd impl updateTexture(texture: Texture, view: const *YuvPlanarView)->bool => .updatePlanarImpl(texture, view)

    mtd impl addImage(fullName: string)->Texture fail => try .addImageImpl(fullName)

    mtd impl addImage(image: Image)->Texture => .addImageImpl(&image)

    mtd impl updateTexture(texture: Texture, pixels: const *u8)->bool => .updateTextureImpl(texture, pixels)

    mtd impl readTexturePixels(texture: Texture, pixelFormat: PixelFormat)->Array'u8 => .readTexturePixelsImpl(texture, pixelFormat)

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

    mtd impl acquireRenderTarget(width, height: s32)->*RenderTarget => .acquireRenderTargetImpl(width, height)

    mtd impl releaseRenderTarget(target: *RenderTarget?)
    {
        .releaseRenderTargetImpl(target)
    }
}


impl RenderCpu
{
    // Registers a read-only image for CPU sampling without a pixel copy.
    //
    // Keep the image and its pixels stable until the texture is removed. The
    // renderer never edits or frees a borrowed image and refuses texture
    // updates to it. Premultiplied inputs use an owned conversion to straight alpha.
    mtd addBorrowedImage(image: const *Image)->Texture
    {
        if image.alphaMode == .Premultiplied do
            return .addImageImpl(image)
        if not image.isValid() or not .ensureGeneration() do
            return {}

        var result: #returntype
        result.attach(cast(TextureHandle, .nextHandle), image.pixelFormat, image.width, image.height, .generation)
        .nextHandle += 1
        var storage = CpuTexture{handle: result.handle, borrowed: image}
        .textures.add(#move storage)
        return result
    }
}
