#global if #os == Swag.TargetOs.Linux
#global namespace Env

// Native allocation survives a caller's allocator/context after its Process owner closes.
private struct LinuxProcessState
{
    pid:  s32
    next: *LinuxProcessState?
}

private var g_ProcessReaperMutex:    Swag.Mutex
private var g_ProcessReaperChanged:  Swag.Condition
private var g_ProcessReaperThread:   Linux.pthread_t
private var g_ProcessReaperStarted:  bool
private var g_ProcessReaperStopping: bool
private var g_ClosedProcesses:       *LinuxProcessState?

#init
{
    g_ProcessReaperMutex.lock()
    if not g_ProcessReaperStarted do
        g_ProcessReaperStopping = false
    g_ProcessReaperMutex.unlock()
}

#[Swag.CallingConvention(.C)]
private func processReaperEntry(_: *void?)->*void?
{
    g_ProcessReaperMutex.lock()
    defer g_ProcessReaperMutex.unlock()
    for
    {
        var link = &g_ClosedProcesses
        for
        {
            let state = link[]
            if not state do
                break
            var status: s32
            let reaped = Linux.waitpid(state.pid, &status, Linux.WNOHANG)
            if (reaped > 0 and (Linux.WIFEXITED(status) or Linux.WIFSIGNALED(status))) or
               (reaped < 0 and Linux.errno() == Linux.ECHILD)
            {
                link[] = state.next
                Linux.free(state)
            }
            else
            {
                if reaped < 0 and Linux.errno() != Linux.EINTR do
                    Swag.panic("cannot reap a closed child process", #curlocation)
                link = &state.next
            }
        }

        if g_ProcessReaperStopping and not g_ClosedProcesses do
            return null
        if g_ClosedProcesses do
            discard g_ProcessReaperChanged.waitFor(&g_ProcessReaperMutex, 25)
        else do
            g_ProcessReaperChanged.wait(&g_ProcessReaperMutex)
    }
}

private func ensureProcessReaperNative() fail
{
    g_ProcessReaperMutex.lock()
    defer g_ProcessReaperMutex.unlock()
    if g_ProcessReaperStopping do
        fail Errors.BadParameterError{"process services have shut down"}
    if g_ProcessReaperStarted do
        return
    let error = Linux.pthread_create(&g_ProcessReaperThread, null, &processReaperEntry, null)
    if error != 0 do
        try Errors.failLinuxError(error)
    g_ProcessReaperStarted = true
}

// Only closed owners enter the queue. No background thread can steal an active owner's status.
private func releaseProcessNative(state: *LinuxProcessState)
{
    if state.pid == 0
    {
        Linux.free(state)
        return
    }

    g_ProcessReaperMutex.lock()
    if g_ProcessReaperStopping
    {
        // A late global destructor still owns reaping even after the worker has stopped.
        g_ProcessReaperMutex.unlock()
        for
        {
            var status: s32
            let result = Linux.waitpid(state.pid, &status, 0)
            if result > 0 and (Linux.WIFEXITED(status) or Linux.WIFSIGNALED(status)) do
                break
            if result < 0
            {
                let error = Linux.errno()
                if error == Linux.ECHILD do
                    break
                if error != Linux.EINTR do
                    Swag.panic("cannot reap a closed child process", #curlocation)
            }
        }

        Linux.free(state)
        return
    }

    Swag.assert(g_ProcessReaperStarted)
    state.next        = g_ClosedProcesses
    g_ClosedProcesses = state
    g_ProcessReaperChanged.wake()
    g_ProcessReaperMutex.unlock()
}

internal func shutdownProcessesNative()
{
    g_ProcessReaperMutex.lock()
    g_ProcessReaperStopping = true
    let started = g_ProcessReaperStarted
    g_ProcessReaperChanged.wakeAll()
    g_ProcessReaperMutex.unlock()
    if not started do
        return
    let error = Linux.pthread_join(g_ProcessReaperThread, null)
    if error != 0 do
        Swag.panic("cannot join the process reaper", #curlocation)
    g_ProcessReaperMutex.lock()
    g_ProcessReaperStarted = false
    g_ProcessReaperMutex.unlock()
}
