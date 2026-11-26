//! Format: FLAC (Free Lossless Audio Codec).
//! Supported: Native FLAC files: the stream marker, the metadata prologue, a frame index checked by header and frame checksums, and committed writer prefixes.
//! Not supported: Ogg-encapsulated FLAC, and seek tables, which this reader does not need because it indexes every frame.
//! Role: This file owns native FLAC file traversal and the streamed packet sound it builds.
//
#global namespace Flac

using Core, Core.Errors

// Bytes the longest frame header spans, clause 9.1: what the scan for the end of a frame peeks
// at first.
//
// A frame carries at most 65,535 sample frames, so the largest one a legal stream can hold is a
// little over two megabytes; the peek grows to whatever a particular file turns out to need and
// starts at one header, because the read window of the source already looks ahead further than
// the few kilobytes a real encoder produces.
private const FrameHeaderBytes = 16_u64

// The polynomial a FLAC frame header protects itself with, clause 9.1.
private func headerCrc8(bytes: const [..] u8)->u8
{
    var crc = 0_u8
    for value in bytes
    {
        crc ^= value
        for 8
        {
            crc = (crc & 0x80) != 0 ? cast(u8, ((crc << 1) ^ 0x07)) : cast(u8, (crc << 1))
        }
    }

    return crc
}

// Each row gives the contribution of a byte followed by that many zero bytes.
private const FrameCrcTable: [8, 256] u16 = #run
{
    var checksum = 0_u16
    for byte in bytes
    {
        checksum ^= cast(u16, byte) << 8
        for 8
        {
            checksum = checksum & 0x8000 ? cast(u16, ((cast(u32, checksum) << 1) ^ 0x8005) & 0xFFFF) :
                       cast(u16, (cast(u32, checksum) << 1) & 0xFFFF)
        }
    }

    for row in 1 until 8
    {
        for byte in 256
        {
            let prior = table[row - 1, byte]
            table[row, byte] = ((prior & 0xFF) << 8) ^ table[0, prior >> 8]
        }
    }

    return table
}

private func frameCrc16Table(bytes: const [..] u8, initial: u16)->u16
{
    var checksum = initial
    var offset   = 0_u64
    while bytes.count - offset >= 8
    {
        checksum = FrameCrcTable[7, bytes[offset] ^ (checksum >> 8)] ^
                   FrameCrcTable[6, bytes[offset + 1] ^ (checksum & 0xFF)] ^
                   FrameCrcTable[5, bytes[offset + 2]] ^
                   FrameCrcTable[4, bytes[offset + 3]] ^
                   FrameCrcTable[3, bytes[offset + 4]] ^
                   FrameCrcTable[2, bytes[offset + 5]] ^
                   FrameCrcTable[1, bytes[offset + 6]] ^
                   FrameCrcTable[0, bytes[offset + 7]]
        offset += 8
    }

    for byte in bytes[offset until]
    {
        checksum = ((checksum & 0xFF) << 8) ^ FrameCrcTable[0, byte ^ (checksum >> 8)]
    }

    return checksum
}

// FLAC's frame trailer protects the complete header and coded subframes.
internal func frameCrc16(bytes: const [..] u8, initial = 0_u16)->u16
{
    #static if not Core.BIG_ENDIAN
    {
        if bytes.count >= 64
        {
            let foldedCount = bytes.count & ~15_u64
            let block       = foldMsbChecksum!{16_u32, 0x8005_u32}(bytes[until foldedCount], cast(u32, initial))
            let checksum    = frameCrc16Table(block, 0)
            return frameCrc16Table(bytes[foldedCount until], checksum)
        }
    }

    return frameCrc16Table(bytes, initial)
}

// Returns the length of the frame header starting at `offset`, or zero when none does.
//
// A FLAC frame states no length, so a reader finds the end of one by finding the start of the
// next. The sync code alone cannot decide that — the same fourteen bits occur inside coded
// residuals — so the header's own checksum identifies a candidate.
private func frameHeaderSize(bytes: const [..] u8, offset: u64)->u64
{
    if bytes.count - offset < 5
    {
        return 0
    }

    if bytes[offset] != 0xFF or (bytes[offset + 1] & 0xFC) != 0xF8
    {
        return 0
    }

    let blockSizeCode  = bytes[offset + 2] >> 4
    let sampleRateCode = bytes[offset + 2] & 0x0F
    if not blockSizeCode or sampleRateCode == 0x0F
    {
        return 0
    }

    // The frame or sample number is stored the way UTF-8 stores a code point.
    let lead = bytes[offset + 4]
    var size = 5_u64
    var continuationBytes = 0_u64
    if lead == 0xFE
    {
        size += 6
        continuationBytes = 6
    }
    else if lead == 0xFF
    {
        return 0
    }
    else if lead >= 0xFC
    {
        size += 5
        continuationBytes = 5
    }
    else if lead >= 0xF8
    {
        size += 4
        continuationBytes = 4
    }
    else if lead >= 0xF0
    {
        size += 3
        continuationBytes = 3
    }
    else if lead >= 0xE0
    {
        size += 2
        continuationBytes = 2
    }
    else if lead >= 0xC0
    {
        size += 1
        continuationBytes = 1
    }
    else if lead >= 0x80
    {
        return 0
    }

    if blockSizeCode == 6
    {
        size += 1
    }
    else if blockSizeCode == 7
    {
        size += 2
    }

    if sampleRateCode == 12
    {
        size += 1
    }
    else if sampleRateCode == 13 or sampleRateCode == 14
    {
        size += 2
    }

    if bytes.count - offset < size + 1
    {
        return 0
    }

    for index in continuationBytes where (bytes[offset + 5 + index] & 0xC0) != 0x80
    {
        return 0
    }

    if headerCrc8(bytes[offset until offset + size]) != bytes[offset + size]
    {
        return 0
    }

    return size + 1
}

