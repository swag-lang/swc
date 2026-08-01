#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func audioAssertFloat(actual, expected: f32, epsilon = 0.0001'f32)
{
    @assert(Math.isEqualEpsilon(actual, expected, epsilon))
}

func audioAssertBytes(actual: const [..] u8, expected: const [..] u8)->bool
{
    if @countof(actual) != @countof(expected) do
        return false

    for @countof(actual)
    {
        if actual[@index] != expected[@index] do
            return false
    }

    return true
}

func audioAssertBufferBytes(actual: #null [*] void, actualSize: u64, expected: const [..] u8)
{
    @assert(actualSize == @countof(expected))
    @assert(audioAssertBytes(@mkslice(cast(#null const [*] u8) actual, actualSize), expected))
}

func audioAssertSamples(actual: const [..] u8, expected: const [..] s16)
{
    @assert(@countof(actual) == @countof(expected) * #sizeof(s16))
    let samples = cast(const [*] s16) @dataof(actual)
    for @countof(expected) do
        @assert(samples[@index] == expected[@index])
}

// Returns the OWNED path: a 'string' view would dangle as soon as the intermediate
// 'Path.combine' results are dropped (caught by the owner-view escape analysis).
func audioGetTestDataPath(fileName: string, loc = #callerlocation)->String
{
    let dir  = Path.directoryName(loc.fileName)
    var path = Path.combine(dir, "datas", fileName)
    @assert(File.exists(path))
    return path
}

func audioDecodePcmToPcm16(sourceEncoding: SoundFileEncoding, source: [..] u8, destinationCapacity: u64)->{ destination: Array'u8, progress: CodecProgress } fail
{
    var codec: CodecPcmToPcm16
    codec.sourceEncoding      = sourceEncoding
    codec.destinationEncoding = .Pcm16

    var result: retval
    result.destination.resize(destinationCapacity)
    let itf               = @mkinterface(&codec, #typeof(CodecPcmToPcm16), ICodec)
    let destinationBuffer = notnull result.destination.buffer
    result.progress = itf.decode(destinationBuffer, result.destination.count, @dataof(source), @countof(source))
    return result
}
