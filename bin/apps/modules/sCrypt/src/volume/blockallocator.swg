using Core

struct FreeExtent
{
    first: u64
    count: u64
}

struct BlockAllocator
{
    free:         Array'FreeExtent
    deferredFree: Array'u64
}

impl BlockAllocator
{
    mtd initialize(blockCount: u64)
    {
        Debug.assert(!.free.count and !.deferredFree.count)
        if blockCount do
            .free.add({0, blockCount})
    }

    // Rebuilds the free list as the complement of the blocks `used` marks.
    //
    // The free list is derived rather than stored, which is what keeps a
    // fragmented container from growing its header without bound, and what lets
    // a journal record describe a change without naming a single free extent.
    mtd rebuild(used: const *BitArray, blockCount: u64)
    {
        .free.clear()
        .deferredFree.clear()

        var first = 0'u64
        var index = 0'u64
        var inRun = false
        while index < blockCount
        {
            if used.get(index)
            {
                if inRun
                {
                    .free.add({first, index - first})
                    inRun = false
                }
            }
            elif !inRun
            {
                first = index
                inRun = true
            }

            index += 1
        }

        if inRun do
            .free.add({first, blockCount - first})
    }

    mtd allocate()->u64 fail
    {
        if !.free.count do
            failWith("The virtual disk is full.", .DiskFull)
        let result = .free[0].first
        .free[0].first += 1
        .free[0].count -= 1
        if !.free[0].count do
            .free.removeAtOrdered(0)
        return result
    }

    mtd release(block: u64)
    {
        var index = 0'u64
        while index < .free.count and .free[index].first < block do
            index += 1

        if index and .free[index - 1].first + .free[index - 1].count == block
        {
            .free[index - 1].count += 1
            if index < .free.count and block + 1 == .free[index].first
            {
                .free[index - 1].count += .free[index].count
                .free.removeAtOrdered(index)
            }

            return
        }

        if index < .free.count and block + 1 == .free[index].first
        {
            .free[index].first -= 1
            .free[index].count += 1
            return
        }

        .free.insertAt(index, {block, 1})
    }

    mtd deferRelease(block: u64)
    {
        .deferredFree.add(block)
    }

    mtd publishDeferred()
    {
        for block in .deferredFree do
            .release(block)
    }

    mtd completeCommit()
    {
        .deferredFree.clear()
    }

    mtd freeBlockCount()->u64
    {
        var result = 0'u64
        for extent in .free do
            result += extent.count
        return result
    }
}
