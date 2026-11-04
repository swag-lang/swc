#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

func threadNice(id: u64)->s32
{
    Linux.errno(0)
    let result = Linux.getpriority(Linux.PRIO_PROCESS, cast(u32, id))
    Swag.require(Linux.errno() == 0)
    return result
}

func priorityErrorCode(error: any?)->u64
{
    if error is Swag.SystemError as system do
        return system.errorID
    Swag.panic("expected a system error", #curlocation)
}

struct PriorityProbe
{
    nice:      s32
    childNice: s32
    ready:     Swag.AtomicFlag
}

func observeThreadNice(thread: const *Threading.Thread)
{
    let probe = cast(*PriorityProbe, unwrap thread.userParam)
    probe.nice = threadNice(0)
}

func observeInheritedNice(thread: const *Threading.Thread)
{
    let probe = cast(*PriorityProbe, unwrap thread.userParam)
    probe.nice = threadNice(0)
    var childProbe: PriorityProbe
    var child:      Threading.Thread
    expect child.init(&observeThreadNice, &childProbe)
    expect child.start()
    child.wait()
    probe.childNice = childProbe.nice
}

func waitForPriorityChanges(thread: const *Threading.Thread)
{
    let probe = cast(*PriorityProbe, unwrap thread.userParam)
    probe.ready.raise()
    while not thread.requestEnd.isRaised() do
        Threading.Thread.sleep(1'ms)
}

#[Swag.TestTag("integration.thread")]
#test
{
    let normal = threadNice(0)
    for priority, index in [Threading.ThreadPriority.Normal, .BelowNormal, .Lowest]
    {
        var probe:  PriorityProbe
        var thread: Threading.Thread
        expect thread.init(&observeThreadNice, &probe, priority)
        let suspendedNice = threadNice(thread.id)
        expect thread.start()
        thread.wait()
        let expected = Math.min(normal + cast(s32, index), 19)
        Swag.require(suspendedNice == expected and probe.nice == expected)
        Swag.require(threadNice(0) == normal)
    }
}

#[Swag.TestTag("integration.thread")]
#test
{
    let normal = threadNice(0)
    for priority, index in [Threading.ThreadPriority.AboveNormal, .Highest]
    {
        var probe:  PriorityProbe
        var thread: Threading.Thread
        var denied = false
        catch thread.init(&observeThreadNice, &probe, priority)
        {
            let error = priorityErrorCode(Swag.err)
            Swag.require(error == Linux.EACCES or error == Linux.EPERM)
            denied = true
        }

        if denied
        {
            Swag.require(not thread.isValid() and thread.id == 0)
        }
        else
        {
            expect thread.start()
            thread.wait()
            Swag.require(probe.nice == Math.max(normal - cast(s32, index) - 1, -20))
        }

        Swag.require(threadNice(0) == normal)
    }
}

#[Swag.TestTag("integration.thread")]
#test
{
    let normal = threadNice(0)
    var probe:  PriorityProbe
    var thread: Threading.Thread
    expect thread.init(&observeInheritedNice, &probe, priority: .BelowNormal)
    expect thread.start()
    thread.wait()
    Swag.require(probe.nice == Math.min(normal + 1, 19) and probe.childNice == probe.nice)
    Swag.require(threadNice(0) == normal)
}

#[Swag.TestTag("integration.thread")]
#test
{
    let normal = threadNice(0)
    var probe:  PriorityProbe
    var thread: Threading.Thread
    expect thread.init(&waitForPriorityChanges, &probe)
    expect thread.start()
    defer if thread.isValid()
    {
        thread.safeForceEnd()
        thread.wait()
    }

    let deadline = Time.monotonicMilliseconds() + 5000
    while not probe.ready.isRaised() and Time.monotonicMilliseconds() < deadline do
        Threading.Thread.sleep(1'ms)
    Swag.require(probe.ready.isRaised())
    expect thread.setPriority(.BelowNormal)
    Swag.require(threadNice(thread.id) == Math.min(normal + 1, 19))
    expect thread.setPriority(.Lowest)
    let lowered = threadNice(thread.id)
    Swag.require(lowered == Math.min(normal + 2, 19))
    var denied = false
    catch thread.setPriority(.Normal)
    {
        let error = priorityErrorCode(Swag.err)
        Swag.require(error == Linux.EACCES or error == Linux.EPERM)
        denied = true
    }

    Swag.require(threadNice(thread.id) == (denied ? lowered : normal))
    Swag.require(thread.priority == (denied ? .Lowest : .Normal))
    thread.safeForceEnd()
    let taskPath = Format.toString("/proc/self/task/%", thread.id)
    while Directory.exists(taskPath) and Time.monotonicMilliseconds() < deadline do
        Threading.Thread.sleep(1'ms)
    Swag.require(not Directory.exists(taskPath))
    var finished = false
    catch thread.setPriority(.Normal)
    {
        Swag.require(priorityErrorCode(Swag.err) == Linux.ESRCH)
        finished = true
    }

    Swag.require(finished)
    thread.wait()
    Swag.require(threadNice(0) == normal)
}
