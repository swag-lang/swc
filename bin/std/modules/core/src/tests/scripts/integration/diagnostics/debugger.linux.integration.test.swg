#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

func observeUntracedWorker(thread: const *Threading.Thread)
{
    let traced = cast(*bool, unwrap thread.userParam)
    traced[] = Debugger.isAttached()
}

// Select only when the test process has no attached debugger or syscall tracer.
#[Swag.TestTag("integration.debugger.unattached")]
#test
{
    let attached = Debugger.isAttached()
    Swag.assert(not attached)
    var workerAttached = true
    var worker: Threading.Thread
    expect worker.init(&observeUntracedWorker, &workerAttached)
    expect worker.start()
    worker.wait()
    Swag.assert(not workerAttached)
}

// Run the native test executable under a tracer that follows only its initial thread and
// resumes SIGTRAP without forwarding it. A debugger that follows every new thread changes
// the worker's expected state and is not the harness for this contract.
#[Swag.TestTag("integration.debugger.attached")]
#test
{
    let attached = Debugger.isAttached()
    Swag.assert(attached)
    var workerAttached = true
    var worker: Threading.Thread
    expect worker.init(&observeUntracedWorker, &workerAttached)
    expect worker.start()
    worker.wait()
    Swag.assert(not workerAttached)
    Debugger.debugBreak()
    Swag.assert(Debugger.isAttached())
}
