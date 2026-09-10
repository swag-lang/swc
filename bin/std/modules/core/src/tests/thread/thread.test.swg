#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Win32

const WaitManyThreadCount       = cast(u64) MAXIMUM_WAIT_OBJECTS + 1'u64
const WaitManyExpectedDoneCount = cast(s32) WaitManyThreadCount
const WaitManyDelayedSleepMs    = 1000'u32

struct WaitManyPayload
{
    late doneCount: *s32
    sleepMs:        u32
}

func idleThread(_th: Threading.Thread) {}

func waitManyThread(th: Threading.Thread)
{
    let payload = cast(*WaitManyPayload) th.userParam!
    if payload.sleepMs != 0 do
        Sleep(payload.sleepMs)
    Atomic.add(payload.doneCount, 1)
}

func waitUntilDone(doneCount: *s32)
{
    while Atomic.get(doneCount) != WaitManyExpectedDoneCount do
        Sleep(10)
}

func waitManyThreads(threads: [..] Threading.Thread)
{
    Threading.wait(&threads[0], &threads[1], &threads[2], &threads[3], &threads[4], &threads[5], &threads[6], &threads[7], &threads[8], &threads[9], &threads[10], &threads[11], &threads[12], &threads[13], &threads[14], &threads[15], &threads[16], &threads[17], &threads[18], &threads[19], &threads[20], &threads[21], &threads[22], &threads[23], &threads[24], &threads[25], &threads[26], &threads[27], &threads[28], &threads[29], &threads[30], &threads[31], &threads[32], &threads[33], &threads[34], &threads[35], &threads[36], &threads[37], &threads[38], &threads[39], &threads[40], &threads[41], &threads[42], &threads[43], &threads[44], &threads[45], &threads[46], &threads[47], &threads[48], &threads[49], &threads[50], &threads[51], &threads[52], &threads[53], &threads[54], &threads[55], &threads[56], &threads[57], &threads[58], &threads[59], &threads[60], &threads[61], &threads[62], &threads[63], &threads[64])
}

#test
{
    var thread: Threading.Thread
    discard expect thread.init(&idleThread, null, Threading.ThreadPriority.AboveNormal)
    let initPriority = expect GetThreadPriority(cast(HANDLE) thread.handle)
    discard expect thread.setPriority(Threading.ThreadPriority.Highest)
    let updatedPriority = expect GetThreadPriority(cast(HANDLE) thread.handle)
    discard expect thread.start()
    thread.wait()

    Swag.assert(initPriority == THREAD_PRIORITY_ABOVE_NORMAL)
    Swag.assert(updatedPriority == THREAD_PRIORITY_HIGHEST)
}

#test
{
    var doneCount: s32 = 0
    var payloads:  [WaitManyThreadCount] WaitManyPayload
    var threads:   [WaitManyThreadCount] Threading.Thread

    for i in WaitManyThreadCount
    {
        payloads[i].doneCount = &doneCount
        payloads[i].sleepMs   = i + 1 == WaitManyThreadCount ? WaitManyDelayedSleepMs : 0

        discard expect threads[i].init(&waitManyThread, &payloads[i])
    }

    for i in WaitManyThreadCount
    {
        discard expect threads[i].start()
    }

    waitManyThreads(threads)

    let completedAfterWait = Atomic.get(&doneCount)
    waitUntilDone(&doneCount)

    Swag.assert(completedAfterWait == WaitManyExpectedDoneCount)
}

// Independent owners share an auto-reset event, including a signal sent before opening.
#test
{
    let name = Format.toString("Swag.Event.é.事.%", Guid128.random().toString())
    var first, second, distinct: Sync.Event
    expect first.initNamed(name, initState: true)
    expect second.initNamed(name, manual: true)
    expect distinct.initNamed(Format.toString("%.other", name))
    Swag.assert(first.isValid() and second.isValid())
    Swag.assert((expect WaitForSingleObject(second.handle, 0)) == WAIT_OBJECT_0)
    Swag.assert((expect WaitForSingleObject(first.handle, 0)) == WAIT_TIMEOUT)
    first.signal()
    Swag.assert((expect WaitForSingleObject(distinct.handle, 0)) == WAIT_TIMEOUT)
    Swag.assert((expect WaitForSingleObject(second.handle, 0)) == WAIT_OBJECT_0)
    first.release()
    first.release()
    Swag.assert(not first.isValid())
    second.signal()
    Swag.assert((expect WaitForSingleObject(second.handle, 0)) == WAIT_OBJECT_0)
}

#test
{
    var event: Sync.Event
    for name in ["", "invalid\\name", "invalid\0name"]
    {
        var rejected = false
        catch event.initNamed(name)
        {
            rejected = true
        }

        Swag.assert(rejected and not event.isValid())
    }

    let name = Format.toString("Swag.Event.Manual.%", Guid128.random().toString())
    expect event.initNamed(name, manual: true)
    var second: Sync.Event
    expect second.initNamed(name, initState: true)
    Swag.assert((expect WaitForSingleObject(event.handle, 0)) == WAIT_TIMEOUT)
    event.signal()
    Swag.assert((expect WaitForSingleObject(second.handle, 0)) == WAIT_OBJECT_0)
    Swag.assert((expect WaitForSingleObject(event.handle, 0)) == WAIT_OBJECT_0)
    second.reset()
    Swag.assert((expect WaitForSingleObject(event.handle, 0)) == WAIT_TIMEOUT)
}
