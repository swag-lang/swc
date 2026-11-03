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

#[Swag.TestTag("integration.thread")]
#test
{
    var probe:  LinuxThreadProbe
    var thread: Threading.Thread
    for 3
    {
        probe.ran.reset()
        expect thread.init(&linuxThreadBody, &probe)
        Swag.assert(thread.isValid() and thread.id > 0)
        let premature = thread.isDone()
        Swag.assert(not premature and not probe.ran.isRaised())
        expect thread.start()
        thread.wait()
        Swag.assert(not thread.isValid() and probe.ran.isRaised())
        Swag.assert(thread.id == probe.id)
    }
}

#[Swag.TestTag("integration.thread")]
#test
{
    var probe:  LinuxThreadProbe
    var thread: Threading.Thread
    for priority in [Threading.ThreadPriority.Lowest, .BelowNormal, .AboveNormal, .Highest]
    {
        var rejected = false
        catch thread.init(&linuxThreadBody, &probe, priority)
        {
            rejected = true
        }

        Swag.assert(rejected and not thread.isValid() and not probe.ran.isRaised())
    }

    expect thread.init(&linuxThreadBody, &probe)
    expect thread.start()

    // isDone may reap the pthread, but wait must still release the owner exactly once.
    while not thread.isDone() do
        Threading.Thread.yield()
    let stillDone = thread.isDone()
    Swag.assert(stillDone and probe.ran.isRaised())
    thread.wait()
    Swag.assert(not thread.isValid())
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
    Swag.assert(not first.isValid() and not second.isValid())
    Swag.assert(firstProbe.ran.isRaised() and secondProbe.ran.isRaised())
}
