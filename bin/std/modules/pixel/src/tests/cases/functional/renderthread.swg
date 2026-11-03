#global if #command == Swag.CompilerCommand.Test
#global private
using Core, Core.Math

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
    scope
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
#test
{
    var backend: RenderCpu
    var worker:  RenderThread
    worker.start(&backend)
    defer worker.close()
    let renderer: IRenderer = &worker
    for 3
    {
        var errorOutcome: Swag.Error
        discard catch renderer.addImage("render-thread-missing-image.png") as errorOutcome
        let error = errorOutcome.value()
        Swag.assert(error is RenderThreadError)
        let message = String.from(Errors.message(error))

        // Another worker operation may reset scratch storage; the caller's error stays valid.
        renderer.init()
        Swag.assert(Errors.message(error) == message.toString() and not message.isEmpty())
    }
}
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
