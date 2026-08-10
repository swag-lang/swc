#global if WINDOWS
#global public
#global namespace Sync

using Win32

// Represents mutex.
struct Mutex
{
    public v: SRWLOCK = SRWLOCK_INIT     // V associated with this value.
}

impl Mutex
{
    // Try to lock the mutex, and return 'true' if it's the case
    mtd tryLock()->bool
    {
        return TryAcquireSRWLockExclusive(&.v) ? true : false
    }

    // Lock mutex
    mtd lock()
    {
        AcquireSRWLockExclusive(&.v)
    }

    // Unlock mutex
    mtd unlock()
    {
        ReleaseSRWLockExclusive(&.v)
    }
}
