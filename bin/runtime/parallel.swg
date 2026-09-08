#global namespace Swag

private struct ParallelProfile
{
    entry:        AtomicValue'u64
    grain:        AtomicValue'u64
    observations: AtomicValue'u32
}

// Bounded hints, local to each runtime artifact. Entries never change owner; when nearby slots
// are occupied, the caller measures its own work without retaining a hint in the table.
private var g_ParallelProfiles:   [256] ParallelProfile
private var g_ParallelTickBudget: AtomicValue'u64

private func parallelProfile(entry: u64)->*ParallelProfile?
{
    let first = ((entry >> 4) ^ (entry >> 12) ^ (entry >> 20)) & 255
    for offset in 4
    {
        let profile = &g_ParallelProfiles[(first + offset) & 255]
        var known   = profile.entry.load()
        if known == entry do
            return profile
        if known == 0
        {
            known = profile.entry.compareExchange(0, entry)
            if known == 0 or known == entry do
                return profile
        }
    }

    return null
}

private func recordParallelCost(profile: *ParallelProfile?, count, elapsed: u64)->u64
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
    let result   = grain == 0 ? 1'u64 : grain
    if profile do
        profile.grain.store(result)
    return result
}

// The caller owns the range until every runner joins. Claiming a block advances one cursor;
// accepted nodes stay bounded by the worker count rather than by the number of blocks.
private struct ParallelDispatch
{
    next: AtomicValue'u64
    end:  u64
    step: u64
    body: (func||(u64, u64))?
}

// One runner of a parallel range, submitted to the scheduler as its own unit of work.
#[Swag.NoDoc]
struct ParallelChunk
{
    using node: WorkNode               // Scheduler state. Must stay first.
    dispatch:   *ParallelDispatch?     // Borrowed until all runners have joined.
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
    let entry = cast(u64) (cast(const *ClosureValue) &body).invoke
    parallelRange(begin, end, body, entry)
}

// The first published error is copied out of the worker's scratch error storage before that
// worker can reuse it. Only this owner drops the copy, after every partition has joined.
#[Swag.NoCopy]
private struct ParallelFailure
{
    mutex: Mutex
    value: any?
}

