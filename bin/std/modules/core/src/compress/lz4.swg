#global public
#global namespace Compress.Lz4

using Core.Errors

// Compresses `buffer` into an owned, independent LZ4 block.
//
// The block carries no decoded size, checksum, or frame header. Store the decoded byte count
// separately for [[Core.Compress.Lz4.decompress]]. Inputs above `0x7E000000` bytes fail with
// [[Core.Errors.UnsupportedFormatError]]. Empty input produces a one-byte block.
//
// ```swag
// let source = cast(const [..] u8, "hello, hello, hello")
// let packed = try Compress.Lz4.compress(source)
// let output = try Compress.Lz4.decompress(packed.toSlice(), source.count)
// ```
func compress(buffer: const [..] u8)->Array'u8 fail
{
    if buffer.count > 0x7E000000 do
        fail UnsupportedFormatError{"LZ4 input exceeds the block size limit"}

    var result: Array'u8
    var literalStart = 0'u64

    // A match must start at least twelve bytes before the end and leave five final literals.
    if buffer.count >= 13
    {
        var finder: LzMatchFinder
        finder.init(buffer.count)
        let lastStart = buffer.count - 12
        let matchEnd  = buffer.count - 5
        while literalStart <= lastStart
        {
            let match = finder.find(buffer.buffer, literalStart, lastStart, matchEnd)
            if not match.length do
                break

            writeLiterals(&result, buffer[literalStart until match.at], match.length - 4)
            result.add(Math.byteAt(match.distance, 0))
            result.add(Math.byteAt(match.distance, 1))
            writeLengthExtension(&result, match.length - 4)
            literalStart = match.at + match.length
        }
    }

    writeLiterals(&result, buffer[literalStart to], 0)
    return result
}

// Decodes one independent LZ4 block into an owned array of exactly `outputSize` bytes.
//
// Use a trusted size or check it against an allocation limit before calling. A malformed
// block or a decoded size mismatch fails with [[Core.Errors.InvalidFormatError]].
func decompress(buffer: const [..] u8, outputSize: u64)->Array'u8 fail
{
    if not buffer.count or outputSize / 255 > buffer.count do
        fail InvalidFormatError{"LZ4 block cannot produce the requested output size"}

    var result: Array'u8
    if outputSize
    {
        result.reserve(outputSize)
        result.count = outputSize
    }

    try decompressInto(result.toSlice(), buffer)
    return result
}

// Decodes one independent LZ4 block into an exactly sized output slice.
//
// Input and output must be disjoint. Overlap fails with [[Core.Errors.BadParameterError]].
// A malformed block or size mismatch fails with [[Core.Errors.InvalidFormatError]] and can
// leave a partially written output.
func decompressInto(output: [..] u8, buffer: const [..] u8) fail
{
    if lzBuffersOverlap(output, buffer) do
        fail BadParameterError{}

    var offset   = 0'u64
    var written  = 0'u64
    var hasMatch = false
    while offset < buffer.count
    {
        let token = buffer[offset]
        offset += 1
        var literalLength = cast(u64, token >> 4)
        var matchLength   = cast(u64, token & 15)

        // The usual short sequence fits within these loads and stores. Future sequences
        // overwrite any extra bytes written within the destination slice.
        if literalLength < 15 and
           matchLength < 15 and
           buffer.count - offset >= 16 and
           output.count - written >= 32
        {
            let matchOffset = offset + literalLength
            let matchStart  = written + literalLength
            let distance    = cast(u64, Math.littleEndianToNative(cast(const [*] u16, buffer.buffer + matchOffset)[0]))
            if distance >= 8 and distance <= matchStart
            {
                let destination = output.buffer + matchStart
                let from        = destination - distance
                Math.Simd.store(output.buffer + written, Math.Simd.load(buffer.buffer + offset))
                cast([*] u64, destination)[0]      = cast(const [*] u64, from)[0]
                cast([*] u64, destination)[1]      = cast(const [*] u64, from)[1]
                cast([*] u16, destination + 16)[0] = cast(const [*] u16, from + 16)[0]
                offset                             = matchOffset + 2
                written                            = matchStart + matchLength + 4
                hasMatch                           = true
                continue
            }
        }

        if literalLength == 15 do
            literalLength = try readExtendedLength(buffer, &offset)
        if literalLength > buffer.count - offset or literalLength > output.count - written do
            fail InvalidFormatError{"LZ4 literals exceed the input or output size"}

        if literalLength do
            Memory.copy(output.buffer + written, buffer.buffer + offset, literalLength)
        offset  += literalLength
        written += literalLength

        if offset == buffer.count
        {
            if written != output.count or (hasMatch and literalLength < 5) do
                fail InvalidFormatError{"LZ4 final literals disagree with the output size or block ending"}
            return
        }

        let remaining = output.count - written
        if buffer.count - offset < 2 or remaining < 12 do
            fail InvalidFormatError{"LZ4 block ends inside a match"}

        let distance = cast(u64, buffer[offset]) | (cast(u64, buffer[offset + 1]) << 8)
        offset += 2
        if not distance or distance > written do
            fail InvalidFormatError{"LZ4 match distance exceeds the available history or is zero"}

        if matchLength == 15 do
            matchLength = try readExtendedLength(buffer, &offset)
        if matchLength > remaining - 4 do
            fail InvalidFormatError{"LZ4 match exceeds the output size"}
        copyLzMatch(output.buffer + written, distance, matchLength + 4)
        written  += matchLength + 4
        hasMatch = true
    }

    fail InvalidFormatError{"LZ4 block is missing its final literal sequence"}
}

private func writeLiterals(result: *Array'u8, literals: const [..] u8, matchLength: u64)
{
    result.add(cast(u8, (Math.min(literals.count, 15'u64) << 4) | Math.min(matchLength, 15'u64)))
    writeLengthExtension(result, literals.count)
    result.add(literals)
}

private func writeLengthExtension(result: *Array'u8, length: u64)
{
    if length < 15 do
        return

    let extra = length - 15
    let full  = extra / 255
    result.grow(result.count + full + 1)
    if full do
        Memory.set(result.storage() + result.count, 255, full)
    result.count += full
    result.add(cast(u8, extra % 255))
}

private func readExtendedLength(buffer: const [..] u8, offset: *u64)->u64 fail
{
    var length = 15'u64
    while offset[] < buffer.count
    {
        let extra = buffer[offset[]]
        offset[] += 1
        if length > Swag.U64.Max - extra do
            fail InvalidFormatError{"LZ4 length overflows 64 bits"}
        length += extra
        if extra < 255 do
            return length
    }

    fail InvalidFormatError{"LZ4 block ends inside a length extension"}
}
