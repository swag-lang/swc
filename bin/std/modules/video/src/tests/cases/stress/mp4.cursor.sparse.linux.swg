#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Swag, Core, Core.Errors

// A sparse free box places a valid indexed fragment beyond 4 GiB without filling the gap.
#[Swag.TestTag("stress")]
#test
{
    let compactPath = videoTempPath("fragmented-small-index", "mp4")
    let sparsePath  = videoTempPath("fragmented-sparse-index", "mp4")
    defer discard catch File.delete(compactPath)
    defer discard catch File.delete(sparsePath)

    var input      = expect ByteSource.openFile(videoFixturePath("ffmpeg-h264-baseline.packets").toString())
    let configSize = expect input.readBigEndian'u32()
    var config: Array'u8
    config.resize(configSize)
    expect input.readExact(config.toSlice())
    let packetSize = expect input.readBigEndian'u32()
    var picture: Array'u8
    picture.resize(packetSize)
    expect input.readExact(picture.toSlice())
    var writer = expect Mp4.FragmentedWriter.create(compactPath, 64, 48, 12_800, config.toSlice(), Mp4.FragmentedOptions{3, 4 * 1024 * 1024, 1, true})
    expect writer.addPacket(EncodedPacket{picture.toSlice(), 0, 0, 512, true})
    expect writer.addPacket(EncodedPacket{picture.toSlice(), 512, 512, 512, true})
    expect writer.end()

    let bytes          = expect File.readAllBytes(compactPath)
    var boxes          = ByteSource.openMemory(bytes.toSlice())
    var secondFragment = 0'u64
    var indexOffset    = 0'u64
    var fragmentCount  = 0'u64
    while boxes.position() < bytes.count
    {
        let offset = boxes.position()
        let size   = expect boxes.readBigEndian'u32()
        Swag.require(size >= 8 and size <= bytes.count - offset)
        if Memory.compare(bytes.storage() + offset + 4, "moof".buffer, 4) == 0
        {
            fragmentCount += 1
            if fragmentCount == 2 do
                secondFragment = offset
        }

        if Memory.compare(bytes.storage() + offset + 4, "mfra".buffer, 4) == 0 do
            indexOffset = offset
        expect boxes.seek(offset + size)
    }

    Swag.require(fragmentCount == 2 and secondFragment > 0 and indexOffset > secondFragment)

    const LargeOffset = 0x1_0000_1000'u64
    let freeSize = LargeOffset - secondFragment
    var freeHeader: ConcatBuffer
    var freeSink = ByteSink.createMemory(&freeHeader)
    expect freeSink.writeBigEndian(1'u32)
    expect freeSink.writeText("free")
    expect freeSink.writeBigEndian(freeSize)
    let headerBytes = freeHeader.toArray()

    var trailer: Array'u8
    trailer.add(bytes.toSlice()[indexOffset until bytes.count])
    var trailerReader = ByteSource.openMemory(trailer.toSlice())

    // mfra header, tfra header and fields, then the first 20-byte entry and second entry's time.
    const SecondOffsetField = 8 + 8 + 4 + 4 + 4 + 4 + 20 + 8
    expect trailerReader.seek(SecondOffsetField)
    Swag.require(expect trailerReader.readBigEndian'u64() == secondFragment)
    for byte in 8 do
        trailer[SecondOffsetField + byte] = cast(u8, (LargeOffset >> ((7 - byte) * 8)) & 0xFF)

    scope
    {
        var sparse = expect File.open(sparsePath, .CreateNew, .ReadWrite, .Zero)
        expect sparse.writeAll(bytes.toSlice()[0 until secondFragment])
        expect sparse.writeAll(headerBytes.toSlice())
        expect sparse.seek(.Begin, LargeOffset)
        expect sparse.writeAll(bytes.toSlice()[secondFragment until indexOffset])
        expect sparse.writeAll(trailer.toSlice())
        sparse.close()
    }

    var index = expect Mp4.FragmentedIndex.open(sparsePath)
    Swag.require(index.entryCount() == 2)
    let point = expect index.point(1)
    Swag.require(point.moofOffset == LargeOffset and point.decodeTime == 512)
    var later: Mp4.FragmentedSeekPoint
    Swag.require(expect index.tryFindAtOrAfter(1, &later))
    Swag.require(later.moofOffset == LargeOffset)
    var cursor = expect Mp4.FragmentedPacketCursor.open(sparsePath)
    Swag.require(expect cursor.trySeekVideoAtOrBefore(&index, 512))
    var found: Mp4.FragmentedCursorPacket
    Swag.require(expect cursor.nextPacket(&found))
    Swag.require(found.isVideo and found.info.isKeyFrame and found.info.decodeTime == 512)
    Swag.require(found.fragmentOffset == LargeOffset and found.sampleNumber == 1)
    var payload: Array'u8
    expect cursor.readPayload(found, &payload)
    Swag.require(payload.count == picture.count)
    Swag.require(Memory.compare(payload.storage(), picture.storage(), picture.count) == 0)
    Swag.require(not expect cursor.nextPacket(&found))

    var sequential = expect Mp4.FragmentedPacketCursor.open(sparsePath)
    Swag.require(expect sequential.nextPacket(&found))
    Swag.require(expect sequential.nextPacket(&found))
    Swag.require(found.info.sourceOffset > Swag.U32.Max)
    Swag.require(not expect sequential.nextPacket(&found))
    index.close()
    cursor.close()
    sequential.close()
    Swag.require(expect Mp4.rebuildFragmentedIndex(sparsePath) == 2)
    var rebuilt = expect Mp4.FragmentedIndex.open(sparsePath)
    Swag.require((expect rebuilt.point(1)).moofOffset == LargeOffset)
}
