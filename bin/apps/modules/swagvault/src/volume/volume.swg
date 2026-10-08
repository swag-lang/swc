using Core

// Bounds one encrypted host transfer. Large enough to amortize system calls and small enough to
// keep temporary ciphertext away from the heap's large-allocation path.
const MaximumIoBatchBlocks = 256'u64

// One run of consecutive blocks sealed or opened in parallel, one block per job.
struct CryptoBatch
{
    keys:        const *Crypto.Keys
    physical:    u64            // Container block of the first record.
    records:     [..] u8        // Sealed records, `BlockRecordSize` bytes each.
    plain:       [..] u8        // Plain blocks, `BlockSize` bytes each.
    error:       Swag.Error     // Owns the first failure a job reported until the joining caller raises it.
    errorLock:   Sync.Mutex
    invalidTags: s32     // Number of records that failed authentication.
}

impl CryptoBatch
{
    // Keeps `err` as the batch failure unless a job has already reported one.
    mtd keepFirstError(err: any?)
    {
        if err == null do
            return
        Sync.scopedLock(&.errorLock)
        if .error.isEmpty() do
            .error.capture(err)
    }
}

// Original block map of one node while a shrink is still reversible in memory.
struct BlockMapBackup
{
    blocks: Array'BlockMapping
}

// Serialized timestamps use 100-nanosecond ticks since 1601-01-01 UTC.
// Keeping the epoch in the format layer preserves compatibility with existing volumes.
const VolumeTimestampEpoch = 504_911_232_000_000_000'u64

// Returns the current time in the serialized timestamp unit.
func volumeTimeNow()->u64 => Time.Timestamp.utcNow().ticks - VolumeTimestampEpoch

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

    // Returns whether the watcher asked the operation to stop.
    mtd isCanceled()->bool => Atomic.get(&.canceled) != 0

    // Returns the share of the operation that is done, from zero to one. Zero before it starts.
    mtd ratio()->f32
    {
        let total = Atomic.get(&.total)
        if not total do
            return 0
        return cast(f32, Atomic.get(&.done)) / cast(f32, total)
    }
}

// An open encrypted container: its keys, its geometry, its node table, and the changes not yet durable.
//
// A volume is opened with [[Volume.open]] or made with [[Volume.create]] and
// [[Volume.createHidden]]. A namespace change goes to memory first and becomes durable through
// [[Volume.commit]], which appends a journal record, or [[Volume.checkpoint]], which rewrites
// the metadata image. Closing a volume checkpoints it and wipes its keys.
#[Swag.NoCopy]
struct Volume
{
    file:               VolumeStorage
    keys:               Crypto.Keys
    master:             [Crypto.MasterKeySize] u8
    slotSalt:           [Crypto.SaltSize] u8     // One random salt shared by every password slot.
    path:               String
    label:              String
    containerSize:      u64
    physicalSize:       u64     // Authenticated file length, including the random camouflage tail.
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
    readonly readOnly: bool
}

