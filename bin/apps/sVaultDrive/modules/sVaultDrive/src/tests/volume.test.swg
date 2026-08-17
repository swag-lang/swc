#global if #command == Swag.CompilerCommand.Test
#global private

using Core

func testPassword()->const [..] u8
{
    return @mkslice(cast(const [*] u8) @dataof("correct horse battery staple"), 28)
}

func wrongPassword()->const [..] u8
{
    return @mkslice(cast(const [*] u8) @dataof("wrong password"), 14)
}

func emptyBytes()->const [..] u8
{
    return @mkslice(cast(const [*] u8) @dataof(""), 0)
}

func testContainerPath(tag: string)->String
{
    let temp = Env.getSpecialDirectory(.Temp)
    return Path.combine(temp.toString(), Format.toString("vaultdrive_%_%.bin", tag, Guid64.random()))
}

func sameTestBytes(left, right: const [..] u8)->bool
{
    return @countof(left) == @countof(right) and
           @memcmp(@dataof(left), @dataof(right), @countof(left)) == 0
}

func rejectsPassword(path: string, password: const [..] u8)->bool
{
    discard catch Volume.open(path, password) as openError
    return openError != null
}

func testDigestBytes(digest: Hash.Sha256.Digest)->[32] u8
{
    var result: retval
    for i in 8
    {
        let word = digest[i]
        result[i * 4 + 0] = cast(u8) ((word >> 24) & 0xFF)
        result[i * 4 + 1] = cast(u8) ((word >> 16) & 0xFF)
        result[i * 4 + 2] = cast(u8) ((word >> 8) & 0xFF)
        result[i * 4 + 3] = cast(u8) (word & 0xFF)
    }

    return result
}

func headerDigest(path: string, slot: u64)->[32] u8
{
    var file = expect File.open(path, .Open, .ReadWrite, .Read)
    defer file.close()
    var bytes: Array'u8
    bytes.resize(HeaderSlotSize)
    @assert(expect file.readExactAt(HeaderAreaOffset + slot * HeaderSlotSize, bytes.toSlice()))
    let result = testDigestBytes(Hash.Sha256.compute(bytes.toSlice()))
    Core.Crypto.secureClear(bytes.toSlice())
    return result
}

func flipByteAt(path: string, offset: u64)
{
    var file = expect File.open(path, .Open, .ReadWrite, .Read)
    defer file.close()
    var byte: [1] u8
    @assert(expect file.readExactAt(offset, byte))
    byte[0] ^= 0x5A
    expect file.writeAllAt(offset, byte)
    expect file.flush()
}

// Copies a container its volume still holds open, which is how these tests stand in for a
// crash: the bytes on disk are whatever the last write left there. `File.duplicate` cannot do
// it, because it reads through a handle that shares reading alone and the live volume holds
// the file for writing.
func snapshotContainer(destination, source: string)
{
    var reader = expect File.open(source, .Open, .Read, .ReadWrite)
    defer reader.close()
    var bytes: Array'u8
    bytes.resize(expect reader.size())
    @assert(expect reader.readExactAt(0, bytes.toSlice()))
    expect File.writeAllBytes(destination, bytes.toSlice())
}

func flipHeaderByte(path: string, slot: u64)
{
    flipByteAt(path, HeaderAreaOffset + slot * HeaderSlotSize + HeaderRecordPrefixSize)
}

func secondPassword()->const [..] u8
{
    return @mkslice(cast(const [*] u8) @dataof("a second way in entirely"), 24)
}

func thirdPassword()->const [..] u8
{
    return @mkslice(cast(const [*] u8) @dataof("yet another passphrase!!"), 24)
}

// A container large enough to hold more metadata than one header slot can.
func pagingContainerSize()->u64 => DataOffset + 512 * BlockRecordSize

// A sequential file remains one mapping extent. In particular, changing only its name must fit
// the journal instead of checkpointing the complete node table again.
#test
{
    let path = testContainerPath("large-rename")
    defer discard catch File.delete(path)

    const DataBlockCount = 512'u64
    var volume = expect Volume.create(path, testPassword(), DataOffset + (DataBlockCount + 16) * BlockRecordSize)
    let fileId = expect volume.createNode("\\large.bin", false, FileAttributeNormal, emptyBytes())
    var source: Array'u8
    source.resize(DataBlockCount * BlockSize)
    for byte, i in source do
        source[i] = cast(u8) ((i * 37 + 11) & 0xFF)

    @assert(expect volume.writeNode(fileId, 0, source.toSlice(), false, false) == source.count)
    expect volume.commit()
    @assert(volume.nodeById(fileId)!.blocks.count == 1)
    @assert(volume.nodeById(fileId)!.blocks[0].count == DataBlockCount)

    let checkpoint = volume.checkpointAt
    let sequence   = volume.sequence
    expect volume.renameNode(fileId, "\\renamed.bin", false)
    @assert(volume.checkpointAt == checkpoint)
    @assert(volume.sequence == sequence + 1)
    volume.close()

    var reopened = expect Volume.open(path, testPassword())
    let node     = reopened.resolve("\\renamed.bin")
    @assert(node != null and node!.blocks.count == 1)
    var first: [BlockSize] u8
    var last:  [BlockSize] u8
    @assert(expect reopened.readNode(node!.id, 0, first) == BlockSize)
    @assert(expect reopened.readNode(node!.id, (DataBlockCount - 1) * BlockSize, last) == BlockSize)
    @assert(sameTestBytes(first, source[until BlockSize]))
    @assert(sameTestBytes(last, source[(DataBlockCount - 1) * BlockSize until DataBlockCount * BlockSize]))
    reopened.close()
}

