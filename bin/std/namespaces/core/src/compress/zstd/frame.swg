#global namespace Compress.Zstd

using Core.Errors

internal const Magic    = 0xFD2FB528_u32
internal const MaxBlock = 128_u64 * 1024

private struct FrameHeader
{
    consumed: u64
    window:   u64
    size:     u64
    known:    bool
    checksum: bool
}

// Decompresses the Zstandard frames in `buffer` into an owned array (RFC 8878).
//
// Accepts concatenated and skippable frames and verifies any advertised sizes and checksums.
// `maxOutputSize` limits total decoded bytes. Malformed frames fail with
// [[Core.Errors.InvalidFormatError]]. Output beyond the limit or a required dictionary
// fails with [[Core.Errors.UnsupportedFormatError]].
public func decompress(buffer: const [..] u8, maxOutputSize: u64)->Array!{u8} fail
{
    var result: #returntype
    try decodeFrames(&result, buffer, maxOutputSize)
    return result
}

// Decompresses the Zstandard frames in `buffer` into `output` and returns the bytes written.
//
// Overlapping slices fail with [[Core.Errors.BadParameterError]]. Insufficient capacity
// fails with [[Core.Errors.UnsupportedFormatError]]. The call can modify `output` before failing.
public func decompressInto(output: [..] u8, buffer: const [..] u8)->u64 fail
{
    if lzBuffersOverlap(output, buffer)
    {
        fail BadParameterError{}
    }

    var result = Array!{u8}{buffer: output.buffer, capacity: output.count}
    defer result.buffer = null
    try decodeFrames(&result, buffer, output.count)
    return result.count
}

private func readHeader(frame: const [..] u8)->FrameHeader fail
{
    if frame.count < 5
    {
        fail InvalidFormatError{"truncated Zstandard frame header"}
    }

    let flags = frame[4]
    if flags & 8
    {
        fail InvalidFormatError{"Zstandard frame header has a reserved bit set"}
    }

    let single          = (flags & 32) != 0
    let sizeFlag        = flags >> 6
    let sizeWidth       = sizeFlag ? 1_u32 << sizeFlag : (single ? 1_u32 : 0)
    let dictionaryFlag  = flags & 3
    let dictionaryWidth = dictionaryFlag == 3 ? 4_u32 : cast(u32, dictionaryFlag)
    let headerSize      = 5_u64 + (single ? 0 : 1) + dictionaryWidth + sizeWidth
    if headerSize > frame.count
    {
        fail InvalidFormatError{"truncated Zstandard frame header fields"}
    }

    var cursor = 5_u64
    var window = 0_u64
    if not single
    {
        let windowByte = frame[cursor]
        cursor += 1
        let base = 1_u64 << (10 + (windowByte >> 3))
        window = base + ((base >> 3) * (windowByte & 7))
    }

    if dictionaryWidth and readLittle(frame.buffer + cursor, dictionaryWidth)
    {
        fail UnsupportedFormatError{"Zstandard frame requires an external dictionary"}
    }

    cursor += dictionaryWidth
    var size = Swag.U64.Max
    if sizeWidth
    {
        size = readLittle(frame.buffer + cursor, sizeWidth)
        if sizeWidth == 2
        {
            size += 256
        }
    }

    if single
    {
        window = size
    }

    return {consumed: headerSize, window: window, size: size, known: sizeWidth != 0, checksum: (flags & 4) != 0}
}

private func decodeFrames(result: *Array!{u8}, buffer: const [..] u8, limit: u64) fail
{
    if not buffer.count
    {
        fail InvalidFormatError{"missing Zstandard frame"}
    }

    var offset = 0_u64
    while offset < buffer.count
    {
        let frame = buffer[offset to]
        if frame.count < 4
        {
            fail InvalidFormatError{"truncated Zstandard frame magic"}
        }

        let magic = readLe32(frame.buffer)
        if magic == Magic
        {
            offset += try decodeFrame(result, frame, limit)
        }
        else if (magic & 0xFFFFFFF0) == 0x184D2A50
        {
            if frame.count < 8
            {
                fail InvalidFormatError{"truncated Zstandard skippable frame header"}
            }

            let size = cast(u64, readLe32(frame.buffer + 4))
            if size > frame.count - 8
            {
                fail InvalidFormatError{"truncated Zstandard skippable frame"}
            }

            offset += 8 + size
        }
        else
        {
            fail InvalidFormatError{"invalid Zstandard frame magic"}
        }
    }
}

private func decodeFrame(result: *Array!{u8}, frame: const [..] u8, limit: u64)->u64 fail
{
    let header = try readHeader(frame)
    let start  = result.count
    if header.known and header.size > limit - start
    {
        fail UnsupportedFormatError{"Zstandard output exceeds the configured limit"}
    }

    let maxBlock = Math.min(MaxBlock, header.window)
    var cursor   = header.consumed
    var literals:  LiteralDecoder
    var sequences: SequenceDecoder
    for
    {
        if frame.count - cursor < 3
        {
            fail InvalidFormatError{"truncated Zstandard block header"}
        }

        let field = cast(u32, readLittle(frame.buffer + cursor, 3))
        cursor += 3
        let kind   = (field >> 1) & 3
        let size   = cast(u64, field >> 3)
        let stored = kind == 1 ? 1_u64 : size
        if kind == 3 or size > maxBlock or stored > frame.count - cursor
        {
            fail InvalidFormatError{"invalid Zstandard block type or size"}
        }

        let block = frame[cursor until cursor + stored]
        cursor += stored

        let decoded   = result.count - start
        let permitted = Math.min(maxBlock, header.size - decoded)
        let available = limit - result.count
        if kind == 2
        {
            let section  = try literals.decode(block, maxBlock)
            let capacity = Math.min(available, permitted)
            let history  = Math.min(decoded, header.window)
            result.grow(result.count + capacity)
            let destination = Swag.makeSlice(result.buffer + (result.count - history), history + capacity)
            result.count += try sequences.decode(destination, history, header.window, section.literals, block[section.consumed to], available < permitted)
        }
        else
        {
            if size > permitted
            {
                fail InvalidFormatError{"Zstandard block exceeds the declared decoded size"}
            }

            if size > available
            {
                fail UnsupportedFormatError{"Zstandard output exceeds the configured limit"}
            }

            if kind == 0
            {
                result.add(block)
            }
            else if size
            {
                let destination = result.emplaceAddress(cast(u32, size))
                Memory.set(destination, block[0], size)
            }
        }

        if field & 1
        {
            break
        }
    }

    if header.known and result.count - start != header.size
    {
        fail InvalidFormatError{"Zstandard frame decoded size mismatch"}
    }

    if header.checksum
    {
        if frame.count - cursor < 4
        {
            fail InvalidFormatError{"truncated Zstandard frame checksum"}
        }

        if readLe32(frame.buffer + cursor) != contentChecksum(result.toSlice()[start to])
        {
            fail InvalidFormatError{"Zstandard frame checksum mismatch"}
        }

        cursor += 4
    }

    return cursor
}
