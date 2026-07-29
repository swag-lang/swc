#global public

using Core

// Represents timer.
struct Timer
{
    timeMs:    s32 // Time ms associated with this value.
    target:    *Wnd = undefined // Target associated with this value.
    stopwatch: Time.Stopwatch // Stopwatch associated with this value.
    toDelete:  bool // To delete associated with this value.
}

impl Timer
{
    // Performs the restart operation.
    #[Swag.Inline]
    mtd restart()
    {
        .stopwatch.reset()
    }
}
