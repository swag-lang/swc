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
    let testTag    = Format.toString("swag.test-tag=%", tag)
    let arguments  = ["swag.test", testTag.toString(), "render-failure-child"]
    var child      = expect Env.startProcess(Env.StartInfo{fileName: executable.toString(), arguments: arguments, standardOutput: .Pipe, standardError: .Pipe, consoleWindow: false})
    let finished   = expect child.tryWaitForExit(10's)
    if not finished
    {
        expect child.kill()
        discard expect child.waitForExit()
    }

    Swag.require(finished, "the failed render request must terminate without hanging")
    Swag.require(child.exitCode() != 0)
    let output = String.from(child.standardOutput())
    Swag.require(output.contains("render failure observed after retirement"))
    Swag.require(not output.contains("render failure resumed"))
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

func runWaitFailure(thread: const *Threading.Thread)
{
    let probe = cast(*WaitFailureProbe, unwrap thread.userParam)
    probe.worker.checkWaitFailure(probe)
}

// The worker releases its borrow before reporting a failed wait, even with safety disabled.

// An already-published completion failure is fatal on the fast wait path too.
