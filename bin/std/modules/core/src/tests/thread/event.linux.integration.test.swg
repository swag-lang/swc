#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

struct LinuxEventProbe
{
    event:     Sync.Event
    completed: Swag.AtomicValue'u32
    rounds = 1'u32
    published: u32
    observed:  u32
}

func linuxEventWaiter(thread: const *Threading.Thread)
{
    let probe = cast(*LinuxEventProbe, unwrap thread.userParam)
    for probe.rounds
    {
        probe.event.wait()
        if probe.rounds == 2 do
            probe.observed = probe.published
        discard probe.completed.add(1)
    }
}

// Observe registration under the native mutex; sleeps alone cannot establish that a waiter
// reached its wait before the test signals and immediately resets the event.
internal impl Sync.Event
{
    mtd waitForTestWaiters(count: u32)->bool
    {
        let state = unwrap .state
        var watch: Time.Stopwatch
        watch.start()
        while watch.elapsedMilliseconds() < 2000
        {
            Swag.assert(Linux.pthread_mutex_lock(&state.mutex) == 0)
            let ready = state.waiters == count
            Swag.assert(Linux.pthread_mutex_unlock(&state.mutex) == 0)
            if ready do
                return true
            Threading.Thread.yield()
        }

        return false
    }
}

func waitForEventCompletion(probe: *LinuxEventProbe, count: u32)->bool
{
    var watch: Time.Stopwatch
    watch.start()
    while watch.elapsedMilliseconds() < 2000
    {
        if probe.completed.load() == count do
            return true
        Threading.Thread.yield()
    }

    return false
}

// Repeated pre-wait signals coalesce; a second wait needs a fresh signal and observes its data.
#[Swag.TestTag("integration.thread")]
#test
{
    var probe: LinuxEventProbe
    probe.rounds = 2
    probe.event.init()
    probe.event.signal()
    probe.event.signal()
    var thread: Threading.Thread
    expect thread.init(&linuxEventWaiter, &probe)
    expect thread.start()
    let waiting   = probe.event.waitForTestWaiters(1)
    let firstOnly = probe.completed.load() == 1
    probe.published = 42
    probe.event.signal()
    thread.wait()
    Swag.assert(waiting and firstOnly and probe.completed.load() == 2 and probe.observed == 42)
    probe.event.release()
    probe.event.release()
    Swag.assert(not probe.event.isValid())
    probe.event.init(initState: true)
    probe.event.wait()
}

// A manual signal releases every registered waiter, even when immediately reset.
#[Swag.TestTag("integration.thread")]
#test
{
    for 8
    {
        var probe: LinuxEventProbe
        probe.event.init(manual: true)
        var threads: [3] Threading.Thread
        for &thread in threads
        {
            expect thread.init(&linuxEventWaiter, &probe)
            expect thread.start()
        }

        let waiting = probe.event.waitForTestWaiters(3)
        probe.event.signal()
        probe.event.reset()
        let completed = waitForEventCompletion(&probe, 3)

        // Release any stranded waiter before reporting a failed assertion.
        probe.event.signal()
        for &thread in threads do
            thread.wait()
        Swag.assert(waiting and completed)
    }
}

// Auto-reset signals reserve one release each for blocked waiters; resetting does not revoke it.
#[Swag.TestTag("integration.thread")]
#test
{
    var probe: LinuxEventProbe
    probe.event.init()
    var threads: [3] Threading.Thread
    for &thread in threads
    {
        expect thread.init(&linuxEventWaiter, &probe)
        expect thread.start()
    }

    let waiting = probe.event.waitForTestWaiters(3)
    var each    = true
    for i in 3'u32
    {
        probe.event.signal()
        probe.event.reset()
        each = waitForEventCompletion(&probe, i + 1) and each
    }

    for 3 do
        probe.event.signal()
    for &thread in threads do
        thread.wait()
    Swag.assert(waiting and each and probe.completed.load() == 3)
}
