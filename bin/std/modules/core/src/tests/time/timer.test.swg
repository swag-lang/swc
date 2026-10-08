#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// The callback runs on an operating-system worker thread. That thread never entered Swag, so the
// runtime would hand it a default context created on first access; the timer inherits the
// arming thread's policy and user values. The marker below travels through that snapshot.

const TimerTestMarker = 0x5741474E'u64

var g_timerFired:  s32
var g_timerMarker: u64

func timerTestCallback(?: *Time.Timer)
{
    g_timerMarker = Swag.getContext().user0
    Atomic.add(&g_timerFired, 1)
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

    Swag.assert(Atomic.get(&g_timerFired) != 0)
    Swag.assert(g_timerMarker == TimerTestMarker)

    timer.release()
}

var g_timerOwnedFired: Swag.AtomicValue'u32
var g_timerOwnedBad:   Swag.AtomicValue'u32

func failTimerMessage(text: string) fail
{
    fail Errors.BadParameterError{Errors.mkString(text)}
}

func timerOwnedContextCallback(?: *Time.Timer)
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

    catch failTimerMessage("the callback owns this copied error message") as error
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
    catch failTimerMessage("the creator retains its own copied error message") as creatorError
    var timer = expect Time.Timer.create(1'ms, &timerOwnedContextCallback, periodic: true)
    for 200
    {
        if g_timerOwnedFired.load() >= 4 do
            break
        Threading.Thread.sleep(10'ms)
    }

    timer.release()

    Swag.assert(g_timerOwnedFired.load() >= 4)
    Swag.assert(g_timerOwnedBad.load() == 0)
    Swag.assert(Errors.message(creatorError) == "the creator retains its own copied error message")
}
