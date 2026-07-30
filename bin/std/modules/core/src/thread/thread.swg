#global public
#global namespace Threading

// Names the thread handle type.
alias ThreadHandle = #null const *void

// Selects thread priority.
enum ThreadPriority
{
    Lowest          // Selects lowest.
    BelowNormal     // Selects below normal.
    Normal          // Selects normal.
    AboveNormal     // Selects above normal.
    Highest         // Selects highest.
}

// Represents thread.
#[Swag.NoCopy]
struct Thread
{
    userLambda: #null func||(Thread)     // User lambda associated with this value.

    context:   Swag.Context     // Context associated with this value.
    userParam: #null *void      // User param associated with this value.

    priority   = ThreadPriority.Normal     // Priority associated with this value.
    requestEnd = false                     // Cooperative stop flag the thread body polls.

    // Identity of the running thread, established when it starts.
    readonly id: u32

    // Platform handle of the thread, owned by this value.
    internal handle: ThreadHandle
}

impl Thread
{
    // Releases resources owned by this value.
    mtd opDrop()
    {
        Debug.assert(!.isValid(), "thread is not terminated")
    }

    // Returns true if the thread is valid
    mtd const isValid()->bool
    {
        return .handle != null
    }

    // Force the thread to safely exist
    // User code needs to check for 'requestEnd'
    mtd safeForceEnd()
    {
        .requestEnd = true
    }
}
