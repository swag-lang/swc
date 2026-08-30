#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// The callback runs on an operating-system worker thread. That thread never entered Swag, so the
// runtime would hand it a default context created on first access; the timer installs the context
// of the thread that armed it instead. The marker below travels through that context.

const TimerTestMarker = 0x5741474E'u64

var g_timerFired:  s32
var g_timerMarker: u64

func timerTestCallback(_timer: *Time.Timer)
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
