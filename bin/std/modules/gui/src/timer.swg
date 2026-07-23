#global public

using Core

struct Timer
{
    timeMs:    s32
    target:    *Wnd = undefined
    stopwatch: Time.Stopwatch
    toDelete:  bool
}

impl Timer
{
    #[Swag.Inline]
    mtd restart()
    {
        .stopwatch.reset()
    }
}
