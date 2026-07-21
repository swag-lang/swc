#global #if #command == Swag.CompilerCommand.Test
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
    let dir  = Path.getDirectoryName(loc.fileName)
    var path = Path.combine(dir, "datas", fileName)
    @assert(File.exists(path))
    return path
}

func audioDecodePcmToPcm16(srcEncoding: SoundFileEncoding, src: [..] u8, destCapacity: u64)->{ dest: Array'u8, used: { write, read: u64 } } throw
{
    var codec: CodecPcmToPcm16
    codec.srcEncoding = srcEncoding
    codec.dstEncoding = .Pcm16

    var result: retval
    result.dest.resize(destCapacity)
    let itf = @mkinterface(&codec, #typeof(CodecPcmToPcm16), ICodec)
    let destBuffer = assume result.dest.buffer
    result.used = itf.decode(destBuffer, result.dest.count, @dataof(src), @countof(src))
    return result
}
