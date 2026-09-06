//! Format: FLAC (Free Lossless Audio Codec).
//! Supported: Native FLAC files: the stream marker, the metadata prologue, and a frame index built by validating each frame header checksum.
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
            crc = (crc & 0x80) != 0 ? cast(u8) ((crc << 1) ^ 0x07) : cast(u8) (crc << 1)
    }

    return crc
}

// Returns the length of the frame header starting at `offset`, or zero when none does.
//
// A FLAC frame states no length, so a reader finds the end of one by finding the start of the
// next. The sync code alone cannot decide that — the same fourteen bits occur inside coded
// residuals — so the header's own checksum is what answers.
private func frameHeaderSize(bytes: const [..] u8, offset: u64)->u64
{
    if bytes.count - offset < 5 do
        return 0
    if bytes[offset] != 0xFF or (bytes[offset + 1] & 0xFC) != 0xF8 do
        return 0

    let blockSizeCode  = bytes[offset + 2] >> 4
    let sampleRateCode = bytes[offset + 2] & 0x0F
    if !blockSizeCode or sampleRateCode == 0x0F do
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
    sampleRate:  u32
    channels:    u32
    totalFrames: u64     // Sample frames the stream information states, or zero when unknown.
}

// Reads the marker and the metadata blocks that precede the audio.
private func readPrologue(source: *ByteSource)->Prologue fail
{
    var result: retval

    let size = source.size()
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
        let length = (cast(u64) header[1] << 16) | (cast(u64) header[2] << 8) | cast(u64) header[3]
        if size - offset - 4 < length do
            fail InvalidFormatError{"FLAC metadata block runs past the end of the file"}

        // The stream information block is the first one, and the only one this reads.
        if !kind and !sawFirst
        {
            if length != StreamInfoSize do
                fail InvalidFormatError{"FLAC stream information block has the wrong size"}
            sawFirst = true
        }

        offset += 4 + length
        if isLast do
            break
    }

    if !sawFirst do
        fail InvalidFormatError{"FLAC file has no stream information block"}

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
// The peek starts at one header and doubles until the next header is inside what it returned,
// so a frame of any legal size is found without the file being read past it.
private func findFrameEnd(source: *ByteSource, start: u64)->u64 fail
{
    let size = source.size()
    var want = Math.min(FrameHeaderBytes, size - start)
    for
    {
        try source.seek(start)
        let bytes = try source.peek(want)
        if !frameHeaderSize(bytes, 0) do
            fail InvalidFormatError{"FLAC file does not start a frame where one is expected"}

        var scan = 1'u64
        while scan < bytes.count and !frameHeaderSize(bytes, scan) do
            scan += 1
        if scan < bytes.count do
            return start + scan
        if start + bytes.count >= size do
            return size

        want = Math.min(bytes.count * 2, size - start)
    }
}

// Walks the audio frames of a file and records where each one starts and how long it plays.
//
// Only the read window of the source is held at a time, so indexing a long album costs its
// index and not its audio.
private func readFrameIndex(source: *ByteSource, firstFrame: u64, packets: *Array'SoundPacket)->u64 fail
{
    let size  = source.size()
    var start = firstFrame
    var total = 0'u64

    while start < size
    {
        let next  = try findFrameEnd(source, start)
        let frame = try source.peek(next - start)
        let count = try packetFrameCount(frame[0 until next - start])
        if next - start > Swag.U32.Max do
            fail InvalidFormatError{"FLAC audio frame is larger than a packet may be"}
        packets.add({start, cast(u32) (next - start), count})
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
    let frames = try readFrameIndex(&source, prologue.firstFrame, &packets)
    if !packets.count do
        fail InvalidFormatError{"FLAC file carries no audio frame"}

    // The stream information may state the length; when it does, it is what the file promises.
    var declared = frames
    if prologue.totalFrames and prologue.totalFrames <= frames do
        declared = prologue.totalFrames

    source.close()
    return try SoundFile.openPacketStream(path, .Flac, prologue.sampleRate, prologue.channels, declared, packets.toSlice(), prologue.config.toSlice())
}
