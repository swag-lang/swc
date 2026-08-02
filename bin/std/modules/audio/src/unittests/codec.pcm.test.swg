#global if #command == Swag.CompilerCommand.Test

using Swag, Core

#test
{
    var codec: CodecPcmToPcm16
    let itf: ICodec = &codec

    @assert(itf.canEncode(.Pcm16))
    @assert(!itf.canEncode(.Pcm8))
    @assert(itf.canDecode(.Pcm8))
    @assert(itf.canDecode(.Pcm16))
    @assert(itf.canDecode(.Pcm24))
    @assert(itf.canDecode(.Pcm32))
    @assert(itf.canDecode(.Float32))
    @assert(!itf.canDecode(.Unknown))
}

#test
{
    var src: [4] u8 = [0x34, 0x12, 0xFE, 0xFF]
    let decoded = expect audioDecodePcmToPcm16(.Pcm16, src, 4)
    @assert(decoded.progress.bytesWritten == 4)
    @assert(decoded.progress.bytesRead == 4)
    @assert(audioAssertBytes(decoded.destination.toSlice(), [0x34, 0x12, 0xFE, 0xFF]))
}

#test
{
    var src: [4] u8 = [0x34, 0x12, 0xFE, 0xFF]
    let decoded = expect audioDecodePcmToPcm16(.Pcm16, src, 2)
    @assert(decoded.progress.bytesWritten == 2)
    @assert(decoded.progress.bytesRead == 2)
    @assert(audioAssertBytes(decoded.destination.toSlice(), [0x34, 0x12]))
}

#test
{
    var src: [3] u8 = [0'u8, 128'u8, 255'u8]
    let decoded = expect audioDecodePcmToPcm16(.Pcm8, src, 6)
    @assert(decoded.progress.bytesWritten == 6)
    @assert(decoded.progress.bytesRead == 3)
    audioAssertSamples(decoded.destination.toSlice(), [-32768's16, 0's16, 32512's16])
}

#test
{
    var src: [9] u8 = [0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x7F]
    let decoded = expect audioDecodePcmToPcm16(.Pcm24, src, 6)
    @assert(decoded.progress.bytesWritten == 6)
    @assert(decoded.progress.bytesRead == 9)
    audioAssertSamples(decoded.destination.toSlice(), [-32768's16, 0's16, 32767's16])
}

#test
{
    var src: [8] u8 = [0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0xFF, 0x7F]
    let decoded = expect audioDecodePcmToPcm16(.Pcm32, src, 4)
    @assert(decoded.progress.bytesWritten == 4)
    @assert(decoded.progress.bytesRead == 8)
    audioAssertSamples(decoded.destination.toSlice(), [-32768's16, 32767's16])
}

#test
{
    var src: [12] f32 = [-1.0, 0.0, 0.5, 1.0, 2.0, -2.0, 0.25, -0.25, 0.9999, -0.9999, 0.0001, -0.0001]
    let decoded = expect audioDecodePcmToPcm16(.Float32, cast([..] u8) src, @countof(src) * #sizeof(s16))
    @assert(decoded.progress.bytesWritten == @countof(src) * #sizeof(s16))
    @assert(decoded.progress.bytesRead == @countof(src) * #sizeof(f32))
    audioAssertSamples(decoded.destination.toSlice(), [-32768's16, 0's16, 16384's16, 32767's16, 32767's16, -32768's16, 8192's16, -8192's16, 32764's16, -32764's16, 3's16, -3's16])
}
