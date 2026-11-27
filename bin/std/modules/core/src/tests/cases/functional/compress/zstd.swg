#global if #command == Swag.CompilerCommand.Test
#global private

using Compress

// A checked frame with a Huffman literal table whose weights are themselves FSE-coded.
const HuffmanFrame: [?] u8 = [
    0x28, 0xB5, 0x2F, 0xFD, 0x24, 0x80, 0x9D, 0x02, 0x00, 0x02, 0xC8, 0x13, 0x0F, 0xB0,
    0x25, 0x0F, 0x8C, 0x5C, 0x23, 0x45, 0x32, 0xC9, 0x7A, 0x92, 0x24, 0x49, 0x45, 0x05,
    0x33, 0x99, 0xDE, 0xD8, 0x43, 0x34, 0x20, 0x2B, 0xAF, 0xF3, 0xD8, 0x6F, 0x98, 0xC2,
    0x09, 0x21, 0xDB, 0xB9, 0x9B, 0x54, 0xBB, 0x5B, 0x09, 0x33, 0xFE, 0x2B, 0xB6, 0x95,
    0x80, 0x94, 0xD3, 0x92, 0x81, 0x82, 0x5F, 0x44, 0x6C, 0x41, 0xDA, 0x93, 0x58, 0x19,
    0xF4, 0xC2, 0x82, 0xAE, 0x68, 0x64, 0xFE, 0x5A, 0xF5, 0x83, 0x71, 0x31, 0x82, 0xAC,
    0x36, 0x54, 0x2E, 0x5A, 0xBC, 0xB3, 0x3F, 0x00, 0xDD, 0xF5, 0xAD, 0x00]

// The header omits the decoded size. The block has a long match and a checksum.
const UnknownSizeFrame: [?] u8 = [
    0x28, 0xB5, 0x2F, 0xFD, 0x04, 0x58, 0x95, 0x00, 0x00, 0x50, 0x73, 0x77, 0x61, 0x67, 0x2D, 0x7A,
    0x73, 0x74, 0x64, 0x2D, 0x01, 0x00, 0x63, 0x11, 0xCD, 0x0B, 0x12, 0x20, 0xF4, 0x28, 0x80]
const UnknownSize       = 70000_u64
const Skippable: [?] u8 = [0x5A, 0x2A, 0x4D, 0x18, 3, 0, 0, 0, 11, 22, 33]

func fillLetters(output: [..] u8)
{
    var random = 13_u32
    for index in output.count
    {
        random        ^= random << 13
        random        ^= random >> 17
        random        ^= random << 5
        output[index] = cast(u8, 'a' + (random & 15))
    }
}

#test
{
    var expected: [128] u8
    fillLetters(expected)
    let plain = expect Zstd.decompress(HuffmanFrame, expected.count)
    Swag.require(Slice.equals(plain.toSlice(), expected))

    for size in HuffmanFrame.count
    {
        var error: Swag.Error
        discard catch Zstd.decompress(HuffmanFrame[until size], expected.count) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }

    var corrupt: Array!{u8}
    corrupt.add(HuffmanFrame)
    corrupt[corrupt.count - 1] ^= 0x80
    var error: Swag.Error
    discard catch Zstd.decompress(corrupt.toSlice(), expected.count) as error
    Swag.require(error.value() is Errors.InvalidFormatError)
}

#test
{
    const Period = "swag-zstd-"
    const Suffix = "last frame"
    let last  = Zstd.compress(Suffix)
    let empty = Zstd.compress("")
    var frames: Array!{u8}
    frames.add(UnknownSizeFrame)
    frames.add(Skippable)
    frames.add(empty.toSlice())
    frames.add(last.toSlice())

    const Size = UnknownSize + Suffix.count
    var output: [Size + 2] u8
    output[0]        = 37
    output[Size + 1] = 73
    let destination = output[1 until Size + 1]
    let written     = expect Zstd.decompressInto(destination, frames.toSlice())
    Swag.require(written == Size and output[0] == 37 and output[Size + 1] == 73)
    for index in UnknownSize
    {
        Swag.require(destination[index] == Period[index % Period.count])
    }

    Swag.require(Slice.equals(destination[UnknownSize to], Suffix))

    var limitError: Swag.Error
    discard catch Zstd.decompress(UnknownSizeFrame, UnknownSize - 1) as limitError
    Swag.require(limitError.value() is Errors.UnsupportedFormatError)
    var overlapError: Swag.Error
    discard catch Zstd.decompressInto(frames.toSlice(), frames.toSlice()) as overlapError
    Swag.require(overlapError.value() is Errors.BadParameterError)
}

#test
{
    var data: Array!{u8}
    data.resize(262145)
    fillLetters(data.toSlice()[until 131072])
    Memory.set(data.storage() + 131072, 0xC7, data.count - 131072)
    for count in [0_u64, 1, 255, 256, 65791, 65792, 131072, 131073, data.count]
    {
        let input = data.toSlice()[until count]
        let frame = Zstd.compress(input)
        let plain = expect Zstd.decompress(frame.toSlice(), count)
        Swag.require(Slice.equals(plain.toSlice(), input))
    }
}

#test
{
    const DictionaryHeader: [?] u8 = [0x28, 0xB5, 0x2F, 0xFD, 0x21, 7, 0, 1, 0, 0]
    var error: Swag.Error
    discard catch Zstd.decompress(DictionaryHeader, 0) as error
    Swag.require(error.value() is Errors.UnsupportedFormatError)
}
