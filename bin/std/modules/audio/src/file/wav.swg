#global namespace Wav

using Core, Core.Errors, Win32

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
const WAVE_FORMAT_EXTENSIBLE = 0xFFFE     /* Microsoft */

const GUID_PCM        = GUID{0x00000001, 0x0000, 0x0010, [0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71]}
const GUID_ADPCM      = GUID{0x00000002, 0x0000, 0x0010, [0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71]}
const GUID_IEEE_FLOAT = GUID{0x00000003, 0x0000, 0x0010, [0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71]}

#[Swag.Pack(1)]
struct WAVEFORMAT
{
    wFormatTag:      u16     // Format type
    nChannels:       u16     // Number of nChannels (i.e. mono, stereo, etc.)
    nSamplesPerSec:  u32     // Sample rate
    nAvgBytesPerSec: u32     // For buffer estimation
    nBlockAlign:     u16     // Block size of data
}

#[Swag.Pack(1)]
struct PCMWAVEFORMAT
{
    using wf:       WAVEFORMAT
    wBitsPerSample: u16
}

#[Swag.Pack(1)]
struct WAVEFORMATEX
{
    using pcmwf: PCMWAVEFORMAT
    cbSize:      u16     // The count in bytes of the size of extra information (after cbSize)
}

#[Swag.Pack(1)]
struct WAVEFORMATEXTENSIBLE
{
    using fmtex: WAVEFORMATEX

    samples: union
    {
        wValidBitsPerSample: u16     // Valid bits in each sample container
        wSamplesPerBlock:    u16     // Samples per block of audio data valid
        wReserved:           u16     // If wBitsPerSample=0 (but rarely used). Zero if neither case above applies.
    }

    dwChannelMask: u32      // Positions of the audio nChannels
    subFormat:     GUID     // Format identifier GUID
}

func setEncodingFormat(file: *SoundFile, formatTag: u16) fail
{
    switch formatTag
    {
    case WAVE_FORMAT_PCM:
        if file.bitsPerSample == 8 do
            file.encoding = .Pcm8
        elif file.bitsPerSample == 16 do
            file.encoding = .Pcm16
        elif file.bitsPerSample == 24 do
            file.encoding = .Pcm24
        elif file.bitsPerSample == 32 do
            file.encoding = .Pcm32
        else do
            fail UnsupportedFormatError{"unsupported pcm bitPerSample"}

    case WAVE_FORMAT_IEEE_FLOAT:
        if file.bitsPerSample == 32 do
            file.encoding = .Float32
        else do
            fail UnsupportedFormatError{"unsupported float bitPerSample"}

    case WAVE_FORMAT_EXTENSIBLE:
        break

    default:
        fail UnsupportedFormatError{"unsupported wav format"}
    }
}