#test
{
    // A rename is namespace metadata, even when the file itself has enough disjoint runs to make
    // a full-node journal entry overflow. It must append one small record instead of checkpointing
    // the complete node table while Explorer waits under the namespace lock.
    let path = testContainerPath("fragmented-rename")
    defer discard catch File.delete(path)
    let salvaged = testContainerPath("fragmented-rename-salvaged")
    defer discard catch File.delete(salvaged)

    const RunCount = 180'u64
    var volume    = expect Volume.create(path, testPassword(), pagingContainerSize())
    let directory = expect volume.createNode("\\destination", true, FileAttributeDirectory, emptyBytes())
    discard directory
    let fileId                = expect volume.createNode("\\fragmented.bin", false, FileAttributeNormal, emptyBytes())
    var block: [BlockSize] u8 = [0x5A]
    for index in RunCount do
        @assert(expect volume.writeNode(fileId, index * 2 * BlockSize, block, false, false) == BlockSize)
    expect volume.commit()
    @assert(volume.nodeById(fileId)!.blocks.count == RunCount)

    let checkpoint = volume.checkpointAt
    let sequence   = volume.sequence
    expect volume.renameNode(fileId, "\\destination\\moved.bin", false)
    @assert(volume.checkpointAt == checkpoint)
    @assert(volume.sequence == sequence + 1)

    // Copy the still-mounted image to model a process stopping before close consolidates it.
    snapshotContainer(salvaged, path)
    volume.close()

    var recovered = expect Volume.open(salvaged, testPassword())
    let moved     = recovered.resolve("\\destination\\moved.bin")
    @assert(moved != null and moved!.blocks.count == RunCount)
    var readBack: [BlockSize] u8
    @assert(expect recovered.readNode(moved!.id, (RunCount - 1) * 2 * BlockSize, readBack) == BlockSize)
    @assert(sameTestBytes(block, readBack))
    recovered.close()
}

