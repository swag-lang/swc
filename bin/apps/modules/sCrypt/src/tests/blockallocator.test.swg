#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Allocation covers every free block once, but no longer reveals creation order by walking the
// container from its first block upward. A sequential result has probability 1/64! under the
// CSPRNG, so seeing it is a regression to the old lowest-block policy rather than a random event.
#test
{
    const BlockCount = 64'u64

    var allocator: BlockAllocator
    allocator.initialize(BlockCount)

    var seen: BitArray
    seen.resize(BlockCount)
    var differsFromSequential: bool
    for [expected] in BlockCount
    {
        let block = expect allocator.allocate()
        @assert(block < BlockCount)
        @assert(!seen.get(block))
        seen.set(block, true)
        if block != expected do
            differsFromSequential = true
    }

    @assert(differsFromSequential)
    @assert(allocator.freeBlockCount() == 0)
    discard catch allocator.allocate() as fullError
    @assert(fullError != null)
}

// Removing a block from the middle of an extent leaves both sides available and lets release
// merge them back into one run.
#test
{
    var allocator: BlockAllocator
    allocator.initialize(8)

    let removed = allocator.allocateAtOffset(3)
    @assert(removed == 3)
    @assert(allocator.free.count == 2)
    @assert(allocator.free[0].first == 0 and allocator.free[0].count == 3)
    @assert(allocator.free[1].first == 4 and allocator.free[1].count == 4)
    @assert(allocator.freeBlockCount() == 7)
    allocator.release(removed)
    @assert(allocator.freeBlockCount() == 8)
    @assert(allocator.free.count == 1)
    @assert(allocator.free[0].first == 0 and allocator.free[0].count == 8)
}
