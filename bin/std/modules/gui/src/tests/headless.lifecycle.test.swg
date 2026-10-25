#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// An unused host can be shut down repeatedly and dropped without setup.
#test
{
    var host: Testing.HeadlessHost
    host.shutdown()
    host.shutdown()
}

// Scope exit destroys the tree once, including after an explicit shutdown.
#test
{
    for explicitShutdown in [false, true]
    {
        var destroyed = 0'u32
        scope
        {
            var host: Testing.HeadlessHost
            host.setup(160, 80)
            let child = Wnd.create'Wnd(&host.root)
            child.hookOnEvent = func|count = &destroyed|(_, evt)->bool
            {
                if evt is DestroyEvent do
                    count[] += 1
                return false
            }

            if explicitShutdown
            {
                host.shutdown()
                host.shutdown()
                Swag.assert(destroyed == 1)
                Swag.assert(host.app.surfaces.isEmpty())
            }
        }

        Swag.assert(destroyed == 1)
    }
}

// Returning early still delivers destruction while the callback's borrowed data is alive.
#test
{
    func leaveHost(destroyed: *u32)
    {
        var host: Testing.HeadlessHost
        host.setup(160, 80)
        let child = Wnd.create'Wnd(&host.root)
        child.hookOnEvent = func|destroyed|(_, evt)->bool
        {
            if evt is DestroyEvent do
                destroyed[] += 1
            return false
        }

        return
    }

    var destroyed = 0'u32
    leaveHost(&destroyed)
    Swag.assert(destroyed == 1)
}
