impl Volume
{
    // Reads the data block stored at block `physical`.
    mtd readPhysical(physical: u64, destination: [..] u8) fail
    {
        try .readRecord(physical, DataKind, destination)
    }

    // Reads the logical block `logical` of a node; a block never written reads as zeros.
    mtd readBlock(node: *Node, logical: u64, destination: [..] u8) fail
    {
        Swag.memset(destination.buffer, 0, destination.count)
        let search = node.blockSearch(logical)
        if search.found
        {
            let mapping = node.blocks[search.index]
            try .readPhysical(mapping.physical + logical - mapping.logical, destination)
        }
    }

    // Reads consecutive data blocks from `physical` and decrypts them in parallel.
    mtd readPhysicalRun(physical: u64, destination: [..] u8) fail
    {
        Swag.assert(destination.count != 0 and destination.count % BlockSize == 0)
        let count = destination.count / BlockSize
        Swag.assert(count <= MaximumIoBatchBlocks)

        var records: Array'u8
        records.resize(count * BlockRecordSize)
        {
            Sync.scopedLock(&.ioLock)
            if not (try .file.readExactAt(DataOffset + physical * BlockRecordSize, records.toSlice())) do
                fail volumeError(.Io)
        }

        var batch = CryptoBatch{keys: &.keys, physical: physical, records: records.toSlice(), plain: destination}
        parallel for |&batch| parIndex in cast(u64, count)
        {
            let jobIndex     = cast(u32, parIndex)
            let index        = cast(u64, jobIndex)
            let recordOffset = index * BlockRecordSize
            let plainOffset  = index * BlockSize
            let nonce        = batch.records[recordOffset until recordOffset + Crypto.NonceSize]
            let ciphertext   = batch.records[recordOffset + Crypto.NonceSize until recordOffset + Crypto.NonceSize + BlockSize]
            let tag          = batch.records[recordOffset + Crypto.NonceSize + BlockSize until recordOffset + BlockRecordSize]
            let opened       = catch Crypto.open(batch.keys,
                                                 DataKind,
                                                 batch.physical + index,
                                                 nonce,
                                                 ciphertext,
                                                 tag,
                                                 batch.plain[plainOffset until plainOffset + BlockSize]) as openError
            batch.keepFirstError(openError)
            if openError == null and not opened do
                Atomic.add(&batch.invalidTags, 1)
        }

        try batch.error.raise()
        if batch.invalidTags do
            fail volumeError(.Corrupted)
    }

