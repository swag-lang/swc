#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// The callback runs on an operating-system worker thread. That thread never entered Swag, so the
// runtime would hand it a default context created on first access; the timer inherits the
// arming thread's policy and user values. The marker below travels through that snapshot.

const TimerTestMarker = 0x5741474E'u64

var g_timerFired:  s32
var g_timerMarker: u64

func timerTestCallback(_: *Time.Timer)
{
    g_timerMarker = Swag.getContext().user0
    Atomic.add(&g_timerFired, 1)
}

#test
{
    var zeroFailure: Swag.Error
    discard catch Time.Timer.create(0'ms, &timerTestCallback) as zeroFailure
    Swag.require(zeroFailure.value() is Errors.BadParameterError)
    Swag.require(Errors.message(zeroFailure.value()) == "timer delay must be positive and finite")

    let tooLong = Time.Duration.fromSeconds(cast(f64, Swag.U32.Max) / 1000.0)
    var rangeFailure: Swag.Error
    discard catch Time.Timer.create(tooLong, &timerTestCallback) as rangeFailure
    Swag.require(rangeFailure.value() is Errors.OverflowError)
    Swag.require(Errors.message(rangeFailure.value()) == "timer delay must be between 1 and 4294967294 milliseconds")
}

#test
{
    let context       = Swag.getContext()
    let previousUser0 = context.user0
    context.user0 = TimerTestMarker
    defer context.user0 = previousUser0

    var timer = expect Time.Timer.create(1'ms, &timerTestCallback)

    // The worker thread is scheduled by the operating system: wait for it, but never forever.
    for 200
    {
        if Atomic.get(&g_timerFired) != 0 do
            break
        Threading.Thread.sleep(10'ms)
    }

    Swag.require(Atomic.get(&g_timerFired) != 0)
    Swag.require(g_timerMarker == TimerTestMarker)

    timer.release()
}

var g_timerOwnedFired: Swag.AtomicValue'u32
var g_timerOwnedBad:   Swag.AtomicValue'u32

func failTimerMessage(text: string) fail
{
    fail Errors.BadParameterError{Errors.mkString(text)}
}

func timerOwnedContextCallback(_: *Time.Timer)
{
    let context = Swag.getContext()
    if context.errorIndex != 0 or
       context.hasError != 0 or
       context.curError != null or
       context.errorCaptures != null or
       context.tempAllocator.block != null or
       context.tempAllocator.firstLeak != null or
       context.errorAllocator.block != null or
       context.errorAllocator.firstLeak != null do
        g_timerOwnedBad.add(1)

    var errorOutcome: Swag.Error
    catch failTimerMessage("the callback owns this copied error message") as errorOutcome
    let error = errorOutcome.value()
    if Errors.message(error) != "the callback owns this copied error message" do
        g_timerOwnedBad.add(1)
    Threading.Thread.sleep(3'ms)
    g_timerOwnedFired.add(1)
}

// Arming while a captured error is live must not lend its owner, message blocks or mutable
// error stack to an OS callback. Repeated callbacks each start with fresh storage.
#test
{
    if Swag.jit() do
        return
    g_timerOwnedFired.store(0)
    g_timerOwnedBad.store(0)
    var creatorErrorOutcome: Swag.Error
    catch failTimerMessage("the creator retains its own copied error message") as creatorErrorOutcome
    let creatorError = creatorErrorOutcome.value()
    var timer        = expect Time.Timer.create(1'ms, &timerOwnedContextCallback, periodic: true)
    for 200
    {
        if g_timerOwnedFired.load() >= 4 do
            break
        Threading.Thread.sleep(10'ms)
    }

    timer.release()

    Swag.require(g_timerOwnedFired.load() >= 4)
    Swag.require(g_timerOwnedBad.load() == 0)
    Swag.require(Errors.message(creatorError) == "the creator retains its own copied error message")
}
