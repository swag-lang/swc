#global if WINDOWS
#global public
#global namespace Sync

using Win32

// Represents rw lock.
struct RWLock
{
    public v: SRWLOCK = SRWLOCK_INIT     // V associated with this value.
}

impl RWLock
{
    // Acquires the lock.
    mtd lock()
    {
        .lockExclusive()
    }

    // Releases the lock.
    mtd unlock()
    {
        .unlockExclusive()
    }

    // Try to lock the mutex, and return 'true' if it's the case
    mtd tryLockExclusive()->bool
    {
        return TryAcquireSRWLockExclusive(&.v) ? true : false
    }

    // Lock mutex
    mtd lockExclusive()
    {
        AcquireSRWLockExclusive(&.v)
    }

    // Unlock mutex
    mtd unlockExclusive()
    {
        ReleaseSRWLockExclusive(&.v)
    }

    // Try to lock the mutex, and return 'true' if it's the case
    mtd tryLockShared()->bool
    {
        return TryAcquireSRWLockShared(&.v) ? true : false
    }

    // Lock mutex
    mtd lockShared()
    {
        AcquireSRWLockShared(&.v)
    }

    // Unlock mutex
    mtd unlockShared()
    {
        ReleaseSRWLockShared(&.v)
    }
}