    // Encrypts consecutive data blocks in parallel, each under a fresh nonce, and writes them from
    // `physical`.
    mtd writePhysicalRun(physical: u64, source: const [..] u8) fail
    {
        Swag.assert(source.count != 0 and source.count % BlockSize == 0)
        let count = source.count / BlockSize
        Swag.assert(count <= MaximumIoBatchBlocks)

        var records: Array'u8
        records.resize(count * BlockRecordSize)
        try Core.Crypto.randomBytes(records.toSlice())

        var plain = Swag.makeSlice(cast #unconst ([*] u8, source.buffer), source.count)
        var batch = CryptoBatch{keys: &.keys, physical: physical, records: records.toSlice(), plain: plain}
        parallel for |&batch| parIndex in cast(u64, count)
        {
            let jobIndex     = cast(u32, parIndex)
            let index        = cast(u64, jobIndex)
            let recordOffset = index * BlockRecordSize
            let plainOffset  = index * BlockSize
            let nonce        = batch.records[recordOffset until recordOffset + Crypto.NonceSize]
            let ciphertext   = batch.records[recordOffset + Crypto.NonceSize until recordOffset + Crypto.NonceSize + BlockSize]
            let tag          = batch.records[recordOffset + Crypto.NonceSize + BlockSize until recordOffset + BlockRecordSize]
            discard catch Core.Crypto.chacha20Poly1305Seal(batch.keys.record,
                                                           nonce,
                                                           batch.plain[plainOffset until plainOffset + BlockSize],
                                                           Crypto.associatedData(DataKind, batch.physical + index),
                                                           ciphertext,
                                                           tag) as sealError
            batch.keepFirstError(sealError)
        }

        try batch.error.raise()

        Sync.scopedLock(&.ioLock)
        try .file.writeAllAt(DataOffset + physical * BlockRecordSize, records.toSlice())
    }

    // Replaces a logical range with one physical run and defers the old physical ranges until
    // the metadata commit makes the new mapping durable.
    mtd replaceBlockRun(node: *Node, logical, physical, count: u64)
    {
        Swag.assert(count != 0 and logical <= Swag.U64.Max - count)
        let end = logical + count
        var updated: Array'BlockMapping
        updated.reserve(node.blocks.count + 2)
        var inserted = false

        for mapping in node.blocks
        {
            let mappingEnd = mapping.logical + mapping.count
            if mappingEnd <= logical
            {
                updated.add(mapping[])
                continue
            }

            if mapping.logical >= end
            {
                if not inserted
                {
                    updated.add({logical, physical, count})
                    inserted = true
                }

                updated.add(mapping[])
                continue
            }

            if mapping.logical < logical do
                updated.add({mapping.logical, mapping.physical, logical - mapping.logical})

            let overlapFirst = Math.max(mapping.logical, logical)
            let overlapEnd   = Math.min(mappingEnd, end)
            .blocks.deferReleaseRun(mapping.physical + overlapFirst - mapping.logical, overlapEnd - overlapFirst)

            if mappingEnd > end
            {
                if not inserted
                {
                    updated.add({logical, physical, count})
                    inserted = true
                }

                updated.add({end, mapping.physical + end - mapping.logical, mappingEnd - end})
            }
        }

        if not inserted do
            updated.add({logical, physical, count})

        node.blocks.clear()
        for mapping in updated do
            node.appendMapping(mapping[])
    }

    // Writes one logical block of a node to a newly allocated block, and releases the allocation
    // when the write fails.
    mtd writeBlock(nodeId, logical: u64, source: const [..] u8) fail
    {
        Swag.assert(source.count == BlockSize)
        let allocated = try .blocks.allocateRun(1)
        let physical  = allocated.first
        var published = false
        defer
        {
            if not published do
                .blocks.release(physical)
        }

        try .writePhysicalRun(physical, source)

        let node = .nodeById(nodeId)!
        .replaceBlockRun(node, logical, physical, 1)
        .touch(nodeId)
        published = true
    }

    // Writes whole logical blocks of a node in batches of newly allocated runs.
    mtd writeFullBlocks(nodeId, logical: u64, source: const [..] u8) fail
    {
        Swag.assert(source.count != 0 and source.count % BlockSize == 0)
        var doneBlocks = 0'u64
        let blockCount = source.count / BlockSize
        while doneBlocks < blockCount
        {
            let requested = Math.min(blockCount - doneBlocks, MaximumIoBatchBlocks)
            let allocated = try .blocks.allocateRun(requested)
            var published = false
            defer
            {
                if not published do
                    .blocks.releaseRun(allocated.first, allocated.count)
            }

            let firstByte = doneBlocks * BlockSize
            let byteCount = allocated.count * BlockSize
            try .writePhysicalRun(allocated.first, source[firstByte until firstByte + byteCount])
            let node = .nodeById(nodeId)!
            .replaceBlockRun(node, logical + doneBlocks, allocated.first, allocated.count)
            .touch(nodeId)
            published  = true
            doneBlocks += allocated.count
        }
    }

    // Releases every block of a node at the next commit.
    mtd freeNodeBlocks(node: *Node)
    {
        for mapping in node.blocks do
            .blocks.deferReleaseRun(mapping.physical, mapping.count)
        node.blocks.clear()
        .touch(node.id)
    }

    // Releases, at the next commit, the blocks of a node past `newSize`.
    mtd trimNode(node: *Node, newSize: u64)
    {
        let keepBlocks = (newSize + BlockSize - 1) / BlockSize
        for index in reversed(node.blocks.count)
        {
            let mapping = node.blocks[index]
            if mapping.logical >= keepBlocks
            {
                .blocks.deferReleaseRun(mapping.physical, mapping.count)
                node.blocks.removeAtOrdered(index)
                continue
            }

            if mapping.logical + mapping.count > keepBlocks
            {
                let removed = mapping.logical + mapping.count - keepBlocks
                .blocks.deferReleaseRun(mapping.physical + mapping.count - removed, removed)
                node.blocks[index].count -= removed
            }

            break
        }

        .touch(node.id)
    }

    // Clears the bytes past the old end in the last block, so a file that grows never shows
    // what a shrink left there.
    mtd zeroOldTail(nodeId, oldSize, newSize: u64) fail
    {
        if newSize <= oldSize or oldSize % BlockSize == 0 do
            return
        let node    = .nodeById(nodeId)!
        let logical = oldSize / BlockSize
        let search  = node.blockSearch(logical)
        if not search.found do
            return
        var block: [BlockSize] u8
        defer Core.Crypto.secureClear(block)
        let mapping = node.blocks[search.index]
        try .readPhysical(mapping.physical + logical - mapping.logical, block)
        let end = Math.min(newSize, (logical + 1) * BlockSize)
        Swag.memset(&block[oldSize % BlockSize], 0, end - oldSize)
        try .writeBlock(nodeId, logical, block)
    }

    // Sets the size of a file: a longer file reads zeros past its old end, and a shorter one
    // releases the blocks it no longer reaches.
    mtd resizeNode(nodeId, newSize: u64) fail
    {
        try .requireWritable()
        let node = .nodeById(nodeId)!
        if node.isDirectory() do
            fail volumeError(.IsDirectory)
        let oldSize = node.size
        if newSize > oldSize do
            try .zeroOldTail(nodeId, oldSize, newSize)
        elif newSize < oldSize do
            .trimNode(node, newSize)
        let current = .nodeById(nodeId)!
        current.size          = newSize
        current.changeTime    = volumeTimeNow()
        current.lastWriteTime = current.changeTime
        .touch(nodeId)
    }

    // The node a file handle names; fails once the entry is gone.
    mtd fileNode(nodeId: u64)->*Node fail
    {
        let node = .nodeById(nodeId)
        if not node do
            fail volumeError(.NotFound)
        return node
    }

    // Reads from a file at `offset`, a run of whole blocks at a time where it can; returns the
    // bytes read.
    mtd readNode(nodeId: u64, offset: u64, destination: [..] u8)->u32 fail
    {
        let node = try .fileNode(nodeId)
        if node.isDirectory() do
            fail volumeError(.IsDirectory)
        if offset >= node.size or not destination.count do
            return 0

        let count = Math.min(destination.count, node.size - offset)
        var done  = 0'u64
        while done < count
        {
            let absolute = offset + done
            let logical  = absolute / BlockSize
            let inBlock  = absolute % BlockSize
            let chunk    = Math.min(count - done, BlockSize - inBlock)

            if not inBlock and chunk == BlockSize
            {
                let remainingBlocks = (count - done) / BlockSize
                let search = node.blockSearch(logical)
                if search.found
                {
                    let mapping       = node.blocks[search.index]
                    let mappingOffset = logical - mapping.logical
                    let batchBlocks   = Math.min(remainingBlocks, mapping.count - mappingOffset, MaximumIoBatchBlocks)
                    let batchBytes    = batchBlocks * BlockSize
                    try .readPhysicalRun(mapping.physical + mappingOffset, destination[done until done + batchBytes])
                    done += batchBytes
                    continue
                }

                let nextLogical = search.index < node.blocks.count ? node.blocks[search.index].logical : logical + remainingBlocks
                let holeBlocks  = Math.min(remainingBlocks, nextLogical - logical)
                let holeBytes   = holeBlocks * BlockSize
                Swag.memset(destination.buffer + done, 0, holeBytes)
                done += holeBytes
                continue
            }

            var block: [BlockSize] u8
            try .readBlock(node, logical, block)
            Swag.memcpy(destination.buffer + done, &block[inBlock], chunk)
            Core.Crypto.secureClear(block)
            done += chunk
        }

        return cast(u32, count)
    }

    // Writes to a file at `offset`, or at its end; a constrained write stays within the current
    // size. Returns the bytes written.
    mtd writeNode(nodeId: u64, offset: u64, source: const [..] u8, writeToEnd, constrained: bool)->u32 fail
    {
        try .requireWritable()
        let node = try .fileNode(nodeId)
        if node.isDirectory() do
            fail volumeError(.IsDirectory)
        if (node.attributes & FileAttributeReadOnly) != 0 do
            fail volumeError(.AccessDenied)

        var writeOffset = offset
        if writeToEnd do
            writeOffset = node.size
        var count = source.count
        if constrained
        {
            if writeOffset >= node.size do
                return 0
            count = Math.min(count, node.size - writeOffset)
        }

        if not count do
            return 0
        if writeOffset > Swag.U64.Max - count do
            fail volumeError(.InvalidInput)

        let oldSize = node.size
        let end     = writeOffset + count
        if not constrained and end > oldSize do
            try .zeroOldTail(nodeId, oldSize, end)

        var done = 0'u64
        while done < count
        {
            let absolute = writeOffset + done
            let logical  = absolute / BlockSize
            let inBlock  = absolute % BlockSize
            let chunk    = Math.min(count - done, BlockSize - inBlock)

            if not inBlock and chunk == BlockSize
            {
                let fullBytes = (count - done) / BlockSize * BlockSize
                try .writeFullBlocks(nodeId, logical, source[done until done + fullBytes])
                done += fullBytes
                continue
            }

            let current = .nodeById(nodeId)!
            var block: [BlockSize] u8
            if inBlock or chunk != BlockSize do
                try .readBlock(current, logical, block)
            Swag.memcpy(&block[inBlock], source.buffer + done, chunk)
            try .writeBlock(nodeId, logical, block)
            Core.Crypto.secureClear(block)
            done += chunk
        }

        let updated = .nodeById(nodeId)!
        if end > updated.size do
            updated.size = end
        let now = volumeTimeNow()
        updated.lastWriteTime = now
        updated.changeTime    = now
        updated.attributes    |= FileAttributeArchive
        .touch(nodeId)
        return cast(u32, count)
    }
}
