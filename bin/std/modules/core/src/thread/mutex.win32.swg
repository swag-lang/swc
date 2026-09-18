#global if WINDOWS
#global public
#global namespace Sync

using Win32

// Serializes access to shared data between threads.
//
// The lock is not reentrant: a thread that locks it twice deadlocks. Pair each
// [[Core.Sync.Mutex.lock]] with an [[Core.Sync.Mutex.unlock]] on the same thread, or use
// [[Core.Sync.scopedLock]].
struct Mutex
{
    public v: SRWLOCK = SRWLOCK_INIT     // Native lock state, managed by the methods.
}

impl Mutex
{
    // Acquires the mutex when it is free and returns whether it did, without waiting.
    mtd tryLock()->bool => TryAcquireSRWLockExclusive(&.v) ? true : false

    // Acquires the mutex, waiting until it is free.
    mtd lock()
    {
        AcquireSRWLockExclusive(&.v)
    }

    // Releases the mutex held by the calling thread.
    mtd unlock()
    {
        ReleaseSRWLockExclusive(&.v)
    }
}
