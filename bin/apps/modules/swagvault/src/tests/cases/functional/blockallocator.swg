#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Large requests stay contiguous and the free count remains an owned scalar rather than a scan
// of the extent list.
#test
{
    const BlockCount = 64'u64

    var allocator: BlockAllocator
    allocator.initialize(BlockCount)

    let first  = expect allocator.allocateRun(48)
    let second = expect allocator.allocateRun(48)
    Swag.require(first.first == 0 and first.count == 48)
    Swag.require(second.first == 48 and second.count == 16)
    Swag.require(allocator.freeBlockCount() == 0)
    var fullErrorOutcome: Swag.Error
    discard catch allocator.allocate() as fullErrorOutcome
    let fullError = fullErrorOutcome.value()
    Swag.require(fullError != null)

    allocator.releaseRun(first.first, first.count)
    allocator.releaseRun(second.first, second.count)
    Swag.require(allocator.freeBlockCount() == BlockCount)
    Swag.require(allocator.free.count == 1 and allocator.free[0].count == BlockCount)
}

// A small low-address hole left by an old metadata page does not split a large transfer while a
// contiguous tail can satisfy it.
#test
{
    var allocator: BlockAllocator
    allocator.initialize(16)

    let occupied = expect allocator.allocateRun(4)
    allocator.release(occupied.first)
    let data = expect allocator.allocateRun(8)
    Swag.require(data.first == 4 and data.count == 8)
}
