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
                Swag.require(destroyed == 1)
                Swag.require(host.app.surfaces.isEmpty())
            }
        }

        Swag.require(destroyed == 1)
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
    Swag.require(destroyed == 1)
}

// Replacing the standalone root does not leave the application's view or its floating siblings alive.
#test
{
    for explicitShutdown in [false, true]
    {
        var destroyed = 0'u32
        scope
        {
            var host: Testing.HeadlessHost
            host.setup(160, 80)
            let view = Wnd.create'Wnd(&host.surfaceWnd)
            host.surface.setView(view)
            let child    = Wnd.create'Wnd(view)
            let floating = Wnd.create'Wnd(&host.surfaceWnd)
            let caption  = CaptionButton.createLeading(&host.surface, .ParentFolder)
            let windows: [4] *Wnd = [view, child, floating, caption]
            for wnd in windows
            {
                wnd.hookOnEvent = func|count = &destroyed|(_, evt)->bool
                {
                    if evt is DestroyEvent do
                        count[] += 1
                    return false
                }
            }

            if explicitShutdown
            {
                host.shutdown()
                host.shutdown()
                Swag.require(destroyed == 4 and host.surfaceWnd.isPendingDestroy)
            }
        }

        Swag.require(destroyed == 4)
    }
}

// Unshown dialogs own rendering contexts too; shutdown drains every hosted surface.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    discard EditDlg.createSingleLine(&host.surface, {title: "Rename", message: "Name"})
    discard EditDlg.createMultiLine(&host.surface, {title: "Description"})
    Swag.require(host.openedSurfaceCount() == 2)
    host.shutdown()
    Swag.require(host.app.surfaces.isEmpty())
    host.shutdown()
}

// Hidden windows can keep their activity while they remain alive.
#test
{
    for keep in [false, true]
    {
        var ticks, notifications: u32
        var host: Testing.HeadlessHost
        host.setup(160, 80)
        let child = Wnd.create'Wnd(&host.root)
        child.hookOnEvent = func|ticks = &ticks, notifications = &notifications|(_, evt)->bool
        {
            if evt is TimerEvent do
                ticks[] += 1
            elif evt is NotifyEvent as notify where notify.kind == .KeyboardLayoutChanged do
                notifications[] += 1
            return false
        }

        let timer  = child.addTimer(10'ms)
        let queued = Event.create'NotifyEvent()
        queued.kind = .KeyboardLayoutChanged
        child.postEvent(queued)
        child.hide(keepActivities: keep)
        host.fireTimer(timer)
        Swag.require(not child.isLocallyVisible())
        Swag.require(ticks == (keep ? 1 : 0) and notifications == ticks)

        child.destroy()
        host.fireTimer(timer)
        Swag.require(ticks == (keep ? 1 : 0) and notifications == ticks)
    }
}
