#global if #command == Swag.CompilerCommand.Test
#global private

using Compress

// The second block copies sixteen bytes from the first. Both block checksums and
// the content checksum are present, with no advertised content size.
const LinkedFrame: [?] u8 = [
    0x04, 0x22, 0x4D, 0x18, 0x54, 0x40, 0xAE, 0x10, 0x00, 0x00, 0x80, 0x61, 0x62, 0x63,
    0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E, 0x6F, 0x70, 0x62,
    0x8B, 0x2D, 0x9D, 0x09, 0x00, 0x00, 0x00, 0x0C, 0x10, 0x00, 0x50, 0x74, 0x61, 0x69,
    0x6C, 0x21, 0xD0, 0x13, 0x07, 0xE6, 0x00, 0x00, 0x00, 0x00, 0x8A, 0x33, 0x1C, 0x7B,
]

const LinkedText = "abcdefghijklmnopabcdefghijklmnoptail!"
const Skippable: [?] u8 = [0x5A, 0x2A, 0x4D, 0x18, 3, 0, 0, 0, 11, 22, 33]

#test
{
    let plain = expect Lz4Frame.decompress(LinkedFrame, maxOutputSize: LinkedText.count)
    Swag.require(Slice.equals(plain.toSlice(), LinkedText))

    for size in LinkedFrame.count
    {
        var error: Swag.Error
        discard catch Lz4Frame.decompress(LinkedFrame[until size], LinkedText.count) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }
}

#test
{
    var frame: Array!{u8}
    frame.add(LinkedFrame)
    for index in [6_u64, 27, 44, LinkedFrame.count - 1]
    {
        frame[index] ^= 0x80
        var error: Swag.Error
        discard catch Lz4Frame.decompress(frame.toSlice(), LinkedText.count) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
        frame[index] ^= 0x80
    }

    // Only the descriptor changes. An independent block cannot see the first block.
    frame[4] = 0x74
    frame[6] = 0xBD
    var historyError: Swag.Error
    discard catch Lz4Frame.decompress(frame.toSlice(), LinkedText.count) as historyError
    Swag.require(historyError.value() is Errors.InvalidFormatError)
}

#test
{
    let empty = expect Lz4Frame.compress("")
    let last  = expect Lz4Frame.compress("more")
    var frames: Array!{u8}
    frames.add(Skippable)
    frames.add(LinkedFrame)
    frames.add(empty.toSlice())
    frames.add(last.toSlice())

    const Expected = "abcdefghijklmnopabcdefghijklmnoptail!more"
    var output: [Expected.count + 2] u8
    output[0] = 13
    output[output.count - 1] = 31
    let destination = output[1 until output.count - 1]
    let written = expect Lz4Frame.decompressInto(destination, frames.toSlice())
    Swag.require(written == Expected.count and Slice.equals(destination, Expected))
    Swag.require(output[0] == 13 and output[output.count - 1] == 31)

    let decodedEmpty = expect Lz4Frame.decompress(empty.toSlice(), 0)
    Swag.require(not decodedEmpty.count)
    let skipped = expect Lz4Frame.decompress(Skippable, 0)
    Swag.require(not skipped.count)

    var limitError: Swag.Error
    discard catch Lz4Frame.decompress(LinkedFrame, LinkedText.count - 1) as limitError
    Swag.require(limitError.value() is Errors.UnsupportedFormatError)

    var overlapError: Swag.Error
    discard catch Lz4Frame.decompressInto(frames.toSlice(), frames.toSlice()) as overlapError
    Swag.require(overlapError.value() is Errors.BadParameterError)
}

#test
{
    const BlockSize = 256_u64 * 1024
    var data: Array!{u8}
    data.resize(BlockSize + 10013)
    var random = 17_u32
    for index in BlockSize
    {
        random ^= random << 13
        random ^= random >> 17
        random ^= random << 5
        data[index] = Math.byteAt(random, 0)
    }

    for index in BlockSize until data.count
    {
        data[index] = cast(u8, index % 9)
    }

    let packed = expect Lz4Frame.compress(data.toSlice())
    Swag.require((packed[15 + 3] & 0x80) != 0)
    Swag.require((packed[15 + 4 + BlockSize + 3] & 0x80) == 0)
    let decoded = expect Lz4Frame.decompress(packed.toSlice(), maxOutputSize: data.count)
    Swag.require(Slice.equals(decoded.toSlice(), data.toSlice()))
}
