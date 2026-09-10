#global namespace Swag

// Waits without a deadline.
const InfiniteWait = 0xFFFF_FFFF'u32

// Mutual exclusion over the state a program keeps beside it.
//
// A zero-initialized value is a free lock, so a `Mutex` needs no construction and can be a
// global. The lock is neither recursive nor fair: a thread that locks twice deadlocks, and a
// waiter has no ordering guarantee. The value must stay at one address while another thread can
// reach it, so it must not be copied or moved once anything can lock it.
struct Mutex
{
    // Host lock storage. Never read or written by user code.
    #[Swag.NoDoc]
    storage: *void?
}

impl Mutex
{
    // Acquires the lock, waiting until no other thread holds it.
    mtd lock() => __hostLockExclusive(&.storage)

    // Releases the lock. Only the thread that acquired it may release it.
    mtd unlock() => __hostUnlockExclusive(&.storage)

    // Acquires the lock only if it is free, and returns whether it did.
    mtd tryLock()->bool => __hostTryLockExclusive(&.storage)
}

// A lock that admits either one writer or any number of concurrent readers.
//
// A zero-initialized value is a free lock. Readers and writers use different release operations,
// and a reader cannot upgrade to a writer while holding the shared side: release first, then
// acquire exclusively and revalidate whatever the read observed.
struct RWLock
{
    // Host lock storage. Never read or written by user code.
    #[Swag.NoDoc]
    storage: *void?
}

impl RWLock
{
    // Acquires exclusive access, waiting until no reader or writer holds the lock.
    mtd lock() => __hostLockExclusive(&.storage)

    // Releases exclusive access.
    mtd unlock() => __hostUnlockExclusive(&.storage)

    // Acquires exclusive access only if the lock is free, and returns whether it did.
    mtd tryLock()->bool => __hostTryLockExclusive(&.storage)

    // Acquires shared access, waiting until no writer holds the lock.
    mtd lockShared() => __hostLockShared(&.storage)

    // Releases shared access.
    mtd unlockShared() => __hostUnlockShared(&.storage)

    // Acquires shared access only if no writer holds the lock, and returns whether it did.
    mtd tryLockShared()->bool => __hostTryLockShared(&.storage)
}

// A wait queue attached to a [[Swag.Mutex]], for state one thread publishes and another awaits.
//
// A zero-initialized value is an empty queue. [[Swag.Condition.wait]] releases the mutex, waits,
// and reacquires it, so a wake can be lost between the two: always wait in a loop that rechecks
// the predicate the state actually encodes.
//
// ```swag
// mutex.lock()
// while not ready do
//     condition.wait(&mutex)
// mutex.unlock()
// ```
struct Condition
{
    // Host condition storage. Never read or written by user code.
    #[Swag.NoDoc]
    storage: *void?
}

impl Condition
{
    // Releases `mutex`, waits for a wake, then reacquires `mutex` before returning.
    //
    // A waiting thread does not run ready work, so the wake must come from something that is
    // already running rather than from work still queued behind this wait.
    mtd wait(mutex: *Mutex)
    {
        discard __hostConditionWait(&.storage, &mutex.storage, InfiniteWait)
    }

    // Waits like [[Swag.Condition.wait]] but gives up after `milliseconds`.
    //
    // Returns `false` when the deadline expired rather than a wake arriving. `mutex` is
    // reacquired either way.
    mtd waitFor(mutex: *Mutex, milliseconds: u32)->bool
    {
        return __hostConditionWait(&.storage, &mutex.storage, milliseconds)
    }

    // Wakes one waiter, if any is waiting.
    mtd wake() => __hostConditionWake(&.storage)

    // Wakes every current waiter.
    mtd wakeAll() => __hostConditionWakeAll(&.storage)
}

