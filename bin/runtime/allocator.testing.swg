#global if #command == Swag.CompilerCommand.Test
#global namespace Swag

// A test seam that makes the host refuse the allocator's reservations and commits on demand.
//
// Every reservation goes through 'allocatorOsReserve' and every commit through 'allocatorOsCommit',
// which consult this state only in a test build. A test arms a countdown, runs a scenario, and checks
// that the allocator's metadata stays consistent and that the request fails cleanly or is served
// another way. Only the arming thread sees the failures: the other threads of the process keep
// allocating normally.
struct AllocatorOsFailure
{
    // Calls left to succeed before one fails; negative while disarmed.
    countdown: s64 = -1

    // Keeps failing after the first refusal until the seam is cleared, instead of refusing once.
    sticky: bool

    // Refusals delivered since the seam was armed.
    failures: u32
}

struct AllocatorOsFailures
{
    reserve: AllocatorOsFailure
    commit:  AllocatorOsFailure

    // The thread whose calls the countdowns apply to.
    threadId: u64

    // Makes every arena report no room for a segment, which is the only way a test reaches the path
    // that reserves another one.
    arenasFull: bool
}

var g_AllocatorOsFailures: AllocatorOsFailures

// Takes one step of a countdown and reports whether this call is one that fails.
func allocatorInjectOsFailure(failure: *AllocatorOsFailure)->bool
{
    if failure.countdown < 0 or __hostCurrentThreadId() != g_AllocatorOsFailures.threadId do
        return false

    if failure.countdown > 0
    {
        failure.countdown -= 1
        return false
    }

    if not failure.sticky do
        failure.countdown = -1
    failure.failures += 1
    return true
}

// Makes the host refuse the calling thread's next reservation after 'after' successful ones.
func allocatorFailOsReserve(after: u32 = 0, sticky = false)
{
    g_AllocatorOsFailures.reserve  = AllocatorOsFailure{cast(s64, after), sticky}
    g_AllocatorOsFailures.threadId = __hostCurrentThreadId()
}

// Makes the host refuse the calling thread's next commit after 'after' successful ones.
func allocatorFailOsCommit(after: u32 = 0, sticky = false)
{
    g_AllocatorOsFailures.commit   = AllocatorOsFailure{cast(s64, after), sticky}
    g_AllocatorOsFailures.threadId = __hostCurrentThreadId()
}

// Makes every arena report no room, so the next segment needs a new reservation.
func allocatorFillArenas()
{
    g_AllocatorOsFailures.arenasFull = true
}

// Disarms every injected failure.
func allocatorClearOsFailures()
{
    g_AllocatorOsFailures = AllocatorOsFailures{}
}

// Counts the emptied segments of one shape waiting in the pool, which an acquisition takes before
// it creates a segment.
func allocatorPooledSegmentCount(unitShift: u32)->u32
{
    g_AllocatorArenaMutex.lock()
    defer g_AllocatorArenaMutex.unlock()

    var count = 0'u32
    var scan  = g_AllocatorFreeSegment
    while scan
    {
        if scan.unitShift == unitShift do
            count += 1
        scan = scan.nextSegment
    }

    return count
}
