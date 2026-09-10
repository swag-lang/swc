//! Format: MPEG-1, MPEG-2, and MPEG-2.5 Layer III sound file.
//! Supported: Native `.mp3` files: ID3v2 prologues, an encoder information frame, the LAME encoder delay, and a frame index built by walking the frame headers.
//! Not supported: Free-format streams, ID3v1 trailers as metadata, and writing MP3.
//! Role: This file owns native MP3 file traversal and the streamed packet sound it builds.
//
#global namespace Mp3
#global internal

using Core, Core.Errors

// The delay a Layer III decoder adds on its own, before any encoder delay.
//
// The filter bank looks back over blocks that did not exist when the stream started, so its first
// 529 samples belong to no input sample. Every player drops them, which is what makes two players
// line up on the same file.
const DecoderDelay = 529'u64

// Bytes a frame header spans, which is what the walk peeks at each frame.
private const HeaderBytes = 4'u64

// Returns where the audio starts, past any ID3v2 prologue.
private func skipMetadata(source: *ByteSource)->u64 fail
{
    let size = source.size()
    if size < 10 do
        return 0

    try source.seek(0)
    let header = try source.peek(10)
    if header[0] != 'I' or header[1] != 'D' or header[2] != '3' do
        return 0

    // The length is four groups of seven bits, most significant first, and excludes the header.
    var length = 0'u64
    for index in 4'u64 do
        length = (length << 7) | cast(u64) (header[6 + index] & 0x7F)

    // A footer, when the flags announce one, adds ten bytes more.
    if (header[5] & 0x10) != 0 do
        length += 10
    let start = 10 + length
    return start <= size ? start : size
}

// What the encoder wrote about its own stream, when it wrote anything.
private struct EncoderInfo
{
    isHeaderFrame: bool     // The first frame carries the tag and decodes to silence.
    delayFrames:   u64      // Priming the encoder added and a player drops.
}

// Reads the Xing or Info tag a first frame may carry, clause-free and encoder-specific.
private func readEncoderInfo(frame: const [..] u8, header: const *FrameHeader)->EncoderInfo
{
    var result: retval

    // The tag sits right after the side information of the frame that carries it.
    let at = 4 + header.sideInfoBytes
    if at + 8 > frame.count do
        return result
    let isXing = frame[at] == 'X' and frame[at + 1] == 'i' and frame[at + 2] == 'n' and frame[at + 3] == 'g'
    let isInfo = frame[at] == 'I' and frame[at + 1] == 'n' and frame[at + 2] == 'f' and frame[at + 3] == 'o'
    if not isXing and not isInfo do
        return result

    result.isHeaderFrame = true

    // The LAME extension follows the tag at a fixed distance and states the priming.
    let lame = at + 120
    if lame + 24 > frame.count do
        return result
    let delay = (cast(u64) frame[lame + 0x15] << 4) | (cast(u64) frame[lame + 0x16] >> 4)
    if delay do
        result.delayFrames = delay + DecoderDelay
    return result
}

// Walks the frames of a file and records where each one starts and how long it plays.
//
// Only the read window of the source is held at a time, so indexing a long recording costs its
// index and not its audio.
private func readFrameIndex(source: *ByteSource, start: u64, packets: *Array'SoundPacket, info: *EncoderInfo, first: *FrameHeader)->u64 fail
{
    let size  = source.size()
    var at    = start
    var total = 0'u64
    var seen  = false

    while at + HeaderBytes <= size
    {
        try source.seek(at)
        let probe  = try source.peek(HeaderBytes)
        let header = catch readHeader(probe) as err
        if err != null
        {
            // Tags and padding sit between frames often enough that one bad byte is not the end
            // of the stream; a run of them is.
            at += 1
            continue
        }

        if at + header.frameBytes > size do
            break

        if not seen
        {
            seen    = true
            first[] = header
            let frame = try source.peek(header.frameBytes)
            info[] = readEncoderInfo(frame[0 until header.frameBytes], &header)
            if info.isHeaderFrame
            {
                // The tag frame decodes to silence and belongs to no sample.
                at += header.frameBytes
                continue
            }
        }
        elif header.sampleRate != first.sampleRate or header.channels != first.channels
        {
            // A file that changes shape mid-stream is not one this reader indexes.
            break
        }

        if header.frameBytes > Swag.U32.Max do
            fail InvalidFormatError{"MP3 frame is larger than a packet may be"}
        packets.add({at, cast(u32) header.frameBytes, header.frameSamples})
        total += cast(u64) header.frameSamples
        at    += header.frameBytes
    }

    if not seen do
        fail InvalidFormatError{"file carries no MP3 frame"}
    return total
}

// Opens a native MP3 file as a streamed packet sound.
//
// The audio stays in the file: opening walks the frame headers to build the packet index every
// voice then reads through, exactly as a container reader does for a Layer III track it carries.
internal func openFile(path: string)->SoundFile fail
{
    var source = try ByteSource.openFile(path)
    let start  = try skipMetadata(&source)

    var packets: Array'SoundPacket
    var info:    EncoderInfo
    var first:   FrameHeader
    let frames = try readFrameIndex(&source, start, &packets, &info, &first)
    if not packets.count do
        fail InvalidFormatError{"MP3 file carries no audio frame"}

    // A file with no encoder tag still has the decoder's own priming to drop.
    var trim = info.delayFrames
    if not trim and info.isHeaderFrame do
        trim = DecoderDelay
    if trim >= frames do
        trim = 0

    let options = PacketStreamOptions{leadingTrimFrames: trim}
    source.close()
    var config: Array'u8
    return try SoundFile.openPacketStream(path, .Mp3, first.sampleRate, first.channels, frames, packets.toSlice(), config.toSlice(), options)
}
