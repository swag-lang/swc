#global public

using Core, Core.Math

// Platform context operations. Each backend supplies the implementation used by RenderOgl.
#[Swag.Opaque, Swag.NoDoc]
struct NativeRenderOgl {}

// Describes a platform rendering context and drawable.
#[Swag.Opaque, Swag.NoDoc]
struct OglContext
{
    public
    {
        hDC:    #null const *void     // Platform device context.
        hRC:    #null const *void     // OpenGL rendering context.
        hWnd:   #null const *void     // Associated drawable, or `null` for an externally supplied context.
        width:  s32                   // Drawable width, in pixels.
        height: s32                   // Drawable height, in pixels.
        ownsDC: bool                  // Whether dropping the context must release `hDC`.
        ownsRC: bool                  // Whether dropping the context must delete `hRC`.
    }
}

impl IRenderer for RenderOgl
{
    mtd const impl needsNativeWindow()->bool => true

    mtd impl createContext(renderHandle: #null const *void, width, height: s32, shared: #null *RenderContext = null)->RenderContext fail
    {
        Debug.assert(renderHandle != null, "OpenGL renderer contexts need a platform drawable")
        Debug.assert(width > 0 and height > 0, "renderer context dimensions must be positive")

        if shared
        {
            let sharedOgl = oglContext(dref shared)
            Debug.assert(.nativeContext == sharedOgl.hRC, "shared context belongs to another renderer")
        }

        let sharedRC = .nativeContext
        var ogl      = try .native.createWindowContext(renderHandle, width, height, sharedRC)
        if !.nativeContext
        {
            .nativeContext = ogl.hRC
            ogl.ownsRC     = false
        }

        let storage = Memory.new'OglContext()
        dref storage  = ogl
        .contextCount += 1
        return {renderHandle, storage, width, height}
    }

    mtd impl deleteContext(context: *RenderContext)
    {
        if !context.data
        {
            dref context = {}
            return
        }

        let ogl = oglContext(dref context)
        Debug.assert(.contextCount > 0)
        .contextCount -= 1
        if !.contextCount
        {
            .native.setCurrentContext(dref ogl)
            .releaseFontTextures()
        }

        .native.dropContext(dref ogl)
        Memory.delete(ogl)

        if !.contextCount
        {
            .native.deleteContextHandle(.nativeContext)
            .nativeContext = null
        }

        dref context = {}
    }

    mtd impl fontCache()->*FontCache => &.fonts

    mtd impl init()
    {
        .initImpl()
    }

    mtd impl setCurrentContext(rc: RenderContext)
    {
        .setCurrentContextImpl(rc)
    }

    mtd impl begin(rc: RenderContext)
    {
        .beginImpl(rc)
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
        .bindRenderTargetImpl(target, vp)
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
