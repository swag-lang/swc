using Core

// Returns an unbiased cryptographically secure value in `[0, limit)`.
//
// Reducing every 64-bit value modulo `limit` would favor the first remainders unless the range
// divides 2^64. Rejecting that short prefix leaves an exact multiple of `limit` candidates.
private func secureRandomBelow(limit: u64)->u64 fail
{
    Debug.assert(limit != 0)
    let threshold = (Swag.U64.Max % limit + 1) % limit
    while true
    {
        var candidate: u64
        try Core.Crypto.randomBytes(@mkslice(cast([*] u8) &candidate, #sizeof(candidate)))
        if candidate >= threshold do
            return candidate % limit
    }
}

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

    // Adds the blocks `[first, first + count)` to the free list.
    //
    // A container only ever grows at its end, so the new blocks sit above every block that
    // exists: they either extend the last free extent or become one of their own. Nothing
    // else in the list can be touched by them.
    mtd extend(first, count: u64)
    {
        if !count do
            return

        if .free.count and .free.back().first + .free.back().count == first
        {
            .free.backPtr().count += count
            return
        }

        Debug.assert(!.free.count or .free.back().first + .free.back().count < first)
        .free.add({first, count})
    }

    // Removes the block at `offset` in the flattened free list.
    mtd allocateAtOffset(offset: u64)->u64
    {
        Debug.assert(offset < .freeBlockCount())
        var remaining = offset
        var index     = 0'u64
        while remaining >= .free[index].count
        {
            remaining -= .free[index].count
            index     += 1
        }

        let extent = .free[index]
        let result = extent.first + remaining
        if !remaining
        {
            .free[index].first += 1
            .free[index].count -= 1
            if !.free[index].count do
                .free.removeAtOrdered(index)
        }
        elif remaining + 1 == extent.count do
            .free[index].count -= 1
        else
        {
            .free[index].count = remaining
            .free.insertAt(index + 1, {result + 1, extent.count - remaining - 1})
        }

        return result
    }

    mtd allocate()->u64 fail
    {
        if !.free.count do
            failWith("The virtual disk is full.", .DiskFull)

        // Choose among blocks rather than extents: every free physical position has the same
        // probability, whatever fragmentation did to the shape of the free list.
        return .allocateAtOffset(try secureRandomBelow(.freeBlockCount()))
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
