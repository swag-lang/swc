//! Format: RIFF/WAVE sound-file decoder.
//! Supported: PCM8/16/24/32 and IEEE Float32 in classic or WAVE_FORMAT_EXTENSIBLE `fmt ` chunks, including speaker masks and streamed `data` chunks, and Microsoft or IMA ADPCM blocks indexed as a streamed packet sound.
//! Not supported: Other compressed WAVE codecs, IEEE Float64, RF64/WAVE64, big-endian RIFX, and multiple data segments.
//! Role: This file owns RIFF chunk traversal, WAVE format validation, metadata, and SoundFile construction.
//
#global namespace Wav

using Core, Core.Errors

struct ChunkHeader
{
    chunkID:   ChunkID
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
    SND_WAV_FOURCC_RIFF = SND_WAV_FOURCC_MARKER('R'_u32, 'I'_u32, 'F'_u32, 'F'_u32)
    SND_WAV_FOURCC_RIFX = SND_WAV_FOURCC_MARKER('R'_u32, 'I'_u32, 'F'_u32, 'X'_u32)
    SND_WAV_FOURCC_WAVE = SND_WAV_FOURCC_MARKER('W'_u32, 'A'_u32, 'V'_u32, 'E'_u32)
    SND_WAV_FOURCC_fmt  = SND_WAV_FOURCC_MARKER('f'_u32, 'm'_u32, 't'_u32, ' '_u32)
    SND_WAV_FOURCC_data = SND_WAV_FOURCC_MARKER('d'_u32, 'a'_u32, 't'_u32, 'a'_u32)
    SND_WAV_FOURCC_fact = SND_WAV_FOURCC_MARKER('f'_u32, 'a'_u32, 'c'_u32, 't'_u32)
    SND_WAV_FOURCC_PEAK = SND_WAV_FOURCC_MARKER('P'_u32, 'E'_u32, 'A'_u32, 'K'_u32)
    SND_WAV_FOURCC_cue  = SND_WAV_FOURCC_MARKER('c'_u32, 'u'_u32, 'e'_u32, ' '_u32)
    SND_WAV_FOURCC_LIST = SND_WAV_FOURCC_MARKER('L'_u32, 'I'_u32, 'S'_u32, 'T'_u32)
    SND_WAV_FOURCC_slnt = SND_WAV_FOURCC_MARKER('s'_u32, 'l'_u32, 'n'_u32, 't'_u32)
    SND_WAV_FOURCC_wavl = SND_WAV_FOURCC_MARKER('w'_u32, 'a'_u32, 'v'_u32, 'l'_u32)
    SND_WAV_FOURCC_INFO = SND_WAV_FOURCC_MARKER('I'_u32, 'N'_u32, 'F'_u32, 'O'_u32)
    SND_WAV_FOURCC_plst = SND_WAV_FOURCC_MARKER('p'_u32, 'l'_u32, 's'_u32, 't'_u32)
    SND_WAV_FOURCC_adtl = SND_WAV_FOURCC_MARKER('a'_u32, 'd'_u32, 't'_u32, 'l'_u32)
    SND_WAV_FOURCC_labl = SND_WAV_FOURCC_MARKER('l'_u32, 'a'_u32, 'b'_u32, 'l'_u32)
    SND_WAV_FOURCC_ltxt = SND_WAV_FOURCC_MARKER('l'_u32, 't'_u32, 'x'_u32, 't'_u32)
    SND_WAV_FOURCC_note = SND_WAV_FOURCC_MARKER('n'_u32, 'o'_u32, 't'_u32, 'e'_u32)
    SND_WAV_FOURCC_smpl = SND_WAV_FOURCC_MARKER('s'_u32, 'm'_u32, 'p'_u32, 'l'_u32)
    SND_WAV_FOURCC_bext = SND_WAV_FOURCC_MARKER('b'_u32, 'e'_u32, 'x'_u32, 't'_u32)
    SND_WAV_FOURCC_levl = SND_WAV_FOURCC_MARKER('l'_u32, 'e'_u32, 'v'_u32, 'l'_u32)
    SND_WAV_FOURCC_MEXT = SND_WAV_FOURCC_MARKER('M'_u32, 'E'_u32, 'X'_u32, 'T'_u32)
    SND_WAV_FOURCC_DISP = SND_WAV_FOURCC_MARKER('D'_u32, 'I'_u32, 'S'_u32, 'P'_u32)
    SND_WAV_FOURCC_acid = SND_WAV_FOURCC_MARKER('a'_u32, 'c'_u32, 'i'_u32, 'd'_u32)
    SND_WAV_FOURCC_strc = SND_WAV_FOURCC_MARKER('s'_u32, 't'_u32, 'r'_u32, 'c'_u32)
    SND_WAV_FOURCC_PAD  = SND_WAV_FOURCC_MARKER('P'_u32, 'A'_u32, 'D'_u32, ' '_u32)
    SND_WAV_FOURCC_afsp = SND_WAV_FOURCC_MARKER('a'_u32, 'f'_u32, 's'_u32, 'p'_u32)
    SND_WAV_FOURCC_clm  = SND_WAV_FOURCC_MARKER('c'_u32, 'l'_u32, 'm'_u32, ' '_u32)
    SND_WAV_FOURCC_elmo = SND_WAV_FOURCC_MARKER('e'_u32, 'l'_u32, 'm'_u32, 'o'_u32)
    SND_WAV_FOURCC_ISFT = SND_WAV_FOURCC_MARKER('I'_u32, 'S'_u32, 'F'_u32, 'T'_u32)
    SND_WAV_FOURCC_ICRD = SND_WAV_FOURCC_MARKER('I'_u32, 'C'_u32, 'R'_u32, 'D'_u32)
    SND_WAV_FOURCC_ICOP = SND_WAV_FOURCC_MARKER('I'_u32, 'C'_u32, 'O'_u32, 'P'_u32)
    SND_WAV_FOURCC_IARL = SND_WAV_FOURCC_MARKER('I'_u32, 'A'_u32, 'R'_u32, 'L'_u32)
    SND_WAV_FOURCC_IART = SND_WAV_FOURCC_MARKER('I'_u32, 'A'_u32, 'R'_u32, 'T'_u32)
    SND_WAV_FOURCC_INAM = SND_WAV_FOURCC_MARKER('I'_u32, 'N'_u32, 'A'_u32, 'M'_u32)
    SND_WAV_FOURCC_IENG = SND_WAV_FOURCC_MARKER('I'_u32, 'E'_u32, 'N'_u32, 'G'_u32)
    SND_WAV_FOURCC_IPRD = SND_WAV_FOURCC_MARKER('I'_u32, 'P'_u32, 'R'_u32, 'D'_u32)
    SND_WAV_FOURCC_ISRC = SND_WAV_FOURCC_MARKER('I'_u32, 'S'_u32, 'R'_u32, 'C'_u32)
    SND_WAV_FOURCC_ISBJ = SND_WAV_FOURCC_MARKER('I'_u32, 'S'_u32, 'B'_u32, 'J'_u32)
    SND_WAV_FOURCC_ICMT = SND_WAV_FOURCC_MARKER('I'_u32, 'C'_u32, 'M'_u32, 'T'_u32)
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
private const FormatBaseSize       = 14_u64     // WAVEFORMAT: tag, channels, rate, average bytes, block alignment.
private const FormatBitsSize       = 16_u64     // PCMWAVEFORMAT adds the bits per sample.
private const FormatExtraSize      = 18_u64     // WAVEFORMATEX adds the size of what follows.
private const FormatExtensibleSize = 40_u64     // WAVEFORMATEXTENSIBLE adds valid bits, the speaker mask, and the subformat.

// A `fmt ` chunk larger than this is not one; the extensible form is forty bytes and a Microsoft
// ADPCM coefficient table adds a few dozen more.
private const MaxFormatChunk = 4096_u64

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
    hasBitsField:  bool           // The chunk states the bits per sample rather than implying them.
    hasExtensible: bool           // The chunk carries the valid bits, the speaker mask, and a subformat.
    extra:         Array!{u8}     // Format-specific bytes after the subformat, or after `cbSize` in a classic chunk.
}