// Chooses a byte-granular physical length above the logical capacity. The
// optional avoided length makes an explicit camouflage refresh observable.
func camouflageSize(logicalSize: u64, avoidedSize = 0'u64)->u64 fail
{
    var minimum = CamouflageMinimum
    var maximum = CamouflageMaximum
    #static if #command != Swag.CompilerCommand.Test
    {
        minimum = Math.min(Math.max(minimum, logicalSize / 32), 512'u64 * 1024 * 1024)
        maximum = Math.min(Math.max(64'u64 * 1024 * 1024, logicalSize / 8), maximum)
    }

    if logicalSize > Swag.U64.Max - minimum do
        try failWith("The requested capacity leaves no room for camouflage.", .InvalidInput)
    maximum = Math.min(maximum, Swag.U64.Max - logicalSize)
    if maximum < minimum do
        try failWith("The requested capacity leaves no room for camouflage.", .InvalidInput)

    var random = 0'u64
    try Core.Crypto.randomBytes(Swag.makeSlice(cast([*] u8, &random), #sizeof(random)))
    let range  = maximum - minimum + 1
    var result = logicalSize + minimum + random % range
    if result == avoidedSize do
        result = result == logicalSize + maximum ? logicalSize + minimum : result + 1
    return result
}

impl Volume
{
    // Fills a physical range rather than merely resizing the file. This keeps
    // the container fully allocated and makes the camouflage tail look exactly
    // like encrypted data.
    mtd randomizeRange(first, last: u64, progress: *VolumeProgress?, progressBase: u64, canceledMessage: string) fail
    {
        if first >= last do
            return

        var randomChunk: Array'u8
        randomChunk.resize(RandomizeChunkSize)
        defer Core.Crypto.secureClear(randomChunk.toSlice())

        var offset = first
        while offset < last
        {
            if progress and progress.isCanceled() do
                try failWith(canceledMessage, .Canceled)

            let count = Math.min(last - offset, randomChunk.count)
            try Core.Crypto.randomBytes(randomChunk[0 until count])
            try .file.writeAllAt(offset, randomChunk[0 until count])
            offset += count
            progress?.publish(progressBase + offset - first)
        }
    }

    // Refuses an operation that would change a container opened read only.
    //
    // Every entry point that can reach the file goes through it first, so a caller gets the same
    // answer whether it asks to write a byte, to rename an entry, or to rewrite a key slot.
    mtd requireWritable() fail
    {
        if .file.protectionTriggered do
            try failWith("Hidden-volume protection has stopped writes until unmount.", .HiddenProtected)
        if .readOnly do
            try failWith("The container is mounted read only.", .WriteProtected)
    }

    // Checkpoints pending changes, closes the file, and wipes every key the volume holds.
    // Closing a closed volume only wipes again.
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
        Core.Crypto.secureClear(.slotSalt)
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
    func create(path: string, password: const [..] u8, requestedSize: u64, progress: *VolumeProgress? = null)->Volume fail
    {
        if requestedSize < MinimumSize do
            try failWith(Format.toString("The container must be at least % bytes.", MinimumSize), .SizeTooSmall)

        var result: retval
        var created   = false
        var completed = false

        // `completed` is set only on the last line, so any failure below unwinds
        // everything and leaves no half-written container on disk.
        defer
        {
            if not completed
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
            .physicalSize  = try camouflageSize(requestedSize)
            .blockCount    = (requestedSize - DataOffset) / BlockRecordSize
            .nextNodeId    = RootNodeId + 1
            .label         = ProductName
        }

        result.file.stream = try File.open(path, .CreateNew, .ReadWrite, .Read)
        created = true
        try result.file.resize(result.physicalSize)

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
        progress?.setTotal(result.physicalSize)
        try result.randomizeRange(0, result.physicalSize, progress, 0, "Container creation was canceled.")
        if (try File.attributes(path)).has(.SparseFile) do
            try failWith("Sparse container files are not supported.", .SparseContainer)

        // The master key is drawn once and never derived. A password only ever
        // unwraps it, which is what makes changing a password cheap.
        try Core.Crypto.randomBytes(result.master)
        try Core.Crypto.randomBytes(result.slotSalt)
        try result.file.writeAllAt(KeySlotAreaOffset, result.slotSalt)
        result.keys = try Crypto.deriveKeys(result.master)
        let initialKeySlot = try randomKeySlotIndex()
        result.keySlotMask = keySlotBit(initialKeySlot)
        try result.writeKeySlot(initialKeySlot, password)

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
        Swag.assert(rootIndexed)

        result.blocks.initialize(result.blockCount)
        result.dirty = true
        try result.checkpoint()

        completed = true
        return result
    }

    // Opens the container `password` unlocks, or an unprotected one when `password` is empty.
    //
    // `readOnly` opens the file without write access at all, so nothing above this layer has to
    // be trusted to leave the container alone: the operating system refuses the write, and every
    // operation that would have needed one fails with [[ErrorKind.WriteProtected]] before it is
    // attempted. It is also what lets a container be read while another tool holds it.
    //
    // The password selects the outer or hidden filesystem. Supplying protectionPassword
    // authenticates the hidden range and rejects outer writes into it for this handle only.
    // Empty protection bytes leave normal allocation and writes unrestricted.
    func open(path: string, password: const [..] u8, readOnly = false, protectionPassword: const [..] u8 = "")->Volume fail
    {
        if (try File.attributes(path)).has(.SparseFile) do
            try failWith("Sparse container files are not supported.", .SparseContainer)

        var result: retval
        result.dirty    = false
        result.readOnly = readOnly
        result.path     = path
        if readOnly do
            result.file.stream = try File.open(path, .Open, .Read, .Read)
        else do
            result.file.stream = try File.open(path, .Open, .ReadWrite, .Read)
        var completed = false
        defer
        {
            if not completed
            {
                result.dirty = false
                result.close()
            }
        }

        result.physicalSize = try result.file.size()
        if result.physicalSize < MinimumSize do
            try failWith("The password is incorrect or the container is damaged.", .PasswordOrDamaged)
        result.containerSize = result.physicalSize
        result.blockCount    = (result.physicalSize - DataOffset) / BlockRecordSize

        discard catch result.unlock(password) as outerError
        if outerError != null
        {
            let region = try HiddenLocator.find(&result.file.stream, password)
            result.file.base     = region.first
            result.file.limit    = region.count
            result.physicalSize  = region.count
            result.containerSize = region.count
            result.blockCount    = (region.count - DataOffset) / BlockRecordSize
            try result.unlock(password)
        }

        if protectionPassword.count
        {
            if result.file.base do
                try failWith("Hidden-volume protection needs the outer volume password.", .InvalidInput)
            let region = try HiddenLocator.find(&result.file.stream, protectionPassword)
            result.file.protectedFirst = region.first
            result.file.protectedEnd   = region.first + region.count
        }

        var first = try result.readHeader(0)
        defer Core.Crypto.secureClear(first.plain.toSlice())
        var second = try result.readHeader(1)
        defer Core.Crypto.secureClear(second.plain.toSlice())
        var selected: *HeaderCandidate?
        if first.valid and second.valid do
            selected = first.sequence >= second.sequence ? &first : &second
        elif first.valid do
            selected = &first
        elif second.valid do
            selected = &second
        else do
            try failWith("The password is incorrect or the container is damaged.", .PasswordOrDamaged)

        let validHeader = selected!
        result.activeSlot = validHeader == &first ? 0 : 1

        // Every way the metadata can be rejected reports the same thing: a
        // caller must not be able to tell a wrong password from a damaged
        // container, from an older format version, or from which field gave up
        // first.
        discard catch result.restore(validHeader.plain.toSlice()) as parseError
        if parseError != null do
            try failWith("The password is incorrect or the container is damaged.", .PasswordOrDamaged)

        if result.file.protectedEnd do
            try result.validateHiddenRegion({result.file.protectedFirst, result.file.protectedEnd - result.file.protectedFirst})

        // A shrink publishes its authenticated geometry before truncating the now-unused tail.
        // If the process stopped between those steps, the next writable open completes the
        // truncation; a read-only open simply ignores the unauthenticated excess bytes.
        if not readOnly and not result.file.base and not result.file.protectedEnd and (try result.file.size()) > result.physicalSize
        {
            try result.file.resize(result.physicalSize)
            try result.file.flush()
        }

        completed = true
        return result
    }

    // Checks that the entire hidden view still belongs to one genuinely free outer extent.
    mtd validateHiddenRegion(region: FreeExtent) fail
    {
        if region.first < DataOffset or region.first > .containerSize or region.count > .containerSize - region.first do
            try failWith("The hidden region no longer fits the outer volume.", .HiddenProtected)
        for extent in .blocks.free
        {
            let first = DataOffset + extent.first * BlockRecordSize
            let end   = first + extent.count * BlockRecordSize
            if region.first >= first and region.first <= end and region.count <= end - region.first do
                return
        }

        try failWith("The outer volume has allocated part of the hidden region.", .HiddenProtected)
    }

    // Creates one hidden volume inside a contiguous free outer extent. The outer handle is
    // consumed before returning: a writable outer and its hidden view can never coexist here.
    // Creating another hidden volume replaces the previous hidden access and may overwrite it.
    func createHidden(path: string, outerPassword, hiddenPassword: const [..] u8, requestedSize: u64, progress: *VolumeProgress? = null, outerReserve: u64 = MinimumBlocks * BlockSize)->Volume fail
    {
        if requestedSize < MinimumSize do
            try failWith("The hidden volume is too small for its metadata.", .SizeTooSmall)
        if not hiddenPassword.count do
            try failWith("A hidden volume needs a password or key files.", .PasswordRequired)
        var outer = try Volume.open(path, outerPassword)
        if outer.file.base do
            try failWith("A hidden volume needs an outer container.", .InvalidInput)
        if (try outer.findKeySlot(hiddenPassword)) != Swag.U64.Max do
            try failWith("Hidden and outer access need different credentials.", .InvalidInput)
        try outer.checkpoint()
        let hiddenBlocks  = requestedSize / BlockRecordSize + (requestedSize % BlockRecordSize != 0 ? 1'u64 : 0)
        let reserveBlocks = outerReserve / BlockSize + (outerReserve % BlockSize != 0 ? 1'u64 : 0)
        let freeBlocks    = outer.blocks.freeBlockCount()
        if hiddenBlocks > freeBlocks or Math.max(reserveBlocks, MinimumBlocks) > freeBlocks - hiddenBlocks do
            try failWith("The hidden capacity leaves too little free space for the outer volume.", .DiskFull)
        var region: FreeExtent
        for extent in outer.blocks.free
        {
            let size = extent.count * BlockRecordSize
            if size >= requestedSize and size > region.count do
                region = {DataOffset + extent.first * BlockRecordSize, size}
        }

        if region.count < requestedSize do
            try failWith("No contiguous free region fits the hidden volume.", .DiskFull)
        region.first += region.count - requestedSize
        region.count = requestedSize
        try outer.validateHiddenRegion(region)
        if progress and progress.isCanceled() do
            try failWith("Container creation was canceled.", .Canceled)

        with var result: retval
        {
            .file.stream   = #move outer.file.stream
            .file.base     = region.first
            .file.limit    = region.count
            .path          = path
            .containerSize = requestedSize
            .physicalSize  = requestedSize
            .blockCount    = (requestedSize - DataOffset) / BlockRecordSize
            .nextNodeId    = RootNodeId + 1
            .label         = ProductName
        }

        var completed = false
        defer
        {
            if not completed
            {
                result.dirty = false
                result.close()
            }
        }

        progress?.setTotal(requestedSize)

        // Clearing old journal records is essential when this free extent held an older volume.
        try result.randomizeRange(0, requestedSize, progress, 0, "Container creation was canceled.")
        try Core.Crypto.randomBytes(result.master)
        try Core.Crypto.randomBytes(result.slotSalt)
        try result.file.writeAllAt(0, result.slotSalt)
        result.keys = try Crypto.deriveKeys(result.master)
        let slot = try randomKeySlotIndex()
        result.keySlotMask = keySlotBit(slot)
        let now = volumeTimeNow()
        with var root: Node
        {
            .id             = RootNodeId
            .parentId       = RootNodeId
            .attributes     = FileAttributeDirectory
            .creationTime   = now
            .lastAccessTime = now
            .lastWriteTime  = now
            .changeTime     = now
        }

        result.nodes.add(#move root)
        let indexed = result.nodeLookup.add(&result.nodes[0], 0)
        Swag.assert(indexed)
        result.blocks.initialize(result.blockCount)
        result.dirty = true
        try result.checkpoint()

        // Remove every old hidden access before publishing the replacement's first locator.
        for index in KeySlotCount do
            try HiddenLocator.erase(&result.file.stream, index)
        try result.writeKeySlot(slot, hiddenPassword)
        completed = true
        return result
    }

    mtd freeBytes()->u64 => .blocks.freeBlockCount() * BlockSize

    mtd freeBlockCount()->u64 => .blocks.freeBlockCount()

    mtd totalBytes()->u64 => .blockCount * BlockSize
}
