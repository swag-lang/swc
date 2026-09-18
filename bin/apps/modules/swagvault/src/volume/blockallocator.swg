using Core

// A run of consecutive blocks, `[first, first + count)`.
struct FreeExtent
{
    first: u64
    count: u64
}

// Hands out the free data blocks of a volume.
//
// Blocks a pending change stops using are deferred rather than freed: they stay reserved until
// the record that drops them is durable, so a block the last durable state still references is
// never handed out again before that state is replaced.
struct BlockAllocator
{
    free:            Array'FreeExtent     // Free extents, sorted by `first` and never adjacent.
    deferredFree:    Array'FreeExtent     // Extents that become free once the pending change is durable.
    freeBlocksCount: u64                  // Total number of blocks in `free`.
}

impl BlockAllocator
{
    // Makes all `blockCount` blocks of a fresh volume free.
    mtd initialize(blockCount: u64)
    {
        Swag.assert(.free.isEmpty() and .deferredFree.isEmpty())
        if blockCount do
            .free.add({0, blockCount})
        .freeBlocksCount = blockCount
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
        .freeBlocksCount = 0

        var first = 0'u64
        var inRun = false
        for index in blockCount
        {
            if used.get(index)
            {
                if inRun
                {
                    .free.add({first, index - first})
                    inRun = false
                }
            }
            elif not inRun
            {
                first = index
                inRun = true
            }
        }

        if inRun do
            .free.add({first, blockCount - first})
        for extent in .free do
            .freeBlocksCount += extent.count
    }

    // Adds the blocks `[first, first + count)` to the free list.
    //
    // A container only ever grows at its end, so the new blocks sit above every block that
    // exists: they either extend the last free extent or become one of their own. Nothing
    // else in the list can be touched by them.
    mtd extend(first, count: u64)
    {
        if not count do
            return

        if not .free.isEmpty() and .free.back().first + .free.back().count == first
        {
            .free.backPtr().count += count
            .freeBlocksCount      += count
            return
        }

        Swag.assert(.free.isEmpty() or .free.back().first + .free.back().count < first)
        .free.add({first, count})
        .freeBlocksCount += count
    }

    // Takes up to `maximumCount` adjacent blocks from the highest free extent.
    //
    // The container is randomized before use, so allocating it in runs reveals no plaintext.
    // Keeping one logical transfer physically adjacent is what lets the host combine its I/O and
    // keeps the node map proportional to extents rather than to every 4 KiB block.
    mtd allocateRun(maximumCount: u64)->FreeExtent fail
    {
        if .free.isEmpty() do
            try failWith("The virtual disk is full.", .DiskFull)
        Swag.assert(maximumCount != 0)

        let index  = .free.count - 1
        let count  = Math.min(maximumCount, .free[index].count)
        let result = FreeExtent{.free[index].first, count}
        .free[index].first += count
        .free[index].count -= count
        if not .free[index].count do
            .free.removeAtOrdered(index)
        .freeBlocksCount -= count
        return result
    }

    // Takes adjacent blocks strictly below `limit`. Shrinking uses this to evacuate the tail
    // without accidentally choosing another block that the new geometry will discard.
    mtd allocateRunBelow(limit, maximumCount: u64)->FreeExtent fail
    {
        Swag.assert(maximumCount != 0)
        for index in reversed(.free.count)
        {
            let extent = .free[index]
            if extent.first >= limit do
                continue

            let availableEnd = Math.min(extent.first + extent.count, limit)
            let count        = Math.min(maximumCount, availableEnd - extent.first)
            if not count do
                continue

            let first = extent.first
            .free[index].first += count
            .free[index].count -= count
            if not .free[index].count do
                .free.removeAtOrdered(index)
            .freeBlocksCount -= count
            return {first, count}
        }

        try failWith("The smaller container has no room for every used block.", .DiskFull)
        unreachable
    }

    // Discards free extents outside a new, smaller geometry.
    mtd trim(limit: u64)
    {
        for index in reversed(.free.count)
        {
            let extent = .free[index]
            if extent.first >= limit
            {
                .freeBlocksCount -= extent.count
                .free.removeAtOrdered(index)
                continue
            }

            if extent.first + extent.count > limit
            {
                let removed = extent.first + extent.count - limit
                .free[index].count -= removed
                .freeBlocksCount   -= removed
            }
        }
    }

    // Takes one block from the highest free extent.
    mtd allocate()->u64 fail => (try .allocateRun(1)).first

    // Returns the blocks `[first, first + count)` to the free list, merging them with their
    // neighbours.
    mtd releaseRun(first, count: u64)
    {
        if not count do
            return
        var index = 0'u64
        while index < .free.count and .free[index].first < first do
            index += 1

        if index and .free[index - 1].first + .free[index - 1].count == first
        {
            .free[index - 1].count += count
            if index < .free.count and first + count == .free[index].first
            {
                .free[index - 1].count += .free[index].count
                .free.removeAtOrdered(index)
            }
        }
        elif index < .free.count and first + count == .free[index].first
        {
            .free[index].first -= count
            .free[index].count += count
        }
        else do
            .free.insertAt(index, {first, count})
        .freeBlocksCount += count
    }

    // Returns one block to the free list.
    mtd release(block: u64) { .releaseRun(block, 1) }

    // Frees the blocks `[first, first + count)` once the pending change is durable.
    mtd deferReleaseRun(first, count: u64)
    {
        if count do
            .deferredFree.add({first, count})
    }

    // Frees one block once the pending change is durable.
    mtd deferRelease(block: u64) { .deferReleaseRun(block, 1) }

    // Returns every deferred extent to the free list. Called once the change that dropped them
    // is durable, and followed by [[BlockAllocator.completeCommit]].
    mtd publishDeferred()
    {
        for extent in .deferredFree do
            .releaseRun(extent.first, extent.count)
    }

    // Forgets the deferred extents [[BlockAllocator.publishDeferred]] has returned.
    mtd completeCommit() { .deferredFree.clear() }

    // Returns the number of blocks that are free now, deferred ones excluded.
    mtd freeBlockCount()->u64 => .freeBlocksCount
}
