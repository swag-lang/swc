#global namespace Compress.Lz4Frame

using Core.Errors

private
{
    const FrameMagic       = 0x184D2204_u32
    const SkippableMagic   = 0x184D2A50_u32
    const SkippableMask    = 0xFFFFFFF0_u32
    const Independent      = 0x20_u8
    const BlockChecksum    = 0x10_u8
    const ContentSize      = 0x08_u8
    const ContentChecksum  = 0x04_u8
    const DictionaryId     = 0x01_u8
    const StoredBlock      = 0x80000000_u32
    const BlockSizeCode    = 5_u8
    const EncodeBlockSize  = 256_u64 * 1024

    struct FrameDescriptor
    {
        flags:     u8
        body:      u64
        blockSize: u64
        size:      u64
    }
}

// Compresses `buffer` into an owned LZ4 frame with independent 256 KiB blocks.
//
// The frame records the decoded size and a content checksum. A block is stored verbatim
// when compression would increase its size. Use [[Core.Compress.Lz4.compress]] when the
// caller owns the framing and already stores the decoded size.
//
// ```swag
// let frame = try Compress.Lz4Frame.compress("one LZ4 frame")
// let plain = try Compress.Lz4Frame.decompress(frame.toSlice(), maxOutputSize: 1024)
// ```
public func compress(buffer: const [..] u8)->Array!{u8} fail
{
    const Flags = 0x40_u8 | Independent | ContentSize | ContentChecksum
    var result: #returntype
    let header = result.emplaceAddress(15)
    cast([*] u32, header)[0]     = Math.nativeToLittleEndian(FrameMagic)
    header[4]                   = Flags
    header[5]                   = BlockSizeCode << 4
    cast([*] u64, header + 6)[0] = Math.nativeToLittleEndian(buffer.count)
    header[14]                  = headerChecksum(Swag.makeSlice(header + 4, 10))

    var offset = 0_u64
    while offset < buffer.count
    {
        let size = Math.min(EncodeBlockSize, buffer.count - offset)
        let block = buffer[offset until offset + size]
        let packed = try Lz4.compress(block)
        let stored = packed.count >= size
        let data: const [..] u8 = stored ? block : packed.toSlice()
        let length = cast(u32, data.count) | (stored ? StoredBlock : 0)
        cast([*] u32, result.emplaceAddress(4))[0] = Math.nativeToLittleEndian(length)
        result.add(data)
        offset += size
    }

    let footer = cast([*] u32, result.emplaceAddress(8))
    footer[0] = 0
    footer[1] = Math.nativeToLittleEndian(checksum(buffer))
    return result
}

// Decompresses the LZ4 frames in `buffer` into an owned array.
//
// Accepts independent, linked, concatenated, and skippable frames, and validates every
// checksum and decoded size that is present. `maxOutputSize` limits total decoded bytes.
// Malformed frames fail with [[Core.Errors.InvalidFormatError]]. External dictionaries,
// unsupported frame versions, and output beyond the limit fail with
// [[Core.Errors.UnsupportedFormatError]].
public func decompress(buffer: const [..] u8, maxOutputSize: u64)->Array!{u8} fail
{
    var result: #returntype
    try decodeFrames(&result, buffer, maxOutputSize)
    return result
}

// Decompresses all LZ4 frames in `buffer` and returns the number of bytes written to `output`.
//
// The slices must be disjoint. Insufficient space fails with
// [[Core.Errors.UnsupportedFormatError]]. The call may modify `output` before failing.
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

private func decodeFrames(result: *Array!{u8}, buffer: const [..] u8, limit: u64) fail
{
    if not buffer.count
    {
        fail InvalidFormatError{"missing LZ4 frame"}
    }

    var offset = 0_u64
    while offset < buffer.count
    {
        let frame = buffer[offset to]
        if frame.count < 4
        {
            fail InvalidFormatError{"truncated LZ4 frame magic"}
        }

        let magic = readU32(frame.buffer)
        if magic == FrameMagic
        {
            offset += try decodeFrame(result, frame, limit)
        }
        else if (magic & SkippableMask) == SkippableMagic
        {
            if frame.count < 8
            {
                fail InvalidFormatError{"truncated LZ4 skippable frame header"}
            }
            let size = cast(u64, readU32(frame.buffer + 4))
            if size > frame.count - 8
            {
                fail InvalidFormatError{"truncated LZ4 skippable frame"}
            }
            offset += 8 + size
        }
        else
        {
            fail InvalidFormatError{"invalid LZ4 frame magic"}
        }
    }
}

private func readDescriptor(frame: const [..] u8)->FrameDescriptor fail
{
    if frame.count < 7
    {
        fail InvalidFormatError{"truncated LZ4 frame descriptor"}
    }

    let flags = frame[4]
    if (flags >> 6) != 1
    {
        fail UnsupportedFormatError{"unsupported LZ4 frame version"}
    }

    let block = frame[5]
    let sizeCode = (block >> 4) & 7
    if (flags & 2) or (block & 0x8F) or sizeCode < 4
    {
        fail InvalidFormatError{"invalid LZ4 frame descriptor flags"}
    }

    let hasSize = (flags & ContentSize) != 0
    let hasDictionary = (flags & DictionaryId) != 0
    let body = 7_u64 + (hasSize ? 8 : 0) + (hasDictionary ? 4 : 0)
    if frame.count < body
    {
        fail InvalidFormatError{"truncated LZ4 frame descriptor"}
    }

    if frame[body - 1] != headerChecksum(frame[4 until body - 1])
    {
        fail InvalidFormatError{"LZ4 frame header checksum mismatch"}
    }
    if hasDictionary
    {
        fail UnsupportedFormatError{"LZ4 frame requires an external dictionary"}
    }

    let size = hasSize ? Math.littleEndianToNative(cast(const [*] u64, frame.buffer + 6)[0]) : Swag.U64.Max
    return {flags: flags, body: body, blockSize: 1_u64 << (8 + 2 * sizeCode), size: size}
}

