#global if #command == Swag.CompilerCommand.Test
#global private

struct ContextProbe
{
    late parent: *Swag.Context
    isolated:    bool
}

func probeContext(thread: Threading.Thread)
{
    let probe   = cast(*ContextProbe) thread.userParam!
    let context = Swag.getContext()
    probe.isolated = context.errorAllocator.block != probe.parent.errorAllocator.block and context.errorIndex == 0 and context.curError == null and context.hasError == 0
}

// Creating a worker inside a fallible call must not inherit its live error stack or storage.
func checkThreadContext() fail
{
    var thread: Threading.Thread
    let probe = Memory.new'ContextProbe()
    defer Memory.delete(probe)
    probe.parent = Swag.getContext()
    expect thread.init(&probeContext, probe)
    expect thread.start()
    thread.wait()
    Swag.assert(probe.isolated)
}

#test
{
    expect checkThreadContext()
}
