#global private
#global #[Swag.Safety(.ValueBorrow, true)]

struct Small { bytes: [96] u8 }
struct Large { bytes: [2048] u8 }

#[Swag.NoInline]
func readSmall(value: Small)->u8 => value.bytes[95]

#[Swag.NoInline]
func writeSmall(value: Small, target: *Small)->u8
{
    let inner = readSmall(value)
    Swag.assert(inner == 0)
    target.bytes[95] = 7
    return value.bytes[95]
}

#[Swag.NoInline]
func writeLarge(value: Large, target: *Large)->u8
{
    target.bytes[2047] = 11
    return value.bytes[2047]
}

// Workers register overlapping inner/outer borrows while other workers remove theirs.
// Each failed write must still be caught; panic cleanup must leave no stale filter cells.
#test
{
    let previous = Swag.workerCount()
    Swag.setWorkerCount(4)
    defer Swag.setWorkerCount(previous)

    parallel for 128
    {
        var small: Small
        var other: Small
        let observed = writeSmall(small, &other)
        Swag.assert(observed == 0 and other.bytes[95] == 7)
        let caught = Swag.catchPanic(func|&small|() { discard writeSmall(small, &small) })
        Swag.assert(caught.raised and small.bytes[95] == 0)
        small.bytes[95] = 13
        Swag.assert(small.bytes[95] == 13)
    }
}

// Wide ranges and unrelated short ranges share the same writer lock and epoch.
#test
{
    let previous = Swag.workerCount()
    Swag.setWorkerCount(4)
    defer Swag.setWorkerCount(previous)

    parallel for 128
    {
        var large: Large
        var other: Large
        let observed = writeLarge(large, &other)
        Swag.assert(observed == 0 and other.bytes[2047] == 11)
        let caught = Swag.catchPanic(func|&large|() { discard writeLarge(large, &large) })
        Swag.assert(caught.raised and large.bytes[2047] == 0)
        large.bytes[2047] = 17
        Swag.assert(large.bytes[2047] == 17)
    }
}

struct SharedBorrow
{
    small:   Small
    large:   Large
    ready:   Swag.Semaphore
    release: Swag.Semaphore
}

#[Swag.NoInline]
func holdAcrossThreads(small: Small, large: Large, state: *SharedBorrow)->u64
{
    state.ready.release()
    state.release.acquire()
    return cast(u64, small.bytes[95]) + large.bytes[2047]
}

// The writer is a different thread from the borrower. Both short and wide ranges must
// remain protected, then allow writes after their owner returns.
#test
{
    // The JIT runs tasks inline, so it cannot rendezvous with its submitting thread.
    if Swag.jit() do return
    Swag.startWorkers()
    var state: SharedBorrow
    var task:  Swag.Task'u64
    task.submit(func|&state|() => holdAcrossThreads(state.small, state.large, &state))
    state.ready.acquire()
    let small = Swag.catchPanic(func|&state|() { state.small.bytes[95] = 7 })
    let large = Swag.catchPanic(func|&state|() { state.large.bytes[2047] = 11 })
    state.release.release()
    let result = expect task.take()
    Swag.assert(small.raised and large.raised and result == 0)
    Swag.assert(small.message() == "write overlaps storage borrowed by a value argument")
    Swag.assert(large.message() == "write overlaps storage borrowed by a value argument")
    state.small.bytes[95]   = 13
    state.large.bytes[2047] = 17
    Swag.assert(state.small.bytes[95] == 13 and state.large.bytes[2047] == 17)
}
