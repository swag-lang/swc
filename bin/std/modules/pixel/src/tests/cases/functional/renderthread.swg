#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Core.Math

#test
{
    var backend: PresentProbe
    backend.entered.init()
    backend.allow.init()
    var worker: RenderThread
    Swag.require(worker.isReady())
    worker.start(&backend)
    defer worker.close()
    let renderer: IRenderer = &worker
    scope
    {
        var context = expect renderer.createContext(null, 64, 64)
        defer renderer.deleteContext(&context)
        Swag.require(backend.workerId != Env.Process.currentThreadId())
        renderer.init()
        for iteration in 2
        {
            renderer.begin(context)
            renderer.end()
            backend.entered.wait()

            // Neither the previous ticket nor its native signal can complete this request.
            Swag.require(not worker.isReady() and backend.presented == iteration)
            backend.allow.signal()
            worker.wait()
            Swag.require(worker.isReady() and backend.presented == iteration + 1)
        }
    }

    worker.close()
    worker.close()
    Swag.require(worker.isReady() and not worker.isStarted())
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
        Swag.require(error is RenderThreadError)
        let message = String.from(Errors.message(error))

        // Another worker operation may reset scratch storage; the caller's error stays valid.
        renderer.init()
        Swag.require(Errors.message(error) == message.toString() and not message.isEmpty())
    }
}