private func decodeFrame(result: *Array!{u8}, frame: const [..] u8, limit: u64)->u64 fail
{
    let desc = try readDescriptor(frame)
    let start = result.count
    if (desc.flags & ContentSize) and desc.size > limit - start
    {
        fail UnsupportedFormatError{"LZ4 output exceeds the configured limit"}
    }

    var offset = desc.body
    for
    {
        if frame.count - offset < 4
        {
            fail InvalidFormatError{"truncated LZ4 frame block header"}
        }
        let field = readU32(frame.buffer + offset)
        offset += 4
        if not field
        {
            break
        }

        let size = cast(u64, field & ~StoredBlock)
        if size > desc.blockSize or size > frame.count - offset
        {
            fail InvalidFormatError{"LZ4 frame block exceeds its declared or available size"}
        }
        let block = frame[offset until offset + size]
        offset += size
        if desc.flags & BlockChecksum
        {
            offset = try checkDigest(frame, offset, block)
        }

        let frameOutput = result.count - start
        let permitted = Math.min(desc.blockSize, desc.size - frameOutput)
        let available = limit - result.count
        if field & StoredBlock
        {
            if size > permitted
            {
                fail InvalidFormatError{"LZ4 stored block exceeds the declared decoded size"}
            }
            if size > available
            {
                fail UnsupportedFormatError{"LZ4 output exceeds the configured limit"}
            }
            result.add(block)
        }
        else
        {
            // Each extension byte can add at most 255 decoded bytes. Bound the scratch
            // span even for a small frame with no advertised size.
            let blockLimit = Math.min(permitted, size * 255 + 254)
            let capacity   = Math.min(available, blockLimit)
            let history    = (desc.flags & Independent) ? 0 : Math.min(frameOutput, cast(u64, Swag.U16.Max))
            result.grow(result.count + capacity)
            let destination = Swag.makeSlice(result.buffer + (result.count - history), history + capacity)
            result.count += try Lz4.decodeBlock!{false}(destination, block, history, available < blockLimit)
        }
    }

    if (desc.flags & ContentSize) and result.count - start != desc.size
    {
        fail InvalidFormatError{"LZ4 frame decoded size mismatch"}
    }
    if desc.flags & ContentChecksum
    {
        offset = try checkDigest(frame, offset, result.toSlice()[start to])
    }
    return offset
}

private func checkDigest(frame: const [..] u8, offset: u64, bytes: const [..] u8)->u64 fail
{
    if frame.count - offset < 4
    {
        fail InvalidFormatError{"truncated LZ4 frame checksum"}
    }
    if readU32(frame.buffer + offset) != checksum(bytes)
    {
        fail InvalidFormatError{"LZ4 frame checksum mismatch"}
    }
    return offset + 4
}

#[Swag.Inline]
private func readU32(source: const [*] u8)->u32 => Math.littleEndianToNative(cast(const [*] u32, source)[0])

private func headerChecksum(bytes: const [..] u8)->u8 => cast(u8, (checksum(bytes) >> 8) & 255)

// LZ4 frame descriptors and payloads use XXH32 with a zero seed.
#[Swag.Safety(.Overflow, false)]
private func checksum(bytes: const [..] u8)->u32
{
    const Prime1 = 0x9E3779B1_u32
    const Prime2 = 0x85EBCA77_u32
    const Prime3 = 0xC2B2AE3D_u32
    const Prime4 = 0x27D4EB2F_u32
    const Prime5 = 0x165667B1_u32

    var offset = 0_u64
    var hash   = Prime5
    if bytes.count >= 16
    {
        var lane0 = Prime1 + #wrap Prime2
        var lane1 = Prime2
        var lane2 = 0_u32
        var lane3 = 0_u32 - #wrap Prime1
        while bytes.count - offset >= 16
        {
            let input = bytes.buffer + offset
            lane0 = Swag.rol(lane0 + readU32(input) * Prime2, 13) * Prime1
            lane1 = Swag.rol(lane1 + readU32(input + 4) * Prime2, 13) * Prime1
            lane2 = Swag.rol(lane2 + readU32(input + 8) * Prime2, 13) * Prime1
            lane3 = Swag.rol(lane3 + readU32(input + 12) * Prime2, 13) * Prime1
            offset += 16
        }
        hash = Swag.rol(lane0, 1) + Swag.rol(lane1, 7) + Swag.rol(lane2, 12) + Swag.rol(lane3, 18)
    }

    hash += cast #wrap (u32, bytes.count)
    while bytes.count - offset >= 4
    {
        hash = Swag.rol(hash + readU32(bytes.buffer + offset) * Prime3, 17) * Prime4
        offset += 4
    }
    for index in offset until bytes.count
    {
        hash = Swag.rol(hash + cast(u32, bytes[index]) * Prime5, 11) * Prime1
    }

    hash = (hash ^ (hash >> 15)) * Prime2
    hash = (hash ^ (hash >> 13)) * Prime3
    return hash ^ (hash >> 16)
}