func readChunkFmt(file: *SoundFile, stream: *File.FileStream, chunkSize: u32) fail
{
    if chunkSize < #sizeof(WAVEFORMAT) do
        fail InvalidFormatError{"invalid wav"}

    let chunkStart = stream.position()

    var wf: WAVEFORMAT
    if !stream.readValue(&wf) do
        fail InvalidFormatError{"invalid wav"}

    file.frequency     = wf.nSamplesPerSec
    file.channelCount  = wf.nChannels
    file.bitsPerSample = (wf.nAvgBytesPerSec * 8 / wf.nChannels) / wf.nSamplesPerSec
    file.setEncodingFormat(wf.wFormatTag)

    file.validity = .Format
    file.validity |= .Frequency
    file.validity |= .ChannelCount

    ////////
    if chunkSize >= #sizeof(PCMWAVEFORMAT)
    {
        var pcmwf: PCMWAVEFORMAT
        pcmwf.wf      = wf
        file.validity |= .BitsPerSample

        if !stream.readValue(&pcmwf.wBitsPerSample) do
            fail InvalidFormatError{"invalid wav"}
        file.bitsPerSample = pcmwf.wBitsPerSample
        file.setEncodingFormat(wf.wFormatTag)

        ////////
        if chunkSize >= #sizeof(WAVEFORMATEX)
        {
            var wfx: WAVEFORMATEX
            wfx.pcmwf = pcmwf

            if !stream.readValue(&wfx.cbSize) do
                fail InvalidFormatError{"invalid wav"}

            ////////
            if chunkSize >= #sizeof(WAVEFORMATEXTENSIBLE)
            {
                var wfex: WAVEFORMATEXTENSIBLE
                wfex.fmtex    = wfx
                file.validity |= .ChannelMask
                file.validity |= .ValidBitsPerSample

                if !stream.readValue(&wfex.samples) do
                    fail InvalidFormatError{"invalid wav"}
                if !stream.readValue(&wfex.dwChannelMask) do
                    fail InvalidFormatError{"invalid wav"}
                if !stream.readValue(&wfex.subFormat) do
                    fail InvalidFormatError{"invalid wav"}

                file.validBitsPerSample = wfex.samples.wValidBitsPerSample
                file.channelMask        = wfex.dwChannelMask

                if wf.wFormatTag == WAVE_FORMAT_EXTENSIBLE
                {
                    switch
                    {
                    case Memory.bytesEqual(&wfex.subFormat, GUID_PCM):        file.setEncodingFormat(WAVE_FORMAT_PCM)
                    case Memory.bytesEqual(&wfex.subFormat, GUID_IEEE_FLOAT): file.setEncodingFormat(WAVE_FORMAT_IEEE_FLOAT)
                    default:                                              fail UnsupportedFormatError{"unsupported wav format"}
                    }
                }
            }
        }
    }

    if wf.wFormatTag == WAVE_FORMAT_EXTENSIBLE and chunkSize < #sizeof(WAVEFORMATEXTENSIBLE) do
        fail InvalidFormatError{"invalid wav"}

    let readSize = stream.position() - chunkStart
    if readSize < chunkSize do
        stream.skip(chunkSize - readSize)
}

func readChunkData(file: *SoundFile, stream: *File.FileStream, chunkSize: u32) fail
{
    file.validity |= .Data
    file.dataSeek = stream.position()
    file.dataSize = chunkSize

    file.validity    |= .SampleCount
    file.sampleCount = file.dataSize / (file.channelCount * (file.bitsPerSample / 8))
    if file.validity & .Frequency
    {
        file.duration = cast(f32) (file.sampleCount / cast(f64) file.frequency)
        file.validity |= .Duration
    }
}

// Decodes WAV headers and optional payload bytes from an open stream.
//
// The stream must be positioned at the beginning of a RIFF or RIFX WAVE file.
// Parsed properties are written to `file`; see [[Audio.SoundFile.load]] for the
// path-based entry point.
public func loadFile(file: *SoundFile, stream: *File.FileStream, loadDatas = true, loadMetaDatas = false) fail
{
    enum Stage
    {
        FindRiff
        FindFmt
        FindData
        BreakOnSuccess
    }

    var stage:  Stage = FindRiff
    var header: ChunkHeader

    for
    {
        let seek = stream.position()
        if seek >= stream.size()
        {
            if file.validity.has(.Data) do
                return
            fail InvalidFormatError{"invalid wav"}
        }

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
                file.readChunkFmt(stream, header.chunkSize)
                stage = .FindData
            }

        case .SND_WAV_FOURCC_data:
            if stage == .FindData
            {
                readChunkData(file, stream, header.chunkSize)
                if loadDatas
                {
                    file.datas.resize(header.chunkSize)
                    if stream.read(file.datas.buffer, header.chunkSize) != header.chunkSize do
                        fail InvalidFormatError{"cannot read datas"}
                }
                elif loadMetaDatas
                {
                    stream.skip(header.chunkSize)
                }

                if !loadMetaDatas do
                    return
            }

        case .SND_WAV_FOURCC_fact:
            stream.skip(header.chunkSize)

        case .SND_WAV_FOURCC_cue:
            stream.skip(header.chunkSize)

        case .SND_WAV_FOURCC_LIST:
            stream.skip(header.chunkSize)

        case .SND_WAV_FOURCC_labl:
            stream.skip(header.chunkSize)

        case .SND_WAV_FOURCC_note:
            stream.skip(header.chunkSize)

        case .SND_WAV_FOURCC_ltxt:
            stream.skip(header.chunkSize)

        case .SND_WAV_FOURCC_bext:
            stream.skip(header.chunkSize)

        default:
            if header.chunkSize do
                stream.skip(header.chunkSize)
            else do
                fail InvalidFormatError{"invalid wav"}
        }
    }
}
