//! Format: RIFF/WAVE sound-file decoder.
//! Supported: PCM8/16/24/32 and IEEE Float32 in classic or WAVE_FORMAT_EXTENSIBLE `fmt ` chunks, including speaker masks and streamed `data` chunks, and Microsoft or IMA ADPCM blocks indexed as a streamed packet sound.
//! Not supported: Other compressed WAVE codecs, IEEE Float64, RF64/WAVE64, big-endian RIFX, and multiple data segments.
//! Role: This file owns RIFF chunk traversal, WAVE format validation, metadata, and SoundFile construction.
//
#global namespace Wav

using Core, Core.Errors

struct ChunkHeader
{
    chunkID:   ChunkID = undefined
    chunkSize: u32
}

#static if Core.BIG_ENDIAN
{
    #[Swag.ConstExpr]
    func SND_WAV_FOURCC_MARKER(a, b, c, d: u32) => ((a << 24) | (b << 16) | (c << 8) | d)
}
else
{
    #[Swag.ConstExpr]
    func SND_WAV_FOURCC_MARKER(a, b, c, d: u32) => (a | (b << 8) | (c << 16) | (d << 24))
}

enum ChunkID: u32
{
    SND_WAV_FOURCC_RIFF = SND_WAV_FOURCC_MARKER('R'u32, 'I'u32, 'F'u32, 'F'u32)
    SND_WAV_FOURCC_RIFX = SND_WAV_FOURCC_MARKER('R'u32, 'I'u32, 'F'u32, 'X'u32)
    SND_WAV_FOURCC_WAVE = SND_WAV_FOURCC_MARKER('W'u32, 'A'u32, 'V'u32, 'E'u32)
    SND_WAV_FOURCC_fmt  = SND_WAV_FOURCC_MARKER('f'u32, 'm'u32, 't'u32, ' 'u32)
    SND_WAV_FOURCC_data = SND_WAV_FOURCC_MARKER('d'u32, 'a'u32, 't'u32, 'a'u32)
    SND_WAV_FOURCC_fact = SND_WAV_FOURCC_MARKER('f'u32, 'a'u32, 'c'u32, 't'u32)
    SND_WAV_FOURCC_PEAK = SND_WAV_FOURCC_MARKER('P'u32, 'E'u32, 'A'u32, 'K'u32)
    SND_WAV_FOURCC_cue  = SND_WAV_FOURCC_MARKER('c'u32, 'u'u32, 'e'u32, ' 'u32)
    SND_WAV_FOURCC_LIST = SND_WAV_FOURCC_MARKER('L'u32, 'I'u32, 'S'u32, 'T'u32)
    SND_WAV_FOURCC_slnt = SND_WAV_FOURCC_MARKER('s'u32, 'l'u32, 'n'u32, 't'u32)
    SND_WAV_FOURCC_wavl = SND_WAV_FOURCC_MARKER('w'u32, 'a'u32, 'v'u32, 'l'u32)
    SND_WAV_FOURCC_INFO = SND_WAV_FOURCC_MARKER('I'u32, 'N'u32, 'F'u32, 'O'u32)
    SND_WAV_FOURCC_plst = SND_WAV_FOURCC_MARKER('p'u32, 'l'u32, 's'u32, 't'u32)
    SND_WAV_FOURCC_adtl = SND_WAV_FOURCC_MARKER('a'u32, 'd'u32, 't'u32, 'l'u32)
    SND_WAV_FOURCC_labl = SND_WAV_FOURCC_MARKER('l'u32, 'a'u32, 'b'u32, 'l'u32)
    SND_WAV_FOURCC_ltxt = SND_WAV_FOURCC_MARKER('l'u32, 't'u32, 'x'u32, 't'u32)
    SND_WAV_FOURCC_note = SND_WAV_FOURCC_MARKER('n'u32, 'o'u32, 't'u32, 'e'u32)
    SND_WAV_FOURCC_smpl = SND_WAV_FOURCC_MARKER('s'u32, 'm'u32, 'p'u32, 'l'u32)
    SND_WAV_FOURCC_bext = SND_WAV_FOURCC_MARKER('b'u32, 'e'u32, 'x'u32, 't'u32)
    SND_WAV_FOURCC_levl = SND_WAV_FOURCC_MARKER('l'u32, 'e'u32, 'v'u32, 'l'u32)
    SND_WAV_FOURCC_MEXT = SND_WAV_FOURCC_MARKER('M'u32, 'E'u32, 'X'u32, 'T'u32)
    SND_WAV_FOURCC_DISP = SND_WAV_FOURCC_MARKER('D'u32, 'I'u32, 'S'u32, 'P'u32)
    SND_WAV_FOURCC_acid = SND_WAV_FOURCC_MARKER('a'u32, 'c'u32, 'i'u32, 'd'u32)
    SND_WAV_FOURCC_strc = SND_WAV_FOURCC_MARKER('s'u32, 't'u32, 'r'u32, 'c'u32)
    SND_WAV_FOURCC_PAD  = SND_WAV_FOURCC_MARKER('P'u32, 'A'u32, 'D'u32, ' 'u32)
    SND_WAV_FOURCC_afsp = SND_WAV_FOURCC_MARKER('a'u32, 'f'u32, 's'u32, 'p'u32)
    SND_WAV_FOURCC_clm  = SND_WAV_FOURCC_MARKER('c'u32, 'l'u32, 'm'u32, ' 'u32)
    SND_WAV_FOURCC_elmo = SND_WAV_FOURCC_MARKER('e'u32, 'l'u32, 'm'u32, 'o'u32)
    SND_WAV_FOURCC_ISFT = SND_WAV_FOURCC_MARKER('I'u32, 'S'u32, 'F'u32, 'T'u32)
    SND_WAV_FOURCC_ICRD = SND_WAV_FOURCC_MARKER('I'u32, 'C'u32, 'R'u32, 'D'u32)
    SND_WAV_FOURCC_ICOP = SND_WAV_FOURCC_MARKER('I'u32, 'C'u32, 'O'u32, 'P'u32)
    SND_WAV_FOURCC_IARL = SND_WAV_FOURCC_MARKER('I'u32, 'A'u32, 'R'u32, 'L'u32)
    SND_WAV_FOURCC_IART = SND_WAV_FOURCC_MARKER('I'u32, 'A'u32, 'R'u32, 'T'u32)
    SND_WAV_FOURCC_INAM = SND_WAV_FOURCC_MARKER('I'u32, 'N'u32, 'A'u32, 'M'u32)
    SND_WAV_FOURCC_IENG = SND_WAV_FOURCC_MARKER('I'u32, 'E'u32, 'N'u32, 'G'u32)
    SND_WAV_FOURCC_IPRD = SND_WAV_FOURCC_MARKER('I'u32, 'P'u32, 'R'u32, 'D'u32)
    SND_WAV_FOURCC_ISRC = SND_WAV_FOURCC_MARKER('I'u32, 'S'u32, 'R'u32, 'C'u32)
    SND_WAV_FOURCC_ISBJ = SND_WAV_FOURCC_MARKER('I'u32, 'S'u32, 'B'u32, 'J'u32)
    SND_WAV_FOURCC_ICMT = SND_WAV_FOURCC_MARKER('I'u32, 'C'u32, 'M'u32, 'T'u32)
}

