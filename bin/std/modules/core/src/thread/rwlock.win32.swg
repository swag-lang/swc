#global if WINDOWS
#global public
#global namespace Sync

using Win32

// Lets many threads read shared data at once while one thread at a time writes it.
//
// The lock is not reentrant, in either mode. [[Core.Sync.scopedLock]] and
// [[Core.Sync.sharedLock]] pair each acquisition with its release.
struct RWLock
{
    public v: SRWLOCK = SRWLOCK_INIT     // Native lock state, managed by the methods.
}

impl RWLock
{
    // Acquires the lock exclusively, like [[Core.Sync.RWLock.lockExclusive]].
    mtd lock()
    {
        .lockExclusive()
    }

    // Releases an exclusive hold, like [[Core.Sync.RWLock.unlockExclusive]].
    mtd unlock()
    {
        .unlockExclusive()
    }

    // Acquires the lock exclusively when it is free and returns whether it did, without waiting.
    mtd tryLockExclusive()->bool => TryAcquireSRWLockExclusive(&.v) ? true : false

    // Acquires the lock exclusively, waiting until no other thread holds it.
    mtd lockExclusive()
    {
        AcquireSRWLockExclusive(&.v)
    }

    // Releases the exclusive hold of the calling thread.
    mtd unlockExclusive()
    {
        ReleaseSRWLockExclusive(&.v)
    }

    // Acquires the lock for shared access when no writer holds it and returns whether it did, without waiting.
    mtd tryLockShared()->bool => TryAcquireSRWLockShared(&.v) ? true : false

    // Acquires the lock for shared access, waiting while a writer holds it.
    mtd lockShared()
    {
        AcquireSRWLockShared(&.v)
    }

    // Releases a shared hold of the calling thread.
    mtd unlockShared()
    {
        ReleaseSRWLockShared(&.v)
    }
}
