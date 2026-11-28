#global if #command == Swag.CompilerCommand.Test
#global private

using Compress, Swag

// Generated with Python's zlib and an RFC 1952 header containing all optional fields.
const ReferenceMember: [?] u8 = [
    0x1F, 0x8B, 0x08, 0x1E, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF, 0x06, 0x00, 0x58, 0x59,
    0x02, 0x00, 0x41, 0x42, 0x73, 0x61, 0x6D, 0x70, 0x6C, 0x65, 0x00, 0x63, 0x6F, 0x6D,
    0x6D, 0x65, 0x6E, 0x74, 0x00, 0x2F, 0x54, 0x0B, 0x72, 0x73, 0x56, 0x30, 0xB4, 0x34,
    0x35, 0x52, 0x28, 0x49, 0x2D, 0x2E, 0x51, 0x28, 0x48, 0xAC, 0xCC, 0xC9, 0x4F, 0x4C,
    0xE1, 0x02, 0x00, 0x25, 0xC0, 0x7B, 0x57, 0x16, 0x00, 0x00, 0x00,
]

const ReferenceText = "RFC 1952 test payload\n"

#test
{
    var gzip: Gzip
    let decoded = expect gzip.decompress(ReferenceMember)
    Swag.require(Slice.equals(decoded.toSlice(), cast(const [..] u8, ReferenceText)))

    for size in ReferenceMember.count
    {
        var error: Swag.Error
        discard catch gzip.decompress(ReferenceMember[until size]) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }
}

#test
{
    var gzip: Gzip
    var member: Array!{u8}
    member.add(ReferenceMember)
    // Corrupt the magic, method, reserved flags, header CRC, content CRC, and ISIZE.
    for index in [1_u64, 2, 3, 33, ReferenceMember.count - 8, ReferenceMember.count - 4]
    {
        member[index] ^= 0x20
        var error: Swag.Error
        discard catch gzip.decompress(member.toSlice()) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
        member[index] ^= 0x20
    }
}

#test
{
    var gzip: Gzip
    let empty = expect gzip.compress("", .NoCompression)
    let last  = expect gzip.compress("tail", .BestSpeed)
    var members: Array!{u8}
    members.add(ReferenceMember)
    members.add(empty.toSlice())
    members.add(last.toSlice())

    const Expected = "RFC 1952 test payload\ntail"
    var output: [Expected.count + 2] u8
    output[0] = 79
    output[output.count - 1] = 93
    let destination = output[1 until output.count - 1]
    let written = expect gzip.decompressInto(destination, members.toSlice())
    Swag.require(written == Expected.count)
    Swag.require(Slice.equals(destination, cast(const [..] u8, Expected)))
    Swag.require(output[0] == 79 and output[output.count - 1] == 93)
    let decodedEmpty = expect gzip.decompress(empty.toSlice(), maxOutputSize: 0)
    Swag.require(decodedEmpty.count == 0)

    var intoError: Swag.Error
    discard catch gzip.decompressInto(destination[until destination.count - 1], members.toSlice()) as intoError
    Swag.require(intoError.value() is Errors.UnsupportedFormatError)
    Swag.require(output[0] == 79 and output[output.count - 1] == 93)
}

#test
{
    var gzip: Gzip
    let compressed = expect gzip.compress(ReferenceText)
    var members: Array!{u8}
    members.add(compressed.toSlice())
    members.add(compressed.toSlice())
    var result: Array!{u8}
    result.add(cast(const [..] u8, "prefix"))

    var limitError: Swag.Error
    catch gzip.decompress(&result, members.toSlice(), maxOutputSize: ReferenceText.count) as limitError
    Swag.require(limitError.value() is Errors.UnsupportedFormatError)
    Swag.require(Slice.equals(result.toSlice(), cast(const [..] u8, "prefix")))

    members[members.count - 8] ^= 0x80
    var checksumError: Swag.Error
    catch gzip.decompress(&result, members.toSlice()) as checksumError
    Swag.require(checksumError.value() is Errors.InvalidFormatError)
    Swag.require(Slice.equals(result.toSlice(), cast(const [..] u8, "prefix")))

    var overlapError: Swag.Error
    discard catch gzip.decompressInto(members.toSlice(), members.toSlice()) as overlapError
    Swag.require(overlapError.value() is Errors.BadParameterError)
}