const WAVE_FORMAT_UNKNOWN    = 0x0000     /* Microsoft Corporation */
const WAVE_FORMAT_PCM        = 0x0001     /* Microsoft Corporation */
const WAVE_FORMAT_ADPCM      = 0x0002     /* Microsoft Corporation */
const WAVE_FORMAT_IEEE_FLOAT = 0x0003     /* Microsoft Corporation */
const WAVE_FORMAT_IMA_ADPCM  = 0x0011     /* Intel Corporation */
const WAVE_FORMAT_EXTENSIBLE = 0xFFFE     /* Microsoft */

// Packed UUID representation used by the WAVE extensible header.
#[Swag.Pack(1)]
struct SubformatUuid
{
    data1: u32
    data2: u16
    data3: u16
    data4: [8] u8
}

#assert(#sizeof(SubformatUuid) == 16)

const SubformatPcm       = SubformatUuid{0x00000001, 0x0000, 0x0010, [0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71]}
const SubformatAdpcm     = SubformatUuid{0x00000002, 0x0000, 0x0010, [0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71]}
const SubformatIeeeFloat = SubformatUuid{0x00000003, 0x0000, 0x0010, [0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71]}
const SubformatImaAdpcm  = SubformatUuid{0x00000011, 0x0000, 0x0010, [0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71]}

