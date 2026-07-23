#global #if #command == Swag.CompilerCommand.Test
#global #if WINDOWS
#global private
using Win32

private const WaitManyThreadCount       = cast(u64) MAXIMUM_WAIT_OBJECTS + 1'u64
private const WaitManyExpectedDoneCount = cast(s32) WaitManyThreadCount
private const WaitManyDelayedSleepMs    = 1000'u32

struct WaitManyPayload
{
    doneCount: *s32
    sleepMs:   u32
}

func idleThread(_th: Threading.Thread) {}

func waitManyThread(th: Threading.Thread)
{
    let payload = cast(#null *WaitManyPayload) th.userParam
    if payload.sleepMs != 0 do
        Sleep(payload.sleepMs)
    Atomic.add(payload.doneCount, 1)
}

func waitUntilDone(doneCount: &s32)
{
    while Atomic.get(&doneCount) != WaitManyExpectedDoneCount do
        Sleep(10)
}

func waitManyThreads(threads: &[WaitManyThreadCount] Threading.Thread)
{
    Threading.wait(&threads[0], &threads[1], &threads[2], &threads[3], &threads[4], &threads[5], &threads[6], &threads[7], &threads[8], &threads[9], &threads[10], &threads[11], &threads[12], &threads[13], &threads[14], &threads[15], &threads[16], &threads[17], &threads[18], &threads[19], &threads[20], &threads[21], &threads[22], &threads[23], &threads[24], &threads[25], &threads[26], &threads[27], &threads[28], &threads[29], &threads[30], &threads[31], &threads[32], &threads[33], &threads[34], &threads[35], &threads[36], &threads[37], &threads[38], &threads[39], &threads[40], &threads[41], &threads[42], &threads[43], &threads[44], &threads[45], &threads[46], &threads[47], &threads[48], &threads[49], &threads[50], &threads[51], &threads[52], &threads[53], &threads[54], &threads[55], &threads[56], &threads[57], &threads[58], &threads[59], &threads[60], &threads[61], &threads[62], &threads[63], &threads[64])
}

#test
{
    var thread: Threading.Thread
    discard catch thread.init(&idleThread, null, Threading.ThreadPriority.AboveNormal)
    @assert(@err == null)

    let initPriority = catch GetThreadPriority(cast(HANDLE) thread.handle)
    @assert(@err == null)

    discard catch thread.setPriority(Threading.ThreadPriority.Highest)
    @assert(@err == null)

    let updatedPriority = catch GetThreadPriority(cast(HANDLE) thread.handle)
    @assert(@err == null)

    discard catch thread.start()
    @assert(@err == null)
    thread.wait()

    @assert(initPriority == THREAD_PRIORITY_ABOVE_NORMAL)
    @assert(updatedPriority == THREAD_PRIORITY_HIGHEST)
}

#test
{
    var doneCount: s32 = 0
    var payloads: [WaitManyThreadCount] WaitManyPayload = undefined
    var threads: [WaitManyThreadCount] Threading.Thread

    for i in WaitManyThreadCount
    {
        payloads[i].doneCount = &doneCount
        payloads[i].sleepMs   = i + 1 == WaitManyThreadCount ? WaitManyDelayedSleepMs : 0

        discard catch threads[i].init(&waitManyThread, &payloads[i])
        @assert(@err == null)
    }

    for i in WaitManyThreadCount
    {
        discard catch threads[i].start()
        @assert(@err == null)
    }

    waitManyThreads(&threads)

    let completedAfterWait = Atomic.get(&doneCount)
    waitUntilDone(&doneCount)

    @assert(completedAfterWait == WaitManyExpectedDoneCount)
}