impl ParallelFailure
{
    mtd record(error: any)
    {
        .mutex.lock()
        defer .mutex.unlock()
        if .value != null do
            return

        let type = cast(const *TypeInfoStruct) Swag.kindOf(error)
        let data = __bootstrapAlloc(cast(u64) type.sizeof)
        if !data do
            Swag.panic("cannot allocate a parallel loop error", #curlocation)
        Swag.memcpy(data, error.buffer, cast(u64) type.sizeof)
        if type.opPostCopy do
            type.opPostCopy(data)
        .value = Swag.makeAny(data!, type)
    }

    mtd opDrop()
    {
        if .value == null do
            return
        let data = .value.buffer
        __dropErr(.value)
        __bootstrapFree(cast([*] void?) data)
    }
}

// Explicit try/catch/expect owns this call. A failing partition stops its remaining iterations;
// other partitions finish, then the first published error is raised on the caller. Effects are
// not rolled back, and no cancellation or deterministic error order is implied.
#[Swag.NoDoc]
internal func __parallelRangeFallible(begin, end: u64, body: func||(u64, u64) fail) fail
{
    var failure: ParallelFailure
    let entry     = cast(u64) (cast(const *ClosureValue) &body).invoke
    let partition = func|&body, &failure|(first, last: u64)
    {
        catch body(first, last) as error
        if error != null do
            failure.record(error!)
    }
    parallelRange(begin, end, partition, entry)

    if failure.value != null do
        fail failure.value!
}

private func parallelRange(begin, end: u64, body: func||(u64, u64), entry: u64)
{
    if end <= begin do
        return

    var count = end - begin
    if count == 1 or Swag.jit() or hasSerialWorkerPool()
    {
        body(begin, end)
        return
    }

    let profile = parallelProfile(entry)
    var grain   = profile ? profile.grain.load() : 0'u64
    var first   = begin
    if grain == 0
    {
        // A cold or uncached loop tries one real iteration before acquiring execution resources.
        // The local estimate remains useful even when the hint table has no available slot.
        let started = __hostMonotonicTicks()
        body(first, first + 1)
        grain = recordParallelCost(profile, 1, __hostMonotonicTicks() - started)
        first += 1
        count -= 1
    }

    // Amortize the clock reads on repeated short loops. A stale observation can only change
    // placement; every call still executes its complete range and joins all accepted work.
    let measure = profile and (profile.observations.add(1) & 15) == 0
    if count / grain < 2
    {
        let started = measure ? __hostMonotonicTicks() : 0'u64
        body(first, end)
        if measure do
            discard recordParallelCost(profile, count, __hostMonotonicTicks() - started)
        return
    }

    let workers = workerCount()
    var chunks  = cast(u64) workers
    if chunks > count do
        chunks = count
    if chunks > count / grain do
        chunks = count / grain

    if chunks <= 1
    {
        let started = measure ? __hostMonotonicTicks() : 0'u64
        body(first, end)
        if measure do
            discard recordParallelCost(profile, count, __hostMonotonicTicks() - started)
        return
    }

    dispatchParallelRange(first, end, chunks, grain, body, profile, measure)
}

// Keep the partition storage out of serial calls, including empty and nested short loops.
// Inlining would put the full worker array and its stack probes back in their entry frame.
#[Swag.NoInline]
private func dispatchParallelRange(begin, end, chunks, grain: u64, body: func||(u64, u64), profile: *ParallelProfile?, measure: bool)
{
    // Several blocks per runner let an idle runner take remaining work from a costly region.
    // The cost hint still imposes a minimum useful block size. At most eight times as many
    // blocks as runners bound cursor contention and closure calls on large uniform ranges.
    let count    = end - begin
    let balanced = (count - 1) / (chunks * 8) + 1
    var dispatch: ParallelDispatch
    dispatch.end  = end
    dispatch.step = balanced > grain ? balanced : grain
    dispatch.body = body

    // Reserve useful work for the caller before publishing nodes, so worker startup cannot
    // consume its whole sample or leave it idle while a few expensive iterations remain.
    let firstEnd = begin + dispatch.step
    dispatch.next.store(firstEnd)
    var slices: [MaxWorkers] ParallelChunk

    for index in chunks
    {
        let slice = &slices[index]
        slice.dispatch   = &dispatch
        slice.node.entry = &parallelChunkEntry

        // The caller participates directly, so its runner is never queued.
        if index != 0 do
            submitWork(&slice.node)
    }

    let started = measure ? __hostMonotonicTicks() : 0'u64
    body(begin, firstEnd)
    let completed = dispatch.step + runParallelChunk(&slices[0])
    if measure do
        discard recordParallelCost(profile, completed, __hostMonotonicTicks() - started)

    for index in 1 until chunks do
        waitWork(&slices[index].node)
}

private func parallelChunkEntry(node: *WorkNode)
{
    discard runParallelChunk(cast(*ParallelChunk) node)
}

private func runParallelChunk(chunk: *ParallelChunk)->u64
{
    let dispatch = chunk.dispatch
    if !dispatch do
        return 0
    let body = dispatch.body
    if !body do
        return 0

    let safeBody  = body orelse func(begin, end: u64) {}
    var completed = 0'u64
    var first     = dispatch.next.load()
    while first < dispatch.end
    {
        let remaining = dispatch.end - first
        let count     = remaining < dispatch.step ? remaining : dispatch.step
        let last      = first + count
        let observed  = dispatch.next.compareExchange(first, last)
        if observed != first
        {
            first = observed
            continue
        }

        safeBody(first, last)
        completed += count
        first     = dispatch.next.load()
    }

    return completed
}
