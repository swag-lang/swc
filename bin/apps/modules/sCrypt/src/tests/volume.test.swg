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
    return Path.combine(temp.toString(), Format.toString("scrypt_%_%.bin", tag, Guid64.random()))
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
    for [i] in 8
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

#test
{
    let path = testContainerPath("lifecycle")
    defer discard catch File.delete(path)

    let security: [6] u8 = [1, 4, 9, 16, 25, 36]
    var volume           = expect Volume.create(path, testPassword(), MinimumSize)
    @assert(volume.containerSize == MinimumSize)
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
    for value, [i] in source do
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
    volume.close()

    var raw = expect File.open(path, .Open, .ReadWrite, .Read)
    @assert(expect raw.size() == MinimumSize)
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
    for [i] in 10 do
        @assert(grown[i] == 0)
    @assert(grown[10] == 1 and grown[11] == 2)
    for [i] in 12 until 20 do
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

    var emptyAttempt = catch Volume.create(path, emptyBytes(), MinimumSize) as emptyError
    emptyAttempt.close()
    @assert(emptyError != null)
    @assert(!File.exists(path))

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

    flipHeaderByte(path, 1 - activeSlot)
    @assert(rejectsPassword(path, testPassword()))
}

#test
{
    // A change is one small journal record, not a rewrite of the whole metadata
    // image, and an unmount consolidates the journal into a checkpoint.
    let path = testContainerPath("journal")
    defer discard catch File.delete(path)

    var volume = expect Volume.create(path, testPassword(), MinimumSize)
    let afterCreate = volume.sequence
    @assert(volume.checkpointAt == afterCreate)

    discard expect volume.createNode("\\one", true, FileAttributeDirectory, emptyBytes())
    discard expect volume.createNode("\\two", true, FileAttributeDirectory, emptyBytes())
    @assert(volume.sequence == afterCreate + 2)
    @assert(volume.checkpointAt == afterCreate)

    // Filling the journal forces a checkpoint rather than overwriting a record
    // that has not been consolidated yet.
    for [i] in JournalCapacity do
        discard expect volume.createNode(Format.toString("\\filler_%", i), true, FileAttributeDirectory, emptyBytes())
    @assert(volume.checkpointAt > afterCreate)
    @assert(volume.sequence - volume.checkpointAt < JournalCapacity)
    volume.close()

    var reopened = expect Volume.open(path, testPassword())
    @assert(reopened.resolve("\\one") != null)
    @assert(reopened.resolve("\\two") != null)
    for [i] in JournalCapacity do
        @assert(reopened.resolve(Format.toString("\\filler_%", i)) != null)

    // Closing consolidated everything, so nothing is left to replay.
    @assert(reopened.sequence == reopened.checkpointAt)
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

    var volume = expect Volume.create(path, testPassword(), MinimumSize)
    let checkpointBefore = volume.checkpointAt

    let fileId = expect volume.createNode("\\survivor.bin", false, FileAttributeNormal, emptyBytes())
    let payload: [40] u8 = [3]
    @assert(expect volume.writeNode(fileId, 0, payload, false, false) == #sizeof(payload))
    expect volume.commit()
    discard expect volume.createNode("\\also_here", true, FileAttributeDirectory, emptyBytes())

    // No checkpoint has happened since creation: everything above lives only in
    // the journal.
    @assert(volume.checkpointAt == checkpointBefore)
    @assert(volume.sequence > checkpointBefore)
    expect File.duplicate(salvaged, path)
    volume.close()

    var recovered = expect Volume.open(salvaged, testPassword())
    let node = recovered.resolve("\\survivor.bin")
    @assert(node != null)
    @assert(node.size == #sizeof(payload))
    var readBack: [40] u8
    @assert(expect recovered.readNode(node.id, 0, readBack) == #sizeof(readBack))
    @assert(sameTestBytes(payload, readBack))
    @assert(recovered.resolve("\\also_here") != null)
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

    var volume = expect Volume.create(path, testPassword(), MinimumSize)
    let firstSequence = volume.sequence + 1
    discard expect volume.createNode("\\first", true, FileAttributeDirectory, emptyBytes())
    discard expect volume.createNode("\\second", true, FileAttributeDirectory, emptyBytes())
    let salvaged = testContainerPath("torn_salvaged")
    defer discard catch File.delete(salvaged)
    expect File.duplicate(salvaged, path)
    volume.close()

    // Damage the first record. The second one is intact but unreachable, because
    // replay may not skip a missing sequence.
    flipByteAt(salvaged, JournalAreaOffset + (firstSequence % JournalCapacity) * JournalRecordSize + HeaderRecordPrefixSize)

    var recovered = expect Volume.open(salvaged, testPassword())
    @assert(recovered.resolve("\\first") == null)
    @assert(recovered.resolve("\\second") == null)
    recovered.close()
}

#test
{
    // A container may now hold far more metadata than one header slot, because
    // the node table lives in encrypted blocks and the header only indexes them.
    let path = testContainerPath("paging")
    defer discard catch File.delete(path)

    const FileCount = 1200'u64

    var volume = expect Volume.create(path, testPassword(), pagingContainerSize())
    for [i] in FileCount do
        discard expect volume.createNode(Format.toString("\\entry_%.bin", i), false, FileAttributeNormal, emptyBytes())
    volume.close()

    @assert(volume.metadataSize > HeaderPlainSize)
    @assert(volume.metadataPages.count > 1)

    var reopened = expect Volume.open(path, testPassword())
    @assert(reopened.nodes.count == FileCount + 1)
    for [i] in FileCount do
        @assert(reopened.resolve(Format.toString("\\entry_%.bin", i)) != null)

    // Deleting everything gives the metadata pages back too.
    for [i] in FileCount
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
    var volume = expect Volume.create(path, testPassword(), MinimumSize)
    let fileId = expect volume.createNode("\\secret.bin", false, FileAttributeNormal, emptyBytes())
    @assert(expect volume.writeNode(fileId, 0, payload, false, false) == #sizeof(payload))
    @assert(volume.keySlotCount() == 1)

    expect volume.changePassword(testPassword(), secondPassword())
    volume.close()

    @assert(rejectsPassword(path, testPassword()))
    var reopened = expect Volume.open(path, secondPassword())
    var readBack: [64] u8
    let node = reopened.resolve("\\secret.bin")!
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
    for [i] in KeySlotAreaSize - 1
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
