#global namespace Swag

// One partition of a parallel range, submitted to the scheduler as its own unit of work.
#[Swag.NoDoc]
struct ParallelChunk
{
    using node: WorkNode                // Scheduler state. Must stay first.
    body:       (func||(u64, u64))?     // The loop body, one copy per chunk.
    begin:      u64                     // First index of this chunk.
    end:        u64                     // One past the last index of this chunk.
}

// Runs `body` over every index of `[0, count)`, splitting the range across the worker pool.
//
// This is what `parallel for` lowers to. `body` is called once per partition with the half-open
// bounds of that partition; every index of the range is covered exactly once, and the call
// returns only after every partition has finished.
//
// Partition boundaries and the order partitions run in are not part of the contract, so a body
// must not depend on either. The body executes on a worker thread, so everything it reaches must
// either be owned by that partition or be safe to share; the caller's frame stays alive for the
// whole call, which is what makes an `&` capture of a local valid here.
//
// With fewer than two workers, and under compile-time execution, the whole range runs as one
// partition on the calling thread.
//
// ```swag
// parallel for row in image.height do
//     convertRow(row)
// ```
public func parallelRange(count: u64, body: func||(u64, u64))
{
    __parallelRange(0, count, body)
}

// Runs `body` over the half-open index range `[begin, end)`, split across the worker pool.
//
// A `parallel for` statement lowers to this call. It behaves exactly like
// [[Swag.parallelRange]] over an offset range: the partitions it hands to `body` are absolute
// indices of that range, and an empty range runs nothing.
public func parallelRangeFrom(begin, end: u64, body: func||(u64, u64))
{
    __parallelRange(begin, end, body)
}

#[Swag.NoDoc]
internal func __parallelRange(begin, end: u64, body: func||(u64, u64))
{
    if end <= begin do
        return

    let count   = end - begin
    let workers = workerCount()
    var chunks  = cast(u64) workers
    if chunks > count do
        chunks = count

    if chunks <= 1
    {
        body(begin, end)
        return
    }

    var slices: [MaxWorkers] ParallelChunk
    let step  = count / chunks
    var start = begin

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

    runParallelChunk(&slices[0])

    for index in 1 until chunks do
        waitWork(&slices[index].node)
}

// Runs `body` over every index of `[0, count)` when the range is large enough to be worth
// splitting, and on the calling thread otherwise.
//
// `threshold` is the smallest range the caller considers worth distributing. Below it the whole
// range runs as one partition, which avoids paying for submission and joining on work that is
// shorter than they cost.
public func parallelRangeAbove(count: u64, threshold: u64, body: func||(u64, u64))
{
    if count == 0 do
        return

    if count < threshold
    {
        body(0, count)
        return
    }

    parallelRange(count, body)
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
