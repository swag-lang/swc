impl Volume
{
    // Extends the container to `requestedSize` bytes and gives the new blocks to the free list.
    //
    // Growing writes nothing an existing block owns: the file is extended, the added region is
    // filled with random bytes like a fresh container, and only then does a checkpoint publish
    // the new geometry. Until that checkpoint lands, the header still describes the old size,
    // so an interruption at any point leaves a container that opens exactly as it did before.
    //
    // The fill dominates the call, so `progress` reports how far it has come and carries the
    // caller's cancellation, as in [[Volume.create]]. A stopped growth fails with `.Canceled`
    // and puts the file back to its previous length.
    //
    // Shrinking is [[Volume.shrink]], which first moves the blocks above the new end.
    mtd grow(requestedSize: u64, progress: *VolumeProgress? = null) fail
    {
        try .requireWritable()
        if .file.base or .file.protectedEnd do
            try failWith("Capacity changes are disabled for hidden or protected volumes.", .HiddenProtected)
        if progress and progress.isCanceled() do
            try failWith("Growing the container was canceled.", .Canceled)
        if requestedSize <= .containerSize do
            try failWith("A container can only grow.", .InvalidInput)

        let newBlockCount = (requestedSize - DataOffset) / BlockRecordSize
        if newBlockCount <= .blockCount do
            try failWith("The requested size does not add a single block.", .InvalidInput)

        // Everything below is undone by putting the file back to the length the durable header
        // already claims. `committed` is set on the last line, so every failure — including the
        // cancellation — unwinds through here.
        let previousSize       = .containerSize
        let previousPhysical   = .physicalSize
        let previousBlockCount = .blockCount
        let targetPhysical     = try camouflageSize(requestedSize)
        var previousFree: Array'FreeExtent
        previousFree.add(.blocks.free.toSlice())

        var committed = false
        defer
        {
            if not committed
            {
                .blocks.free   = #move previousFree
                .containerSize = previousSize
                .physicalSize  = previousPhysical
                .blockCount    = previousBlockCount
                discard catch .file.resize(previousPhysical)
            }
        }

        let addedPhysical = targetPhysical > previousPhysical ? targetPhysical - previousPhysical : 0
        progress?.setTotal(addedPhysical)
        if targetPhysical > previousPhysical
        {
            try .file.resize(targetPhysical)
            try .randomizeRange(previousPhysical, targetPhysical, progress, 0, "Growing the container was canceled.")
        }

        try .file.flush()
        .containerSize = requestedSize
        .physicalSize  = targetPhysical
        .blockCount    = newBlockCount
        .blocks.extend(previousBlockCount, newBlockCount - previousBlockCount)
        .scalarsDirty = true
        .dirty        = true
        try .checkpoint()

        committed = true
        if targetPhysical < previousPhysical
        {
            try .file.resize(targetPhysical)
            try .file.flush()
        }
    }

    // Chooses and authenticates a fresh random physical size while leaving the
    // logical capacity and every live block in place. It can be repeated on an
    // existing volume whenever its current file size has become identifying.
    mtd reapplyCamouflage(progress: *VolumeProgress? = null) fail
    {
        try .requireWritable()
        if .file.base or .file.protectedEnd do
            try failWith("Capacity changes are disabled for hidden or protected volumes.", .HiddenProtected)
        let previousPhysical = .physicalSize
        let targetPhysical   = try camouflageSize(.containerSize, previousPhysical)
        let addedPhysical    = targetPhysical > previousPhysical ? targetPhysical - previousPhysical : 0
        progress?.setTotal(addedPhysical)

        var committed = false
        defer
        {
            if not committed
            {
                .physicalSize = previousPhysical
                discard catch .file.resize(previousPhysical)
            }
        }

        if targetPhysical > previousPhysical
        {
            try .file.resize(targetPhysical)
            try .randomizeRange(previousPhysical, targetPhysical, progress, 0, "Camouflage refresh was canceled.")
            try .file.flush()
        }
        elif progress and progress.isCanceled()
        {
            try failWith("Camouflage refresh was canceled.", .Canceled)
        }

        .physicalSize = targetPhysical
        .scalarsDirty = true
        .dirty        = true
        try .checkpoint()
        committed = true

        if targetPhysical < previousPhysical
        {
            try .file.resize(targetPhysical)
            try .file.flush()
        }
    }

    // Changes the capacity in either direction, through [[Volume.grow]] or [[Volume.shrink]].
    mtd resize(requestedSize: u64, progress: *VolumeProgress? = null) fail
    {
        if requestedSize > .containerSize
        {
            try .grow(requestedSize, progress)
            return
        }

        try .shrink(requestedSize, progress)
    }

    // How many stored blocks lie at or past `limit`: the ones a shrink to `limit` blocks moves.
    mtd const blocksPast(limit: u64)->u64
    {
        var result = 0'u64
        for node in .nodes
        {
            for mapping in node.blocks
            {
                if mapping.physical >= limit do
                    result += mapping.count
                elif mapping.physical + mapping.count > limit do
                    result += mapping.physical + mapping.count - limit
            }
        }

        return result
    }

    // Moves the blocks of `node` stored at or past `limit` into free blocks below it, through the
    // `plain` buffer, and returns the progress total `moved` grown by the bytes it moved.
    mtd relocateBelow(node: *Node, limit: u64, plain: [..] u8, progress: *VolumeProgress?, moved: u64)->u64 fail
    {
        var result = moved
        var updated: Array'BlockMapping
        updated.reserve(node.blocks.count + 2)
        for mapping in node.blocks
        {
            var logical  = mapping.logical
            var physical = mapping.physical
            var count    = mapping.count

            if physical < limit
            {
                let kept = Math.min(count, limit - physical)
                updated.add({logical, physical, kept})
                logical  += kept
                physical += kept
                count    -= kept
            }

            while count
            {
                if progress and progress.isCanceled() do
                    try failWith("Resizing the container was canceled.", .Canceled)

                let destination = try .blocks.allocateRunBelow(limit, Math.min(count, MaximumIoBatchBlocks))
                let bytes       = destination.count * BlockSize
                try .readPhysicalRun(physical, plain[until bytes])
                try .writePhysicalRun(destination.first, plain[until bytes])
                updated.add({logical, destination.first, destination.count})

                logical  += destination.count
                physical += destination.count
                count    -= destination.count
                result   += bytes
                progress?.publish(result)
            }
        }

        node.blocks.clear()
        for mapping in updated do
            node.appendMapping(mapping[])
        return result
    }

    // Moves every live data block below the new end, checkpoints the smaller authenticated
    // geometry, then truncates the tail. Until the checkpoint lands, every old mapping and the
    // old file length remain valid; after it lands, an interrupted truncation is completed by
    // [[Volume.open]].
    mtd shrink(requestedSize: u64, progress: *VolumeProgress? = null) fail
    {
        try .requireWritable()
        if .file.base or .file.protectedEnd do
            try failWith("Capacity changes are disabled for hidden or protected volumes.", .HiddenProtected)
        if progress and progress.isCanceled() do
            try failWith("Resizing the container was canceled.", .Canceled)
        if requestedSize < MinimumSize do
            try failWith(Format.toString("The container must be at least % bytes.", MinimumSize), .SizeTooSmall)
        if requestedSize >= .containerSize do
            try failWith("Shrinking needs a smaller container size.", .InvalidInput)

        let newBlockCount = (requestedSize - DataOffset) / BlockRecordSize
        if newBlockCount >= .blockCount do
            try failWith("The requested size does not remove a single block.", .InvalidInput)

        // Start from one durable image. The relocation itself writes only into free blocks and
        // therefore changes nothing the active header can reach until the final checkpoint.
        try .checkpoint()

        var previousMaps: Array'BlockMapBackup
        previousMaps.reserve(.nodes.count)
        for node in .nodes
        {
            var backup: BlockMapBackup
            backup.blocks.add(node.blocks.toSlice())
            previousMaps.add(#move backup)
        }

        var previousFree: Array'FreeExtent
        previousFree.add(.blocks.free.toSlice())
        let previousFreeBlocksCount = .blocks.freeBlocksCount
        let previousSize            = .containerSize
        let previousPhysical        = .physicalSize
        let previousBlockCount      = .blockCount
        let targetPhysical          = try camouflageSize(requestedSize)

        var committed = false
        defer
        {
            if not committed
            {
                for &node, index in .nodes do
                    node.blocks = #move previousMaps[index].blocks
                .blocks.free   = #move previousFree
                .blocks.freeBlocksCount = previousFreeBlocksCount
                .containerSize = previousSize
                .physicalSize  = previousPhysical
                .blockCount    = previousBlockCount
                .scalarsDirty  = false
                .dirty         = false
                discard catch .file.resize(previousPhysical)
            }
        }

        let blocksToMove  = .blocksPast(newBlockCount)
        let addedPhysical = targetPhysical > previousPhysical ? targetPhysical - previousPhysical : 0
        progress?.setTotal(addedPhysical + blocksToMove * BlockSize)
        if targetPhysical > previousPhysical
        {
            try .file.resize(targetPhysical)
            try .randomizeRange(previousPhysical, targetPhysical, progress, 0, "Resizing the container was canceled.")
            try .file.flush()
        }

        var moved = addedPhysical
        var plain: Array'u8
        plain.resize(MaximumIoBatchBlocks * BlockSize)
        defer Core.Crypto.secureClear(plain.toSlice())

        for &node in .nodes do
            moved = try .relocateBelow(node, newBlockCount, plain.toSlice(), progress, moved)

        .containerSize = requestedSize
        .physicalSize  = targetPhysical
        .blockCount    = newBlockCount
        .blocks.trim(newBlockCount)
        .scalarsDirty = true
        .dirty        = true
        try .checkpoint()
        .blocks.trim(newBlockCount)

        // From this point the smaller geometry is durable. Leaving the physical tail in place on
        // a truncation error is recoverable and must not resurrect the old mappings in memory.
        committed = true
        try .file.resize(targetPhysical)
        try .file.flush()
    }
}
