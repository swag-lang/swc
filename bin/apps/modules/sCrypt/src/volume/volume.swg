using Core

// Bounds one encrypted host transfer. Large enough to amortize system calls and small enough to
// keep temporary ciphertext away from the heap's large-allocation path.
const MaximumIoBatchBlocks = 256'u64

struct CryptoBatch
{
    keys:        const *Crypto.Keys = undefined
    physical:    u64
    records:     [..] u8
    plain:       [..] u8
    error:       #null any
    errorLock:   Sync.Mutex
    invalidTags: s32
}

// Original block map of one node while a shrink is still reversible in memory.
struct BlockMapBackup
{
    blocks: Array'BlockMapping
}

private func keepFirstBatchError(batch: *CryptoBatch, err: #null any)
{
    if err == null do
        return
    Sync.scopedLock(&batch.errorLock)
    if batch.error == null do
        batch.error = err
}

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

// Progress and cancellation of a long volume operation, shared between the thread that runs it
// and the thread that watches it.
//
// The operation publishes what it has written and gives up at its next boundary once the watcher
// asks it to. Every field is read and written atomically, so neither side needs a lock, and a
// watcher that reads a value one step behind simply reports the previous instant.
struct VolumeProgress
{
    private
    {
        done:     u64     // Bytes the operation has written so far.
        total:    u64     // Bytes it has to write, or zero before it starts.
        canceled: u8      // Non-zero once the watcher asked the operation to stop.
    }
}

impl VolumeProgress
{
    // Arms the tracker for an operation with `total` bytes to write, clearing any earlier
    // cancellation so a stopped operation cannot stop the next one. This belongs to the
    // watcher: it is what says a new operation is about to start.
    mtd begin(total: u64)
    {
        .setTotal(total)
        Atomic.exchange(&.canceled, 0'u8)
    }

    // Records how much the running operation has to write. The cancellation is deliberately
    // left alone: the watcher arms the tracker, and an operation that cleared the flag on its
    // way in would drop every cancellation asked for between those two moments — which is
    // exactly the window in which the user hits Cancel while the job is still queued.
    mtd setTotal(total: u64)
    {
        Atomic.exchange(&.done, 0)
        Atomic.exchange(&.total, total)
    }

    // Publishes how many bytes the operation has written.
    mtd publish(done: u64)
    {
        Atomic.exchange(&.done, done)
    }

    // Asks the operation to stop at its next boundary.
    mtd cancel()
    {
        Atomic.exchange(&.canceled, 1'u8)
    }

    // Whether the watcher asked the operation to stop.
    mtd isCanceled()->bool => Atomic.get(&.canceled) != 0

    // Share of the operation that is done, from zero to one. Zero before it starts.
    mtd ratio()->f32
    {
        let total = Atomic.get(&.total)
        if !total do
            return 0
        return cast(f32) Atomic.get(&.done) / cast(f32) total
    }
}

#[Swag.NoCopy]
struct Volume
{
    file:               File.FileStream
    keys:               Crypto.Keys
    master:             [Crypto.MasterKeySize] u8
    path:               String
    label:              String
    containerSize:      u64
    blockCount:         u64
    sequence:           u64     // Sequence of the last durable change, checkpoint or journal record.
    checkpointAt:       u64     // Sequence of the last checkpoint; journal records above it are live.
    nextNodeId:         u64
    activeSlot:         u32
    keySlotMask:        u32           // Which key slots hold a password; kept in the encrypted header, never in the slot area.
    metadataPages:      Array'u64     // Physical blocks holding the metadata image, in order.
    metadataSize:       u64           // Exact byte count of that image.
    nodes:              Array'Node
    nodeLookup:         NodeIndex
    blocks:             BlockAllocator
    ioLock:             Sync.Mutex      // Serializes the shared seek-based container stream.
    accessLock:         Sync.RWLock     // Protects nodes and allocation across concurrent host callbacks.
    touched:            Array'u64       // Nodes changed since the last journal record.
    touchedSet:         HashSet'u64
    metadataTouched:    Array'u64     // Nodes whose block map and security data did not change.
    metadataTouchedSet: HashSet'u64
    removed:            Array'u64     // Nodes deleted since the last journal record.
    scalarsDirty:       bool          // Whether a scalar such as the label or the next identifier changed.
    dirty:              bool          // Whether anything at all is not yet in a checkpoint.

    #static if #command == Swag.CompilerCommand.Test
    {
        journalRecordsRead: u64     // Number of journal slots the latest restore inspected.
    }

    // Whether this volume refuses every change. See [[Volume.open]]: the file itself is opened
    // without write access, so the refusal is the operating system's and not a promise this
    // layer makes to itself.
    readonly
    readOnly: bool
}

impl Volume
{
    // Refuses an operation that would change a container opened read only.
    //
    // Every entry point that can reach the file goes through it first, so a caller gets the same
    // answer whether it asks to write a byte, to rename an entry, or to rewrite a key slot.
    mtd requireWritable() fail
    {
        if .readOnly do
            failWith("The container is mounted read only.", .WriteProtected)
    }

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

    // Creates an encrypted container of `requestedSize` bytes that `password` opens.
    //
    // An empty `password` is a container that opens without one. Everything else is unchanged:
    // the blocks are encrypted under the same master key, and the key slot wraps it exactly the
    // same way. What an empty password gives up is the protection of the wrapping, not the
    // encryption — a virtual drive that is private on disk rather than locked.
    //
    // Randomizing the container dominates the call, so `progress` reports how far it has come
    // and carries the caller's cancellation. A canceled creation fails with `.Canceled` and
    // deletes the partial file, exactly like any other failure.
    func create(path: string, password: const [..] u8, requestedSize: u64, progress: #null *VolumeProgress = null)->Volume fail
    {
        if requestedSize < MinimumSize do
            failWith(Format.toString("The container must be at least % bytes.", MinimumSize), .SizeTooSmall)

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
        //
        // Every byte comes from the system generator. Expanding one seed with a key stream
        // was measured instead and is far slower here: the system generator runs at about
        // 5.5 GiB/s while `Core.Crypto.chacha20Xor` runs at about 50 MiB/s, and the disk
        // bounds this loop long before either of them does.
        var randomChunk: Array'u8
        randomChunk.resize(RandomizeChunkSize)
        defer Core.Crypto.secureClear(randomChunk.toSlice())

        if progress do
            progress!.setTotal(requestedSize)

        var offset = 0'u64
        while offset < requestedSize
        {
            // Cancellation is checked once per chunk, which bounds how long the caller waits
            // for the operation to notice without making the fill itself check anything.
            if progress and progress!.isCanceled() do
                failWith("Container creation was canceled.", .Canceled)

            let count = Math.min(requestedSize - offset, randomChunk.count)
            Core.Crypto.randomBytes(randomChunk[0 until count])
            result.file.writeAllAt(offset, randomChunk[0 until count])
            offset += count

            if progress do
                progress!.publish(offset)
        }

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

    // Opens the container `password` unlocks, or an unprotected one when `password` is empty.
    //
    // `readOnly` opens the file without write access at all, so nothing above this layer has to
    // be trusted to leave the container alone: the operating system refuses the write, and every
    // operation that would have needed one fails with [[ErrorKind.WriteProtected]] before it is
    // attempted. It is also what lets a container be read while another tool holds it.
    func open(path: string, password: const [..] u8, readOnly = false)->Volume fail
    {
        var result: retval
        result.dirty    = false
        result.readOnly = readOnly
        result.path     = path
        if readOnly do
            result.file = File.open(path, .Open, .Read, .Read)
        else do
            result.file = File.open(path, .Open, .ReadWrite, .Read)
        var completed = false
        defer
        {
            if !completed do
                result.close()
        }

        result.containerSize = result.file.size()
        if result.containerSize < MinimumSize do
            failWith("The password is incorrect or the container is damaged.", .PasswordOrDamaged)
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
            failWith("The password is incorrect or the container is damaged.", .PasswordOrDamaged)

        let validHeader = selected!
        result.activeSlot = validHeader == &first ? 0 : 1

        // Every way the metadata can be rejected reports the same thing: a
        // caller must not be able to tell a wrong password from a damaged
        // container, from an older format version, or from which field gave up
        // first.
        discard catch result.restore(validHeader.plain.toSlice()) as parseError
        if parseError != null do
            failWith("The password is incorrect or the container is damaged.", .PasswordOrDamaged)

        // A shrink publishes its authenticated geometry before truncating the now-unused tail.
        // If the process stopped between those steps, the next writable open completes the
        // truncation; a read-only open simply ignores the unauthenticated excess bytes.
        if !readOnly and result.file.size() > result.containerSize
        {
            result.file.resize(result.containerSize)
            result.file.flush()
        }

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
            failWith("The password is incorrect or the container is damaged.", .PasswordOrDamaged)

        for index in KeySlotCount
        {
            var slot = KeySlot.decode(area[index * KeySlotSize until (index + 1) * KeySlotSize])
            defer slot.clear()
            if try slot.unwrap(password, index, .master)
            {
                .keys = try Crypto.deriveKeys(.master)
                return
            }
        }

        failWith("The password is incorrect or the container is damaged.", .PasswordOrDamaged)
    }

    // Writes the key slot at `index` so that `password` unwraps the master key.
    mtd writeKeySlot(index: u64, password: const [..] u8, profile: Crypto.Argon2Profile) fail
    {
        try .requireWritable()
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
        try .requireWritable()
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
        for index in KeySlotCount
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
    //
    // An empty `replacement` removes the protection: the slot then unwraps under the
    // empty password, which is how a container stops asking for one. That is a
    // deliberate downgrade a caller states outright, unlike [[Volume.addPassword]],
    // which refuses to add an unprotected way into a container that has one.
    mtd changePassword(current, replacement: const [..] u8, profile = Crypto.Argon2Profile.Moderate) fail
    {
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
    // An empty `additional` is refused: a second way in that needs no password would
    // undo the protection of every other slot without saying so. Removing the
    // protection is [[Volume.changePassword]] with an empty replacement.
    mtd addPassword(additional: const [..] u8, profile = Crypto.Argon2Profile.Moderate)->u64 fail
    {
        if !@countof(additional) do
            failWith("A password is required.", .PasswordRequired)
        if (try .findKeySlot(additional)) != Swag.U64.Max do
            failWith("That password already opens this container.", .AlreadyExists)

        for index in KeySlotCount
        {
            if (.keySlotMask & keySlotBit(index)) != 0 do
                continue

            // The slot is reserved before it is written, so an interrupted add
            // wastes a slot instead of letting a later one overwrite a password
            // that already works.
            .keySlotMask  |= keySlotBit(index)
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
        .keySlotMask  &= ~keySlotBit(index)
        .scalarsDirty = true
        .dirty        = true
        try .checkpoint()
    }

    // Number of passwords that currently open this container.
    mtd const keySlotCount()->u64 => @bitcountnz(.keySlotMask)

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
    // Shrinking is not offered: blocks above the new limit would have to be evacuated first,
    // and a container that has to be rewritten to lose space is not worth the risk.
    mtd grow(requestedSize: u64, progress: #null *VolumeProgress = null) fail
    {
        try .requireWritable()
        if requestedSize <= .containerSize do
            failWith("A container can only grow.", .InvalidInput)

        let newBlockCount = (requestedSize - DataOffset) / BlockRecordSize
        if newBlockCount <= .blockCount do
            failWith("The requested size does not add a single block.", .InvalidInput)

        // Everything below is undone by putting the file back to the length the durable header
        // already claims. `committed` is set on the last line, so every failure — including the
        // cancellation — unwinds through here.
        let previousSize       = .containerSize
        let previousBlockCount = .blockCount
        var previousFree: Array'FreeExtent
        previousFree.add(.blocks.free.toSlice())

        var committed = false
        defer
        {
            if !committed
            {
                .blocks.free   = #move previousFree
                .containerSize = previousSize
                .blockCount    = previousBlockCount
                discard catch .file.resize(previousSize)
            }
        }

        .file.resize(requestedSize)

        // The added region has to look like the rest of the container, or the growth would draw
        // a visible line between the blocks that hold data and the ones that never have.
        var randomChunk: Array'u8
        randomChunk.resize(RandomizeChunkSize)
        defer Core.Crypto.secureClear(randomChunk.toSlice())

        if progress do
            progress!.setTotal(requestedSize - previousSize)

        var offset = previousSize
        while offset < requestedSize
        {
            if progress and progress!.isCanceled() do
                failWith("Growing the container was canceled.", .Canceled)

            let count = Math.min(requestedSize - offset, randomChunk.count)
            Core.Crypto.randomBytes(randomChunk[0 until count])
            .file.writeAllAt(offset, randomChunk[0 until count])
            offset += count

            if progress do
                progress!.publish(offset - previousSize)
        }

        .file.flush()
        .containerSize = requestedSize
        .blockCount    = newBlockCount
        .blocks.extend(previousBlockCount, newBlockCount - previousBlockCount)
        .scalarsDirty = true
        .dirty        = true
        try .checkpoint()

        committed = true
    }

    // Changes the physical capacity in either direction.
    mtd resize(requestedSize: u64, progress: #null *VolumeProgress = null) fail
    {
        if requestedSize > .containerSize
        {
            try .grow(requestedSize, progress)
            return
        }

        try .shrink(requestedSize, progress)
    }

    // Moves every live data block below the new end, checkpoints the smaller authenticated
    // geometry, then truncates the tail. Until the checkpoint lands, every old mapping and the
    // old file length remain valid; after it lands, an interrupted truncation is completed by
    // [[Volume.open]].
    mtd shrink(requestedSize: u64, progress: #null *VolumeProgress = null) fail
    {
        try .requireWritable()
        if requestedSize < MinimumSize do
            failWith(Format.toString("The container must be at least % bytes.", MinimumSize), .SizeTooSmall)
        if requestedSize >= .containerSize do
            failWith("Shrinking needs a smaller container size.", .InvalidInput)

        let newBlockCount = (requestedSize - DataOffset) / BlockRecordSize
        if newBlockCount >= .blockCount do
            failWith("The requested size does not remove a single block.", .InvalidInput)

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
        let previousBlockCount      = .blockCount

        var committed = false
        defer
        {
            if !committed
            {
                for &node, index in .nodes do
                    node.blocks = #move previousMaps[index].blocks
                .blocks.free            = #move previousFree
                .blocks.freeBlocksCount = previousFreeBlocksCount
                .containerSize          = previousSize
                .blockCount             = previousBlockCount
                .scalarsDirty           = false
                .dirty                  = false
            }
        }

        var blocksToMove = 0'u64
        for node in .nodes
        {
            for mapping in node.blocks
            {
                if mapping.physical >= newBlockCount do
                    blocksToMove += mapping.count
                elif mapping.physical + mapping.count > newBlockCount do
                    blocksToMove += mapping.physical + mapping.count - newBlockCount
            }
        }

        if progress do
            progress!.setTotal(blocksToMove * BlockSize)

        var moved = 0'u64
        var plain: Array'u8
        plain.resize(MaximumIoBatchBlocks * BlockSize)
        defer Core.Crypto.secureClear(plain.toSlice())

        for &node in .nodes
        {
            var updated: Array'BlockMapping
            updated.reserve(node.blocks.count + 2)
            for mapping in node.blocks
            {
                var logical  = mapping.logical
                var physical = mapping.physical
                var count    = mapping.count

                if physical < newBlockCount
                {
                    let kept = Math.min(count, newBlockCount - physical)
                    updated.add({logical, physical, kept})
                    logical  += kept
                    physical += kept
                    count    -= kept
                }

                while count
                {
                    if progress and progress!.isCanceled() do
                        failWith("Resizing the container was canceled.", .Canceled)

                    let destination = try .blocks.allocateRunBelow(newBlockCount, Math.min(count, MaximumIoBatchBlocks))
                    let bytes       = destination.count * BlockSize
                    try .readPhysicalRun(physical, plain[until bytes])
                    try .writePhysicalRun(destination.first, plain[until bytes])
                    updated.add({logical, destination.first, destination.count})

                    logical  += destination.count
                    physical += destination.count
                    count    -= destination.count
                    moved    += bytes
                    if progress do
                        progress!.publish(moved)
                }
            }

            node.blocks.clear()
            for mapping in updated do
                node.appendMapping(mapping[])
        }

        .containerSize = requestedSize
        .blockCount    = newBlockCount
        .blocks.trim(newBlockCount)
        .scalarsDirty = true
        .dirty        = true
        try .checkpoint()
        .blocks.trim(newBlockCount)

        // From this point the smaller geometry is durable. Leaving the physical tail in place on
        // a truncation error is recoverable and must not resurrect the old mappings in memory.
        committed = true
        .file.resize(requestedSize)
        .file.flush()
    }

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

        .sequence     = reader.readLittleEndian'u64()
        .checkpointAt = .sequence
        if .sequence == Swag.U64.Max do
            failWith("The container sequence can no longer advance.", .Corrupted)
        let physicalSize = .containerSize
        let storedSize   = reader.readLittleEndian'u64()
        .blockCount   = reader.readLittleEndian'u64()
        .nextNodeId   = reader.readLittleEndian'u64()
        .label        = reader.readSizedString(MaximumLabelSize)
        .keySlotMask  = reader.readLittleEndian'u32()
        .metadataSize = reader.readLittleEndian'u64()
        if storedSize < MinimumSize or storedSize > physicalSize or .blockCount != (storedSize - DataOffset) / BlockRecordSize do
            failWith("The container geometry does not match its size.", .Corrupted)
        .containerSize = storedSize

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
            for i in count do
                .metadataPages.add(first + i)
        }

        if .metadataPages.count != expectedPages do
            failWith("The metadata index is incomplete.", .Corrupted)

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
            failWith("The container has no root directory.", .Corrupted)
        try .rebuildFreeList()
    }

    // Reads the node table out of a decrypted metadata image.
    mtd loadNodes(image: const [..] u8) fail
    {
        var reader    = ByteStream.openRead(image)
        let nodeCount = reader.readLittleEndian'u64()
        if !nodeCount or nodeCount > MaximumNodeCount do
            failWith("The container declares an implausible number of entries.", .Corrupted)

        .nodes.reserve(nodeCount)
        for nodeCount
        {
            let node      = try Node.deserialize(&reader, .blockCount)
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
                if mapping.physical >= .blockCount or !mapping.count or mapping.count > .blockCount - mapping.physical do
                    failWith("A block mapping falls outside the container.", .Corrupted)
                for physical in mapping.physical until mapping.physical + mapping.count do
                    used.set(physical, true)
            }
        }

        .blocks.rebuild(&used, .blockCount)
    }

    mtd readMetadataPage(physical: u64, destination: [..] u8) fail
    {
        Debug.assert(@countof(destination) == BlockSize)
        var record: [BlockRecordSize] u8
        {
            Sync.scopedLock(&.ioLock)
            if !.file.readExactAt(DataOffset + physical * BlockRecordSize, record) do
                failWith("The container is truncated or unreadable.", .Io)
        }

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
        Sync.scopedLock(&.ioLock)
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
        try .requireWritable()
        if !.dirty do
            return

        var previousPages: Array'u64
        previousPages.add(.metadataPages.toSlice())
        var previousFree: Array'FreeExtent
        previousFree.add(.blocks.free.toSlice())
        let previousFreeBlocksCount = .blocks.freeBlocksCount

        var committed = false
        defer
        {
            if !committed
            {
                .blocks.free            = #move previousFree
                .blocks.freeBlocksCount = previousFreeBlocksCount
                .metadataPages          = #move previousPages
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
        for i in pageCount do
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
        Sync.scopedLock(&.ioLock)
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

        if !.touchedSet.contains(id)
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

    mtd clearPending()
    {
        .touched.clear()
        .touchedSet.clear()
        .metadataTouched.clear()
        .metadataTouchedSet.clear()
        .removed.clear()
        .scalarsDirty = false
    }

    mtd hasPendingChanges()->bool
    {
        return .touched.count != 0 or .metadataTouched.count != 0 or .removed.count != 0 or .scalarsDirty
    }

    // Makes every pending change durable.
    //
    // The common path appends one journal record, which is a single small write
    // whatever the size of the node table. A checkpoint happens only when the
    // journal is full, when the change is too large to fit one record, or when
    // the volume closes.
    mtd commit() fail
    {
        try .requireWritable()
        if !.dirty do
            return
        if !.hasPendingChanges() do
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

        var metadata: Array'(*Node)
        metadata.reserve(.metadataTouched.count)
        for id in .metadataTouched
        {
            let node = .nodeById(id)
            if node do
                metadata.add(node!)
        }

        var plain = JournalRecord.encode(.sequence + 1, .nextNodeId, .label, .removed.toSlice(), upserted.toSlice(), metadata.toSlice())
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
            if !plain.count do
                break

            var record = catch JournalRecord.decode(plain.toSlice(), .blockCount) as decodeError
            if decodeError != null or record.sequence != expected do
                break
            if record.sequence == Swag.U64.Max do
                failWith("The container sequence can no longer advance.", .Corrupted)
            try .applyJournal(record)
            .sequence = record.sequence
            expected  += 1
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

            var copy   = node[]
            let target = .nodes.count
            .nodes.add(#move copy)
            if !.nodeLookup.add(&.nodes[target], target) do
                failWith("A journal record contains a duplicate entry.", .Corrupted)
        }

        for patch in record.metadata
        {
            let node = .nodeById(patch.id)
            if !node do
                failWith("A journal metadata change names an entry that does not exist.", .Corrupted)
            let validNode = node!
            if patch.id != RootNodeId
            {
                let parent = .nodeById(patch.parentId)
                if !parent or !parent!.isDirectory() or !.nodeLookup.changeParent(validNode, patch.parentId, patch.name) do
                    failWith("A journal metadata change has an invalid destination.", .Corrupted)
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

    mtd firstChild(parentId: u64)->#null *Node
    {
        let id = .nodeLookup.firstChildId(parentId)
        return id ? .nodeById(id) : null
    }

    mtd nextSibling(id: u64)->#null *Node
    {
        let nextId = .nodeLookup.nextSiblingId(id)
        return nextId ? .nodeById(nextId) : null
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
        for i in 0 until parts.count - 1
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
        {
            Sync.scopedLock(&.ioLock)
            if !.file.readExactAt(DataOffset + physical * BlockRecordSize, record) do
                failWith("The container is truncated or unreadable.", .Io)
        }

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
        if search.found
        {
            let mapping = node.blocks[search.index]
            .readPhysical(mapping.physical + logical - mapping.logical, destination)
        }
    }

    mtd readPhysicalRun(physical: u64, destination: [..] u8) fail
    {
        Debug.assert(@countof(destination) != 0 and @countof(destination) % BlockSize == 0)
        let count = @countof(destination) / BlockSize
        Debug.assert(count <= MaximumIoBatchBlocks)

        var records: Array'u8
        records.resize(count * BlockRecordSize)
        {
            Sync.scopedLock(&.ioLock)
            if !.file.readExactAt(DataOffset + physical * BlockRecordSize, records.toSlice()) do
                failWith("The container is truncated or unreadable.", .Io)
        }

        var batch = CryptoBatch{keys: &.keys, physical: physical, records: records.toSlice(), plain: destination}
        Jobs.parallelFor(cast(u32) count, &batch) #code(jobIndex, data)
        {
            let batch        = cast(*CryptoBatch) data!
            let index        = cast(u64) jobIndex
            let recordOffset = index * BlockRecordSize
            let plainOffset  = index * BlockSize
            let nonce        = batch.records[recordOffset until recordOffset + Crypto.NonceSize]
            let ciphertext   = batch.records[recordOffset + Crypto.NonceSize until recordOffset + Crypto.NonceSize + BlockSize]
            let tag          = batch.records[recordOffset + Crypto.NonceSize + BlockSize until recordOffset + BlockRecordSize]
            let opened       = catch Crypto.open(batch.keys, DataKind, batch.physical + index, nonce, ciphertext, tag, batch.plain[plainOffset until plainOffset + BlockSize]) as openError
            keepFirstBatchError(batch, openError)
            if openError == null and !opened do
                Atomic.add(&batch.invalidTags, 1)
        }

        if batch.error != null do
            fail batch.error!
        if batch.invalidTags do
            failWith("An encrypted data block is damaged.", .Corrupted)
    }

    mtd writePhysicalRun(physical: u64, source: const [..] u8) fail
    {
        Debug.assert(@countof(source) != 0 and @countof(source) % BlockSize == 0)
        let count = @countof(source) / BlockSize
        Debug.assert(count <= MaximumIoBatchBlocks)

        var records: Array'u8
        records.resize(count * BlockRecordSize)
        Core.Crypto.randomBytes(records.toSlice())

        var plain = @mkslice(cast #unconst ([*] u8) @dataof(source), @countof(source))
        var batch = CryptoBatch{keys: &.keys, physical: physical, records: records.toSlice(), plain: plain}
        Jobs.parallelFor(cast(u32) count, &batch) #code(jobIndex, data)
        {
            let batch        = cast(*CryptoBatch) data!
            let index        = cast(u64) jobIndex
            let recordOffset = index * BlockRecordSize
            let plainOffset  = index * BlockSize
            let nonce        = batch.records[recordOffset until recordOffset + Crypto.NonceSize]
            let ciphertext   = batch.records[recordOffset + Crypto.NonceSize until recordOffset + Crypto.NonceSize + BlockSize]
            let tag          = batch.records[recordOffset + Crypto.NonceSize + BlockSize until recordOffset + BlockRecordSize]
            discard catch Core.Crypto.chacha20Poly1305Seal(batch.keys.record, nonce, batch.plain[plainOffset until plainOffset + BlockSize], Crypto.associatedData(DataKind, batch.physical + index), ciphertext, tag) as sealError
            keepFirstBatchError(batch, sealError)
        }

        if batch.error != null do
            fail batch.error!

        Sync.scopedLock(&.ioLock)
        .file.writeAllAt(DataOffset + physical * BlockRecordSize, records.toSlice())
    }

    // Replaces a logical range with one physical run and defers the old physical ranges until
    // the metadata commit makes the new mapping durable.
    mtd replaceBlockRun(node: *Node, logical, physical, count: u64)
    {
        Debug.assert(count != 0 and logical <= Swag.U64.Max - count)
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
                if !inserted
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
                if !inserted
                {
                    updated.add({logical, physical, count})
                    inserted = true
                }

                updated.add({end, mapping.physical + end - mapping.logical, mappingEnd - end})
            }
        }

        if !inserted do
            updated.add({logical, physical, count})

        node.blocks.clear()
        for mapping in updated do
            node.appendMapping(mapping[])
    }

    mtd writeBlock(nodeId, logical: u64, source: const [..] u8) fail
    {
        Debug.assert(@countof(source) == BlockSize)
        let allocated = try .blocks.allocateRun(1)
        let physical  = allocated.first
        var published = false
        defer
        {
            if !published do
                .blocks.release(physical)
        }

        try .writePhysicalRun(physical, source)

        let node = .nodeById(nodeId)!
        .replaceBlockRun(node, logical, physical, 1)
        .touch(nodeId)
        published = true
    }

    mtd writeFullBlocks(nodeId, logical: u64, source: const [..] u8) fail
    {
        Debug.assert(@countof(source) != 0 and @countof(source) % BlockSize == 0)
        var doneBlocks = 0'u64
        let blockCount = @countof(source) / BlockSize
        while doneBlocks < blockCount
        {
            let requested = Math.min(blockCount - doneBlocks, MaximumIoBatchBlocks)
            let allocated = try .blocks.allocateRun(requested)
            var published = false
            defer
            {
                if !published do
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

    mtd freeNodeBlocks(node: *Node)
    {
        for mapping in node.blocks do
            .blocks.deferReleaseRun(mapping.physical, mapping.count)
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
        let mapping = node.blocks[search.index]
        .readPhysical(mapping.physical + logical - mapping.logical, block)
        let end = Math.min(newSize, (logical + 1) * BlockSize)
        @memset(&block[oldSize % BlockSize], 0, end - oldSize)
        .writeBlock(nodeId, logical, block)
    }

    mtd resizeNode(nodeId, newSize: u64) fail
    {
        try .requireWritable()
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

            if !inBlock and chunk == BlockSize
            {
                let remainingBlocks = (count - done) / BlockSize
                let search          = validNode.blockSearch(logical)
                if search.found
                {
                    let mapping       = validNode.blocks[search.index]
                    let mappingOffset = logical - mapping.logical
                    let batchBlocks   = Math.min(Math.min(remainingBlocks, mapping.count - mappingOffset), MaximumIoBatchBlocks)
                    let batchBytes    = batchBlocks * BlockSize
                    .readPhysicalRun(mapping.physical + mappingOffset, destination[done until done + batchBytes])
                    done += batchBytes
                    continue
                }

                let nextLogical = search.index < validNode.blocks.count ? validNode.blocks[search.index].logical : logical + remainingBlocks
                let holeBlocks  = Math.min(remainingBlocks, nextLogical - logical)
                let holeBytes   = holeBlocks * BlockSize
                @memset(@dataof(destination) + done, 0, holeBytes)
                done += holeBytes
                continue
            }

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
        try .requireWritable()
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

            if !inBlock and chunk == BlockSize
            {
                let fullBytes = (count - done) / BlockSize * BlockSize
                .writeFullBlocks(nodeId, logical, source[done until done + fullBytes])
                done += fullBytes
                continue
            }

            let current = .nodeById(nodeId)!
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

    // Creates an in-memory node and leaves its journal commit to the caller.
    // The WinFsp lifecycle uses this to combine create, initial writes, and
    // cleanup metadata into one durable record.
    mtd createNodePending(path: string, directory: bool, attributes: u32, security: const [..] u8)->u64 fail
    {
        try .requireWritable()
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
        return result
    }

    // Creates one node as a complete durable volume operation.
    mtd createNode(path: string, directory: bool, attributes: u32, security: const [..] u8)->u64 fail
    {
        let result = try .createNodePending(path, directory, attributes, security)
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
        try .requireWritable()
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
        try .requireWritable()
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
        .touchMetadata(id)
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