// A counted set of permits, acquired and released by any thread.
//
// A zero-initialized value holds no permit. Call [[Swag.Semaphore.setPermits]] before the first
// acquisition, or release the initial permits explicitly. The count is the resource; the
// semaphore does not track which thread took a permit, so releasing one that was never acquired
// is a program error rather than a detected fault.
struct Semaphore
{
    // Serializes the permit count and its wait queue.
    #[Swag.NoDoc]
    mutex: Mutex

    // Wakes a waiter when a permit is returned.
    #[Swag.NoDoc]
    available: Condition

    // Permits currently free.
    #[Swag.NoDoc]
    permits: u32
}

impl Semaphore
{
    // Sets the number of free permits. Call it before any thread can acquire.
    mtd setPermits(count: u32)
    {
        .mutex.lock()
        .permits = count
        .mutex.unlock()
    }

    // Takes one permit, waiting until one is free.
    //
    // A waiting thread does not run ready work, so a task that waits here occupies its worker.
    // The permits must be returned by something that is already running.
    mtd acquire()
    {
        .mutex.lock()
        while .permits == 0 do
            .available.wait(&.mutex)
        .permits -= 1
        .mutex.unlock()
    }

    // Takes one permit only if one is free, and returns whether it did.
    mtd tryAcquire()->bool
    {
        .mutex.lock()
        defer .mutex.unlock()
        if .permits == 0 do
            return false
        .permits -= 1
        return true
    }

    // Returns `count` permits and wakes that many waiters.
    mtd release(count: u32 = 1)
    {
        if count == 0 do
            return

        .mutex.lock()
        .permits += count
        .mutex.unlock()

        if count == 1 do
            .available.wake()
        else do
            .available.wakeAll()
    }
}

// A rendezvous point that releases a fixed number of participants together.
//
// Every phase is independent: once `participants` threads have arrived, all of them resume and
// the barrier is ready for the next phase. A participant that leaves without arriving strands
// the others, so the participant count must match the threads that actually reach the barrier.
//
// > WARNING:
// > The participants must all be running. Tasks submitted to the worker pool are not: the pool
// > decides how many run at once, so a participant can wait for one the pool has not started.
// > Use a barrier between threads that own themselves.
struct Barrier
{
    // Serializes arrival counting.
    #[Swag.NoDoc]
    mutex: Mutex

    // Wakes the phase when the last participant arrives.
    #[Swag.NoDoc]
    released: Condition

    // Threads expected in one phase.
    #[Swag.NoDoc]
    participants: u32

    // Threads still missing from the current phase.
    #[Swag.NoDoc]
    waiting: u32

    // Phase number, so a late waiter cannot be released by the previous phase.
    #[Swag.NoDoc]
    phase: u32
}

impl Barrier
{
    // Sets how many participants one phase expects. Call it before any thread arrives.
    mtd setParticipants(count: u32)
    {
        .mutex.lock()
        .participants = count
        .waiting      = count
        .mutex.unlock()
    }

    // Waits until every participant of the current phase has arrived.
    //
    // Returns `true` to the participant that completed the phase, and `false` to the others.
    mtd arrive()->bool
    {
        .mutex.lock()

        if .participants <= 1
        {
            .mutex.unlock()
            return true
        }

        let current = .phase
        .waiting -= 1
        if .waiting == 0
        {
            .waiting = .participants
            .phase   += 1
            .mutex.unlock()
            .released.wakeAll()
            return true
        }

        while .phase == current do
            .released.wait(&.mutex)
        .mutex.unlock()
        return false
    }
}

// Locks `syncObj` for the rest of the enclosing scope.
//
// The lock is released by the scope's exit, including an early return or a raised error.
#[Swag.Mixin]
func(T) scopedLock(syncObj: *T)
{
    syncObj.lock()
    defer syncObj.unlock()
}

// Takes shared access to `syncObj` for the rest of the enclosing scope.
#[Swag.Mixin]
func(T) scopedLockShared(syncObj: *T)
{
    syncObj.lockShared()
    defer syncObj.unlockShared()
}
