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

    mtd impl createContext(renderHandle: const *void?, width, height: s32, _: *RenderContext? = null)->RenderContext fail
    {
        Swag.assert(renderHandle == null, "CPU renderer contexts do not use a platform drawable")
        Swag.assert(width > 0 and height > 0, "renderer context dimensions must be positive")
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
        for iteration in 2
        {
            renderer.begin(context)
            renderer.end()
            backend.entered.wait()

            // Neither the previous ticket nor its native signal can complete this request.
            Swag.assert(not worker.isReady() and backend.presented == iteration)
            backend.allow.signal()
            worker.wait()
            Swag.assert(worker.isReady() and backend.presented == iteration + 1)
        }
    }

    worker.close()
    worker.close()
    Swag.assert(worker.isReady() and not worker.isStarted())
}

#[Swag.TestTag("integration.renderer.opengl")]
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
    for 3
    {
        discard catch renderer.addImage("render-thread-missing-image.png") as error
        Swag.assert(error is RenderThreadError)
        let message = String.from(Errors.message(error))

        // Another worker operation may reset scratch storage; the caller's error stays valid.
        renderer.init()
        Swag.assert(Errors.message(error) == message.toString() and not message.isEmpty())
    }
}

// Fatal failures run in the already-prepared native test artifact. The child inherits
// the tool's working directory and deployed resources, and selects this one test by tag.
func waitFailureChild()->bool
{
    for arg in Swag.args() where arg == "render-failure-child" do
        return true
    return false
}

func verifyWaitFailureProcess(tag: string)
{
    let executable = expect Env.Process.currentExecutablePath()
    let arguments  = Format.toString("swag.test swag.test-tag=% render-failure-child", tag)
    var child      = expect Env.startProcess(Env.StartInfo{fileName: executable.toString(), arguments: arguments.toString(), standardOutput: .Pipe, standardError: .Pipe, consoleWindow: false})
    let finished   = expect child.tryWaitForExit(10's)
    if not finished
    {
        expect child.kill()
        discard expect child.waitForExit()
    }

    Swag.assert(finished, "the failed render request must terminate without hanging")
    Swag.assert(child.exitCode() != 0)
    let output = String.from(child.standardOutput())
    Swag.assert(output.contains("render failure observed after retirement"))
    Swag.assert(not output.contains("render failure resumed"))
}

var waitFailureBorrowLive: Swag.AtomicValue'u32
var waitFailureWorker:     *RenderThread?

func observeWaitFailurePanic(_: string?, _: Swag.SourceCodeLocation)
{
    let worker = waitFailureWorker
    if waitFailureBorrowLive.load() == 0 and worker != null and worker.isReady() do
        Swag.print("render failure observed after retirement\n")
}

struct WaitFailureProbe
{
    backend:        RenderCpu
    worker:         RenderThread
    entered, allow: Sync.Event
}

internal impl RenderThread
{
    mtd checkCompletionSignalFailure()
    {
        // Exercise the worker's final publication while it is idle; its real event stays valid.
        var invalid: Sync.Event
        .requestSerial += #wrap 1
        .publishCompletion(.requestSerial, &invalid)
        .wait()
    }

    mtd checkWaitFailure(probe: *WaitFailureProbe)
    {
        var invalid: Sync.Event
        waitFailureBorrowLive.store(1)
        .execute(func|probe|()
        {
            probe.entered.signal()
            probe.allow.wait()
            waitFailureBorrowLive.store(0)
        },
                 &invalid)
        Swag.print("render failure resumed\n")
    }
}

func runWaitFailure(thread: Threading.Thread)
{
    let probe = cast(*WaitFailureProbe, thread.userParam!)
    probe.worker.checkWaitFailure(probe)
}

// The worker releases its borrow before reporting a failed wait, even with safety disabled.
#[Swag.TestTag("render.wait-failure")]
#test
{
    if Swag.jit() do
        return
    if not waitFailureChild()
    {
        verifyWaitFailureProcess("render.wait-failure")
        return
    }

    let probe = Memory.new'WaitFailureProbe()
    probe.entered.init()
    probe.allow.init()
    probe.worker.start(&probe.backend)
    waitFailureWorker = &probe.worker
    var caller: Threading.Thread
    expect caller.init(&runWaitFailure, probe)
    caller.context.panic = &observeWaitFailurePanic
    expect caller.start()
    probe.entered.wait()
    Swag.assert(not probe.worker.isReady() and waitFailureBorrowLive.load() == 1)
    probe.allow.signal()
    caller.wait()
    Swag.print("render failure resumed\n")
}

// An already-published completion failure is fatal on the fast wait path too.
#[Swag.TestTag("render.signal-failure")]
#test
{
    if Swag.jit() do
        return
    if not waitFailureChild()
    {
        verifyWaitFailureProcess("render.signal-failure")
        return
    }

    let probe = Memory.new'WaitFailureProbe()
    probe.worker.start(&probe.backend)
    waitFailureWorker = &probe.worker
    waitFailureBorrowLive.store(0)
    Swag.getContext().panic = &observeWaitFailurePanic
    probe.worker.checkCompletionSignalFailure()
    Swag.print("render failure resumed\n")
}
