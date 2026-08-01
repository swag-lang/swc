#global public
#global namespace Time

// Internal native timer handle required by the public value layout.
#[Swag.NoDoc]
alias TimerHandle = #null const *void

// Owns an operating-system timer that invokes a callback on a worker thread.
#[Swag.NoCopy]
struct Timer
{
    internal
    {
        callback: #null func(*Timer)
        handle:   TimerHandle
        context:  Swag.Context
    }
}