private func readU16(bytes: const [..] u8, offset: u64)->u32
{
    let low  = bytes[offset]
    let high = bytes[offset + 1]
    return Math.make16(high, low)
}

private func readU32(bytes: const [..] u8, offset: u64)->u32
{
    let low  = cast(u16, readU16(bytes, offset))
    let high = cast(u16, readU16(bytes, offset + 2))
    return Math.make32(high, low)
}

// Reads the FourCC in its native byte representation and the RIFF size as little-endian.
internal func decodeChunkHeader(bytes: const [..] u8)->ChunkHeader fail
{
    if bytes.count < 8
    {
        fail InvalidFormatError{"truncated RIFF chunk header"}
    }

    var result: #returntype
    Memory.copy(&result.chunkID, bytes.buffer, 4)
    result.chunkSize = readU32(bytes, 4)
    return result
}

// RIFF's fact sample-frame count is little-endian on every host.
internal func decodeFactFrameCount(bytes: const [..] u8)->u32 fail
{
    if bytes.count < 4
    {
        fail InvalidFormatError{"truncated WAVE fact sample count"}
    }

    return readU32(bytes, 0)
}

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
        if bitsPerSample != 32
        {
            fail UnsupportedFormatError{"unsupported float bitPerSample"}
        }

        return .Float32

    case WAVE_FORMAT_ADPCM:
        if bitsPerSample != 4
        {
            fail UnsupportedFormatError{"WAV Microsoft ADPCM is only supported at four bits a sample"}
        }

        return .AdpcmMs

    case WAVE_FORMAT_IMA_ADPCM:
        if bitsPerSample != 4
        {
            fail UnsupportedFormatError{"WAV IMA ADPCM is only supported at four bits a sample"}
        }

        return .AdpcmIma

    default:
        fail UnsupportedFormatError{"unsupported wav format"}
    }
}

