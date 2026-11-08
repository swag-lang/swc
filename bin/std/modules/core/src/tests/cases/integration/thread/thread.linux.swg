#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

struct LinuxThreadProbe
{
    ran: Swag.AtomicFlag
    id:  u64
}

func linuxThreadBody(thread: const *Threading.Thread)
{
    let probe = cast(*LinuxThreadProbe, unwrap thread.userParam)
    probe.id = Env.Process.currentThreadId()
    probe.ran.raise()
}

func linuxCountedThreadBody(thread: const *Threading.Thread)
{
    let completed = cast(*Swag.AtomicValue'u32, unwrap thread.userParam)
    discard completed.add(1)
}

// A rejected second start must leave the original owner joinable and run its body only once.
#[Swag.TestTag("integration.thread")]
#test
{
    var completed: Swag.AtomicValue'u32
    var thread:    Threading.Thread
    for cycle in 64'u32
    {
        expect thread.init(&linuxCountedThreadBody, &completed)
        Swag.require(thread.isValid())
        expect thread.start()
        var rejected = false
        catch thread.start()
        {
            if Swag.err is Swag.SystemError as system do
                Swag.require(system.errorID == Linux.EINVAL)
            else do
                Swag.require(false, "second start returned a different error type")
            rejected = true
        }

        Swag.require(rejected and thread.isValid())
        thread.wait()
        Swag.require(not thread.isValid() and completed.load() == cycle + 1)
    }
}

#[Swag.TestTag("integration.thread")]
#test
{
    var probe:  LinuxThreadProbe
    var thread: Threading.Thread
    for 3
    {
        probe.ran.reset()
        expect thread.init(&linuxThreadBody, &probe)
        Swag.require(thread.isValid() and thread.id > 0)
        let premature = thread.isDone()
        Swag.require(not premature and not probe.ran.isRaised())
        expect thread.start()
        thread.wait()
        Swag.require(not thread.isValid() and probe.ran.isRaised())
        Swag.require(thread.id == probe.id)
    }
}

#[Swag.TestTag("integration.thread")]
#test
{
    var probe:  LinuxThreadProbe
    var thread: Threading.Thread
    expect thread.init(&linuxThreadBody, &probe)
    expect thread.start()

    // isDone may reap the pthread, but wait must still release the owner exactly once.
    while not thread.isDone() do
        Threading.Thread.yield()
    let stillDone = thread.isDone()
    Swag.require(stillDone and probe.ran.isRaised())
    thread.wait()
    Swag.require(not thread.isValid())
}

#[Swag.TestTag("integration.thread")]
#test
{
    var firstProbe, secondProbe: LinuxThreadProbe
    var first, second: Threading.Thread
    expect first.init(&linuxThreadBody, &firstProbe)
    expect second.init(&linuxThreadBody, &secondProbe)
    expect first.start()
    expect second.start()
    Threading.wait(&first, &second)
    Swag.require(not first.isValid() and not second.isValid())
    Swag.require(firstProbe.ran.isRaised() and secondProbe.ran.isRaised())
}
