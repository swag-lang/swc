#global public

using Core, Core.Math

// Reports a backend failure with a message copied into the calling thread's error storage.
//
// The original backend type is named in the message; its thread-local error object is not exposed.
struct RenderThreadError
{
    public using base: Swag.BaseError     // Message owned by the calling thread's error allocator.
}

// Executes renderer operations on one dedicated thread, with at most one pending presentation.
//
// Call `start` before creating contexts, and access the borrowed backend only through this
// adapter until `close`. The backend and this nonmoving adapter must outlive their contexts.
// Drawing and resource operations are synchronous: painter commands, fonts, and image data
// are never retained after those calls. Only `end` returns before the backend has finished.
// Before recording another frame, poll `isReady` and coalesce invalidations while it is false.
// Other operations wait for the pending presentation; destruction therefore drains it too.
// The backend's `end` must not access its font cache, which the caller may use while presenting.
// Fallible backend calls report [[Pixel.RenderThreadError]], with an owned message transferred
// to the caller's error storage instead of exposing the backend's thread-local error object.
//
// ```swag
// var backend: RenderCpu
// var worker: RenderThread
// worker.start(&backend)
// defer worker.close()
// let renderer: IRenderer = &worker
// var context = try renderer.createContext(null, 32, 32)
// defer renderer.deleteContext(&context)
// renderer.init()
// renderer.begin(context)
// renderer.end()
// worker.wait()
// ```
#[Swag.Opaque, Swag.NoCopy]
struct RenderThread
{
    private
    {
        late backend:        IRenderer
        thread:              Threading.Thread
        requested:           Sync.Event
        completed:           Sync.Event
        callback:            (func||())?
        stopping:            bool
        nativeWindow:        bool
        late fonts:          *FontCache
        presentMicroseconds: u64
    }
}

impl RenderThread
{
    // Starts the worker before the borrowed `backend` has created any native contexts.
    //
    // The caller must serialize all adapter calls on its own thread. The backend must support
    // creation and use on a worker thread. Failure to start a native thread raises a panic.
    mtd start(backend: IRenderer)
    {
        Swag.assert(not .thread.isValid(), "render worker is already running")
        .backend      = backend
        .nativeWindow = backend.needsNativeWindow()
        .fonts        = backend.fontCache()
        .stopping     = false
        .requested.init()
        .completed.init(manual: true, initState: true)
        expect .thread.init(&worker, me)
        expect .thread.start()
    }

    // Reports whether the worker has been started and not yet closed.
    mtd const isStarted()->bool => .thread.isValid()

    // Waits until the pending presentation is complete; does nothing before start or after close.
    mtd wait()
    {
        if .isStarted() do
            .completed.wait()
    }

    // Returns and clears the duration, in microseconds, of the last completed presentation.
    //
    // Returns zero while busy. This measures the backend's `end`, not input-to-display latency.
    mtd takePresentMicroseconds()->u64
    {
        if not .isReady() do
            return 0
        let result = .presentMicroseconds
        .presentMicroseconds = 0
        return result
    }

    // Drains pending work and joins the worker. Delete all renderer contexts before calling it.
    //
    // Repeated calls do nothing. The adapter may subsequently be started with another backend.
    mtd close()
    {
        if not .isStarted() do
            return
        .wait()
        .stopping = true
        .requested.signal()
        .thread.wait()
        .requested.release()
        .completed.release()
    }

    // Drains and joins any worker still owned by this adapter.
    mtd opDrop() { .close() }
}

private impl RenderThread
{
    func worker(thread: Threading.Thread)
    {
        let owner = cast(*RenderThread) thread.userParam!
        while true
        {
            owner.requested.wait()
            if owner.stopping do
                return
            if owner.callback do
                owner.callback()
            else
            {
                var watch: Time.Stopwatch
                watch.start()
                owner.backend.end()
                owner.presentMicroseconds += watch.elapsedMicroseconds()
            }

            // Clear borrowed captures before publishing completion. The caller can immediately
            // reuse their storage or reset the event for the next request after this signal.
            owner.callback = null
            Memory.releaseTemporaryAllocations()
            owner.completed.signal()
        }
    }

    mtd execute(callback: func||())
    {
        Swag.assert(.isStarted(), "render worker has not been started")
        .wait()
        .completed.reset()
        .callback = callback
        .requested.signal()
        .wait()
    }

    mtd executeFallible(callback: func||() fail) fail
    {
        var message: String
        var failed = false
        .execute(func|&callback, &message, &failed|()
        {
            catch callback() as error
            if error != null
            {
                // Never transfer a borrowed message or error-allocator pointer between contexts.
                message = Format.toString("%: %", Swag.kindOf(error).name orelse "backend", Errors.message(error))
                failed  = true
            }
        })
        if failed do
            fail RenderThreadError{Errors.mkString(message.toString())}
    }
}

impl IRenderer for RenderThread
{
    mtd const impl needsNativeWindow()->bool => .nativeWindow
    mtd impl fontCache()->*FontCache         => .fonts

    mtd impl createContext(renderHandle: const *void?, width, height: s32, shared: *RenderContext? = null)->RenderContext fail
    {
        var result: retval
        try .executeFallible(func|me, renderHandle, width, height, shared, &result|() fail { result = try me.backend.createContext(renderHandle, width, height, shared) })
        return result
    }

