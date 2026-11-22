#global if #command == Swag.CompilerCommand.Test
#global internal

using Swag, Core, Core.Math

// The gate makes presentation observably pending without depending on a driver or a sleep.
struct PresentProbe
{
    cpu:            RenderCpu
    entered, allow: Sync.Event
    workerId:       u64
    presented:      u32
}

impl IRenderer for PresentProbe
{
    mtd const impl needsNativeWindow()->bool => false

    mtd impl createContext(renderHandle: const *void?, width, height: s32, _: *RenderContext? = null)->RenderContext fail
    {
        Swag.require(renderHandle == null, "CPU renderer contexts do not use a platform drawable")
        Swag.require(width > 0 and height > 0, "renderer context dimensions must be positive")
        .workerId = Env.Process.currentThreadId()
        return RenderContext{renderHandle, null, width, height}
    }

    mtd impl deleteContext(context: *RenderContext)
    {
        context[] = {}
    }

    mtd impl fontCache()->*FontCache => &.cpu.fonts

    mtd impl init() {}

    mtd impl setCurrentContext(rc: RenderContext)
    {
        RenderCpu.begin(&.cpu, rc.width, rc.height)
    }

    mtd impl begin(rc: RenderContext)
    {
        RenderCpu.begin(&.cpu, rc.width, rc.height)
    }

    mtd impl end()
    {
        .entered.signal()
        .allow.wait()
        .presented += 1
    }

    mtd impl clear()
    {
        .cpu.clearImpl()
    }

    mtd impl targetSize()->{ width, height: s32 } => .cpu.targetSizeImpl()

    mtd impl setScissorRect(rect: Math.Rectangle)
    {
        .cpu.setScissorRectImpl(rect)
    }

    mtd impl resetScissorRect()
    {
        .cpu.resetScissorRectImpl()
    }

    mtd impl draw(painter: *Painter) fail
    {
        try .cpu.drawImpl(painter)
        painter.markSubmitted()
    }

    mtd impl bindRenderTarget(target: *RenderTarget, _: *Math.Rectangle? = null)
    {
        .cpu.bindRenderTargetImpl(target)
    }

    mtd impl readRenderTarget(target: const *RenderTarget, x, y, width, height: s32)->Image => .cpu.readRenderTargetImpl(target, x, y, width, height)

    mtd impl unbindRenderTargetToImage(x, y, width, height: s32)->Image => .cpu.unbindRenderTargetToImageImpl(x, y, width, height)

    mtd impl unbindRenderTarget()
    {
        .cpu.unbindRenderTargetImpl()
    }

    mtd impl createRenderTarget(width, height: s32)->RenderTarget => .cpu.createRenderTargetImpl(width, height)

    mtd impl deleteRenderTarget(target: *RenderTarget)
    {
        .cpu.deleteRenderTargetImpl(target)
    }

    mtd impl addImage(view: const *YuvPlanarView)->Texture => .cpu.addImageImpl(view)

    mtd impl updateTexture(texture: Texture, view: const *YuvPlanarView)->bool => .cpu.updatePlanarImpl(texture, view)

    mtd impl addImage(fullName: string)->Texture fail => try .cpu.addImageImpl(fullName)

    mtd impl addImage(image: Image)->Texture => .cpu.addImageImpl(&image)

    mtd impl updateTexture(texture: Texture, pixels: const *u8)->bool => .cpu.updateTextureImpl(texture, pixels)

    mtd impl readTexturePixels(texture: Texture, pixelFormat: PixelFormat)->Array'u8 => .cpu.readTexturePixelsImpl(texture, pixelFormat)

    mtd impl removeTexture(texture: *Texture)
    {
        .cpu.removeTextureImpl(texture)
    }

    mtd impl translateTransform(x, y: f32)
    {
        .cpu.translateTransformImpl(x, y)
    }

    mtd impl rotateTransform(angle: Math.Angle)
    {
        .cpu.rotateTransformImpl(angle)
    }

    mtd impl rotateTransform(angle: Math.Angle, centerX, centerY: f32)
    {
        .cpu.rotateTransformImpl(angle, centerX, centerY)
    }

    mtd impl scaleTransform(x, y: f32)
    {
        .cpu.scaleTransformImpl(x, y)
    }

    mtd impl scaleTransform(scale: f32)
    {
        .cpu.scaleTransformImpl(scale)
    }

    mtd impl resetTransform()
    {
        .cpu.resetTransformImpl()
    }

    mtd impl acquireRenderTarget(width, height: s32)->*RenderTarget => .cpu.acquireRenderTargetImpl(width, height)

    mtd impl releaseRenderTarget(target: *RenderTarget?)
    {
        .cpu.releaseRenderTargetImpl(target)
    }
}
