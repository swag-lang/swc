//! Format: FLAC (Free Lossless Audio Codec).
//! Supported: Native FLAC files: the stream marker, the metadata prologue, and a frame index built by validating each frame header checksum.
//! Not supported: Ogg-encapsulated FLAC, and seek tables, which this reader does not need because it indexes every frame.
//! Role: This file owns native FLAC file traversal and the streamed packet sound it builds.
//
#global namespace Flac

using Core, Core.Errors

// How much of the file the frame scan holds while looking for the end of one frame.
//
// A frame carries at most 65,535 sample frames, so the largest one a legal stream can hold is a
// little over two megabytes; the window grows to whatever a particular file turns out to need and
// starts far below that, because a real encoder produces frames of a few kilobytes.
private const ScanWindow = 64 * 1024'u64

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
    if @countof(bytes) - offset < 5 do
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

    if @countof(bytes) - offset < size + 1 do
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
private func readPrologue(stream: *File.FileStream, size: u64)->Prologue fail
{
    var result: retval

    var marker: [4] u8
    let read = try stream.readExactAt(0, marker)
    if !read or marker[0] != 'f' or marker[1] != 'L' or marker[2] != 'a' or marker[3] != 'C' do
        fail InvalidFormatError{"file does not start with the FLAC stream marker"}

    var offset   = 4'u64
    var sawFirst = false
    for
    {
        if offset > size or size - offset < 4 do
            fail InvalidFormatError{"FLAC metadata block header is truncated"}

        var header: [4] u8
        if !try stream.readExactAt(offset, header) do
            fail InvalidFormatError{"FLAC metadata block header is truncated"}

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
    if !try stream.readExactAt(0, result.config.toSlice()) do
        fail InvalidFormatError{"FLAC metadata prologue is truncated"}
    result.firstFrame = offset

    // The codec answers what the block means, so the file reader and a container reader agree.
    var probe: Codec
    try probe.readStreamInfo(result.config.toSlice())
    result.sampleRate  = probe.info.sampleRate
    result.channels    = probe.info.channels
    result.totalFrames = probe.info.totalSamples
    return result
}

// Walks the audio frames of a file and records where each one starts and how long it plays.
//
// Only one frame is held in memory at a time, so indexing a long album costs its index and not
// its audio.
private func readFrameIndex(stream: *File.FileStream, size, firstFrame: u64, packets: *Array'SoundPacket)->u64 fail
{
    var window: Array'u8
    var start    = firstFrame
    var loaded   = 0'u64     // Bytes of `window` that hold file content.
    var capacity = ScanWindow
    var total    = 0'u64

    while start < size
    {
        // Load a window at the frame start, growing it until the next frame header is inside it
        // or the file ends.
        var next = 0'u64
        for
        {
            let want = Math.min(capacity, size - start)
            if want != loaded
            {
                window.resize(want)
                if !try stream.readExactAt(start, window.toSlice()) do
                    fail InvalidFormatError{"FLAC audio frame is truncated"}
                loaded = want
            }

            let bytes = window.toSlice()
            if !frameHeaderSize(bytes, 0) do
                fail InvalidFormatError{"FLAC file does not start a frame where one is expected"}

            var scan = 1'u64
            while scan < loaded and !frameHeaderSize(bytes, scan) do
                scan += 1
            if scan < loaded
            {
                next = start + scan
                break
            }

            if start + loaded >= size
            {
                next = size
                break
            }

            capacity *= 2
            loaded   = 0
        }

        let count = try packetFrameCount(window.toSlice()[0 until Math.min(loaded, next - start)])
        if next - start > Swag.U32.Max do
            fail InvalidFormatError{"FLAC audio frame is larger than a packet may be"}
        packets.add({start, cast(u32) (next - start), count})
        total  += count
        start  = next
        loaded = 0
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
    var stream   = File.openRead(path)
    let size     = try stream.size()
    let prologue = try readPrologue(&stream, size)

    var packets: Array'SoundPacket
    let frames = try readFrameIndex(&stream, size, prologue.firstFrame, &packets)
    if !packets.count do
        fail InvalidFormatError{"FLAC file carries no audio frame"}

    // The stream information may state the length; when it does, it is what the file promises.
    var declared = frames
    if prologue.totalFrames and prologue.totalFrames <= frames do
        declared = prologue.totalFrames

    stream.close()
    return try SoundFile.openPacketStream(path, .Flac, prologue.sampleRate, prologue.channels, declared, packets.toSlice(), prologue.config.toSlice())
}
