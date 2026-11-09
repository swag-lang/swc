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
private const FrameHeaderBytes = 16'u64

// The polynomial a FLAC frame header protects itself with, clause 9.1.
private func headerCrc8(bytes: const [..] u8)->u8
{
    var crc = 0'u8
    for value in bytes
    {
        crc ^= value
        for 8 do
            crc = (crc & 0x80) != 0 ? cast(u8, ((crc << 1) ^ 0x07)) : cast(u8, (crc << 1))
    }

    return crc
}

// FLAC's frame trailer protects the complete header and coded subframes.
internal func frameCrc16(bytes: const [..] u8)->u16
{
    var checksum = 0'u16
    for byte in bytes
    {
        checksum ^= cast(u16, byte) << 8
        for 8 do
            checksum = checksum & 0x8000 ? cast(u16, ((cast(u32, checksum) << 1) ^ 0x8005) & 0xFFFF) :
                                          cast(u16, (cast(u32, checksum) << 1) & 0xFFFF)
    }
    return checksum
}

// Returns the length of the frame header starting at `offset`, or zero when none does.
//
// A FLAC frame states no length, so a reader finds the end of one by finding the start of the
// next. The sync code alone cannot decide that — the same fourteen bits occur inside coded
// residuals — so the header's own checksum identifies a candidate.
private func frameHeaderSize(bytes: const [..] u8, offset: u64)->u64
{
    if bytes.count - offset < 5 do
        return 0
    if bytes[offset] != 0xFF or (bytes[offset + 1] & 0xFC) != 0xF8 do
        return 0

    let blockSizeCode  = bytes[offset + 2] >> 4
    let sampleRateCode = bytes[offset + 2] & 0x0F
    if not blockSizeCode or sampleRateCode == 0x0F do
        return 0

    // The frame or sample number is stored the way UTF-8 stores a code point.
    let lead = bytes[offset + 4]
    var size = 5'u64
    if lead >= 0xFE do
        size += 6
    elif lead >= 0xFC do
        size += 5
    elif lead >= 0xF8 do
        size += 4
    elif lead >= 0xF0 do
        size += 3
    elif lead >= 0xE0 do
        size += 2
    elif lead >= 0xC0 do
        size += 1
    elif lead >= 0x80 do
        return 0

    if blockSizeCode == 6 do
        size += 1
    elif blockSizeCode == 7 do
        size += 2
    if sampleRateCode == 12 do
        size += 1
    elif sampleRateCode == 13 or sampleRateCode == 14 do
        size += 2

    if bytes.count - offset < size + 1 do
        return 0
    if headerCrc8(bytes[offset until offset + size]) != bytes[offset + size] do
        return 0
    return size + 1
}

// What the metadata prologue of a file says about the stream that follows it.
private struct Prologue
{
    config:      Array'u8     // The marker and every metadata block, as a container would carry it.
    firstFrame:  u64          // Offset of the first audio frame.
    mediaEnd:    u64          // End of the last committed frame when this writer left a checkpoint.
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
    if size < 4 do
        fail InvalidFormatError{"file does not start with the FLAC stream marker"}
    try source.seek(0)
    let marker = try source.peek(4)
    if marker[0] != 'f' or marker[1] != 'L' or marker[2] != 'a' or marker[3] != 'C' do
        fail InvalidFormatError{"file does not start with the FLAC stream marker"}

    var offset   = 4'u64
    var sawFirst = false
    for
    {
        if offset > size or size - offset < 4 do
            fail InvalidFormatError{"FLAC metadata block header is truncated"}

        try source.seek(offset)
        let header = try source.peek(4)

        let isLast = (header[0] & 0x80) != 0
        let kind   = header[0] & 0x7F
        let length = (cast(u64, header[1]) << 16) | (cast(u64, header[2]) << 8) | cast(u64, header[3])
        if size - offset - 4 < length do
            fail InvalidFormatError{"FLAC metadata block runs past the end of the file"}

        // The stream information block is the first one, and the only one this reads.
        if not kind and not sawFirst
        {
            if length != StreamInfoSize do
                fail InvalidFormatError{"FLAC stream information block has the wrong size"}
            sawFirst = true
        }

        if kind == 2 and length == 12
        {
            try source.seek(offset + 4)
            let application = try source.peek(12)
            if Memory.compare(application.buffer, "SWAG".buffer, 4) == 0
            {
                var boundary = 0'u64
                for index in 4 until 12 do
                    boundary = (boundary << 8) | application[index]
                result.mediaEnd = boundary
            }
        }

        offset += 4 + length
        if isLast do
            break
    }

    if not sawFirst do
        fail InvalidFormatError{"FLAC file has no stream information block"}
    if result.mediaEnd < offset or result.mediaEnd > size do
        fail InvalidFormatError{"FLAC recording checkpoint is outside the file"}

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
// data cannot divide the frame. `limit` excludes an uncommitted tail of this writer's files.
internal func findFrameEnd(source: *ByteSource, start, limit: u64)->u64 fail
{
    var want = Math.min(FrameHeaderBytes, limit - start)
    for
    {
        try source.seek(start)
        let available = try source.peek(want)
        let bytes     = available[until Math.min(available.count, limit - start)]
        if not frameHeaderSize(bytes, 0) do
            fail InvalidFormatError{"FLAC file does not start a frame where one is expected"}

        var scan = 2'u64
        while scan < bytes.count
        {
            if frameHeaderSize(bytes, scan) and
               frameCrc16(bytes[until scan - 2]) == (cast(u16, bytes[scan - 2]) << 8 | bytes[scan - 1]) do
                return start + scan
            scan += 1
        }
        if start + bytes.count >= limit
        {
            if bytes.count < 2 or
               frameCrc16(bytes[until bytes.count - 2]) !=
                   (cast(u16, bytes[bytes.count - 2]) << 8 | bytes[bytes.count - 1]) do
                fail InvalidFormatError{"FLAC frame checksum differs from its trailer"}
            return limit
        }

        want = Math.min(bytes.count * 2, limit - start)
    }
}

// Walks the audio frames of a file and records where each one starts and how long it plays.
//
// Only the read window of the source is held at a time, so indexing a long album costs its
// index and not its audio.
private func readFrameIndex(source: *ByteSource, firstFrame, mediaEnd: u64, packets: *Array'SoundPacket)->u64 fail
{
    var start = firstFrame
    var total = 0'u64

    while start < mediaEnd
    {
        let next  = try findFrameEnd(source, start, mediaEnd)
        let frame = try source.peek(next - start)
        let count = try packetFrameCount(frame[0 until next - start])
        if next - start > Swag.U32.Max do
            fail InvalidFormatError{"FLAC audio frame is larger than a packet may be"}
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
    var source   = try ByteSource.openFile(path)
    let prologue = try readPrologue(&source)

    var packets: Array'SoundPacket
    let frames = try readFrameIndex(&source, prologue.firstFrame, prologue.mediaEnd, &packets)
    if not packets.count do
        fail InvalidFormatError{"FLAC file carries no audio frame"}

    // The stream information may state the length; when it does, it is what the file promises.
    var declared = frames
    if prologue.totalFrames and prologue.totalFrames <= frames do
        declared = prologue.totalFrames

    source.close()
    return try SoundFile.openPacketStream(path, .Flac, prologue.sampleRate, prologue.channels, declared, packets.toSlice(), prologue.config.toSlice())
}
