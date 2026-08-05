using Core

// Serialized timestamps use 100-nanosecond ticks since 1601-01-01 UTC.
// Keeping the epoch in the format layer preserves compatibility with existing volumes.
const VolumeTimestampEpoch = 504_911_232_000_000_000'u64

func volumeTimeNow()->u64
{
    return Time.Timestamp.utcNow().ticks - VolumeTimestampEpoch
}

const FileAttributeReadOnly  = 0x00000001'u32
const FileAttributeDirectory = 0x00000010'u32
const FileAttributeArchive   = 0x00000020'u32
const FileAttributeNormal    = 0x00000080'u32

#[Swag.NoCopy]
struct Volume
{
    file:          File.FileStream
    keys:          Crypto.Keys
    master:        [Crypto.MasterKeySize] u8
    path:          String
    label:         String
    containerSize: u64
    blockCount:    u64
    sequence:      u64                  // Sequence of the last durable change, checkpoint or journal record.
    checkpointAt:  u64                  // Sequence of the last checkpoint; journal records above it are live.
    nextNodeId:    u64
    activeSlot:    u32
    keySlotMask:   u32                  // Which key slots hold a password; kept in the encrypted header, never in the slot area.
    metadataPages: Array'u64            // Physical blocks holding the metadata image, in order.
    metadataSize:  u64                  // Exact byte count of that image.
    nodes:         Array'Node
    nodeLookup:    NodeIndex
    blocks:        BlockAllocator
    touched:       Array'u64            // Nodes changed since the last journal record.
    touchedSet:    HashSet'u64
    removed:       Array'u64            // Nodes deleted since the last journal record.
    scalarsDirty:  bool                 // Whether a scalar such as the label or the next identifier changed.
    dirty:         bool                 // Whether anything at all is not yet in a checkpoint.
}

impl Volume
{
    mtd close()
    {
        if .file.isOpen()
        {
            discard catch .checkpoint()
            .file.close()
        }

        .dirty = false
        .keys.clear()
        Core.Crypto.secureClear(.master)
    }

    mtd opDrop()
    {
        .close()
    }

