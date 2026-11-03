#global if #command == Swag.CompilerCommand.Test
#global internal

using Swag, Core

func audioAssertFloat(actual, expected: f32, epsilon = 0.0001'f32)
{
    Swag.assert(Math.isEqualEpsilon(actual, expected, epsilon))
}

func audioAssertBufferBytes(actual: [*] void?, actualSize: u64, expected: const [..] u8)
{
    Swag.assert(actualSize == expected.count)
    Swag.assert(Slice.equals(Swag.makeSlice(cast(const [*] u8?, actual), actualSize), expected))
}

func audioAssertSamples(actual: const [..] u8, expected: const [..] s16)
{
    Swag.assert(actual.count == expected.count * #sizeof(s16))
    let samples = cast(const [*] s16, actual.buffer)
    for index in expected.count do
        Swag.assert(samples[index] == expected[index])
}

// Returns the OWNED path: a 'string' view would dangle as soon as the intermediate
// 'Path.combine' results are dropped (caught by the owner-view escape analysis).
func audioGetTestDataPath(fileName: string, loc = #callerlocation)->String
{
    let path = Path.combine(testSourceRoot(loc), "datas", fileName)
    Swag.assert(File.exists(path))
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

    Swag.assert(false, "test source is outside cases")
    return ""
}