// Returns the classic format tag an extensible subformat stands for.
private func subformatTag(subformat: const [..] u8)->u32 fail
{
    if Memory.bytesEqual(cast(const *SubformatUuid, subformat.buffer), SubformatPcm)
    {
        return WAVE_FORMAT_PCM
    }

    if Memory.bytesEqual(cast(const *SubformatUuid, subformat.buffer), SubformatIeeeFloat)
    {
        return WAVE_FORMAT_IEEE_FLOAT
    }

    if Memory.bytesEqual(cast(const *SubformatUuid, subformat.buffer), SubformatAdpcm)
    {
        return WAVE_FORMAT_ADPCM
    }

    if Memory.bytesEqual(cast(const *SubformatUuid, subformat.buffer), SubformatImaAdpcm)
    {
        return WAVE_FORMAT_IMA_ADPCM
    }

    fail UnsupportedFormatError{"unsupported wav format"}
}

// Reads what a `fmt ` chunk declares.
private func parseFormat(bytes: const [..] u8)->Format fail
{
    let size = bytes.count
    if size < FormatBaseSize
    {
        fail InvalidFormatError{"invalid wav"}
    }

    var result: #returntype
    let tag = readU16(bytes, 0)
    result.channels   = readU16(bytes, 2)
    result.sampleRate = readU32(bytes, 4)
    let averageBytes = readU32(bytes, 8)
    result.blockAlign = readU16(bytes, 12)
    if not result.channels
    {
        fail InvalidFormatError{"WAV channel count must be greater than zero"}
    }

    if not result.sampleRate
    {
        fail InvalidFormatError{"WAV sample rate must be greater than zero"}
    }

    // The oldest chunks state no sample width; the byte rate implies it.
    let frameByteRate = cast(u64, result.channels) * cast(u64, result.sampleRate)
    let inferredBits  = cast(u64, averageBytes) * 8 / frameByteRate
    if inferredBits > Swag.U32.Max
    {
        fail InvalidFormatError{"WAV inferred sample width exceeds the supported range"}
    }

    result.bitsPerSample = cast(u32, inferredBits)
    if size >= FormatBitsSize
    {
        result.bitsPerSample = readU16(bytes, 14)
        result.hasBitsField  = true
    }

    var extraStart = FormatExtraSize
    var extraEnd   = FormatExtraSize
    if size >= FormatExtraSize
    {
        let extraSize = readU16(bytes, 16)
        if extraSize > size - FormatExtraSize
        {
            fail InvalidFormatError{"invalid wav"}
        }

        extraEnd = FormatExtraSize + extraSize
    }

    var classicTag = tag
    if tag == WAVE_FORMAT_EXTENSIBLE
    {
        if size < FormatExtensibleSize or extraEnd < FormatExtensibleSize
        {
            fail InvalidFormatError{"invalid wav"}
        }

        result.validBits     = cast(u16, readU16(bytes, 18))
        result.speakerMask   = readU32(bytes, 20)
        result.hasExtensible = true
        classicTag           = try subformatTag(bytes[24 until 40])
        extraStart           = FormatExtensibleSize
    }

    result.encoding = try encodingOf(classicTag, result.bitsPerSample)
    switch result.encoding
    {
    case .Pcm8, .Pcm16, .Pcm24, .Pcm32, .Float32:
        if result.hasExtensible and result.validBits > result.bitsPerSample
        {
            fail InvalidFormatError{"WAV valid sample width exceeds its container width"}
        }

        let bytesPerSample = result.bitsPerSample / 8
        let expectedAlign  = result.channels * bytesPerSample
        let expectedRate   = cast(u64, result.sampleRate) * expectedAlign
        if expectedAlign > Swag.U16.Max or
           result.blockAlign != expectedAlign or
           expectedRate != averageBytes
        {
            fail InvalidFormatError{"WAV PCM/float frame alignment or byte rate is inconsistent"}
        }

    default:
        break
    }

    if extraEnd > extraStart
    {
        result.extra.add(bytes[extraStart until extraEnd])
    }

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

// Walks the RIFF chunks and validates the complete container.
//
// Multiple `data` chunks are rejected instead of silently truncating the sound at the first
// segment. The caller owns a newly opened stream positioned at the start of the file.
private func readLayout(stream: *File.FileStream)->Layout fail
{
    enum Stage
    {
        FindRiff
        FindFmt
        FindData
    }

    var result: #returntype
    var stage:  Stage = FindRiff
    let fileBytes = try stream.size()
    var riffEnd   = fileBytes
    var nextOffset = 0_u64
    var streamOffset = 0_u64

    for
    {
        // Offset arithmetic handles padding and skipped payloads without querying the file cursor.
        if nextOffset == riffEnd and result.hasData
        {
            return result
        }

        if nextOffset > riffEnd or riffEnd - nextOffset < #sizeof(ChunkHeader)
        {
            fail InvalidFormatError{"invalid wav"}
        }

        if nextOffset != streamOffset
        {
            try stream.seek(.Begin, nextOffset)
        }

        var rawHeader: [8] u8
        if not (try stream.readExact(rawHeader))
        {
            fail InvalidFormatError{"invalid wav"}
        }

        let header = try decodeChunkHeader(rawHeader)
        let payloadOffset = nextOffset + rawHeader.count
        streamOffset = payloadOffset
        if stage == .FindRiff and header.chunkID == .SND_WAV_FOURCC_RIFF
        {
            if header.chunkSize < 4 or cast(u64, header.chunkSize) > fileBytes - payloadOffset
            {
                fail InvalidFormatError{"invalid riff chunk"}
            }

            var fileType: ChunkID
            if not (try stream.readValue(&fileType))
            {
                fail InvalidFormatError{"invalid riff chunk"}
            }

            if fileType != .SND_WAV_FOURCC_WAVE
            {
                fail InvalidFormatError{"not a wav"}
            }

            riffEnd = payloadOffset + cast(u64, header.chunkSize)
            streamOffset += #sizeof(fileType)
            nextOffset = streamOffset
            stage = .FindFmt
            continue
        }

        // An odd-sized chunk has one padding byte within the RIFF boundary.
        let paddedSize = cast(u64, header.chunkSize) + (header.chunkSize & 1)
        if paddedSize > riffEnd - payloadOffset
        {
            fail InvalidFormatError{"invalid wav"}
        }

        nextOffset = payloadOffset + paddedSize
        switch header.chunkID
        {
        case .SND_WAV_FOURCC_fmt:
            if stage == .FindFmt
            {
                if header.chunkSize > MaxFormatChunk
                {
                    fail InvalidFormatError{"invalid wav"}
                }

                var bytes: Array!{u8}
                bytes.resize(header.chunkSize)
                if not (try stream.readExact(bytes.toSlice()))
                {
                    fail InvalidFormatError{"invalid wav"}
                }

                result.format = try parseFormat(bytes.toSlice())
                streamOffset += header.chunkSize
                stage = .FindData
            }

        case .SND_WAV_FOURCC_fact:
            if header.chunkSize >= 4
            {
                var rawFrameCount: [4] u8
                if not (try stream.readExact(rawFrameCount))
                {
                    fail InvalidFormatError{"invalid wav"}
                }

                result.factFrames = try decodeFactFrameCount(rawFrameCount)
                streamOffset += rawFrameCount.count
            }

        case .SND_WAV_FOURCC_data:
            if stage == .FindData
            {
                if result.hasData
                {
                    fail InvalidFormatError{"multiple WAVE data chunks are not supported"}
                }

                result.hasData    = true
                result.dataOffset = payloadOffset
                result.dataSize   = header.chunkSize
            }

        default:
            break
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
    if not format.blockAlign
    {
        fail InvalidFormatError{"WAV ADPCM block alignment is zero"}
    }

    if format.channels > 2
    {
        fail UnsupportedFormatError{"WAV ADPCM is only supported with one or two channels"}
    }

    var packets: Array!{SoundPacket}
    var totalFrames = 0_u64
    var dataOffset  = 0_u64
    while dataOffset < layout.dataSize
    {
        let blockBytes  = Math.min(cast(u64, format.blockAlign), layout.dataSize - dataOffset)
        let blockFrames = Adpcm.blockFrameCount(format.encoding, format.channels, blockBytes)
        if not blockFrames
        {
            fail InvalidFormatError{"WAV ADPCM block is shorter than its header"}
        }

        packets.add(SoundPacket{layout.dataOffset + dataOffset, cast(u32, blockBytes), cast(u32, blockFrames)})
        totalFrames += blockFrames
        dataOffset  += blockBytes
    }

    if not packets.count
    {
        fail InvalidFormatError{"WAV ADPCM data holds no complete block"}
    }

    if layout.factFrames > totalFrames
    {
        fail InvalidFormatError{"WAV fact chunk declares more sample frames than the blocks decode to"}
    }

    return try SoundFile.openPacketStream(path,
                                          format.encoding,
                                          format.sampleRate,
                                          format.channels,
                                          totalFrames,
                                          packets.toSlice(),
                                          format.extra.toSlice(),
                                          {speakerMask: format.speakerMask})
}

// Opens a RIFF/WAVE file.
//
// PCM and floating-point audio describe the sound in place, kept in memory when `preloadData` is
// set and streamed from `path` otherwise. ADPCM audio is always streamed: its blocks are indexed
// as packets and decoded on demand, so `preloadData` does not apply to it.
internal func openFile(path: string, preloadData: bool)->SoundFile fail
{
    var stream = try File.openRead(path)
    let layout = try readLayout(&stream)
    let format = &layout.format
    if format.encoding == .AdpcmMs or format.encoding == .AdpcmIma
    {
        stream.close()
        return try openAdpcm(path, &layout)
    }

    let bytesPerSample = format.bitsPerSample / 8
    if not bytesPerSample
    {
        fail InvalidFormatError{"invalid wav"}
    }

    let bytesPerFrame = cast(u64, format.blockAlign)
    if not bytesPerFrame or layout.dataSize % bytesPerFrame
    {
        fail InvalidFormatError{"WAV audio data is not aligned to sample frames"}
    }

    with var result: #returntype
    {
        .path               = path
        .encoding           = format.encoding
        .sampleRate         = format.sampleRate
        .channelCount       = format.channels
        .bitsPerSample      = format.bitsPerSample
        .validBitsPerSample = format.validBits
        .waveSpeakerMask    = format.speakerMask
        .availableFields    = .Format | .SampleRate | .ChannelCount
    }

    if format.hasBitsField
    {
        result.availableFields |= .BitsPerSample
    }

    if format.hasExtensible
    {
        result.availableFields |= .SpeakerMask | .ValidBitsPerSample
    }

    result.availableFields |= .Data | .FrameCount | .Duration
    result.dataOffset      = layout.dataOffset
    result.dataSize        = layout.dataSize
    result.frameCount      = layout.dataSize / bytesPerFrame
    result.durationSeconds = cast(f32, (result.frameCount / cast(f64, format.sampleRate)))
    if preloadData
    {
        result.data.reserve(layout.dataSize)
        let payload = Swag.makeSlice(result.data.storage(), layout.dataSize)
        if not (try stream.readExactAt(layout.dataOffset, payload))
        {
            fail InvalidFormatError{"WAV audio data is truncated"}
        }

        result.data.count = layout.dataSize
    }

    return result
}
