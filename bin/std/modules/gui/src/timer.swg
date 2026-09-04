#global public

using Core

// Repeating timer that sends [[Gui.TimerEvent]] values to one target window.
#[Swag.Opaque]
struct Timer
{
    internal
    {
        periodMilliseconds: u64                // Timer period in milliseconds.
        late target:        *Wnd               // Window receiving timer events.
        stopwatch:          Time.Stopwatch     // Elapsed time since the previous event.
        isPendingRemoval:   bool               // Whether removal is deferred until event dispatch ends.
    }
}

impl Timer
{
    // Restarts the period from the current instant.
    #[Swag.Inline]
    mtd restart()
    {
        .stopwatch.reset()
    }
}
