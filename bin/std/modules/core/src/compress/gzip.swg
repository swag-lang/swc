#global namespace Compress
#global public

using Core.Errors

// Compresses and decompresses gzip members (RFC 1952).
//
// A member frames [[Core.Compress.Deflate]] data with a header, CRC-32, and decoded size.
// One `Gzip` instance reuses its encoder and [[Core.Compress.Inflate]] across calls.
//
// ```swag
// var gzip: Compress.Gzip
// let member = try gzip.compress("one gzip member")
// let decoded = try gzip.decompress(member.toSlice(), maxOutputSize: 1024)
// ```
#[Swag.Opaque]
struct Gzip
{
    private
    {
        decoder: Inflate
        encoder: Deflate
    }
}

impl Gzip
{
    // Compresses `buffer` into an owned gzip member without optional header fields.
    //
    // Inputs above `Swag.U32.Max` bytes fail with [[Core.Errors.UnsupportedFormatError]].
    mtd compress(buffer: const [..] u8, level = Deflate.CompressionLevel.Default)->Array!{u8} fail
    {
        const Header: [10] u8 = [0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 255]
        var result: #returntype
        result.add(Header)

        .encoder.init(level, flags: .Zero)
        try .encoder.compress(&result, buffer)

        let trailer = cast([*] u32, result.emplaceAddress(8))
        trailer[0] = Math.nativeToLittleEndian(Hash.Crc32.compute(buffer))
        trailer[1] = Math.nativeToLittleEndian(cast(u32, buffer.count))
        return result
    }

    // Decompresses all gzip members in `buffer` into an owned array.
    //
    // The input must consist of one or more complete members. `hintSize` reserves space
    // up front and `maxOutputSize` limits the total bytes produced across all members.
    // Invalid member headers, Deflate data, CRCs, and sizes fail with
    // [[Core.Errors.InvalidFormatError]]. A hint or output beyond the limit fails with
    // [[Core.Errors.UnsupportedFormatError]].
    mtd decompress(buffer: const [..] u8, hintSize: u64 = 0, maxOutputSize: u64 = Swag.U64.Max)->Array!{u8} fail
    {
        var result: #returntype
        try .decompress(&result, buffer, hintSize, maxOutputSize)
        return result
    }

    // Decompresses all gzip members in `buffer` into `output` and returns the bytes written.
    //
    // Overlap fails with [[Core.Errors.BadParameterError]]. An undersized output fails with
    // [[Core.Errors.UnsupportedFormatError]]. The call may modify `output` before failing.
    mtd decompressInto(output: [..] u8, buffer: const [..] u8)->u64 fail
    {
        var result = Array!{u8}{buffer: output.buffer, capacity: output.count}
        defer result.buffer = null
        try .decompress(&result, buffer, maxOutputSize: output.count)
        return result.count
    }

    // Appends the content of all gzip members in `buffer` to `result`.
    //
    // `hintSize` and `maxOutputSize` apply only to appended bytes. Input overlapping the
    // array's storage fails with [[Core.Errors.BadParameterError]]. On failure the original
    // bytes and count are preserved. A growth can invalidate borrowed views even on failure.
    mtd decompress(result: *Array!{u8}, buffer: const [..] u8, hintSize: u64 = 0, maxOutputSize: u64 = Swag.U64.Max) fail
    {
        if buffer.count and result.buffer and result.capacity and
           buffer.buffer < result.buffer + result.capacity and result.buffer < buffer.buffer + buffer.count
        {
            fail BadParameterError{}
        }

        if not buffer.count
        {
            fail InvalidFormatError{"missing gzip member"}
        }

        let start = result.count
        if hintSize > maxOutputSize or hintSize > Swag.U64.Max - start
        {
            fail UnsupportedFormatError{"gzip output exceeds the configured limit"}
        }

        defer #fail result.count = start
        if hintSize
        {
            result.grow(start + hintSize)
        }

        var offset = 0_u64
        while offset < buffer.count
        {
            let member = buffer[offset to]
            let headerSize = try readGzipHeader(member)
            let decodedStart = result.count
            try .decoder.decompress(result, member[headerSize to], maxOutputSize: maxOutputSize - (decodedStart - start))

            // Inflate may have prefetched bytes of the trailer or the next member.
            .decoder.stream.discardToNextByte()
            .decoder.stream.revert()
            let trailer = headerSize + .decoder.stream.bytePosition()
            if member.count - trailer < 8
            {
                fail InvalidFormatError{"truncated gzip trailer"}
            }

            let fields = cast(const [*] u32, member.buffer + trailer)
            let decoded = result.toSlice()[decodedStart to]
            if Math.littleEndianToNative(fields[1]) != cast #wrap (u32, decoded.count) or
               Math.littleEndianToNative(fields[0]) != Hash.Crc32.compute(decoded)
            {
                fail InvalidFormatError{"gzip checksum or size mismatch"}
            }

            offset += trailer + 8
        }
    }
}

private func readGzipHeader(buffer: const [..] u8)->u64 fail
{
    const HeaderSize = 10_u64
    if buffer.count < HeaderSize or buffer[0] != 0x1F or buffer[1] != 0x8B or buffer[2] != 8
    {
        fail InvalidFormatError{"invalid gzip member header"}
    }

    let flags = buffer[3]
    if flags & 0xE0
    {
        fail InvalidFormatError{"gzip header has reserved flags set"}
    }

    var offset = HeaderSize
    if flags & 4
    {
        if buffer.count - offset < 2
        {
            fail InvalidFormatError{"truncated gzip extra field size"}
        }

        let size = Math.littleEndianToNative(cast(const [*] u16, buffer.buffer + offset)[0])
        offset += 2
        if size > buffer.count - offset
        {
            fail InvalidFormatError{"truncated gzip extra field"}
        }

        offset += size
    }

    // The optional filename and comment each end in a zero byte.
    for flag in [8_u8, 16]
    {
        if flags & flag
        {
            while offset < buffer.count and buffer[offset] != 0
            {
                offset += 1
            }

            if offset == buffer.count
            {
                fail InvalidFormatError{"unterminated gzip header field"}
            }

            offset += 1
        }
    }

    if flags & 2
    {
        if buffer.count - offset < 2
        {
            fail InvalidFormatError{"truncated gzip header checksum"}
        }

        let checksum = Math.littleEndianToNative(cast(const [*] u16, buffer.buffer + offset)[0])
        if checksum != cast #wrap (u16, Hash.Crc32.compute(buffer[until offset]))
        {
            fail InvalidFormatError{"gzip header checksum mismatch"}
        }

        offset += 2
    }

    return offset
}
