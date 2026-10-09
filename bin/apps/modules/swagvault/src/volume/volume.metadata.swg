impl Volume
{
    // Reads and authenticates the header slot `slot`. An unusable slot comes back with `valid` false.
    mtd readHeader(slot: u32)->HeaderCandidate fail
    {
        var result: retval
        result.plain = try .readFramedRecord(HeaderAreaOffset + slot * HeaderSlotSize, HeaderSlotSize, HeaderLocatorKind, HeaderKind, slot, HeaderPlainSize)
        if result.plain.isEmpty() do
            return result

        let sequence = catch parseHeaderSequence(result.plain.toSlice()) as parseError
        if parseError != null do
            return result

        result.sequence = sequence
        result.valid    = true
        return result
    }

    // Serializes the volume header: the scalars, and the index of the blocks
    // that hold the metadata image. The node table itself is not here, which is
    // what removes the ceiling on how many files a container can hold.
    mtd serializeHeader()->Array'u8 fail
    {
        var result: retval
        var writer = ByteStream.openWrite(&result)

        writer.writeBytes(HeaderMagic)
        writer.writeLittleEndian(FormatVersion)
        writer.writeLittleEndian(.sequence)
        writer.writeLittleEndian(.containerSize)
        writer.writeLittleEndian(.blockCount)
        writer.writeLittleEndian(.nextNodeId)
        writer.writeSizedString(.label)
        writer.writeLittleEndian(.keySlotMask)
        writer.writeLittleEndian(.metadataSize)

        // The page index is stored as runs, so a container whose metadata sits
        // in one contiguous stretch costs a single record.
        var runCount = 0'u64
        var index    = 0'u64
        while index < .metadataPages.count
        {
            runCount += 1
            index    += .pageRunLength(index)
        }

        writer.writeLittleEndian(runCount)
        index = 0
        while index < .metadataPages.count
        {
            let count = .pageRunLength(index)
            writer.writeLittleEndian(.metadataPages[index])
            writer.writeLittleEndian(count)
            index += count
        }

        // The authenticated physical size separates the logical capacity from
        // the random camouflage tail.
        writer.writeLittleEndian(.physicalSize)

        if result.count > HeaderPlainSize do
            try failWith("The metadata page index no longer fits in the header.", .DiskFull)
        return result
    }

    // How many metadata pages, from `index`, are stored in consecutive blocks.
    mtd const pageRunLength(index: u64)->u64
    {
        var result = 1'u64
        while index + result < .metadataPages.count and
              .metadataPages[index + result] == .metadataPages[index] + result do
            result += 1
        return result
    }

    // Rebuilds the volume from a header, its metadata pages, and any journal
    // records written after the checkpoint that header describes.
    mtd restore(plain: const [..] u8) fail
    {
        var reader = ByteStream.openRead(plain)
        .sequence     = try readHeaderPrefix(&reader)
        .checkpointAt = .sequence
        if .sequence == Swag.U64.Max do
            try failWith("The container sequence can no longer advance.", .Corrupted)
        let actualSize = .physicalSize
        let storedSize = try reader.readLittleEndian'u64()
        .blockCount   = try reader.readLittleEndian'u64()
        .nextNodeId   = try reader.readLittleEndian'u64()
        .label        = try reader.readSizedString(MaximumLabelSize)
        .keySlotMask  = try reader.readLittleEndian'u32()
        .metadataSize = try reader.readLittleEndian'u64()
        if storedSize < MinimumSize or
           storedSize > actualSize or
           .blockCount != (storedSize - DataOffset) / BlockRecordSize do
            try failWith("The container geometry does not match its size.", .Corrupted)
        .containerSize = storedSize

        let expectedPages = (.metadataSize + BlockSize - 1) / BlockSize
        if expectedPages > .blockCount do
            try failWith("The metadata index is larger than the container.", .Corrupted)

        let runCount = try reader.readLittleEndian'u64()
        if runCount > expectedPages do
            try failWith("The metadata index declares an implausible number of runs.", .Corrupted)

        .metadataPages.reserve(expectedPages)
        for runCount
        {
            let first = try reader.readLittleEndian'u64()
            let count = try reader.readLittleEndian'u64()
            if not count or
               first >= .blockCount or
               count > .blockCount - first or
               count > expectedPages - .metadataPages.count do
                try failWith("A metadata page falls outside the container.", .Corrupted)
            for i in count do
                .metadataPages.add(first + i)
        }

        if .metadataPages.count != expectedPages do
            try failWith("The metadata index is incomplete.", .Corrupted)

        let storedPhysicalSize = try reader.readLittleEndian'u64()
        if storedPhysicalSize < storedSize or storedPhysicalSize > actualSize do
            try failWith("The container geometry does not match its size.", .Corrupted)
        .physicalSize = storedPhysicalSize

        var image: Array'u8
        defer Core.Crypto.secureClear(image.toSlice())
        image.resize(.metadataPages.count * BlockSize)
        for page, i in .metadataPages do
            try .readMetadataPage(page, image[i * BlockSize until (i + 1) * BlockSize])
        image.resize(.metadataSize)
        try .loadNodes(image.toSlice())

        // Reading the checkpoint back is not a change, so the volume starts clean here and the
        // replay is what decides: journal records above the checkpoint are precisely what is not
        // consolidated yet. Clearing this after the replay instead would tell a recovered volume
        // it has nothing to write, so its close would skip the checkpoint and the same records
        // would be replayed again on every open, forever.
        .dirty = false
        try .replayJournal()

        if .nodeById(RootNodeId) == null do
            try failWith("The container has no root directory.", .Corrupted)
        try .rebuildFreeList()
    }

    // Reads the node table out of a decrypted metadata image.
    mtd loadNodes(image: const [..] u8) fail
    {
        var reader    = ByteStream.openRead(image)
        let nodeCount = try reader.readLittleEndian'u64()
        if not nodeCount or nodeCount > MaximumNodeCount do
            try failWith("The container declares an implausible number of entries.", .Corrupted)

        .nodes.reserve(nodeCount)
        for nodeCount
        {
            let node      = try Node.deserialize(&reader, .blockCount)
            let nodeIndex = .nodes.count
            .nodes.add(#move node)
            if not .nodeLookup.add(&.nodes[nodeIndex], nodeIndex) do
                try failWith("The container contains a duplicate entry.", .Corrupted)
        }
    }

    // Derives the free list from what is actually referenced.
    //
    // Storing it would make the header grow with fragmentation, and would make
    // every journal record have to describe extents it does not own. The
    // complement of the referenced blocks is the same answer and cannot drift.
    mtd rebuildFreeList() fail
    {
        var used: BitArray
        used.resize(.blockCount)

        for page in .metadataPages
        {
            if page >= .blockCount do
                try failWith("A metadata page falls outside the container.", .Corrupted)
            used.set(page, true)
        }

        for node in .nodes
        {
            for mapping in node.blocks
            {
                if mapping.physical >= .blockCount or
                   not mapping.count or
                   mapping.count > .blockCount - mapping.physical do
                    try failWith("A block mapping falls outside the container.", .Corrupted)
                for physical in mapping.physical until mapping.physical + mapping.count do
                    used.set(physical, true)
            }
        }

        .blocks.rebuild(&used, .blockCount)
    }

    // Reads the record of block `physical` and decrypts it into `destination`, failing with
    // `damaged` when it was not sealed as a record of `kind` at that block.
    mtd readRecord(physical: u64, kind: u32, destination: [..] u8, damaged: string) fail
    {
        Swag.assert(destination.count == BlockSize)
        var record: [BlockRecordSize] u8
        {
            Sync.scopedLock(&.ioLock)
            if not (try .file.readExactAt(DataOffset + physical * BlockRecordSize, record)) do
                try failWith("The container is truncated or unreadable.", .Io)
        }

        let nonce      = record[0 until Crypto.NonceSize]
        let ciphertext = record[Crypto.NonceSize until Crypto.NonceSize + BlockSize]
        let tag        = record[Crypto.NonceSize + BlockSize until BlockRecordSize]
        if not (try Crypto.open(&.keys, kind, physical, nonce, ciphertext, tag, destination)) do
            try failWith(damaged, .Corrupted)
    }

    // Reads the metadata page stored at block `physical`.
    mtd readMetadataPage(physical: u64, destination: [..] u8) fail
    {
        try .readRecord(physical, MetadataPageKind, destination, "An encrypted metadata page is damaged.")
    }

    // Encrypts a metadata page under a fresh nonce and stores it at block `physical`.
    mtd writeMetadataPage(physical: u64, source: const [..] u8) fail
    {
        Swag.assert(source.count == BlockSize)
        var record: [BlockRecordSize] u8
        let nonce      = record[0 until Crypto.NonceSize]
        let ciphertext = record[Crypto.NonceSize until Crypto.NonceSize + BlockSize]
        let tag        = record[Crypto.NonceSize + BlockSize until BlockRecordSize]
        try Crypto.seal(&.keys, MetadataPageKind, physical, source, nonce, ciphertext, tag)
        Sync.scopedLock(&.ioLock)
        try .file.writeAllAt(DataOffset + physical * BlockRecordSize, record)
    }

    // Writes a full checkpoint: the metadata image into fresh pages, then the
    // header into whichever slot is not active.
    //
    // Nothing that the previous checkpoint still needs is released until the new
    // header is on disk, so an interrupted checkpoint leaves the previous one
    // entirely usable.
    mtd checkpoint() fail
    {
        try .requireWritable()
        if not .dirty do
            return

        var previousPages: Array'u64
        previousPages.add(.metadataPages.toSlice())
        var previousFree: Array'FreeExtent
        previousFree.add(.blocks.free.toSlice())
        let previousFreeBlocksCount = .blocks.freeBlocksCount

        var committed = false
        defer
        {
            if not committed
            {
                .blocks.free   = #move previousFree
                .blocks.freeBlocksCount = previousFreeBlocksCount
                .metadataPages = #move previousPages
            }
        }

        var image = .serializeNodes()
        defer Core.Crypto.secureClear(image.toSlice())
        let imageSize = image.count
        let pageCount = (imageSize + BlockSize - 1) / BlockSize
        image.resize(pageCount * BlockSize)

        // The pages are allocated before anything is released, so a checkpoint
        // never writes over a block the previous one still needs.
        var pages: Array'u64
        pages.reserve(pageCount)
        for pageCount do
            pages.add(try .blocks.allocate())

        for page, i in pages do
            try .writeMetadataPage(page, image[i * BlockSize until (i + 1) * BlockSize])

        .metadataPages = #move pages
        .metadataSize  = imageSize
        .sequence      += 1

        let slot  = 1'u32 - .activeSlot
        var plain = try .serializeHeader()
        defer Core.Crypto.secureClear(plain.toSlice())
        try .writeFramedRecord(HeaderAreaOffset + slot * HeaderSlotSize, HeaderSlotSize, HeaderLocatorKind, HeaderKind, slot, plain.toSlice())

        // The header is durable, so the blocks the previous checkpoint held can
        // finally go back to the free list.
        for page in previousPages do
            .blocks.release(page)
        .blocks.publishDeferred()
        .blocks.completeCommit()

        .checkpointAt = .sequence
        .activeSlot   = slot
        .clearPending()
        .dirty    = false
        committed = true
    }

    // Writes one locator-prefixed, sealed record into a fixed-size area.
    //
    // The locator is key-dependent, so the area carries no signature a scanner
    // could recognize, and the padding is random so two writes of the same
    // record never look alike.
    mtd writeFramedRecord(offset, area: u64, locatorKind, recordKind: u32, recordId: u64, plain: const [..] u8) fail
    {
        let used = HeaderRecordPrefixSize + plain.count + Crypto.TagSize
        if used > area do
            try failWith("A metadata record no longer fits its area.", .DiskFull)

        // Only the bytes the record occupies are written. The rest of the area
        // still holds the noise the container was created with, or an older
        // record's ciphertext, and rewriting it every time would cost a full
        // slot of random bytes per checkpoint for nothing.
        var record: Array'u8
        record.resize(used)

        var locator = try Crypto.recordLocator(.keys.locator, locatorKind, recordId)
        defer Core.Crypto.secureClear(locator)
        Swag.memcpy(record.buffer, &locator[0], HeaderLocatorCheckSize)
        Crypto.store32((record.buffer + HeaderLocatorCheckSize)!, cast(u32, plain.count) ^ Crypto.load32(&locator[HeaderLocatorCheckSize]))

        let nonce      = record[Crypto.RecordLocatorSize until HeaderRecordPrefixSize]
        let ciphertext = record[HeaderRecordPrefixSize until HeaderRecordPrefixSize + plain.count]
        let tag        = record[HeaderRecordPrefixSize + plain.count until used]
        try Crypto.seal(&.keys, recordKind, recordId, plain, nonce, ciphertext, tag)
        Sync.scopedLock(&.ioLock)
        try .file.writeAllAt(offset, record.toSlice())
        try .file.flush()
    }

    // Reads a record written by `writeFramedRecord`. An empty result means the
    // area holds no record for this key.
    mtd readFramedRecord(offset, _: u64, locatorKind, recordKind: u32, recordId, maximumPlain: u64)->Array'u8 fail
    {
        var result: retval

        var prefix: [Crypto.RecordLocatorSize] u8
        if not (try .file.readExactAt(offset, prefix)) do
            return result

        var locator = try Crypto.recordLocator(.keys.locator, locatorKind, recordId)
        defer Core.Crypto.secureClear(locator)
        if not Core.Crypto.constantTimeEqual(prefix[until HeaderLocatorCheckSize], locator[until HeaderLocatorCheckSize]) do
            return result

        let plainSize = Crypto.load32(&prefix[HeaderLocatorCheckSize]) ^ Crypto.load32(&locator[HeaderLocatorCheckSize])
        if not plainSize or plainSize > maximumPlain do
            return result

        var record: Array'u8
        record.resize(Crypto.NonceSize + plainSize + Crypto.TagSize)
        if not (try .file.readExactAt(offset + #sizeof(prefix), record.toSlice())) do
            return result

        var plain: Array'u8
        plain.resize(plainSize)
        let nonce      = record[0 until Crypto.NonceSize]
        let ciphertext = record[Crypto.NonceSize until Crypto.NonceSize + plainSize]
        let tag        = record[Crypto.NonceSize + plainSize until record.count]
        if not (try Crypto.open(&.keys, recordKind, recordId, nonce, ciphertext, tag, plain.toSlice())) do
            return result

        result = #move plain
        return result
    }

    // Serializes the node table. This is the only thing the metadata image
    // holds; the scalars live in the header and the free list is derived.
    mtd serializeNodes()->Array'u8
    {
        var result: retval
        var writer = ByteStream.openWrite(&result)
        writer.writeLittleEndian(.nodes.count)
        for node in .nodes do
            node.serialize(&writer)
        return result
    }

    // Records that `id` changed. The next `commit` folds every touched node into
    // one journal record.
    mtd touch(id: u64)
    {
        .dirty = true
        if .metadataTouchedSet.contains(id)
        {
            .metadataTouchedSet.remove(id)
            for value, i in .metadataTouched
            {
                if value == id
                {
                    .metadataTouched.removeAtOrdered(i)
                    break
                }
            }
        }

        if not .touchedSet.contains(id)
        {
            .touchedSet.add(id)
            .touched.add(id)
        }
    }

    // Records a namespace, attribute, or timestamp change without serializing the file's data map.
    mtd touchMetadata(id: u64)
    {
        .dirty = true
        if .touchedSet.contains(id) or .metadataTouchedSet.contains(id) do
            return
        .metadataTouchedSet.add(id)
        .metadataTouched.add(id)
    }

    // Records that `id` was deleted, and withdraws any pending change to it.
    mtd drop(id: u64)
    {
        .dirty = true
        if .touchedSet.contains(id)
        {
            .touchedSet.remove(id)
            for value, i in .touched
            {
                if value == id
                {
                    .touched.removeAtOrdered(i)
                    break
                }
            }
        }

        if .metadataTouchedSet.contains(id)
        {
            .metadataTouchedSet.remove(id)
            for value, i in .metadataTouched
            {
                if value == id
                {
                    .metadataTouched.removeAtOrdered(i)
                    break
                }
            }
        }

        .removed.add(id)
    }

    // Records that a volume-wide value changed, such as the label or the next
    // node identifier.
    mtd touchScalars()
    {
        .scalarsDirty = true
        .dirty        = true
    }

    // Forgets every pending change, once committed or abandoned.
    mtd clearPending()
    {
        .touched.clear()
        .touchedSet.clear()
        .metadataTouched.clear()
        .metadataTouchedSet.clear()
        .removed.clear()
        .scalarsDirty = false
    }

    mtd hasPendingChanges()->bool => not .touched.isEmpty() or
                                     not .metadataTouched.isEmpty() or
                                     not .removed.isEmpty() or
                                     .scalarsDirty

    // Makes every pending change durable.
    //
    // The common path appends one journal record, which is a single small write
    // whatever the size of the node table. A checkpoint happens only when the
    // journal is full, when the change is too large to fit one record, or when
    // the volume closes.
    mtd commit() fail
    {
        try .requireWritable()
        if not .dirty do
            return
        if not .hasPendingChanges() do
            return try .checkpoint()
        if .sequence - .checkpointAt >= JournalCapacity do
            return try .checkpoint()

        var upserted: Array'(*Node)
        upserted.reserve(.touched.count)
        for id in .touched
        {
            let node = .nodeById(id)
            if node do
                upserted.add(node)
        }

        var metadata: Array'(*Node)
        metadata.reserve(.metadataTouched.count)
        for id in .metadataTouched
        {
            let node = .nodeById(id)
            if node do
                metadata.add(node)
        }

        var plain = JournalRecord.encode(.sequence + 1, .nextNodeId, .label, .removed.toSlice(), upserted.toSlice(), metadata.toSlice())
        defer Core.Crypto.secureClear(plain.toSlice())

        // A change that does not fit one record is rare — a file with a very
        // fragmented block map, or a large security descriptor. Rewriting the
        // whole image is the honest answer rather than a second record format.
        if plain.count > JournalPlainSize do
            return try .checkpoint()

        let sequence = .sequence + 1
        try .writeFramedRecord(JournalAreaOffset + (sequence % JournalCapacity) * JournalRecordSize, JournalRecordSize, JournalLocatorKind, JournalKind, sequence % JournalCapacity, plain.toSlice())
        .sequence = sequence

        // The record that dropped these blocks is durable, so they are genuinely
        // unreferenced now. Holding them back until the next checkpoint would
        // make a busy volume report itself full while it still has room.
        .blocks.publishDeferred()
        .blocks.completeCommit()
        .clearPending()
    }

    // Applies the consecutive journal records written after the checkpoint that was just loaded.
    //
    // A sequence owns `sequence % JournalCapacity`, so replay starts at the one slot that can
    // follow the checkpoint and stops at the first missing, damaged, stale, or misplaced record.
    // Besides rejecting a record in the wrong slot, this keeps a clean mount from decrypting all
    // 256 stale records left behind by earlier checkpoints.
    mtd replayJournal() fail
    {
        #static if #command == Swag.CompilerCommand.Test do
            .journalRecordsRead = 0

        var expected = .checkpointAt + 1
        for JournalCapacity
        {
            let slot = expected % JournalCapacity
            #static if #command == Swag.CompilerCommand.Test do
                .journalRecordsRead += 1

            let plain = try .readFramedRecord(JournalAreaOffset + slot * JournalRecordSize, JournalRecordSize, JournalLocatorKind, JournalKind, slot, JournalPlainSize)
            if plain.isEmpty() do
                break

            var record = catch JournalRecord.decode(plain.toSlice(), .blockCount) as decodeError
            if decodeError != null or record.sequence != expected do
                break
            if record.sequence == Swag.U64.Max do
                try failWith("The container sequence can no longer advance.", .Corrupted)
            try .applyJournal(record)
            .sequence = record.sequence
            expected  += 1
        }

        .dirty = .sequence != .checkpointAt
    }

    // Replays one journal record: removes, replaces, and patches the nodes it names.
    mtd applyJournal(record: const *JournalRecord) fail
    {
        for id in record.removed
        {
            let index = .nodeIndex(id)
            if index != Swag.U64.Max do
                .removeNodeAt(index)
        }

        for node in record.upserted
        {
            let index = .nodeIndex(node.id)
            if index != Swag.U64.Max do
                .removeNodeAt(index)

            var copy   = node[]
            let target = .nodes.count
            .nodes.add(#move copy)
            if not .nodeLookup.add(&.nodes[target], target) do
                try failWith("A journal record contains a duplicate entry.", .Corrupted)
        }

        for patch in record.metadata
        {
            let node = .nodeById(patch.id)
            if not node do
                try failWith("A journal metadata change names an entry that does not exist.", .Corrupted)
            let validNode = node!
            if patch.id != RootNodeId
            {
                let parent = .nodeById(patch.parentId)
                if not parent or
                   not parent.isDirectory() or
                   not .nodeLookup.changeParent(validNode, patch.parentId, patch.name) do
                    try failWith("A journal metadata change has an invalid destination.", .Corrupted)
            }

            validNode.attributes     = patch.attributes
            validNode.creationTime   = patch.creationTime
            validNode.lastAccessTime = patch.lastAccessTime
            validNode.lastWriteTime  = patch.lastWriteTime
            validNode.changeTime     = patch.changeTime
        }

        .nextNodeId = record.nextNodeId
        .label      = record.label
    }
}
