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
    return Path.combine(temp.toString(),
                        Format.toString("scrypt_%_%.bin", tag, Guid64.random()))
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
    @assert(expect file.readExactAt(Crypto.SaltSize + slot * HeaderSlotSize, bytes.toSlice()))
    let result = testDigestBytes(Hash.Sha256.compute(bytes.toSlice()))
    Core.Crypto.secureClear(bytes.toSlice())
    return result
}

func flipHeaderByte(path: string, slot: u64)
{
    var file = expect File.open(path, .Open, .ReadWrite, .Read)
    defer file.close()
    let offset = Crypto.SaltSize + slot * HeaderSlotSize +
                 HeaderRecordPrefixSize
    var byte: [1] u8
    @assert(expect file.readExactAt(offset, byte))
    byte[0] ^= 0x5A
    expect file.writeAllAt(offset, byte)
    expect file.flush()
}

func writeLegacyHeader(volume: *Volume)
{
    let sequence = volume.sequence + 1
    let slot     = 1'u32 - volume.activeSlot
    var plain    = expect volume.serialize(sequence)
    Crypto.store32(notnull plain.buffer + #sizeof(HeaderMagic),
                   LegacyFormatVersion)
    plain.resize(LegacyHeaderPlainSize)

    var record: Array'u8
    record.resize(HeaderSlotSize)
    let nonce      = record[0 until Crypto.NonceSize]
    let ciphertext = record[Crypto.NonceSize until
                            Crypto.NonceSize + LegacyHeaderPlainSize]
    let tag = record[Crypto.NonceSize + LegacyHeaderPlainSize until
                     HeaderSlotSize]
    expect Crypto.seal(&volume.keys, HeaderKind, slot, plain.toSlice(), nonce, ciphertext, tag)
    expect volume.file.writeAllAt(Crypto.SaltSize + slot * HeaderSlotSize, record.toSlice())
    expect volume.file.flush()
    Core.Crypto.secureClear(plain.toSlice())
    Core.Crypto.secureClear(record.toSlice())
}

#test
{
    let path = testContainerPath("lifecycle")
    defer discard catch File.delete(path)

    let security: [6] u8 = [1, 4, 9, 16, 25, 36]
    var volume           = expect Volume.create(path, testPassword(), MinimumSize)
    @assert(volume.containerSize == MinimumSize)
    var storedLocator: [Crypto.RecordLocatorSize] u8
    @assert(expect volume.file.readExactAt(Crypto.SaltSize + volume.activeSlot * HeaderSlotSize, storedLocator))
    var expectedLocator = Crypto.recordLocator(volume.keys.authentication, HeaderLocatorKind, volume.activeSlot)
    @assert(Core.Crypto.constantTimeEqual(storedLocator[until HeaderLocatorCheckSize],
                                          expectedLocator[until HeaderLocatorCheckSize]))
    let encodedSize     = Crypto.load32(&storedLocator[HeaderLocatorCheckSize])
    let locatorMask     = Crypto.load32(&expectedLocator[HeaderLocatorCheckSize])
    let storedPlainSize = encodedSize ^ locatorMask
    @assert(storedPlainSize and storedPlainSize <= HeaderPlainSize)
    Core.Crypto.secureClear(expectedLocator)

    let root = volume.resolve("\\")
    @assert(root != null)
    @assert((notnull root).creationTime != 0)
    let rootTimestamp = Time.Timestamp.fromTicks((notnull root).creationTime + VolumeTimestampEpoch)
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
    @assert((notnull node).size == #sizeof(source))
    @assert(sameTestBytes((notnull node).security.toSlice(), security))
    var reopenedData: [7000] u8
    @assert(expect reopened.readNode((notnull node).id, 0, reopenedData) == #sizeof(reopenedData))
    @assert(sameTestBytes(source, reopenedData))
    expect reopened.deleteNode((notnull node).id)
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
    let sizeBeforeConstraint = (notnull volume.nodeById(fileId)).size
    let constrained: [4] u8  = [4, 5, 6, 7]
    @assert(expect volume.writeNode(fileId, sizeBeforeConstraint - 2, constrained, false, true) == 2)
    @assert((notnull volume.nodeById(fileId)).size == sizeBeforeConstraint)

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
    let reopenedNode = notnull reopened.resolve("\\sparse.bin")
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
    @assert((notnull volume.resolve("\\second.bin")).id == firstId)
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
    let activeSlot = volume.activeSlot
    volume.close()

    flipHeaderByte(path, activeSlot)
    var fallback = expect Volume.open(path, testPassword())
    @assert(fallback.resolve("\\latest") == null)
    fallback.close()

    flipHeaderByte(path, 1 - activeSlot)
    @assert(rejectsPassword(path, testPassword()))
}

#test
{
    let path = testContainerPath("legacy_header")
    defer discard catch File.delete(path)

    var volume = expect Volume.create(path, testPassword(), MinimumSize)
    discard expect volume.createNode("\\legacy", true, FileAttributeDirectory, emptyBytes())
    expect volume.commit()
    writeLegacyHeader(&volume)
    volume.close()

    var reopened = expect Volume.open(path, testPassword())
    @assert(reopened.sequence == 3)
    @assert(reopened.resolve("\\legacy") != null)
    reopened.close()
}
