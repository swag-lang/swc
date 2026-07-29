#global public
#global namespace Threading

// Names the thread handle type.
alias ThreadHandle = #null const *void

// Selects thread priority.
enum ThreadPriority
{
    Lowest // Selects lowest.
    BelowNormal // Selects below normal.
    Normal // Selects normal.
    AboveNormal // Selects above normal.
    Highest // Selects highest.
}

// Represents thread.
#[Swag.NoCopy]
struct Thread
{
    userLambda: #null func||(Thread) // User lambda associated with this value.

    context:   Swag.Context // Context associated with this value.
    userParam: #null *void // User param associated with this value.

    priority   = ThreadPriority.Normal // Priority associated with this value.
    handle: ThreadHandle // Handle associated with this value.
    id:     u32 // Id associated with this value.
    requestEnd = false // Request end associated with this value.
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
