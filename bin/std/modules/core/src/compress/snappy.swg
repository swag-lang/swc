#global public
#global namespace Compress.Snappy

using Core.Errors

// Compresses `buffer` into an owned Snappy raw block with a decoded-size preamble.
//
// The block has no stream framing or checksum. Inputs above `Swag.U32.Max` bytes fail with
// [[Core.Errors.UnsupportedFormatError]]. Empty input produces a one-byte preamble.
//
// ```swag
// let packed = try Compress.Snappy.compress("hello, hello, hello")
// let output = try Compress.Snappy.decompress(packed.toSlice(), maxOutputSize: 1024)
// ```
func compress(buffer: const [..] u8)->Array!{u8} fail
{
    if buffer.count > Swag.U32.Max
    {
        fail UnsupportedFormatError{"Snappy input exceeds the block size limit"}
    }

    var result: Array!{u8}
    var size = buffer.count
    while size >= 128
    {
        result.add(cast(u8, (size & 127) | 128))
        size >>= 7
    }

    result.add(cast(u8, size))

    var literalStart = 0_u64
    if buffer.count >= 5
    {
        var finder: LzMatchFinder
        finder.init(buffer.count)
        let lastStart = buffer.count - 4
        while literalStart <= lastStart
        {
            let match = finder.find(buffer.buffer, literalStart, lastStart, buffer.count)
            if not match.length
            {
                break
            }

            writeLiterals(&result, buffer[literalStart until match.at])
            writeCopies(&result, match.distance, match.length)
            literalStart = match.at + match.length
        }
    }

    writeLiterals(&result, buffer[literalStart to])
    return result
}

// Decodes one Snappy raw block into an owned array.
//
// `maxOutputSize` limits the bytes allocated for the result. A block that exceeds the limit
// fails with [[Core.Errors.UnsupportedFormatError]]. Malformed blocks fail with
// [[Core.Errors.InvalidFormatError]].
func decompress(buffer: const [..] u8, maxOutputSize: u64 = Swag.U32.Max)->Array!{u8} fail
{
    let header = try readHeader(buffer, maxOutputSize)
    var result: Array!{u8}
    if header.size
    {
        result.reserve(header.size)
        result.count = header.size
    }

    try decode(result.toSlice(), buffer, header.end)
    return result
}

// Decodes one Snappy raw block into `output` and returns the number of bytes written.
//
// Input and output must be disjoint. Overlap fails with [[Core.Errors.BadParameterError]].
// An undersized output fails with [[Core.Errors.UnsupportedFormatError]]. A malformed block
// fails with [[Core.Errors.InvalidFormatError]] and can leave a partially written output.
// Bytes past the size in the preamble are left untouched.
func decompressInto(output: [..] u8, buffer: const [..] u8)->u64 fail
{
    if lzBuffersOverlap(output, buffer)
    {
        fail BadParameterError{}
    }

    let header = try readHeader(buffer, output.count)
    try decode(output[until header.size], buffer, header.end)
    return header.size
}

private func readHeader(buffer: const [..] u8, maxOutputSize: u64)->{ size: u64, end: u64 } fail
{
    var size = 0_u64
    for offset in Math.min(buffer.count, 5_u64)
    {
        let byte = buffer[offset]
        size |= cast(u64, byte & 127) << (offset * 7)
        if byte < 128
        {
            if size > Swag.U32.Max
            {
                fail InvalidFormatError{"Snappy decoded size overflows 32 bits"}
            }

            if size > maxOutputSize
            {
                fail UnsupportedFormatError{"Snappy decoded size exceeds the output limit"}
            }

            // Even the densest copy emits fewer than 32 bytes per input byte.
            if (size + 31) / 32 > buffer.count - offset - 1
            {
                fail InvalidFormatError{"Snappy block cannot produce its declared output size"}
            }

            return {size: size, end: offset + 1}
        }
    }

    fail InvalidFormatError{"Snappy block is missing a complete size preamble"}
}