    func create(path: string, password: const [..] u8, requestedSize: u64)->Volume fail
    {
        if !@countof(password) do
            failWith("A password is required.", .InvalidInput)
        if requestedSize < MinimumSize do
            failWith(Format.toString("The container must be at least % bytes.", MinimumSize), .InvalidInput)

        var result: retval
        var created   = false
        var completed = false

        // `completed` is set only on the last line, so any failure below unwinds
        // everything and leaves no half-written container on disk.
        defer
        {
            if !completed
            {
                result.close()
                if created do
                    discard catch File.delete(path)
            }
        }

        with result
        {
            .dirty         = false
            .activeSlot    = 0
            .sequence      = 0
            .checkpointAt  = 0
            .path          = path
            .containerSize = requestedSize
            .blockCount    = (requestedSize - DataOffset) / BlockRecordSize
            .nextNodeId    = RootNodeId + 1
            .label         = "sCrypt"
        }

        result.file = File.open(path, .CreateNew, .ReadWrite, .Read)
        created     = true
        result.file.resize(requestedSize)

        // Fill the whole container with random bytes before anything real is
        // written. Encrypted blocks are indistinguishable from random, so this is
        // what stops an observer from telling which blocks are in use, or how
        // much of the container holds data. It also leaves every unused key slot
        // and journal record filled with noise.
        var randomChunk: Array'u8
        randomChunk.resize(RandomizeChunkSize)
        var offset = 0'u64
        while offset < requestedSize
        {
            let count = Math.min(requestedSize - offset, randomChunk.count)
            Core.Crypto.randomBytes(randomChunk[0 until count])
            result.file.writeAllAt(offset, randomChunk[0 until count])
            offset += count
        }

        Core.Crypto.secureClear(randomChunk.toSlice())

        // The master key is drawn once and never derived. A password only ever
        // unwraps it, which is what makes changing a password cheap.
        Core.Crypto.randomBytes(result.master)
        result.keys        = try Crypto.deriveKeys(result.master)
        result.keySlotMask = keySlotBit(0)
        try result.writeKeySlot(0, password, .Moderate)

        // The root directory is its own parent, which ends every path walk.
        let now = volumeTimeNow()
        with var root: Node
        {
            .id             = RootNodeId
            .parentId       = RootNodeId
            .name           = ""
            .attributes     = FileAttributeDirectory
            .creationTime   = now
            .lastAccessTime = now
            .lastWriteTime  = now
            .changeTime     = now
        }

        result.nodes.add(#move root)
        let rootIndexed = result.nodeLookup.add(&result.nodes[0], 0)
        Debug.assert(rootIndexed)

        result.blocks.initialize(result.blockCount)
        result.dirty = true
        result.checkpoint()

        completed = true
        return result
    }

    func open(path: string, password: const [..] u8)->Volume fail
    {
        if !@countof(password) do
            failWith("A password is required.", .InvalidInput)

        var result: retval
        result.dirty = false
        result.path  = path
        result.file  = File.open(path, .Open, .ReadWrite, .Read)
        var completed = false
        defer
        {
            if !completed do
                result.close()
        }

        result.containerSize = result.file.size()
        if result.containerSize < MinimumSize do
            failWith("The password is incorrect or the container is damaged.", .Corrupted)
        result.blockCount = (result.containerSize - DataOffset) / BlockRecordSize

        try result.unlock(password)

        var first = try result.readHeader(0)
        defer Core.Crypto.secureClear(first.plain.toSlice())
        var second = try result.readHeader(1)
        defer Core.Crypto.secureClear(second.plain.toSlice())
        var selected: #null *HeaderCandidate
        if first.valid and second.valid do
            selected = first.sequence >= second.sequence ? &first : &second
        elif first.valid do
            selected = &first
        elif second.valid do
            selected = &second
        else do
            failWith("The password is incorrect or the container is damaged.", .Corrupted)

        let validHeader = selected!
        result.activeSlot = validHeader == &first ? 0 : 1

        // Every way the metadata can be rejected reports the same thing: a
        // caller must not be able to tell a wrong password from a damaged
        // container, from an older format version, or from which field gave up
        // first.
        discard catch result.restore(validHeader.plain.toSlice()) as parseError
        if parseError != null do
            failWith("The password is incorrect or the container is damaged.", .Corrupted)

        completed = true
        return result
    }

    // Finds the key slot `password` opens and unwraps the master key from it.
    //
    // Every slot costs one full derivation whether or not it holds a password,
    // so the time taken never says how many passwords a container has.
    mtd unlock(password: const [..] u8) fail
    {
        var area: [KeySlotAreaSize] u8
        defer Core.Crypto.secureClear(area)
        if !.file.readExactAt(KeySlotAreaOffset, area) do
            failWith("The password is incorrect or the container is damaged.", .Corrupted)

        for [index] in KeySlotCount
        {
            var slot = KeySlot.decode(area[index * KeySlotSize until (index + 1) * KeySlotSize])
            defer slot.clear()
            if try slot.unwrap(password, index, .master)
            {
                .keys = try Crypto.deriveKeys(.master)
                return
            }
        }

        failWith("The password is incorrect or the container is damaged.", .Corrupted)
    }

    // Writes the key slot at `index` so that `password` unwraps the master key.
    mtd writeKeySlot(index: u64, password: const [..] u8, profile: Crypto.Argon2Profile) fail
    {
        var slot = try KeySlot.create(password, .master, profile, index)
        defer slot.clear()
        let record = try slot.encode()
        .file.writeAllAt(KeySlotAreaOffset + index * KeySlotSize, record)
        .file.flush()
    }

    // Overwrites the key slot at `index` with random bytes, so the password it
    // held no longer opens the container.
    mtd eraseKeySlot(index: u64) fail
    {
        var record: [KeySlotSize] u8
        Core.Crypto.randomBytes(record)
        .file.writeAllAt(KeySlotAreaOffset + index * KeySlotSize, record)
        .file.flush()
    }

    // Reports which slot `password` opens, or `Swag.U64.Max` when none does.
    mtd findKeySlot(password: const [..] u8)->u64 fail
    {
        var area: [KeySlotAreaSize] u8
        defer Core.Crypto.secureClear(area)
        if !.file.readExactAt(KeySlotAreaOffset, area) do
            return Swag.U64.Max

        var candidate: [Crypto.MasterKeySize] u8
        defer Core.Crypto.secureClear(candidate)
        for [index] in KeySlotCount
        {
            var slot = KeySlot.decode(area[index * KeySlotSize until (index + 1) * KeySlotSize])
            defer slot.clear()
            if try slot.unwrap(password, index, candidate) do
                return index
        }

        return Swag.U64.Max
    }

    // Replaces the password of the slot `current` opens.
    //
    // This rewrites one key slot and nothing else: the master key, and therefore
    // every encrypted block in the container, is untouched.
    mtd changePassword(current, replacement: const [..] u8, profile = Crypto.Argon2Profile.Moderate) fail
    {
        if !@countof(replacement) do
            failWith("A password is required.", .InvalidInput)
        let index = try .findKeySlot(current)
        if index == Swag.U64.Max do
            failWith("The current password is incorrect.", .AccessDenied)
        try .writeKeySlot(index, replacement, profile)
    }

    // Adds `additional` as another password that opens this container.
    //
    // Which slots are in use cannot be read from the slot area itself: an unused
    // slot and a slot whose password is unknown are the same random bytes, which
    // is exactly the property that hides how many passwords exist. The container
    // therefore keeps the record in its encrypted header instead.
    mtd addPassword(additional: const [..] u8, profile = Crypto.Argon2Profile.Moderate)->u64 fail
    {
        if !@countof(additional) do
            failWith("A password is required.", .InvalidInput)
        if (try .findKeySlot(additional)) != Swag.U64.Max do
            failWith("That password already opens this container.", .AlreadyExists)

        for [index] in KeySlotCount
        {
            if (.keySlotMask & keySlotBit(index)) != 0 do
                continue

            // The slot is reserved before it is written, so an interrupted add
            // wastes a slot instead of letting a later one overwrite a password
            // that already works.
            .keySlotMask |= keySlotBit(index)
            .scalarsDirty = true
            .dirty        = true
            try .checkpoint()
            try .writeKeySlot(index, additional, profile)
            return index
        }

        failWith("Every key slot is already in use.", .DiskFull)
    }

    // Removes the password that opens a slot.
    //
    // The last remaining password cannot be removed: a container no password
    // opens is unrecoverable, and there is no reason to offer that.
    mtd removePassword(password: const [..] u8) fail
    {
        let index = try .findKeySlot(password)
        if index == Swag.U64.Max do
            failWith("That password does not open this container.", .NotFound)
        if .keySlotCount() <= 1 do
            failWith("The last password cannot be removed.", .AccessDenied)

        try .eraseKeySlot(index)
        .keySlotMask &= ~keySlotBit(index)
        .scalarsDirty = true
        .dirty        = true
        try .checkpoint()
    }

    // Number of passwords that currently open this container.
    mtd const keySlotCount()->u64 => @bitcountnz(.keySlotMask)

    mtd readHeader(slot: u32)->HeaderCandidate fail
    {
        var result: retval
        result.plain = try .readFramedRecord(HeaderAreaOffset + slot * HeaderSlotSize, HeaderSlotSize, HeaderLocatorKind, HeaderKind, slot, HeaderPlainSize)
        if !result.plain.count do
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

        if result.count > HeaderPlainSize do
            failWith("The metadata page index no longer fits in the header.", .DiskFull)
        return result
    }

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

        var magic: [#sizeof(HeaderMagic)] u8
        reader.readBytes(&magic[0], #sizeof(magic))
        if @memcmp(&magic[0], &HeaderMagic[0], #sizeof(magic)) != 0 do
            failWith("The container does not start with an sCrypt header.", .Corrupted)

        let version = reader.readLittleEndian'u32()
        if version != FormatVersion do
            failWith("The container format version is not supported.", .Corrupted)

        .sequence   = reader.readLittleEndian'u64()
        .checkpointAt = .sequence
        let storedSize = reader.readLittleEndian'u64()
        .blockCount   = reader.readLittleEndian'u64()
        .nextNodeId   = reader.readLittleEndian'u64()
        .label        = reader.readSizedString(MaximumLabelSize)
        .keySlotMask  = reader.readLittleEndian'u32()
        .metadataSize = reader.readLittleEndian'u64()
        if storedSize != .containerSize or .blockCount != (.containerSize - DataOffset) / BlockRecordSize do
            failWith("The container geometry does not match its size.", .Corrupted)

        let expectedPages = (.metadataSize + BlockSize - 1) / BlockSize
        if expectedPages > .blockCount do
            failWith("The metadata index is larger than the container.", .Corrupted)

        let runCount = reader.readLittleEndian'u64()
        if runCount > expectedPages do
            failWith("The metadata index declares an implausible number of runs.", .Corrupted)

        .metadataPages.reserve(expectedPages)
        for runCount
        {
            let first = reader.readLittleEndian'u64()
            let count = reader.readLittleEndian'u64()
            if !count or first >= .blockCount or count > .blockCount - first or count > expectedPages - .metadataPages.count do
                failWith("A metadata page falls outside the container.", .Corrupted)
            for [i] in count do
                .metadataPages.add(first + i)
        }

        if .metadataPages.count != expectedPages do
            failWith("The metadata index is incomplete.", .Corrupted)

        var image: Array'u8
        defer Core.Crypto.secureClear(image.toSlice())
        image.resize(.metadataPages.count * BlockSize)
        for page, [i] in .metadataPages do
            try .readMetadataPage(page, image[i * BlockSize until (i + 1) * BlockSize])
        image.resize(.metadataSize)
        try .loadNodes(image.toSlice())

        try .replayJournal()

        if .nodeById(RootNodeId) == null do
            failWith("The container has no root directory.", .Corrupted)
        try .rebuildFreeList()
        .dirty = false
    }

    // Reads the node table out of a decrypted metadata image.
    mtd loadNodes(image: const [..] u8) fail
    {
        var reader = ByteStream.openRead(image)
        let nodeCount = reader.readLittleEndian'u64()
        if !nodeCount or nodeCount > MaximumNodeCount do
            failWith("The container declares an implausible number of entries.", .Corrupted)

        .nodes.reserve(nodeCount)
        for nodeCount
        {
            let node = try Node.deserialize(&reader, .blockCount)
            let nodeIndex = .nodes.count
            .nodes.add(#move node)
            if !.nodeLookup.add(&.nodes[nodeIndex], nodeIndex) do
                failWith("The container contains a duplicate entry.", .Corrupted)
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
                failWith("A metadata page falls outside the container.", .Corrupted)
            used.set(page, true)
        }

        for node in .nodes
        {
            for mapping in node.blocks
            {
                if mapping.physical >= .blockCount do
                    failWith("A block mapping falls outside the container.", .Corrupted)
                used.set(mapping.physical, true)
            }
        }

        .blocks.rebuild(&used, .blockCount)
    }

    mtd readMetadataPage(physical: u64, destination: [..] u8) fail
    {
        Debug.assert(@countof(destination) == BlockSize)
        var record: [BlockRecordSize] u8
        if !.file.readExactAt(DataOffset + physical * BlockRecordSize, record) do
            failWith("The container is truncated or unreadable.", .Io)
        let nonce      = record[0 until Crypto.NonceSize]
        let ciphertext = record[Crypto.NonceSize until Crypto.NonceSize + BlockSize]
        let tag        = record[Crypto.NonceSize + BlockSize until BlockRecordSize]
        if !(try Crypto.open(&.keys, MetadataPageKind, physical, nonce, ciphertext, tag, destination)) do
            failWith("An encrypted metadata page is damaged.", .Corrupted)
    }

    mtd writeMetadataPage(physical: u64, source: const [..] u8) fail
    {
        Debug.assert(@countof(source) == BlockSize)
        var record: [BlockRecordSize] u8
        let nonce      = record[0 until Crypto.NonceSize]
        let ciphertext = record[Crypto.NonceSize until Crypto.NonceSize + BlockSize]
        let tag        = record[Crypto.NonceSize + BlockSize until BlockRecordSize]
        try Crypto.seal(&.keys, MetadataPageKind, physical, source, nonce, ciphertext, tag)
        .file.writeAllAt(DataOffset + physical * BlockRecordSize, record)
    }

    // Writes a full checkpoint: the metadata image into fresh pages, then the
    // header into whichever slot is not active.
    //
    // Nothing that the previous checkpoint still needs is released until the new
    // header is on disk, so an interrupted checkpoint leaves the previous one
    // entirely usable.
    mtd checkpoint() fail
    {
        if !.dirty do
            return

        var previousPages: Array'u64
        previousPages.add(.metadataPages.toSlice())
        var previousFree: Array'FreeExtent
        previousFree.add(.blocks.free.toSlice())

        var committed = false
        defer
        {
            if !committed
            {
                .blocks.free   = #move previousFree
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
        for [i] in pageCount do
            pages.add(try .blocks.allocate())

        for page, [i] in pages do
            try .writeMetadataPage(page, image[i * BlockSize until (i + 1) * BlockSize])

        .metadataPages = #move pages
        .metadataSize  = imageSize
        .sequence     += 1

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
        .activeSlot = slot
        .clearPending()
        .dirty      = false
        committed   = true
    }

    // Writes one locator-prefixed, sealed record into a fixed-size area.
    //
    // The locator is key-dependent, so the area carries no signature a scanner
    // could recognize, and the padding is random so two writes of the same
    // record never look alike.
    mtd writeFramedRecord(offset, area: u64, locatorKind, recordKind: u32, recordId: u64, plain: const [..] u8) fail
    {
        let used = HeaderRecordPrefixSize + @countof(plain) + Crypto.TagSize
        if used > area do
            failWith("A metadata record no longer fits its area.", .DiskFull)

        // Only the bytes the record occupies are written. The rest of the area
        // still holds the noise the container was created with, or an older
        // record's ciphertext, and rewriting it every time would cost a full
        // slot of random bytes per checkpoint for nothing.
        var record: Array'u8
        record.resize(used)

        var locator = try Crypto.recordLocator(.keys.locator, locatorKind, recordId)
        defer Core.Crypto.secureClear(locator)
        @memcpy(record.buffer, &locator[0], HeaderLocatorCheckSize)
        Crypto.store32((record.buffer + HeaderLocatorCheckSize)!, cast(u32) @countof(plain) ^ Crypto.load32(&locator[HeaderLocatorCheckSize]))

        let nonce      = record[Crypto.RecordLocatorSize until HeaderRecordPrefixSize]
        let ciphertext = record[HeaderRecordPrefixSize until HeaderRecordPrefixSize + @countof(plain)]
        let tag        = record[HeaderRecordPrefixSize + @countof(plain) until used]
        try Crypto.seal(&.keys, recordKind, recordId, plain, nonce, ciphertext, tag)
        .file.writeAllAt(offset, record.toSlice())
        .file.flush()
    }

    // Reads a record written by `writeFramedRecord`. An empty result means the
    // area holds no record for this key.
    mtd readFramedRecord(offset, area: u64, locatorKind, recordKind: u32, recordId, maximumPlain: u64)->Array'u8 fail
    {
        var result: retval

        var prefix: [Crypto.RecordLocatorSize] u8
        if !.file.readExactAt(offset, prefix) do
            return result

        var locator = try Crypto.recordLocator(.keys.locator, locatorKind, recordId)
        defer Core.Crypto.secureClear(locator)
        if !Core.Crypto.constantTimeEqual(prefix[until HeaderLocatorCheckSize], locator[until HeaderLocatorCheckSize]) do
            return result

        let plainSize = Crypto.load32(&prefix[HeaderLocatorCheckSize]) ^ Crypto.load32(&locator[HeaderLocatorCheckSize])
        if !plainSize or plainSize > maximumPlain do
            return result

        var record: Array'u8
        record.resize(Crypto.NonceSize + plainSize + Crypto.TagSize)
        if !.file.readExactAt(offset + #sizeof(prefix), record.toSlice()) do
            return result

        var plain: Array'u8
        plain.resize(plainSize)
        let nonce      = record[0 until Crypto.NonceSize]
        let ciphertext = record[Crypto.NonceSize until Crypto.NonceSize + plainSize]
        let tag        = record[Crypto.NonceSize + plainSize until @countof(record)]
        if !(try Crypto.open(&.keys, recordKind, recordId, nonce, ciphertext, tag, plain.toSlice())) do
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
        if !.touchedSet.contains(id)
        {
            .touchedSet.add(id)
            .touched.add(id)
        }
    }

    // Records that `id` was deleted, and withdraws any pending change to it.
    mtd drop(id: u64)
    {
        .dirty = true
        if .touchedSet.contains(id)
        {
            .touchedSet.remove(id)
            for value, [i] in .touched
            {
                if value == id
                {
                    .touched.removeAtOrdered(i)
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

    mtd clearPending()
    {
        .touched.clear()
        .touchedSet.clear()
        .removed.clear()
        .scalarsDirty = false
    }

    // Makes every pending change durable.
    //
    // The common path appends one journal record, which is a single small write
    // whatever the size of the node table. A checkpoint happens only when the
    // journal is full, when the change is too large to fit one record, or when
    // the volume closes.
    mtd commit() fail
    {
        if !.dirty do
            return
        if !.touched.count and !.removed.count and !.scalarsDirty do
            return .checkpoint()
        if .sequence - .checkpointAt >= JournalCapacity do
            return .checkpoint()

        var upserted: Array'(*Node)
        upserted.reserve(.touched.count)
        for id in .touched
        {
            let node = .nodeById(id)
            if node do
                upserted.add(node!)
        }

        let plain = JournalRecord.encode(.sequence + 1, .nextNodeId, .label, .removed.toSlice(), upserted.toSlice())
        defer Core.Crypto.secureClear(plain.toSlice())

        // A change that does not fit one record is rare — a file with a very
        // fragmented block map, or a large security descriptor. Rewriting the
        // whole image is the honest answer rather than a second record format.
        if plain.count > JournalPlainSize do
            return .checkpoint()

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

    // Applies every journal record written after the checkpoint that was just
    // loaded.
    //
    // A slot holds a live record when it authenticates and its sequence is above
    // the checkpoint. Replay stops at the first missing sequence, because a
    // torn write means that operation never completed.
    mtd replayJournal() fail
    {
        var pending: Array'JournalRecord
        for [slot] in JournalCapacity
        {
            let plain = try .readFramedRecord(JournalAreaOffset + slot * JournalRecordSize, JournalRecordSize, JournalLocatorKind, JournalKind, slot, JournalPlainSize)
            if !plain.count do
                continue

            var record = catch JournalRecord.decode(plain.toSlice(), .blockCount) as decodeError
            if decodeError != null do
                continue
            if record.sequence <= .checkpointAt do
                continue
            pending.add(#move record)
        }

        if !pending.count do
            return

        pending.sort(func(left, right) => left.sequence < right.sequence ? -1 : left.sequence > right.sequence ? 1 : 0)

        var expected = .checkpointAt + 1
        for record in pending
        {
            if record.sequence != expected do
                break
            try .applyJournal(record)
            .sequence = record.sequence
            expected += 1
        }

        .dirty = .sequence != .checkpointAt
    }

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

            var copy = node
            let target = .nodes.count
            .nodes.add(#move copy)
            if !.nodeLookup.add(&.nodes[target], target) do
                failWith("A journal record contains a duplicate entry.", .Corrupted)
        }

        .nextNodeId = record.nextNodeId
        .label      = record.label
    }

    mtd nodeById(id: u64)->#null *Node
    {
        let index = .nodeLookup.nodePosition(id)
        return index != Swag.U64.Max ? &.nodes[index] : null
    }

    mtd findChild(parentId: u64, name: string)->#null *Node
    {
        let id = .nodeLookup.childId(parentId, name)
        return id != Swag.U64.Max ? .nodeById(id) : null
    }

    mtd resolve(path: string)->#null *Node
    {
        let parts   = Tokenize.split(path, cast(u8) '\\', removeEmpty: true)
        var current = .nodeById(1)
        if !current do
            return null
        for part in parts
        {
            current = .findChild(current!.id, part)
            if !current do
                return null
        }

        return current
    }

    mtd resolveParent(path: string)->{parent: #null *Node, name: string}
    {
        let parts = Tokenize.split(path, cast(u8) '\\', removeEmpty: true)
        if !parts.count do
            return {null, ""}
        var parent = .nodeById(1)
        if !parent do
            return {null, parts[parts.count - 1]}
        for [i] in 0 until parts.count - 1
        {
            parent = .findChild(parent!.id, parts[i])
            if !parent or !parent!.isDirectory() do
                return {null, parts[parts.count - 1]}
        }

        return {parent, parts[parts.count - 1]}
    }

    mtd readPhysical(physical: u64, destination: [..] u8) fail
    {
        Debug.assert(@countof(destination) == BlockSize)
        var record: [BlockRecordSize] u8
        if !.file.readExactAt(DataOffset + physical * BlockRecordSize, record) do
            failWith("The container is truncated or unreadable.", .Io)
        let nonce      = record[0 until Crypto.NonceSize]
        let ciphertext = record[Crypto.NonceSize until Crypto.NonceSize + BlockSize]
        let tag        = record[Crypto.NonceSize + BlockSize until BlockRecordSize]
        if !(try Crypto.open(&.keys, DataKind, physical, nonce, ciphertext, tag, destination)) do
            failWith("An encrypted data block is damaged.", .Corrupted)
    }

    mtd readBlock(node: *Node, logical: u64, destination: [..] u8) fail
    {
        @memset(@dataof(destination), 0, @countof(destination))
        let search = node.blockSearch(logical)
        if search.found do
            .readPhysical(node.blocks[search.index].physical, destination)
    }

    mtd writeBlock(nodeId, logical: u64, source: const [..] u8) fail
    {
        Debug.assert(@countof(source) == BlockSize)
        let physical  = try .blocks.allocate()
        var published = false
        defer
        {
            if !published do
                .blocks.release(physical)
        }

        var record: [BlockRecordSize] u8
        let nonce      = record[0 until Crypto.NonceSize]
        let ciphertext = record[Crypto.NonceSize until Crypto.NonceSize + BlockSize]
        let tag        = record[Crypto.NonceSize + BlockSize until BlockRecordSize]
        try Crypto.seal(&.keys, DataKind, physical, source, nonce, ciphertext, tag)
        .file.writeAllAt(DataOffset + physical * BlockRecordSize, record)

        let node   = .nodeById(nodeId)!
        let search = node.blockSearch(logical)
        if search.found
        {
            .blocks.deferRelease(node.blocks[search.index].physical)
            node.blocks[search.index].physical = physical
        }
        else do
            node.blocks.insertAt(search.index, BlockMapping{logical, physical})
        .touch(nodeId)
        published = true
    }

    mtd freeNodeBlocks(node: *Node)
    {
        for mapping in node.blocks do
            .blocks.deferRelease(mapping.physical)
        node.blocks.clear()
        .touch(node.id)
    }

    mtd trimNode(node: *Node, newSize: u64)
    {
        let keepBlocks = (newSize + BlockSize - 1) / BlockSize
        var index      = node.blocks.count
        while index
        {
            index -= 1
            if node.blocks[index].logical < keepBlocks do
                break
            .blocks.deferRelease(node.blocks[index].physical)
            node.blocks.removeAtOrdered(index)
        }

        .touch(node.id)
    }

    mtd zeroOldTail(nodeId, oldSize, newSize: u64) fail
    {
        if newSize <= oldSize or oldSize % BlockSize == 0 do
            return
        let node    = .nodeById(nodeId)!
        let logical = oldSize / BlockSize
        let search  = node.blockSearch(logical)
        if !search.found do
            return
        var block: [BlockSize] u8
        defer Core.Crypto.secureClear(block)
        .readPhysical(node.blocks[search.index].physical, block)
        let end = Math.min(newSize, (logical + 1) * BlockSize)
        @memset(&block[oldSize % BlockSize], 0, end - oldSize)
        .writeBlock(nodeId, logical, block)
    }

    mtd resizeNode(nodeId, newSize: u64) fail
    {
        let node = .nodeById(nodeId)!
        if node.isDirectory() do
            failWith("Cannot resize a directory.", .IsDirectory)
        let oldSize = node.size
        if newSize > oldSize do
            .zeroOldTail(nodeId, oldSize, newSize)
        elif newSize < oldSize do
            .trimNode(node, newSize)
        let current = .nodeById(nodeId)!
        current.size          = newSize
        current.changeTime    = volumeTimeNow()
        current.lastWriteTime = current.changeTime
        .touch(nodeId)
    }

    mtd readNode(nodeId: u64, offset: u64, destination: [..] u8)->u32 fail
    {
        let node = .nodeById(nodeId)
        if !node do
            failWith("File handle is no longer valid.", .NotFound)
        let validNode = node!
        if validNode.isDirectory() do
            failWith("Cannot read a directory as a file.", .IsDirectory)
        if offset >= validNode.size or !@countof(destination) do
            return 0

        let count = Math.min(@countof(destination), validNode.size - offset)
        var done  = 0'u64
        while done < count
        {
            let absolute = offset + done
            let logical  = absolute / BlockSize
            let inBlock  = absolute % BlockSize
            let chunk    = Math.min(count - done, BlockSize - inBlock)
            var block: [BlockSize] u8
            .readBlock(validNode, logical, block)
            @memcpy(@dataof(destination) + done, &block[inBlock], chunk)
            Core.Crypto.secureClear(block)
            done += chunk
        }

        return cast(u32) count
    }

    mtd writeNode(nodeId: u64, offset: u64, source: const [..] u8, writeToEnd, constrained: bool)->u32 fail
    {
        let node = .nodeById(nodeId)
        if !node do
            failWith("File handle is no longer valid.", .NotFound)
        let validNode = node!
        if validNode.isDirectory() do
            failWith("Cannot write to a directory.", .IsDirectory)
        if (validNode.attributes & FileAttributeReadOnly) != 0 do
            failWith("The file is read-only.", .AccessDenied)

        var writeOffset = offset
        if writeToEnd do
            writeOffset = validNode.size
        var count = @countof(source)
        if constrained
        {
            if writeOffset >= validNode.size do
                return 0
            count = Math.min(count, validNode.size - writeOffset)
        }

        if !count do
            return 0
        if writeOffset > Swag.U64.Max - count do
            failWith("File size overflow.", .InvalidInput)

        let oldSize = validNode.size
        let end     = writeOffset + count
        if !constrained and end > oldSize do
            .zeroOldTail(nodeId, oldSize, end)

        var done = 0'u64
        while done < count
        {
            let absolute = writeOffset + done
            let logical  = absolute / BlockSize
            let inBlock  = absolute % BlockSize
            let chunk    = Math.min(count - done, BlockSize - inBlock)
            let current  = .nodeById(nodeId)!
            var block: [BlockSize] u8
            if inBlock or chunk != BlockSize do
                .readBlock(current, logical, block)
            @memcpy(&block[inBlock], @dataof(source) + done, chunk)
            .writeBlock(nodeId, logical, block)
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
        return cast(u32) count
    }

    mtd createNode(path: string, directory: bool, attributes: u32, security: const [..] u8)->u64 fail
    {
        let {parent, name} = .resolveParent(path)
        if parent == null or !parent!.isDirectory() do
            failWith("Parent directory does not exist.", .NotFound)
        let validParent = parent!
        if !@countof(name) or name == "." or name == ".." do
            failWith("Invalid file name.", .InvalidInput)
        if .findChild(validParent.id, name) do
            failWith("A file with this name already exists.", .AlreadyExists)

        let now = volumeTimeNow()
        var node: Node
        node.id         = .nextNodeId
        node.parentId   = validParent.id
        node.name       = name
        node.attributes = attributes
        if directory do
            node.attributes |= FileAttributeDirectory
        elif !node.attributes do
            node.attributes = FileAttributeNormal
        node.creationTime   = now
        node.lastAccessTime = now
        node.lastWriteTime  = now
        node.changeTime     = now
        node.security.add(security)
        .nextNodeId += 1
        let result = node.id
        .nodes.add(#move node)
        let indexed = .nodeLookup.add(&.nodes[.nodes.count - 1], .nodes.count - 1)
        Debug.assert(indexed)
        .touch(result)
        .scalarsDirty = true
        .commit()
        return result
    }

    mtd nodeIndex(id: u64)->u64
    {
        return .nodeLookup.nodePosition(id)
    }

    mtd removeNodeAt(index: u64)
    {
        Debug.assert(index < .nodes.count)
        .nodeLookup.remove(&.nodes[index])
        .nodes.removeAt(index)
        if index < .nodes.count do
            .nodeLookup.updateNodePosition(.nodes[index].id, index)
    }

    mtd hasChildren(id: u64)->bool
    {
        return .nodeLookup.hasChildren(id)
    }

    mtd deleteNode(id: u64) fail
    {
        if id == 1 do
            failWith("Cannot delete the root directory.", .AccessDenied)
        let index = .nodeIndex(id)
        if index == Swag.U64.Max do
            return
        if .nodes[index].isDirectory() and .hasChildren(id) do
            failWith("The directory is not empty.", .DirectoryNotEmpty)
        .freeNodeBlocks(&.nodes[index])
        .removeNodeAt(index)

        // A node that is being deleted must leave the pending set, or the
        // journal record would describe a node that no longer exists.
        .drop(id)
        .commit()
    }

    mtd renameNode(id: u64, newPath: string, replace: bool) fail
    {
        if id == 1 do
            failWith("Cannot rename the root directory.", .AccessDenied)
        let {parent, name} = .resolveParent(newPath)
        if parent == null or !parent!.isDirectory() or !@countof(name) do
            failWith("The destination directory does not exist.", .NotFound)
        let validParent         = parent!
        let destinationParentId = validParent.id
        let sourceIsDirectory   = .nodeById(id)!.isDirectory()
        let existing            = .findChild(validParent.id, name)
        if existing and existing.id != id
        {
            if !replace do
                failWith("The destination already exists.", .AlreadyExists)
            if existing.isDirectory() != sourceIsDirectory do
                failWith("A file cannot replace a directory, or conversely.", .InvalidInput)
            if existing.isDirectory() and .hasChildren(existing.id) do
                failWith("The destination directory is not empty.", .DirectoryNotEmpty)
            let existingId    = existing.id
            let existingIndex = .nodeIndex(existingId)
            .freeNodeBlocks(&.nodes[existingIndex])
            .removeNodeAt(existingIndex)
            .drop(existingId)
        }

        let node = .nodeById(id)!
        if node.isDirectory()
        {
            var ancestor = destinationParentId
            while ancestor != 1
            {
                if ancestor == id do
                    failWith("Cannot move a directory into itself.", .InvalidInput)
                ancestor = .nodeById(ancestor)!.parentId
            }
        }

        let updated      = .nodeById(id)!
        let indexUpdated = .nodeLookup.changeParent(updated, destinationParentId, name)
        Debug.assert(indexUpdated)
        updated.changeTime = volumeTimeNow()
        .touch(id)
        .commit()
    }

    mtd freeBytes()->u64
    {
        return .blocks.freeBlockCount() * BlockSize
    }

    mtd freeBlockCount()->u64
    {
        return .blocks.freeBlockCount()
    }

    mtd totalBytes()->u64 => .blockCount * BlockSize
}