private func findFrameSync(bytes: const [..] u8, start, end: u64)->u64
{
    const VectorBytes = #sizeof(Math.Simd.U8x16)

    #[Swag.Inline]
    func syncMask(data: const [*] u8)->Math.Simd.U8x16
    {
        let leading  = Math.Simd.load(data) == Math.Simd.splat(0xFF_u8)
        let trailing = (Math.Simd.load(data + 1) & Math.Simd.splat(0xFC_u8)) == Math.Simd.splat(0xF8_u8)
        return leading & trailing
    }

    let limit = Math.min(end, bytes.count - 1)
    let data  = bytes.buffer
    var scan  = start

    // Reject four vectors at once. The byte order matters only within a group with a match.
    while limit - scan >= 4 * VectorBytes
    {
        let at       = data + scan
        let combined = syncMask(at) |
                       syncMask(at + VectorBytes) |
                       syncMask(at + 2 * VectorBytes) |
                       syncMask(at + 3 * VectorBytes)
        if Math.Simd.bitmask(combined)
        {
            break
        }

        scan += 4 * VectorBytes
    }

    while limit - scan >= VectorBytes
    {
        let matches = Math.Simd.bitmask(syncMask(data + scan))
        if matches
        {
            return scan + Math.trailingZeros(matches)
        }

        scan += VectorBytes
    }

    for index in scan until limit where data[index] == 0xFF and (data[index + 1] & 0xFC) == 0xF8
    {
        return index
    }

    return end
}

// What the metadata prologue of a file says about the stream that follows it.
private struct Prologue
{
    config:      Array!{u8}     // The marker and every metadata block, as a container would carry it.
    firstFrame:  u64            // Offset of the first audio frame.
    mediaEnd:    u64            // End of the last committed frame when this writer left a checkpoint.
    sampleRate:  u32
    channels:    u32
    totalFrames: u64     // Sample frames the stream information states, or zero when unknown.
}

// Reads the marker and the metadata blocks that precede the audio.
private func readPrologue(source: *ByteSource)->Prologue fail
{
    var result: #returntype

    let size = source.size()
    result.mediaEnd = size
    if size < 4
    {
        fail InvalidFormatError{"file does not start with the FLAC stream marker"}
    }

    try source.seek(0)
    let marker = try source.peek(4)
    if marker[0] != 'f' or marker[1] != 'L' or marker[2] != 'a' or marker[3] != 'C'
    {
        fail InvalidFormatError{"file does not start with the FLAC stream marker"}
    }

    var offset   = 4_u64
    var sawFirst = false
    for
    {
        if offset > size or size - offset < 4
        {
            fail InvalidFormatError{"FLAC metadata block header is truncated"}
        }

        try source.seek(offset)
        let header = try source.peek(4)

        let isLast = (header[0] & 0x80) != 0
        let kind   = header[0] & 0x7F
        let length = (cast(u64, header[1]) << 16) | (cast(u64, header[2]) << 8) | cast(u64, header[3])
        if size - offset - 4 < length
        {
            fail InvalidFormatError{"FLAC metadata block runs past the end of the file"}
        }

        // The stream information block is the first one, and the only one this reads.
        if not kind and not sawFirst
        {
            if length != StreamInfoSize
            {
                fail InvalidFormatError{"FLAC stream information block has the wrong size"}
            }

            sawFirst = true
        }

        if kind == 2 and length == 12
        {
            try source.seek(offset + 4)
            let application = try source.peek(12)
            if Memory.compare(application.buffer, "SWAG".buffer, 4) == 0
            {
                var boundary = 0_u64
                for index in 4 until 12
                {
                    boundary = (boundary << 8) | application[index]
                }

                result.mediaEnd = boundary
            }
        }

        offset += 4 + length
        if isLast
        {
            break
        }
    }

    if not sawFirst
    {
        fail InvalidFormatError{"FLAC file has no stream information block"}
    }

    if result.mediaEnd < offset or result.mediaEnd > size
    {
        fail InvalidFormatError{"FLAC recording checkpoint is outside the file"}
    }

    result.config.resize(offset)
    try source.seek(0)
    try source.readExact(result.config.toSlice())
    result.firstFrame = offset

    // The codec answers what the block means, so the file reader and a container reader agree.
    var probe: Codec
    try probe.readStreamInfo(result.config.toSlice())
    result.sampleRate  = probe.info.sampleRate
    result.channels    = probe.info.channels
    result.totalFrames = probe.info.totalSamples
    return result
}

