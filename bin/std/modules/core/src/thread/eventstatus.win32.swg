#global if WINDOWS
#global public
#global namespace Sync

// Carries the outcome of a synchronous event operation until its caller can handle failure.
//
// The default value represents success. Obtaining a status neither allocates error storage nor
// invokes an error or panic hook. [[Core.Sync.EventStatus.raise]] performs that handling later,
// preserving the native error code even when it is zero.
#[Swag.Opaque]
struct EventStatus
{
    succeeded = true
    errorCode: u32
}

impl EventStatus
{
    // Reports whether the native operation succeeded.
    mtd const isSuccess()->bool => .succeeded

    // Raises the saved native failure, or succeeds when the operation succeeded.
    //
    // Error storage is allocated on the calling thread only at this point. The status remains
    // unchanged and can be inspected or raised again.
    mtd const raise() fail
    {
        if not .succeeded do
            try Win32.failWinError(.errorCode)
    }
}