private func decode(output: [..] u8, buffer: const [..] u8, start: u64) fail
{
    var offset  = start
    var written = 0_u64
    while offset < buffer.count
    {
        let tag = buffer[offset]
        offset += 1
        let kind = tag & 3
        if not kind
        {
            var length = cast(u64, tag >> 2) + 1
            if length > 60
            {
                let width = length - 60
                if width > buffer.count - offset
                {
                    fail InvalidFormatError{"Snappy block ends inside a literal length"}
                }

                length = 1
                for index in width
                {
                    length += cast(u64, buffer[offset + index]) << (index * 8)
                }

                offset += width
            }

            if length > buffer.count - offset or length > output.count - written
            {
                fail InvalidFormatError{"Snappy literals exceed the input or output size"}
            }

            Memory.copy(output.buffer + written, buffer.buffer + offset, length)
            offset  += length
            written += length
            continue
        }

        var length, distance: u64
        if kind == 1
        {
            if offset == buffer.count
            {
                fail InvalidFormatError{"Snappy block ends inside a copy offset"}
            }

            length   = cast(u64, (tag >> 2) & 7) + 4
            distance = (cast(u64, tag & 0xE0) << 3) | cast(u64, buffer[offset])
            offset   += 1
        }
        else
        {
            let width = kind == 2 ? 2_u64 : 4_u64
            if width > buffer.count - offset
            {
                fail InvalidFormatError{"Snappy block ends inside a copy offset"}
            }

            length = cast(u64, tag >> 2) + 1
            let encoded = buffer.buffer + offset
            distance = kind == 2 ? cast(u64, Math.littleEndianToNative(cast(const [*] u16, encoded)[0])) :
                       cast(u64, Math.littleEndianToNative(cast(const [*] u32, encoded)[0]))
            offset += width
        }

        let remaining = output.count - written
        if not distance or distance > written or length > remaining
        {
            fail InvalidFormatError{"Snappy copy exceeds the available history or output size, or has a zero offset"}
        }

        let destination = output.buffer + written
        if length <= 16 and distance >= 16 and remaining >= 16
        {
            // The source is already decoded. Later tags overwrite any bytes past this match.
            Math.Simd.store(destination, Math.Simd.load(destination - distance))
        }
        else
        {
            copyLzMatch(destination, distance, length)
        }

        written += length
    }

    if written != output.count
    {
        fail InvalidFormatError{"Snappy decoded size disagrees with the preamble"}
    }
}

private func writeLiterals(result: *Array!{u8}, literals: const [..] u8)
{
    if not literals.count
    {
        return
    }

    let lengthField = cast(u32, literals.count - 1)
    if lengthField < 60
    {
        result.add(cast(u8, lengthField << 2))
    }
    else
    {
        let width = (39 - Math.leadingZeros(lengthField)) / 8
        result.add(cast(u8, (59 + width) << 2))
        for index in width
        {
            result.add(Math.byteAt(lengthField, index))
        }
    }

    result.add(literals)
}

private func writeCopies(result: *Array!{u8}, distance, length: u64)
{
    // Each group of up to 64 bytes uses at most three bytes on the wire.
    result.grow(result.count + ((length + 63) / 64) * 3)
    var output    = result.storage() + result.count
    let start     = output
    let low       = Math.byteAt(distance, 0)
    let high      = Math.byteAt(distance, 1)
    var remaining = length
    while remaining
    {
        let amount = Math.min(remaining, 64_u64)
        if distance < 2048 and amount >= 4 and amount <= 11
        {
            output[0] = cast(u8, ((distance >> 8) << 5) | ((amount - 4) << 2) | 1)
            output[1] = low
            output    += 2
        }
        else
        {
            output[0] = cast(u8, ((amount - 1) << 2) | 2)
            output[1] = low
            output[2] = high
            output    += 3
        }

        remaining -= amount
    }

    result.count += cast(u64, output - start)
}