#test
{
    let path = testContainerPath("lifecycle")
    defer discard catch File.delete(path)

    let security: [6] u8 = [1, 4, 9, 16, 25, 36]
    var volume           = expect Volume.create(path, testPassword(), MinimumSize)
    @assert(volume.containerSize == MinimumSize)
    @assert(volume.physicalSize > volume.containerSize)
    @assert(!(expect File.attributes(path)).has(.SparseFile))
    var storedLocator: [Crypto.RecordLocatorSize] u8
    @assert(expect volume.file.readExactAt(HeaderAreaOffset + volume.activeSlot * HeaderSlotSize, storedLocator))
    var expectedLocator = expect Crypto.recordLocator(volume.keys.locator, HeaderLocatorKind, volume.activeSlot)
    @assert(Core.Crypto.constantTimeEqual(storedLocator[until HeaderLocatorCheckSize], expectedLocator[until HeaderLocatorCheckSize]))
    let encodedSize     = Crypto.load32(&storedLocator[HeaderLocatorCheckSize])
    let locatorMask     = Crypto.load32(&expectedLocator[HeaderLocatorCheckSize])
    let storedPlainSize = encodedSize ^ locatorMask
    @assert(storedPlainSize and storedPlainSize <= HeaderPlainSize)
    Core.Crypto.secureClear(expectedLocator)

    let root = volume.resolve("\\")
    @assert(root != null)
    @assert(root.creationTime != 0)
    let rootTimestamp = Time.Timestamp.fromTicks(root.creationTime + VolumeTimestampEpoch)
    @assert(rootTimestamp.toDateTime().isValid())

    let directoryId = expect volume.createNode("\\documents", true, FileAttributeDirectory, emptyBytes())
    let fileId      = expect volume.createNode("\\documents\\sample.bin", false, FileAttributeNormal, security)
    @assert(directoryId != fileId)
    @assert(volume.resolve("\\DOCUMENTS\\SAMPLE.BIN") != null)

    var source: [7000] u8
    for value, i in source do
        source[i] = cast(u8) ((i * 37 + 11) & 0xFF)
    @assert(expect volume.writeNode(fileId, 0, source, false, false) == #sizeof(source))
    expect volume.commit()

    var readBack: [7000] u8
    @assert(expect volume.readNode(fileId, 0, readBack) == #sizeof(readBack))
    @assert(sameTestBytes(source, readBack))
    var beyondEnd: [16] u8
    @assert(expect volume.readNode(fileId, #sizeof(source), beyondEnd) == 0)

    expect volume.renameNode(fileId, "\\documents\\renamed.bin", false)
    @assert(volume.resolve("\\documents\\sample.bin") == null)
    @assert(volume.resolve("\\documents\\renamed.bin") != null)
    let physicalSize = volume.physicalSize
    volume.close()

    var raw = expect File.open(path, .Open, .ReadWrite, .Read)
    @assert(expect raw.size() == physicalSize)
    raw.close()

    let beforeFirst  = headerDigest(path, 0)
    let beforeSecond = headerDigest(path, 1)
    @assert(rejectsPassword(path, wrongPassword()))
    let afterFirst  = headerDigest(path, 0)
    let afterSecond = headerDigest(path, 1)
    @assert(sameTestBytes(beforeFirst, afterFirst))
    @assert(sameTestBytes(beforeSecond, afterSecond))

    var reopened = expect Volume.open(path, testPassword())
    let node     = reopened.resolve("\\documents\\renamed.bin")
    @assert(node != null)
    @assert(node.size == #sizeof(source))
    @assert(sameTestBytes(node.security.toSlice(), security))
    var reopenedData: [7000] u8
    @assert(expect reopened.readNode(node.id, 0, reopenedData) == #sizeof(reopenedData))
    @assert(sameTestBytes(source, reopenedData))
    expect reopened.deleteNode(node.id)
    expect reopened.deleteNode(directoryId)
    reopened.close()

    var finalOpen = expect Volume.open(path, testPassword())
    @assert(finalOpen.resolve("\\documents") == null)
    finalOpen.close()
}

#test
{
    let path = testContainerPath("sparse")
    defer discard catch File.delete(path)

    var volume       = expect Volume.create(path, testPassword(), MinimumSize)
    let fileId       = expect volume.createNode("\\sparse.bin", false, FileAttributeNormal, emptyBytes())
    let freeBaseline = volume.freeBlockCount()

    let first: [3] u8 = [1, 2, 3]
    @assert(expect volume.writeNode(fileId, 10, first, false, false) == 3)
    expect volume.resizeNode(fileId, 2 * BlockSize + 5)

    let appended: [3] u8 = [9, 8, 7]
    @assert(expect volume.writeNode(fileId, 0, appended, true, false) == 3)
    let sizeBeforeConstraint = volume.nodeById(fileId)!.size
    let constrained: [4] u8  = [4, 5, 6, 7]
    @assert(expect volume.writeNode(fileId, sizeBeforeConstraint - 2, constrained, false, true) == 2)
    @assert(volume.nodeById(fileId)!.size == sizeBeforeConstraint)

    var hole: [32] u8
    @assert(expect volume.readNode(fileId, BlockSize, hole) == #sizeof(hole))
    for byte in hole do
        @assert(byte == 0)

    var tail: [4] u8
    @assert(expect volume.readNode(fileId, sizeBeforeConstraint - 4, tail) == 4)
    @assert(tail[0] == 0 and tail[1] == 9 and tail[2] == 4 and tail[3] == 5)

    expect volume.resizeNode(fileId, 12)
    expect volume.resizeNode(fileId, 20)
    expect volume.commit()
    @assert(volume.freeBlockCount() == freeBaseline - 1)

    var grown: [20] u8
    @assert(expect volume.readNode(fileId, 0, grown) == #sizeof(grown))
    for i in 10 do
        @assert(grown[i] == 0)
    @assert(grown[10] == 1 and grown[11] == 2)
    for i in 12 until 20 do
        @assert(grown[i] == 0)

    volume.close()
    var reopened     = expect Volume.open(path, testPassword())
    let reopenedNode = reopened.resolve("\\sparse.bin")!
    @assert(reopenedNode.size == 20)
    var persisted: [20] u8
    @assert(expect reopened.readNode(reopenedNode.id, 0, persisted) == #sizeof(persisted))
    @assert(sameTestBytes(grown, persisted))
    expect reopened.deleteNode(reopenedNode.id)
    @assert(reopened.freeBlockCount() == freeBaseline)
    reopened.close()
}

#test
{
    let path = testContainerPath("errors")
    defer discard catch File.delete(path)

    var volume     = expect Volume.create(path, testPassword(), MinimumSize)
    let folderId   = expect volume.createNode("\\folder", true, FileAttributeDirectory, emptyBytes())
    let nestedId   = expect volume.createNode("\\folder\\nested", true, FileAttributeDirectory, emptyBytes())
    let readOnlyId = expect volume.createNode("\\readonly.bin", false, FileAttributeReadOnly, emptyBytes())

    discard catch volume.createNode("\\FOLDER", true, 0, emptyBytes()) as duplicateError
    @assert(duplicateError != null)
    discard catch volume.createNode("\\missing\\file", false, 0, emptyBytes()) as parentError
    @assert(parentError != null)
    discard catch volume.createNode("\\.", false, 0, emptyBytes()) as nameError
    @assert(nameError != null)
    discard catch volume.createNode("\\readonly.bin\\child", false, 0, emptyBytes()) as notDirectoryError
    @assert(notDirectoryError != null)

    let data:   [1] u8 = [7]
    var output: [1] u8
    discard catch volume.writeNode(readOnlyId, 0, data, false, false) as readOnlyError
    @assert(readOnlyError != null)
    discard catch volume.readNode(folderId, 0, output) as readDirectoryError
    @assert(readDirectoryError != null)
    discard catch volume.writeNode(folderId, 0, data, false, false) as writeDirectoryError
    @assert(writeDirectoryError != null)
    discard catch volume.resizeNode(folderId, 1) as resizeDirectoryError
    @assert(resizeDirectoryError != null)
    discard catch volume.deleteNode(folderId) as nonEmptyError
    @assert(nonEmptyError != null)
    discard catch volume.deleteNode(1) as rootDeleteError
    @assert(rootDeleteError != null)
    discard catch volume.renameNode(1, "\\root", false) as rootRenameError
    @assert(rootRenameError != null)
    discard catch volume.renameNode(folderId, "\\folder\\nested\\moved", false) as cycleError
    @assert(cycleError != null)

    let firstId  = expect volume.createNode("\\first.bin", false, 0, emptyBytes())
    let secondId = expect volume.createNode("\\second.bin", false, 0, emptyBytes())
    discard catch volume.renameNode(firstId, "\\second.bin", false) as collisionError
    @assert(collisionError != null)
    expect volume.renameNode(firstId, "\\second.bin", true)
    @assert(volume.nodeById(secondId) == null)
    @assert(volume.resolve("\\second.bin")!.id == firstId)
    discard catch volume.renameNode(firstId, "\\folder", true) as typeError
    @assert(typeError != null)

    expect volume.deleteNode(nestedId)
    expect volume.deleteNode(folderId)
    expect volume.deleteNode(readOnlyId)
    expect volume.deleteNode(firstId)
    volume.close()
}

#test
{
    let path = testContainerPath("validation")
    defer discard catch File.delete(path)

    var smallAttempt = catch Volume.create(path, testPassword(), MinimumSize - 1) as sizeError
    smallAttempt.close()
    @assert(sizeError != null)
    @assert(!File.exists(path))

    var original = expect Volume.create(path, testPassword(), MinimumSize)
    original.close()
    var duplicate = catch Volume.create(path, testPassword(), MinimumSize) as duplicateError
    duplicate.close()
    @assert(duplicateError != null)
    @assert(File.exists(path))

    discard catch Volume.open(path, emptyBytes()) as openEmptyError
    @assert(openEmptyError != null)
    let missingPath = testContainerPath("missing")
    discard catch Volume.open(missingPath, testPassword()) as missingError
    @assert(missingError != null)

    var reopened = expect Volume.open(path, testPassword())
    reopened.close()

    let shortPath = testContainerPath("short")
    defer discard catch File.delete(shortPath)
    var shortFile = expect File.open(shortPath, .CreateNew, .ReadWrite, .Read)
    expect shortFile.resize(128)
    shortFile.close()
    @assert(rejectsPassword(shortPath, testPassword()))
}

#test
{
    let path = testContainerPath("headers")
    defer discard catch File.delete(path)

    var volume = expect Volume.create(path, testPassword(), MinimumSize)
    discard expect volume.createNode("\\latest", true, FileAttributeDirectory, emptyBytes())
    volume.close()
    let activeSlot = cast(u64) volume.activeSlot

    // The damaged slot falls back to the other checkpoint, and the journal
    // records written after that checkpoint bring the volume back up to date.
    flipHeaderByte(path, activeSlot)
    var fallback = expect Volume.open(path, testPassword())
    @assert(fallback.resolve("\\latest") != null)
    fallback.close()

    // Recovering consolidated what the journal held into the slot that was damaged, so the
    // container came out of that session whole again. Only damaging both slots leaves it with
    // no checkpoint to fall back to.
    flipHeaderByte(path, activeSlot)
    flipHeaderByte(path, 1 - activeSlot)
    @assert(rejectsPassword(path, testPassword()))
}

#test
{
    // A change is one small journal record, not a rewrite of the whole metadata
    // image, and an unmount consolidates the journal into a checkpoint.
    let path = testContainerPath("journal")
    defer discard catch File.delete(path)

    var volume      = expect Volume.create(path, testPassword(), MinimumSize)
    let afterCreate = volume.sequence
    @assert(volume.checkpointAt == afterCreate)

    discard expect volume.createNode("\\one", true, FileAttributeDirectory, emptyBytes())
    discard expect volume.createNode("\\two", true, FileAttributeDirectory, emptyBytes())
    @assert(volume.sequence == afterCreate + 2)
    @assert(volume.checkpointAt == afterCreate)

    // Filling the journal forces a checkpoint rather than overwriting a record
    // that has not been consolidated yet.
    for i in JournalCapacity do
        discard expect volume.createNode(Format.toString("\\filler_%", i), true, FileAttributeDirectory, emptyBytes())
    @assert(volume.checkpointAt > afterCreate)
    @assert(volume.sequence - volume.checkpointAt < JournalCapacity)
    volume.close()

    var reopened = expect Volume.open(path, testPassword())
    @assert(reopened.resolve("\\one") != null)
    @assert(reopened.resolve("\\two") != null)
    for i in JournalCapacity do
        @assert(reopened.resolve(Format.toString("\\filler_%", i)) != null)

    // Closing consolidated everything, so nothing is left to replay.
    @assert(reopened.sequence == reopened.checkpointAt)
    @assert(reopened.journalRecordsRead == 1)
    reopened.close()
}

#test
{
    // What a crash would leave on disk is exactly the file as it stands between
    // operations, so copying it there and opening the copy is a faithful
    // power-loss test. The journal is what makes those changes survive without
    // a checkpoint having been written.
    let path = testContainerPath("crash")
    defer discard catch File.delete(path)
    let salvaged = testContainerPath("crash_salvaged")
    defer discard catch File.delete(salvaged)

    var volume           = expect Volume.create(path, testPassword(), MinimumSize)
    let checkpointBefore = volume.checkpointAt

    let fileId           = expect volume.createNode("\\survivor.bin", false, FileAttributeNormal, emptyBytes())
    let payload: [40] u8 = [3]
    @assert(expect volume.writeNode(fileId, 0, payload, false, false) == #sizeof(payload))
    expect volume.commit()
    discard expect volume.createNode("\\also_here", true, FileAttributeDirectory, emptyBytes())

    // No checkpoint has happened since creation: everything above lives only in
    // the journal.
    @assert(volume.checkpointAt == checkpointBefore)
    @assert(volume.sequence > checkpointBefore)
    snapshotContainer(salvaged, path)
    volume.close()

    var recovered = expect Volume.open(salvaged, testPassword())
    let node      = recovered.resolve("\\survivor.bin")
    @assert(node != null)
    @assert(node.size == #sizeof(payload))
    var readBack: [40] u8
    @assert(expect recovered.readNode(node.id, 0, readBack) == #sizeof(readBack))
    @assert(sameTestBytes(payload, readBack))
    @assert(recovered.resolve("\\also_here") != null)
    @assert(recovered.journalRecordsRead == recovered.sequence - recovered.checkpointAt + 1)
    recovered.close()

    // The salvaged container is now consolidated and still opens normally.
    var again = expect Volume.open(salvaged, testPassword())
    @assert(again.sequence == again.checkpointAt)
    @assert(again.resolve("\\survivor.bin") != null)
    again.close()
}

#test
{
    // A journal record that was torn stops the replay: everything after it
    // belongs to an operation that never completed.
    let path = testContainerPath("torn")
    defer discard catch File.delete(path)

    var volume        = expect Volume.create(path, testPassword(), MinimumSize)
    let firstSequence = volume.sequence + 1
    discard expect volume.createNode("\\first", true, FileAttributeDirectory, emptyBytes())
    discard expect volume.createNode("\\second", true, FileAttributeDirectory, emptyBytes())
    let salvaged = testContainerPath("torn_salvaged")
    defer discard catch File.delete(salvaged)
    snapshotContainer(salvaged, path)
    volume.close()

    // Damage the first record. The second one is intact but unreachable, because
    // replay may not skip a missing sequence.
    flipByteAt(salvaged, JournalAreaOffset + (firstSequence % JournalCapacity) * JournalRecordSize + HeaderRecordPrefixSize)

    var recovered = expect Volume.open(salvaged, testPassword())
    @assert(recovered.resolve("\\first") == null)
    @assert(recovered.resolve("\\second") == null)
    @assert(recovered.journalRecordsRead == 1)
    recovered.close()
}

#test
{
    // A journal sequence belongs to exactly one circular slot. Even an authentic record in a
    // different slot is not the next durable operation and must not be searched for elsewhere.
    let path = testContainerPath("misplaced_journal")
    defer discard catch File.delete(path)

    var volume    = expect Volume.create(path, testPassword(), MinimumSize)
    let expected  = volume.checkpointAt + 1
    let wrongSlot = (expected + 1) % JournalCapacity
    var removed:  Array'u64
    var upserted: Array'(*Node)
    var metadata: Array'(*Node)
    let plain     = JournalRecord.encode(expected, volume.nextNodeId, volume.label, removed.toSlice(), upserted.toSlice(), metadata.toSlice())
    expect volume.writeFramedRecord(JournalAreaOffset + wrongSlot * JournalRecordSize, JournalRecordSize, JournalLocatorKind, JournalKind, wrongSlot, plain.toSlice())
    volume.close()

    var reopened = expect Volume.open(path, testPassword())
    @assert(reopened.sequence == reopened.checkpointAt)
    @assert(reopened.journalRecordsRead == 1)
    reopened.close()
}

#test
{
    // Advancing a sequence is part of every durable change. A header at the integer limit cannot
    // wrap back to zero and make a later record look older than the container.
    let path = testContainerPath("maximum_sequence")
    defer discard catch File.delete(path)

    var volume = expect Volume.create(path, testPassword(), MinimumSize)
    volume.sequence     = Swag.U64.Max
    volume.checkpointAt = Swag.U64.Max
    var plain = expect volume.serializeHeader()
    expect volume.writeFramedRecord(HeaderAreaOffset + cast(u64) volume.activeSlot * HeaderSlotSize, HeaderSlotSize, HeaderLocatorKind, HeaderKind, volume.activeSlot, plain.toSlice())
    volume.dirty = false
    volume.close()

    @assert(rejectsPassword(path, testPassword()))
}

#test
{
    // A container may now hold far more metadata than one header slot, because
    // the node table lives in encrypted blocks and the header only indexes them.
    let path = testContainerPath("paging")
    defer discard catch File.delete(path)

    // The test format uses a 16 KiB header slot, so 300 ordinary nodes cross the same
    // metadata-paging boundary without performing thousands of durable commits.
    const FileCount = 300'u64

    var volume = expect Volume.create(path, testPassword(), pagingContainerSize())
    for i in FileCount do
        discard expect volume.createNode(Format.toString("\\entry_%.bin", i), false, FileAttributeNormal, emptyBytes())
    volume.close()

    @assert(volume.metadataSize > HeaderPlainSize)
    @assert(volume.metadataPages.count > 1)

    var reopened = expect Volume.open(path, testPassword())
    @assert(reopened.nodes.count == FileCount + 1)
    for i in FileCount do
        @assert(reopened.resolve(Format.toString("\\entry_%.bin", i)) != null)

    // Deleting everything gives the metadata pages back too.
    for i in FileCount
    {
        let node = reopened.resolve(Format.toString("\\entry_%.bin", i))!
        expect reopened.deleteNode(node.id)
    }

    reopened.close()

    var emptied = expect Volume.open(path, testPassword())
    @assert(emptied.nodes.count == 1)
    @assert(emptied.metadataPages.count == 1)
    emptied.close()
}

#test
{
    // A password only ever unwraps the master key, so changing one is a single
    // key-slot write and leaves every encrypted block alone.
    let path = testContainerPath("keyslots")
    defer discard catch File.delete(path)

    let payload: [64] u8 = [7]
    var volume           = expect Volume.create(path, testPassword(), MinimumSize)
    let fileId           = expect volume.createNode("\\secret.bin", false, FileAttributeNormal, emptyBytes())
    @assert(expect volume.writeNode(fileId, 0, payload, false, false) == #sizeof(payload))
    @assert(volume.keySlotCount() == 1)

    expect volume.changePassword(testPassword(), secondPassword())
    volume.close()

    @assert(rejectsPassword(path, testPassword()))
    var reopened = expect Volume.open(path, secondPassword())
    var readBack: [64] u8
    let node     = reopened.resolve("\\secret.bin")!
    @assert(expect reopened.readNode(node.id, 0, readBack) == #sizeof(readBack))
    @assert(sameTestBytes(payload, readBack))

    // A second password opens the same container, and removing one leaves the
    // other working.
    discard expect reopened.addPassword(thirdPassword())
    @assert(reopened.keySlotCount() == 2)
    reopened.close()

    var viaThird = expect Volume.open(path, thirdPassword())
    @assert(viaThird.keySlotCount() == 2)
    @assert(viaThird.resolve("\\secret.bin") != null)
    expect viaThird.removePassword(secondPassword())
    @assert(viaThird.keySlotCount() == 1)
    viaThird.close()

    @assert(rejectsPassword(path, secondPassword()))
    var last = expect Volume.open(path, thirdPassword())
    @assert(last.resolve("\\secret.bin") != null)

    // The last remaining password cannot be removed: a container no password
    // opens is unrecoverable.
    discard catch last.removePassword(thirdPassword()) as lastError
    @assert(lastError != null)

    discard catch last.addPassword(thirdPassword()) as duplicateError
    @assert(duplicateError != null)
    discard catch last.changePassword(secondPassword(), testPassword()) as wrongCurrentError
    @assert(wrongCurrentError != null)
    last.close()
}

#test
{
    // Every key slot is uniformly distributed, so the slot area never says how
    // many passwords a container has.
    let path = testContainerPath("slotnoise")
    defer discard catch File.delete(path)

    var volume = expect Volume.create(path, testPassword(), MinimumSize)
    volume.close()

    var file = expect File.open(path, .Open, .ReadWrite, .Read)
    var area: [KeySlotAreaSize] u8
    @assert(expect file.readExactAt(KeySlotAreaOffset, area))
    file.close()

    // A used slot and an unused one are both noise: no run of repeated bytes
    // marks the boundary between them.
    var runs = 0'u64
    for i in KeySlotAreaSize - 1
    {
        if area[i] == area[i + 1] do
            runs += 1
    }

    @assert(runs < KeySlotAreaSize / 8)

    // Damaging the only slot makes the container unopenable, which is what shows
    // the master key really is wrapped there and nowhere else.
    flipByteAt(path, KeySlotAreaOffset)
    @assert(rejectsPassword(path, testPassword()))
}

#test
{
    // Creation reports how far the randomization has come, and reaches the end of it.
    let path = testContainerPath("progress")
    defer discard catch File.delete(path)

    var progress: VolumeProgress
    @assert(progress.ratio() == 0)
    @assert(!progress.isCanceled())

    var volume = expect Volume.create(path, testPassword(), MinimumSize, &progress)
    volume.close()
    @assert(progress.ratio() == 1)
}

#test
{
    // A creation the caller stops fails with `Canceled` and leaves nothing behind, exactly
    // like every other failure of `create`.
    let path = testContainerPath("cancel")
    defer discard catch File.delete(path)

    var progress: VolumeProgress
    progress.cancel()
    @assert(progress.isCanceled())

    var stopped = catch Volume.create(path, testPassword(), MinimumSize, &progress) as cancelError
    stopped.close()
    @assert(cancelError != null)
    @assert((cast(Error) cancelError).kind == .Canceled)
    @assert(!File.exists(path))

    // Arming the tracker for the next operation clears the cancellation the stopped one left.
    progress.begin(0)
    @assert(!progress.isCanceled())

    var created = expect Volume.create(path, testPassword(), MinimumSize, &progress)
    created.close()
    @assert(File.exists(path))
}

#test
{
    // The fill is what hides which blocks of a container hold data, so it has to look like
    // noise everywhere, including across the chunk boundary the fill loop writes on.
    let path = testContainerPath("fillnoise")
    defer discard catch File.delete(path)

    let size = 2'u64 * 1024 * 1024
    @assert(size > MinimumSize)
    var volume = expect Volume.create(path, testPassword(), size)
    volume.close()

    // A window that straddles the chunk boundary, taken past every structure the container
    // writes, so what it reads is fill and nothing else.
    var file = expect File.open(path, .Open, .ReadWrite, .Read)
    defer file.close()
    var window: [8192] u8
    @assert(expect file.readExactAt(RandomizeChunkSize - 4096, window))

    var runs = 0'u64
    var counts: [256] u64
    for byte, i in window
    {
        counts[byte] += 1
        if i and window[i - 1] == byte do
            runs += 1
    }

    @assert(runs < @countof(window) / 8)
    for count in counts do
        @assert(count > 0)
}

#test
{
    // A container with no password is a container whose key slot the empty password opens.
    // Everything else about it is unchanged: the blocks are encrypted under the same kind of
    // master key, and it reports nothing about itself that a protected one would not.
    let path = testContainerPath("nopassword")
    defer discard catch File.delete(path)

    let payload: [32] u8 = [3]
    var volume           = expect Volume.create(path, emptyBytes(), MinimumSize)
    let fileId           = expect volume.createNode("\\open.bin", false, FileAttributeNormal, emptyBytes())
    @assert(expect volume.writeNode(fileId, 0, payload, false, false) == #sizeof(payload))
    @assert(volume.keySlotCount() == 1)
    volume.close()

    // It opens without one, and refuses a password all the same: an unprotected container is
    // not one that takes anything.
    @assert(rejectsPassword(path, testPassword()))
    var reopened = expect Volume.open(path, emptyBytes())
    var readBack: [32] u8
    let node     = reopened.resolve("\\open.bin")!
    @assert(expect reopened.readNode(node.id, 0, readBack) == #sizeof(readBack))
    @assert(sameTestBytes(payload, readBack))

    // Protecting it afterwards is one key-slot write, and it reads back exactly the same.
    expect reopened.changePassword(emptyBytes(), testPassword())
    reopened.close()

    @assert(rejectsPassword(path, emptyBytes()))
    var protected = expect Volume.open(path, testPassword())
    @assert(protected.resolve("\\open.bin") != null)

    // A second way in still has to be a password: an unprotected slot beside a protected one
    // would undo the protection without saying so.
    discard catch protected.addPassword(emptyBytes()) as emptyAddError
    @assert(emptyAddError != null)

    // Taking the protection back off is the same call the other way round.
    expect protected.changePassword(testPassword(), emptyBytes())
    protected.close()

    @assert(rejectsPassword(path, testPassword()))
    var open = expect Volume.open(path, emptyBytes())
    @assert(open.resolve("\\open.bin") != null)
    open.close()
}

#test
{
    // Growing extends the file, randomizes what it added, and publishes the new geometry in
    // one checkpoint. Everything the container held is where it was.
    let path = testContainerPath("grow")
    defer discard catch File.delete(path)

    let payload: [64] u8 = [9]
    var volume           = expect Volume.create(path, testPassword(), MinimumSize)
    let fileId           = expect volume.createNode("\\kept.bin", false, FileAttributeNormal, emptyBytes())
    @assert(expect volume.writeNode(fileId, 0, payload, false, false) == #sizeof(payload))

    let originalBlocks = volume.blockCount
    let originalFree   = volume.freeBlockCount()

    // A container can only grow, and only by something: neither of those is a size a caller
    // can reasonably have meant.
    discard catch volume.grow(MinimumSize) as sameError
    @assert(sameError != null)
    discard catch volume.grow(MinimumSize - 1) as smallerError
    @assert(smallerError != null)

    let grownSize = MinimumSize + 64 * BlockRecordSize
    expect volume.grow(grownSize)
    @assert(volume.containerSize == grownSize)
    @assert(volume.blockCount == originalBlocks + 64)
    @assert(volume.freeBlockCount() == originalFree + 64)
    let grownPhysical = volume.physicalSize
    volume.close()

    @assert(expect File.info(path).size == grownPhysical)

    // The new geometry survives the round trip, and the added blocks are usable: the free list
    // is derived from what the node table references, so a block that was never published
    // would simply never be handed out.
    var reopened = expect Volume.open(path, testPassword())
    @assert(reopened.containerSize == grownSize)
    @assert(reopened.blockCount == originalBlocks + 64)

    var readBack: [64] u8
    let node = reopened.resolve("\\kept.bin")!
    @assert(expect reopened.readNode(node.id, 0, readBack) == #sizeof(readBack))
    @assert(sameTestBytes(payload, readBack))

    let addedId = expect reopened.createNode("\\added.bin", false, FileAttributeNormal, emptyBytes())
    @assert(expect reopened.writeNode(addedId, 0, payload, false, false) == #sizeof(payload))
    reopened.close()
}

#test
{
    // A growth the caller stops puts the file back to the length its durable header claims,
    // so the container opens exactly as it did before it was asked to grow.
    let path = testContainerPath("growcancel")
    defer discard catch File.delete(path)

    var volume = expect Volume.create(path, testPassword(), MinimumSize)
    discard expect volume.createNode("\\kept.bin", false, FileAttributeNormal, emptyBytes())
    volume.close()

    var progress: VolumeProgress
    progress.cancel()

    var stopped = expect Volume.open(path, testPassword())
    let previousPhysical = stopped.physicalSize
    discard catch stopped.grow(MinimumSize + 64 * BlockRecordSize, &progress) as cancelError
    @assert(cancelError != null)
    @assert((cast(Error) cancelError).kind == .Canceled)
    @assert(stopped.containerSize == MinimumSize)
    stopped.close()

    @assert(expect File.info(path).size == previousPhysical)
    var reopened = expect Volume.open(path, testPassword())
    @assert(reopened.containerSize == MinimumSize)
    @assert(reopened.resolve("\\kept.bin") != null)
    reopened.close()
}

#test
{
    // Shrinking evacuates live blocks and metadata pages from the discarded tail before the
    // authenticated geometry changes. The file and its payload survive the round trip.
    let path = testContainerPath("shrink")
    defer discard catch File.delete(path)

    const InitialSize = MinimumSize + 128 * BlockRecordSize
    var volume   = expect Volume.create(path, testPassword(), InitialSize)
    let fillerId = expect volume.createNode("\\filler.bin", false, FileAttributeNormal, emptyBytes())
    var filler: Array'u8
    filler.resize(MinimumBlocks * BlockSize)
    @assert(expect volume.writeNode(fillerId, 0, filler.toSlice(), false, false) == filler.count)
    expect volume.commit()
    let fileId = expect volume.createNode("\\kept.bin", false, FileAttributeNormal, emptyBytes())
    var payload: [2 * BlockSize] u8
    for &value, index in payload do
        value[] = cast(u8) (index % 251)
    @assert(expect volume.writeNode(fileId, 0, payload, false, false) == #sizeof(payload))
    expect volume.deleteNode(fillerId)

    // Allocation starts at the high end, so this file really occupies the part being removed.
    let before = volume.nodeById(fileId)!
    @assert(before.blocks.count and before.blocks[0].physical >= (MinimumSize - DataOffset) / BlockRecordSize)

    expect volume.resize(MinimumSize)
    @assert(volume.containerSize == MinimumSize)
    @assert(volume.blockCount == (MinimumSize - DataOffset) / BlockRecordSize)
    let shrunkPhysical = volume.physicalSize
    volume.close()
    @assert(expect File.info(path).size == shrunkPhysical)

    var reopened = expect Volume.open(path, testPassword())
    var readBack: [2 * BlockSize] u8
    @assert(expect reopened.readNode(reopened.resolve("\\kept.bin")!.id, 0, readBack) == #sizeof(readBack))
    @assert(sameTestBytes(payload, readBack))
    reopened.close()

    // This is the recoverable state left by a process that stopped after publishing the smaller
    // header but before truncating. The next writable open completes that last step.
    var tail = expect File.open(path, .Open, .ReadWrite, .Read)
    expect tail.resize(shrunkPhysical + RandomizeChunkSize)
    tail.close()
    var recovered = expect Volume.open(path, testPassword())
    @assert(recovered.containerSize == MinimumSize)
    recovered.close()
    @assert(expect File.info(path).size == shrunkPhysical)
}

#test
{
    // Cancellation before the first relocation leaves both the authenticated geometry and the
    // physical file length unchanged.
    let path = testContainerPath("shrinkcancel")
    defer discard catch File.delete(path)

    const InitialSize = MinimumSize + 64 * BlockRecordSize
    var volume   = expect Volume.create(path, testPassword(), InitialSize)
    let fillerId = expect volume.createNode("\\filler.bin", false, FileAttributeNormal, emptyBytes())
    var filler: Array'u8
    filler.resize(MinimumBlocks * BlockSize)
    @assert(expect volume.writeNode(fillerId, 0, filler.toSlice(), false, false) == filler.count)
    expect volume.commit()
    let fileId = expect volume.createNode("\\tail.bin", false, FileAttributeNormal, emptyBytes())
    var payload: [BlockSize] u8 = [7]
    @assert(expect volume.writeNode(fileId, 0, payload, false, false) == BlockSize)
    expect volume.deleteNode(fillerId)

    var progress: VolumeProgress
    progress.cancel()
    let previousPhysical = volume.physicalSize
    discard catch volume.resize(MinimumSize, &progress) as cancelError
    @assert(cancelError != null and (cast(Error) cancelError).kind == .Canceled)
    @assert(volume.containerSize == InitialSize)
    volume.close()
    @assert(expect File.info(path).size == previousPhysical)
}

// An existing volume can refresh its camouflage repeatedly. Its logical capacity and payload
// never move, while every refresh chooses another physical length.
#test
{
    let path = testContainerPath("existing-camouflage")
    defer discard catch File.delete(path)

    var built = expect Volume.create(path, testPassword(), MinimumSize)
    let fileId = expect built.createNode("\\kept.bin", false, FileAttributeNormal, emptyBytes())
    var payload: [BlockSize] u8 = [73]
    @assert(expect built.writeNode(fileId, 0, payload, false, false) == BlockSize)
    expect built.checkpoint()
    built.close()

    var volume = expect Volume.open(path, testPassword())
    @assert(volume.containerSize == MinimumSize)
    let originalPhysical = volume.physicalSize
    expect volume.reapplyCamouflage()
    let firstPhysical = volume.physicalSize
    @assert(firstPhysical > MinimumSize)
    @assert(firstPhysical != originalPhysical)
    expect volume.reapplyCamouflage()
    @assert(volume.physicalSize > MinimumSize)
    @assert(volume.physicalSize != firstPhysical)
    var readBack: [BlockSize] u8
    @assert(expect volume.readNode(volume.resolve("\\kept.bin")!.id, 0, readBack) == BlockSize)
    @assert(sameTestBytes(payload, readBack))
    volume.close()
}

// A container opened read only refuses every change, and the refusal is the file handle's.
//
// The guarantee is not a flag callers are trusted to honour: the file itself is opened without
// write access, so a change that slipped past the checks below would be refused by Windows. What
// the checks add is the *kind*, which is what the filesystem bridge turns into the NTSTATUS a
// program expects from a write-protected volume.
#test
{
    let path = testContainerPath("readonly")
    defer discard catch File.delete(path)

    var built          = expect Volume.create(path, testPassword(), MinimumSize)
    let fileId         = expect built.createNode("\\note.txt", false, FileAttributeNormal, emptyBytes())
    let stored: [4] u8 = [7, 8, 9, 10]
    @assert(expect built.writeNode(fileId, 0, stored, false, false) == 4)
    expect built.commit()
    built.close()

    var volume = expect Volume.open(path, testPassword(), readOnly: true)
    defer volume.close()
    @assert(volume.readOnly)

    // Reading is untouched: a read-only mount is a mount, not a refusal to open.
    let node = volume.resolve("\\note.txt")
    @assert(node != null)
    var readBack: [4] u8
    @assert(expect volume.readNode(node.id, 0, readBack) == 4)
    @assert(sameTestBytes(readBack, stored))

    // Every way in reports the same kind, whether it would have written a byte, a name, or a
    // key slot.
    func refuses(err: #null any)->bool
    {
        if err == null do
            return false
        switch err
        {
        case Error as volumeError: return volumeError.kind == .WriteProtected
        }

        return false
    }

    @assert(refuses(catch volume.writeNode(node.id, 0, stored, false, false)))
    @assert(refuses(catch volume.createNode("\\second.txt", false, FileAttributeNormal, emptyBytes())))
    @assert(refuses(catch volume.renameNode(node.id, "\\other.txt", false)))
    @assert(refuses(catch volume.resizeNode(node.id, 0)))
    @assert(refuses(catch volume.deleteNode(node.id)))
    @assert(refuses(catch volume.commit()))
    @assert(refuses(catch volume.checkpoint()))
    @assert(refuses(catch volume.changePassword(testPassword(), secondPassword())))

    // And nothing was staged either: a read-only mount that quietly marked the container dirty
    // would try to write it back the moment it closed.
    @assert(!volume.dirty)
}