func copySubformat(destination: *void, source: SubformatUuid)
{
    Memory.copy(destination, &source, #sizeof(source))
}

// Offsets of the fields inside a `fmt ` chunk, and the sizes at which each family of fields is present.
private const FormatBaseSize       = 14'u64     // WAVEFORMAT: tag, channels, rate, average bytes, block alignment.
private const FormatBitsSize       = 16'u64     // PCMWAVEFORMAT adds the bits per sample.
private const FormatExtraSize      = 18'u64     // WAVEFORMATEX adds the size of what follows.
private const FormatExtensibleSize = 40'u64     // WAVEFORMATEXTENSIBLE adds valid bits, the speaker mask, and the subformat.

// A `fmt ` chunk larger than this is not one; the extensible form is forty bytes and a Microsoft
// ADPCM coefficient table adds a few dozen more.
private const MaxFormatChunk = 4096'u64

// What the `fmt ` chunk declares, kept apart from the sound so a compressed format can build its
// packet index from it before any [[Audio.SoundFile]] exists.
private struct Format
{
    channels:      u32
    sampleRate:    u32
    blockAlign:    u32
    bitsPerSample: u32
    validBits:     u16
    speakerMask:   u32
    encoding:      SoundFileEncoding
    hasBitsField:  bool         // The chunk states the bits per sample rather than implying them.
    hasExtensible: bool         // The chunk carries the valid bits, the speaker mask, and a subformat.
    extra:         Array'u8     // Format-specific bytes after the subformat, or after `cbSize` in a classic chunk.
}

private func readU16(bytes: const [..] u8, offset: u64)->u32 => cast(u32) bytes[offset] | (cast(u32) bytes[offset + 1] << 8)
private func readU32(bytes: const [..] u8, offset: u64)->u32 => readU16(bytes, offset) | (readU16(bytes, offset + 2) << 16)

private func encodingOf(tag, bitsPerSample: u32)->SoundFileEncoding fail
{
    switch tag
    {
    case WAVE_FORMAT_PCM:
        switch bitsPerSample
        {
        case 8:  return .Pcm8
        case 16: return .Pcm16
        case 24: return .Pcm24
        case 32: return .Pcm32
        default: fail UnsupportedFormatError{"unsupported pcm bitPerSample"}
        }

    case WAVE_FORMAT_IEEE_FLOAT:
        if bitsPerSample != 32 do
            fail UnsupportedFormatError{"unsupported float bitPerSample"}
        return .Float32

    case WAVE_FORMAT_ADPCM:
        if bitsPerSample != 4 do
            fail UnsupportedFormatError{"WAV Microsoft ADPCM is only supported at four bits a sample"}
        return .AdpcmMs

    case WAVE_FORMAT_IMA_ADPCM:
        if bitsPerSample != 4 do
            fail UnsupportedFormatError{"WAV IMA ADPCM is only supported at four bits a sample"}
        return .AdpcmIma

    default:
        fail UnsupportedFormatError{"unsupported wav format"}
    }
}

// Returns the classic format tag an extensible subformat stands for.
private func subformatTag(subformat: const [..] u8)->u32 fail
{
    if Memory.bytesEqual(cast(const *SubformatUuid) subformat.buffer, SubformatPcm) do
        return WAVE_FORMAT_PCM
    if Memory.bytesEqual(cast(const *SubformatUuid) subformat.buffer, SubformatIeeeFloat) do
        return WAVE_FORMAT_IEEE_FLOAT
    if Memory.bytesEqual(cast(const *SubformatUuid) subformat.buffer, SubformatAdpcm) do
        return WAVE_FORMAT_ADPCM
    if Memory.bytesEqual(cast(const *SubformatUuid) subformat.buffer, SubformatImaAdpcm) do
        return WAVE_FORMAT_IMA_ADPCM
    fail UnsupportedFormatError{"unsupported wav format"}
}

// Reads what a `fmt ` chunk declares.
private func parseFormat(bytes: const [..] u8)->Format fail
{
    let size = bytes.count
    if size < FormatBaseSize do
        fail InvalidFormatError{"invalid wav"}

    var result: retval
    let tag = readU16(bytes, 0)
    result.channels   = readU16(bytes, 2)
    result.sampleRate = readU32(bytes, 4)
    let averageBytes = readU32(bytes, 8)
    result.blockAlign = readU16(bytes, 12)
    if !result.channels do
        fail InvalidFormatError{"WAV channel count must be greater than zero"}
    if !result.sampleRate do
        fail InvalidFormatError{"WAV sample rate must be greater than zero"}

    // The oldest chunks state no sample width; the byte rate implies it.
    result.bitsPerSample = (averageBytes * 8 / result.channels) / result.sampleRate
    if size >= FormatBitsSize
    {
        result.bitsPerSample = readU16(bytes, 14)
        result.hasBitsField  = true
    }

    var extraStart = FormatExtraSize
    var extraEnd   = FormatExtraSize
    if size >= FormatExtraSize do
        extraEnd = Math.min(size, FormatExtraSize + readU16(bytes, 16))

    var classicTag = tag
    if size >= FormatExtensibleSize
    {
        result.validBits     = cast(u16) readU16(bytes, 18)
        result.speakerMask   = readU32(bytes, 20)
        result.hasExtensible = true
        if tag == WAVE_FORMAT_EXTENSIBLE
        {
            classicTag = try subformatTag(bytes[24 until 40])
            extraStart = FormatExtensibleSize
        }
    }
    elif tag == WAVE_FORMAT_EXTENSIBLE do
        fail InvalidFormatError{"invalid wav"}

    result.encoding = try encodingOf(classicTag, result.bitsPerSample)
    if extraEnd > extraStart do
        result.extra.add(bytes[extraStart until extraEnd])
    return result
}

// Where the audio and its declared length were found while walking the chunks.
private struct Layout
{
    format:     Format
    dataOffset: u64
    dataSize:   u64
    factFrames: u64     // Sample frames the `fact` chunk states, or zero without one.
    hasData:    bool
}

// Walks the RIFF chunks up to and including the `data` chunk.
//
// The stream is left positioned on the first payload byte, so a caller that keeps the audio in
// memory reads it from there.
private func readLayout(stream: *File.FileStream)->Layout fail
{
    enum Stage
    {
        FindRiff
        FindFmt
        FindData
    }

    var result: retval
    var stage:  Stage = FindRiff
    var header: ChunkHeader
    let size          = stream.size()

    for
    {
        let seek = stream.position()
        if seek >= size do
            fail InvalidFormatError{"invalid wav"}
        if seek & 1 do
            stream.skip(1)

        if !stream.readValue(&header) do
            fail InvalidFormatError{"invalid wav"}

        switch header.chunkID
        {
        case .SND_WAV_FOURCC_RIFF:
            if stage == .FindRiff
            {
                if !stream.readValue(&header.chunkID) do
                    fail InvalidFormatError{"invalid riff chunk"}
                if header.chunkID != SND_WAV_FOURCC_WAVE do
                    fail InvalidFormatError{"not a wav"}
                stage = .FindFmt
            }

        case .SND_WAV_FOURCC_fmt:
            if stage == .FindFmt
            {
                if header.chunkSize > MaxFormatChunk do
                    fail InvalidFormatError{"invalid wav"}
                var bytes: Array'u8
                bytes.resize(header.chunkSize)
                if stream.read(bytes.toSlice()) != header.chunkSize do
                    fail InvalidFormatError{"invalid wav"}
                result.format = try parseFormat(bytes.toSlice())
                stage         = .FindData
            }

        case .SND_WAV_FOURCC_fact:
            if header.chunkSize >= 4
            {
                var count: u32
                if !stream.readValue(&count) do
                    fail InvalidFormatError{"invalid wav"}
                result.factFrames = count
                stream.skip(header.chunkSize - 4)
            }
            else do
                stream.skip(header.chunkSize)

        case .SND_WAV_FOURCC_data:
            if stage == .FindData
            {
                result.hasData    = true
                result.dataOffset = stream.position()
                result.dataSize   = header.chunkSize
                return result
            }

        case .SND_WAV_FOURCC_cue, .SND_WAV_FOURCC_LIST, .SND_WAV_FOURCC_labl, .SND_WAV_FOURCC_note, .SND_WAV_FOURCC_ltxt, .SND_WAV_FOURCC_bext:
            stream.skip(header.chunkSize)

        default:
            if header.chunkSize do
                stream.skip(header.chunkSize)
            else do
                fail InvalidFormatError{"invalid wav"}
        }
    }
}

// Indexes the blocks of an ADPCM `data` chunk as a streamed packet sound.
//
// Every block decodes to what its bytes hold, the final one included, so the duration counts
// every sample the blocks reconstruct, as FFmpeg reports it; a `fact` chunk stating fewer
// frames is accepted, one stating more is not.
private func openAdpcm(path: string, layout: const *Layout)->SoundFile fail
{
    let format = &layout.format
    if !format.blockAlign do
        fail InvalidFormatError{"WAV ADPCM block alignment is zero"}
    if format.channels > 2 do
        fail UnsupportedFormatError{"WAV ADPCM is only supported with one or two channels"}

    var packets: Array'SoundPacket
    var total = 0'u64
    var at    = 0'u64
    while at < layout.dataSize
    {
        let bytes  = Math.min(cast(u64) format.blockAlign, layout.dataSize - at)
        let frames = Adpcm.blockFrameCount(format.encoding, format.channels, bytes)
        if !frames do
            break
        packets.add({layout.dataOffset + at, cast(u32) bytes, cast(u32) frames})
        total += frames
        at    += bytes
    }

    if !packets.count do
        fail InvalidFormatError{"WAV ADPCM data holds no complete block"}
    if layout.factFrames > total do
        fail InvalidFormatError{"WAV fact chunk declares more sample frames than the blocks decode to"}

    return try SoundFile.openPacketStream(path, format.encoding, format.sampleRate, format.channels, total, packets.toSlice(), format.extra.toSlice(), {speakerMask: format.speakerMask})
}

// Opens a RIFF/WAVE file.
//
// PCM and floating-point audio describe the sound in place, kept in memory when `preloadData` is
// set and streamed from `path` otherwise. ADPCM audio is always streamed: its blocks are indexed
// as packets and decoded on demand, so `preloadData` does not apply to it.
internal func openFile(path: string, preloadData: bool)->SoundFile fail
{
    var stream = File.openRead(path)
    let layout = try readLayout(&stream)
    let format = &layout.format
    if format.encoding == .AdpcmMs or format.encoding == .AdpcmIma
    {
        stream.close()
        return try openAdpcm(path, &layout)
    }

    let bytesPerSample = format.bitsPerSample / 8
    if !bytesPerSample do
        fail InvalidFormatError{"invalid wav"}

    var result: retval
    result.path               = path
    result.encoding           = format.encoding
    result.sampleRate         = format.sampleRate
    result.channelCount       = format.channels
    result.bitsPerSample      = format.bitsPerSample
    result.validBitsPerSample = format.validBits
    result.waveSpeakerMask    = format.speakerMask
    result.availableFields    = .Format | .SampleRate | .ChannelCount
    if format.hasBitsField do
        result.availableFields |= .BitsPerSample
    if format.hasExtensible do
        result.availableFields |= .SpeakerMask | .ValidBitsPerSample

    result.availableFields |= .Data | .FrameCount | .Duration
    result.dataOffset      = layout.dataOffset
    result.dataSize        = layout.dataSize
    result.frameCount      = layout.dataSize / (format.channels * bytesPerSample)
    result.durationSeconds = cast(f32) (result.frameCount / cast(f64) format.sampleRate)
    if preloadData
    {
        result.data.resize(layout.dataSize)
        if stream.read(result.data.buffer, layout.dataSize) != layout.dataSize do
            fail InvalidFormatError{"WAV audio data is truncated"}
    }

    return result
}
