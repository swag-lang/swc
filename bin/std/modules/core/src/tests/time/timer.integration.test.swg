#global if #command == Swag.CompilerCommand.Test
#global private

var g_workerTimerEntries:        Swag.AtomicValue'u32
var g_workerTimerCalls:          Swag.AtomicValue'u32
var g_workerTimerEntered:        Swag.AtomicFlag
var g_workerTimerContinue:       Swag.AtomicFlag
var g_workerTimerReleaseStarted: Swag.AtomicFlag
var g_workerTimerReleased:       Swag.AtomicFlag

func workerTimerCount(_: *Time.Timer)
{
    g_workerTimerCalls.add(1)
}

func workerTimerBlocked(_: *Time.Timer)
{
    g_workerTimerEntries.add(1)
    g_workerTimerEntered.raise()
    while not g_workerTimerContinue.isRaised() do
        Threading.Thread.yield()
    g_workerTimerCalls.add(1)
}

func workerTimerRelease(thread: const *Threading.Thread)
{
    let timer = cast(*Time.Timer, unwrap thread.userParam)
    g_workerTimerReleaseStarted.raise()
    timer.release()
    g_workerTimerReleased.raise()
}

func waitForWorkerTimer(flag: *Swag.AtomicFlag)->bool
{
    var elapsed: Time.Stopwatch
    elapsed.start()
    while not flag.isRaised() and elapsed.elapsedMilliseconds() < 5000 do
        Threading.Thread.sleep(1'ms)
    return flag.isRaised()
}

#[Swag.TestTag("integration.timer")]
#test
{
    g_workerTimerCalls.store(0)
    var timer  = expect Time.Timer.create(60's, &workerTimerCount)
    let before = Time.monotonicTicks()
    timer.release()
    timer.release()
    let elapsed = Time.monotonicTicks() - before
    Swag.assert(elapsed < 5 * Time.monotonicFrequency())
    Swag.assert(g_workerTimerCalls.load() == 0)
}

#[Swag.TestTag("integration.timer")]
#test
{
    g_workerTimerCalls.store(0)
    g_workerTimerEntries.store(0)
    g_workerTimerEntered.reset()
    g_workerTimerContinue.reset()
    g_workerTimerReleaseStarted.reset()
    g_workerTimerReleased.reset()
    var timer   = expect Time.Timer.create(1'ms, &workerTimerBlocked, periodic: true)
    let entered = waitForWorkerTimer(&g_workerTimerEntered)
    if not entered
    {
        g_workerTimerContinue.raise()
        timer.release()
        Swag.assert(entered)
        return
    }

    Threading.Thread.sleep(10'ms)
    let entriesBeforeRelease = g_workerTimerEntries.load()
    var releaser: Threading.Thread
    expect releaser.init(&workerTimerRelease, &timer)
    expect releaser.start()
    let releaseStarted = waitForWorkerTimer(&g_workerTimerReleaseStarted)
    Threading.Thread.sleep(10'ms)
    let releasedEarly = g_workerTimerReleased.isRaised()
    g_workerTimerContinue.raise()
    releaser.wait()
    Swag.assert(releaseStarted and not releasedEarly and g_workerTimerReleased.isRaised())
    Swag.assert(entriesBeforeRelease == 1 and g_workerTimerEntries.load() == 1)
    Swag.assert(g_workerTimerCalls.load() == 1)
    timer.release()
}
