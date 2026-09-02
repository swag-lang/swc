#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func audioAssertFloat(actual, expected: f32, epsilon = 0.0001'f32)
{
    Swag.assert(Math.isEqualEpsilon(actual, expected, epsilon))
}

func audioAssertBytes(actual: const [..] u8, expected: const [..] u8)->bool
{
    if actual.count != expected.count do
        return false

    for index in actual.count
    {
        if actual[index] != expected[index] do
            return false
    }

    return true
}

func audioAssertBufferBytes(actual: #null [*] void, actualSize: u64, expected: const [..] u8)
{
    Swag.assert(actualSize == expected.count)
    Swag.assert(audioAssertBytes(Swag.makeSlice(cast(#null const [*] u8) actual, actualSize), expected))
}

func audioAssertSamples(actual: const [..] u8, expected: const [..] s16)
{
    Swag.assert(actual.count == expected.count * #sizeof(s16))
    let samples = cast(const [*] s16) actual.buffer
    for index in expected.count do
        Swag.assert(samples[index] == expected[index])
}

// Returns the OWNED path: a 'string' view would dangle as soon as the intermediate
// 'Path.combine' results are dropped (caught by the owner-view escape analysis).
func audioGetTestDataPath(fileName: string, loc = #callerlocation)->String
{
    let dir  = Path.directoryName(loc.fileName)
    var path = Path.combine(dir, "datas", fileName)
    Swag.assert(File.exists(path))
    return path
}

func audioDecodePcmToPcm16(sourceEncoding: SoundFileEncoding, source: [..] u8, destinationCapacity: u64)->{ destination: Array'u8, progress: CodecProgress } fail
{
    var codec: CodecPcmToPcm16
    let allocator = Swag.getContext().allocator!
    codec.configure(sourceEncoding, .Pcm16, #typeof(CodecPcmToPcm16), allocator)

    var result: retval
    result.destination.resize(destinationCapacity)
    let itf: ICodec       = &codec
    let destinationBuffer = result.destination.buffer!
    result.progress = itf.decode(destinationBuffer, result.destination.count, source.buffer, source.count)
    return result
}
