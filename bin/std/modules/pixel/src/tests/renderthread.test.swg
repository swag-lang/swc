#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Math

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

    mtd impl createContext(renderHandle: const *void?, width, height: s32, shared: *RenderContext? = null)->RenderContext fail
    {
        Swag.assert(renderHandle == null, "CPU renderer contexts do not use a platform drawable")
        Swag.assert(width > 0 and height > 0, "renderer context dimensions must be positive")
        discard shared
        .workerId = Env.Process.currentThreadId()
        return {renderHandle, null, width, height}
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

    mtd impl draw(painter: *Painter)
    {
        .cpu.drawImpl(painter)
    }

    mtd impl bindRenderTarget(target: *RenderTarget, vp: *Math.Rectangle? = null)
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

    mtd impl updateTexture(texture: Texture, view: const *YuvPlanarView)
    {
        .cpu.updatePlanarImpl(texture, view)
    }

    mtd impl addImage(fullName: string)->Texture fail => try .cpu.addImageImpl(fullName)

    mtd impl addImage(image: Image)->Texture => .cpu.addImageImpl(&image)

    mtd impl updateTexture(texture: Texture, pixels: const *u8)
    {
        .cpu.updateTextureImpl(texture, pixels)
    }

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

#test
{
    var backend: PresentProbe
    backend.entered.init()
    backend.allow.init()
    var worker: RenderThread
    Swag.assert(worker.isReady())
    worker.start(&backend)
    defer worker.close()
    let renderer: IRenderer = &worker
    {
        var context = expect renderer.createContext(null, 64, 64)
        defer renderer.deleteContext(&context)
        Swag.assert(backend.workerId != Env.Process.currentThreadId())
        renderer.init()
        renderer.begin(context)
        renderer.end()
        backend.entered.wait()

        // This line runs while the worker is deliberately blocked inside end().
        Swag.assert(not worker.isReady() and backend.presented == 0)
        backend.allow.signal()
        worker.wait()
        Swag.assert(worker.isReady() and backend.presented == 1)
    }

    worker.close()
    worker.close()
    Swag.assert(worker.isReady() and not worker.isStarted())
}

#[Swag.TestTag("gpu")]
#test
{
    var window = expect Env.createWindow({identifier: "render-worker-test", title: "Render worker test", width: 64, height: 64})
    var backend: RenderOgl
    var worker:  RenderThread
    worker.start(&backend)
    defer worker.close()
    let renderer: IRenderer = &worker
    var context = expect renderer.createContext(window.nativeRenderHandle(), 64, 64)
    defer renderer.deleteContext(&context)
    renderer.setCurrentContext(context)
    renderer.init()
    renderer.begin(context)
    var target = renderer.createRenderTarget(32, 32)
    defer renderer.deleteRenderTarget(&target)
    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.clear(Argb.Red)
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)
    let actual   = renderer.readRenderTarget(&target, 0, 0, 32, 32)
    var expected = Image.create(32, 32, .BGRA8)
    expected.fill(Color.fromArgb(Argb.Red))
    Testing.assertImagesNear(&expected, &actual, "renderthread.ogl")
    renderer.end()
    worker.wait()
    Swag.assert(worker.isReady())
}

#test
{
    var backend: RenderCpu
    var worker:  RenderThread
    worker.start(&backend)
    defer worker.close()
    let renderer: IRenderer = &worker
    for attempt in 3
    {
        discard attempt
        discard catch renderer.addImage("render-thread-missing-image.png") as error
        Swag.assert(error is RenderThreadError)
        let message = String.from(Errors.message(error))

        // Another worker operation may reset scratch storage; the caller's error stays valid.
        renderer.init()
        Swag.assert(Errors.message(error) == message.toString() and not message.isEmpty())
    }
}
