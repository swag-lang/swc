#global namespace Swag

private struct ParallelProfile
{
    entry:        AtomicValue'u64
    grain:        AtomicValue'u64
    observations: AtomicValue'u32
}

// Bounded hints, local to each runtime artifact. Entries never change owner: a collision
// falls back to ordinary partitioning, and concurrent observations only replace an estimate.
private var g_ParallelProfiles:   [256] ParallelProfile
private var g_ParallelTickBudget: AtomicValue'u64

private func parallelProfile(entry: u64)->*ParallelProfile?
{
    let profile = &g_ParallelProfiles[((entry >> 4) ^ (entry >> 12) ^ (entry >> 20)) & 255]
    let known   = profile.entry.load()
    if known == entry do
        return profile
    if known == 0 and profile.entry.compareExchange(0, entry) == 0 do
        return profile
    return null
}

private func recordParallelCost(profile: *ParallelProfile, count, elapsed: u64)
{
    var budget = g_ParallelTickBudget.load()
    if budget == 0
    {
        // Aim for at least eight microseconds of useful work per partition. The estimate
        // excludes queue publication and joining; those costs must not make cheap work
        // look expensive and perpetuate its dispatch overhead.
        budget = __hostMonotonicFrequency() / 125000
        if budget == 0 do
            budget = 1
        g_ParallelTickBudget.store(budget)
    }

    let duration = elapsed == 0 ? 1'u64 : elapsed
    let estimate = cast(f64) count * cast(f64) budget / cast(f64) duration
    let grain    = estimate >= cast(f64) 0xFFFF_FFFF_FFFF_FFFF'u64 ? 0xFFFF_FFFF_FFFF_FFFF'u64 : cast(u64) estimate
    profile.grain.store(grain == 0 ? 1 : grain)
}

// One partition of a parallel range, submitted to the scheduler as its own unit of work.
#[Swag.NoDoc]
struct ParallelChunk
{
    using node: WorkNode                // Scheduler state. Must stay first.
    body:       (func||(u64, u64))?     // The loop body, one copy per chunk.
    begin:      u64                     // First index of this chunk.
    end:        u64                     // One past the last index of this chunk.
}

// Runs the compiler-generated body over [begin, end), splitting it across the worker pool.
//
// This is what `parallel for` lowers to. The body is called once per partition with the half-open
// bounds of that partition; every index of the range is covered exactly once, and the call
// returns only after every partition has finished.
//
// Partition boundaries and the order partitions run in are not part of the contract, so a body
// must not depend on either. The body can execute on the caller or a worker, so everything it reaches must
// either be owned by that partition or be safe to share; the caller's frame stays alive for the
// whole call, which is what makes an `&` capture of a local valid here.
//
// Cost observations can keep short work on the caller or reduce the number of partitions.
// With fewer than two workers, and under compile-time execution, all work stays on the caller.
#[Swag.NoDoc]
internal func __parallelRange(begin, end: u64, body: func||(u64, u64))
{
    if end <= begin do
        return

    var count = end - begin
    if count == 1 or Swag.jit()
    {
        body(begin, end)
        return
    }

    let entry   = cast(u64) (cast(const *ClosureValue) &body).invoke
    let profile = parallelProfile(entry)
    var grain   = profile ? profile.grain.load() : 0'u64
    var first   = begin
    if profile and grain == 0
    {
        // A cold loop tries one real iteration before acquiring any execution resource.
        // Expensive iterations still fan out; cheap short ranges never start the pool.
        let started = __hostMonotonicTicks()
        body(first, first + 1)
        recordParallelCost(profile!, 1, __hostMonotonicTicks() - started)
        first += 1
        count -= 1
        grain = profile.grain.load()
    }

    // Amortize the clock reads on repeated short loops. A stale observation can only change
    // placement; every call still executes its complete range and joins all accepted work.
    let measure = profile and (grain == 0 or (profile.observations.add(1) & 15) == 0)
    if grain != 0 and count / grain < 2
    {
        let started = measure ? __hostMonotonicTicks() : 0'u64
        body(first, end)
        if measure do
            recordParallelCost(profile!, count, __hostMonotonicTicks() - started)
        return
    }

    let workers = workerCount()
    var chunks  = cast(u64) workers
    if chunks > count do
        chunks = count
    if grain != 0 and chunks > count / grain do
        chunks = count / grain

    if chunks <= 1
    {
        let started = measure ? __hostMonotonicTicks() : 0'u64
        body(first, end)
        if measure do
            recordParallelCost(profile!, count, __hostMonotonicTicks() - started)
        return
    }

    var slices: [MaxWorkers] ParallelChunk
    let step  = count / chunks
    var start = first

    for index in chunks
    {
        let slice = &slices[index]
        slice.body       = body
        slice.begin      = start
        slice.end        = index == chunks - 1 ? end : start + step
        slice.node.entry = &parallelChunkEntry
        start            = slice.end

        // The caller runs the first partition itself, so it is never queued.
        if index != 0 do
            submitWork(&slice.node)
    }

    let started = measure ? __hostMonotonicTicks() : 0'u64
    runParallelChunk(&slices[0])
    if measure do
        recordParallelCost(profile!, slices[0].end - slices[0].begin, __hostMonotonicTicks() - started)

    for index in 1 until chunks do
        waitWork(&slices[index].node)
}

private func parallelChunkEntry(node: *WorkNode)
{
    runParallelChunk(cast(*ParallelChunk) node)
}

private func runParallelChunk(chunk: *ParallelChunk)
{
    let body = chunk.body
    if !body do
        return

    let safeBody = body orelse func(begin, end: u64) {}
    safeBody(chunk.begin, chunk.end)
}