    mtd impl deleteContext(context: *RenderContext) { .execute(func|me, context|() { me.backend.deleteContext(context) }) }
    mtd impl init() { .execute(func|me|() { me.backend.init() }) }
    mtd impl setCurrentContext(rc: RenderContext) { .execute(func|me, &rc|() { me.backend.setCurrentContext(rc) }) }
    mtd impl begin(rc: RenderContext) { .execute(func|me, &rc|() { me.backend.begin(rc) }) }

    mtd impl end()
    {
        Swag.assert(.isStarted(), "render worker has not been started")
        .wait()
        .completed.reset()

        // An empty callback is an owned present request: no stack capture survives this call.
        .requested.signal()
    }

    mtd impl clear() { .execute(func|me|() { me.backend.clear() }) }

    mtd impl targetSize()->{ width, height: s32 }
    {
        var result: retval
        .execute(func|me, &result|() { result = me.backend.targetSize() })
        return result
    }

    mtd impl setScissorRect(rect: Math.Rectangle) { .execute(func|me, &rect|() { me.backend.setScissorRect(rect) }) }
    mtd impl resetScissorRect() { .execute(func|me|() { me.backend.resetScissorRect() }) }
    mtd impl draw(painter: *Painter) { .execute(func|me, painter|() { me.backend.draw(painter) }) }
    mtd impl bindRenderTarget(target: *RenderTarget, vp: *Math.Rectangle? = null) { .execute(func|me, target, vp|() { me.backend.bindRenderTarget(target, vp) }) }

    mtd impl readRenderTarget(target: const *RenderTarget, x, y, width, height: s32)->Image
    {
        var result: retval
        .execute(func|me, target, x, y, width, height, &result|() { result = me.backend.readRenderTarget(target, x, y, width, height) })
        return result
    }

    mtd impl unbindRenderTargetToImage(x, y, width, height: s32)->Image
    {
        var result: retval
        .execute(func|me, x, y, width, height, &result|() { result = me.backend.unbindRenderTargetToImage(x, y, width, height) })
        return result
    }

    mtd impl unbindRenderTarget() { .execute(func|me|() { me.backend.unbindRenderTarget() }) }

    mtd impl createRenderTarget(width, height: s32)->RenderTarget
    {
        var result: retval
        .execute(func|me, width, height, &result|() { result = me.backend.createRenderTarget(width, height) })
        return result
    }

    mtd impl deleteRenderTarget(target: *RenderTarget) { .execute(func|me, target|() { me.backend.deleteRenderTarget(target) }) }

    mtd impl addImage(fullName: string)->Texture fail
    {
        var result: retval
        try .executeFallible(func|me, fullName, &result|() fail { result = try me.backend.addImage(fullName) })
        return result
    }

    mtd impl addImage(image: Image)->Texture
    {
        var result: retval
        .execute(func|me, &image, &result|() { result = me.backend.addImage(image) })
        return result
    }

    mtd impl addImage(view: const *YuvPlanarView)->Texture
    {
        var result: retval
        .execute(func|me, view, &result|() { result = me.backend.addImage(view) })
        return result
    }

    mtd impl updateTexture(texture: Texture, view: const *YuvPlanarView) { .execute(func|me, &texture, view|() { me.backend.updateTexture(texture, view) }) }
    mtd impl updateTexture(texture: Texture, pixels: const *u8) { .execute(func|me, &texture, pixels|() { me.backend.updateTexture(texture, pixels) }) }

    mtd impl readTexturePixels(texture: Texture, pixelFormat: PixelFormat)->Array'u8
    {
        var result: retval
        .execute(func|me, &texture, pixelFormat, &result|() { result = me.backend.readTexturePixels(texture, pixelFormat) })
        return result
    }

    mtd impl removeTexture(texture: *Texture) { .execute(func|me, texture|() { me.backend.removeTexture(texture) }) }
    mtd impl translateTransform(x, y: f32) { .execute(func|me, x, y|() { me.backend.translateTransform(x, y) }) }
    mtd impl rotateTransform(angle: Angle) { .execute(func|me, &angle|() { me.backend.rotateTransform(angle) }) }
    mtd impl rotateTransform(angle: Angle, centerX, centerY: f32) { .execute(func|me, &angle, centerX, centerY|() { me.backend.rotateTransform(angle, centerX, centerY) }) }
    mtd impl scaleTransform(x, y: f32) { .execute(func|me, x, y|() { me.backend.scaleTransform(x, y) }) }
    mtd impl scaleTransform(scale: f32) { .execute(func|me, scale|() { me.backend.scaleTransform(scale) }) }
    mtd impl resetTransform() { .execute(func|me|() { me.backend.resetTransform() }) }

    mtd impl acquireRenderTarget(width, height: s32)->*RenderTarget
    {
        var result: *RenderTarget?
        .execute(func|me, width, height, &result|() { result = me.backend.acquireRenderTarget(width, height) })
        return result!
    }

    mtd impl releaseRenderTarget(target: *RenderTarget?) { .execute(func|me, target|() { me.backend.releaseRenderTarget(target) }) }
}
