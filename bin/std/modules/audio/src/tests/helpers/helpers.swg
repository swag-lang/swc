#global if #command == Swag.CompilerCommand.Test
#global internal

using Swag, Core

func audioAssertFloat(actual, expected: f32, epsilon = 0.0001'f32)
{
    Swag.require(Math.isEqualEpsilon(actual, expected, epsilon))
}

func audioAssertBufferBytes(actual: [*] void?, actualSize: u64, expected: const [..] u8)
{
    Swag.require(actualSize == expected.count)
    Swag.require(Slice.equals(Swag.makeSlice(cast(const [*] u8?, actual), actualSize), expected))
}

func audioAssertSamples(actual: const [..] u8, expected: const [..] s16)
{
    Swag.require(actual.count == expected.count * #sizeof(s16))
    let samples = cast(const [*] s16, actual.buffer)
    for index in expected.count do
        Swag.require(samples[index] == expected[index])
}

// Returns the OWNED path: a 'string' view would dangle as soon as the intermediate
// 'Path.combine' results are dropped (caught by the owner-view escape analysis).
func audioGetTestDataPath(fileName: string, loc = #callerlocation)->String
{
    var directory  = "../../../../../testdata/audio"
    var sharedName = fileName
    switch fileName
    {
    case "aac-lc-stereo-44100.aac": sharedName = "viewer.aac"
    case "ac3-5.1-48000.ac3": sharedName = "viewer.ac3"
    case "eac3-5.1-48000.eac3": sharedName = "viewer.surround.eac3"
    case "dts-5.1-48000.dts": sharedName = "viewer.dts"
    case "eac3-stereo-48000.eac3": sharedName = "viewer.eac3"
    case "flac-stereo-44100.flac": sharedName = "viewer.flac"
    case "opus-stereo-hybrid.opus": sharedName = "viewer.hybrid.opus"
    case "mp3-mono-16000.mp3": sharedName = "viewer.mp3"
    case "vorbis-stereo-44100.ogg": sharedName = "viewer.ogg"
    case "opus-mono-silk.opus": sharedName = "viewer.opus"
    case "flac-5.1-48000.flac": sharedName = "viewer.surround.flac"
    case "mp3-mono-48000.pcm", "opus-stereo-48000.pcm", "vorbis-stereo-44100.pcm":
        break
    default:
        directory = "datas"
    }

    let path = Path.combine(testSourceRoot(loc), directory, sharedName)
    Swag.require(File.exists(path))
    return path
}

func audioDecodePcmToPcm16(sourceEncoding: SoundFileEncoding,
                           source: [..] u8,
                           destinationCapacity: u64)->{ destination: Array'u8, progress: CodecProgress } fail
{
    var codec: CodecPcmToPcm16
    let allocator = unwrap Swag.getContext().allocator
    codec.configure(sourceEncoding, .Pcm16, #typeof(CodecPcmToPcm16), allocator)

    var result: #returntype
    result.destination.resize(destinationCapacity)
    let itf: ICodec       = &codec
    let destinationBuffer = result.destination.storage()
    result.progress = try itf.decode(destinationBuffer, result.destination.count, source.buffer, source.count)
    return result
}

// Returns the module's test root for test cases stored under cases/<type>.

func testSourceRoot(loc: Swag.SourceCodeLocation = #callerlocation)->String
{
    var directory = Path.directoryName(loc.fileName)
    while directory != null
    {
        if Path.fileName(directory) == "cases" do
            return unwrap Path.directoryName(directory)
        directory = Path.directoryName(directory)
    }

    Swag.require(false, "test source is outside cases")
    return ""
}
