#global if #os == Swag.TargetOs.Linux

using Core

private var g_IdleMilliseconds: u64

struct AutoUnmountMonitor
{
    window:  *MainWindow?
    session: SessionWatch.Monitor
}

impl AutoUnmountMonitor
{
    mtd start(window: *MainWindow)
    {
        .window = window
        .session.start()
        .poll()
    }

    // Runs on the existing security timer, on the window's owning thread. The delay inhibitor
    // stays held until the synchronous suspension handler has finished committing and unmounting.
    mtd poll()
    {
        if not .window do
            return
        let snapshot = .session.poll()
        g_IdleMilliseconds = snapshot.idleMilliseconds
        if snapshot.locked do
            .window.handleAutoUnmount(.SessionLock)
        if snapshot.suspending
        {
            .window.handleAutoUnmount(.Suspend)
            .session.finishSuspend()
        }
    }

    mtd stop()
    {
        .session.stop()
        .window = null
        g_IdleMilliseconds = 0
    }
}

// Zero means no desktop idle clock is currently available, never an invented idle interval.
func autoUnmountIdleMilliseconds()->u64 => g_IdleMilliseconds