// Returns where the frame starting at `start` ends: at the next frame header, or at the end of
// the file.
//
// The peek starts at one header and doubles until the next validated header is inside what it
// returned. The preceding frame's CRC16 confirms the boundary; a false sync inside compressed
// data cannot divide the frame. `maxFrameBytes` bounds the scan plus one header to validate a
// boundary; `limit` excludes an uncommitted tail of this writer's files.
internal func findFrameEnd(source: *ByteSource,
                           start,
                           limit: u64,
                           maxFrameBytes: u64 = Swag.U64.Max)->u64 fail
{
    let remaining     = limit - start
    let boundedFrame  = Math.min(maxFrameBytes, remaining)
    let boundaryBytes = Math.min(FrameHeaderBytes, remaining)
    let scanLimit     = boundedFrame > remaining - boundaryBytes ? remaining : boundedFrame + boundaryBytes
    var want          = Math.min(FrameHeaderBytes, scanLimit)
    var scan          = 2_u64
    var checkedBytes  = 0_u64
    var checksum      = 0_u16
    for
    {
        try source.seek(start)
        let available = try source.peek(want)
        let bytes     = available[until Math.min(available.count, scanLimit)]
        if not frameHeaderSize(bytes, 0)
        {
            fail InvalidFormatError{"FLAC file does not start a frame where one is expected"}
        }

        var scan = 2_u64
        while scan < bytes.count
        {
            if frameHeaderSize(bytes, scan) and
               frameCrc16(bytes[until scan - 2]) == (cast(u16, bytes[scan - 2]) << 8 | bytes[scan - 1])
            {
                return start + scan
            }

            scan += 1
        }

        if start + bytes.count >= limit
        {
            if bytes.count < 2 or
               frameCrc16(bytes[until bytes.count - 2]) !=
               (cast(u16, bytes[bytes.count - 2]) << 8 | bytes[bytes.count - 1])
            {
                fail InvalidFormatError{"FLAC frame checksum differs from its trailer"}
            }

            return limit
        }

        if bytes.count >= scanLimit
        {
            fail InvalidFormatError{"FLAC frame exceeds its maximum size before the next frame boundary"}
        }

        want = Math.min(bytes.count * 2, scanLimit)
    }
}

// Walks the audio frames of a file and records where each one starts and how long it plays.
//
// Only the read window of the source is held at a time, so indexing a long album costs its
// index and not its audio.
private func readFrameIndex(source: *ByteSource, firstFrame, mediaEnd: u64, packets: *Array!{SoundPacket})->u64 fail
{
    var start = firstFrame
    var total = 0_u64

    while start < mediaEnd
    {
        let next  = try findFrameEnd(source, start, mediaEnd)
        let frame = try source.peek(next - start)
        let count = try packetFrameCount(frame[0 until next - start])
        if next - start > Swag.U32.Max
        {
            fail InvalidFormatError{"FLAC audio frame is larger than a packet may be"}
        }

        packets.add(SoundPacket{start, cast(u32, (next - start)), count})
        total += count
        start = next
    }

    return total
}

// Opens a native FLAC file as a streamed packet sound.
//
// The audio stays in the file: opening reads the metadata prologue and walks the frame headers to
// build the packet index every voice then reads through, exactly as a container reader does for a
// FLAC track it carries.
internal func openFile(path: string)->SoundFile fail
{
    var source   = try ByteSource.openFile(path, .ReadWrite)
    let prologue = try readPrologue(&source)

    var packets: Array!{SoundPacket}
    let frames = try readFrameIndex(&source, prologue.firstFrame, prologue.mediaEnd, &packets)
    if not packets.count
    {
        fail InvalidFormatError{"FLAC file carries no audio frame"}
    }

    // The stream information may state the length; when it does, it is what the file promises.
    if prologue.totalFrames and prologue.totalFrames != frames
    {
        fail InvalidFormatError{"FLAC stream sample count differs from its frames"}
    }

    source.close()
    return try SoundFile.openPacketStream(path, .Flac, prologue.sampleRate, prologue.channels, frames, packets.toSlice(), prologue.config.toSlice())
}
