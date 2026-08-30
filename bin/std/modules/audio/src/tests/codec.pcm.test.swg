#global if #command == Swag.CompilerCommand.Test

using Swag, Core

private func audioPcmReferenceSample(encoding: SoundFileEncoding, source: const [*] u8)->s16
{
    switch encoding
    {
    case .Pcm8:
        return cast(s16) ((cast(s32) source[0] - 128) << 8)

    case .Pcm24:
        var sample = cast(u32) source[0] | (cast(u32) source[1] << 8) | (cast(u32) source[2] << 16)
        if sample & 0x00800000 do
            sample |= 0xFF000000
        return cast(s16) (cast #wrap (s32) sample >> 8)

    case .Pcm32:
        return cast(s16) ((cast(const [*] s32) source)[0] >> 16)

    case .Float32:
        let sample = (cast(const [*] f32) source)[0] * 32768.0
        return cast(s16) Math.clamp(cast #wrap (s32) sample, -32768, 32767)
    }

    Swag.assert(false)
    return 0
}

private func audioCheckPcmTails(encoding: SoundFileEncoding, sampleSize: u64) fail
{
    const MaxSamples = 40'u64
    const Sentinel   = 0xA5'u8

    var source: Array'u8
    source.resize((MaxSamples + 4) * sampleSize)
    for index in source.count do
        source[index] = cast(u8) ((index * 73 + 19) & 255)

    if encoding == .Float32
    {
        let values = cast([*] f32) source.buffer!
        for index in MaxSamples + 4
        {
            values[index] = cast(f32) (cast(s64) (index % 23) - 11) / 7.0
        }
    }

    var destination: Array'u8
    destination.resize((MaxSamples + 2) * #sizeof(s16))

    var codec: CodecPcmToPcm16
    codec.configure(encoding, .Pcm16, #typeof(CodecPcmToPcm16), Swag.getContext().allocator!)
    let decoder: ICodec = &codec

    // Every source tail crosses every vector boundary, while every destination byte count
    // checks truncation to whole samples, including odd capacities and zero space.
    for sourceSamples in MaxSamples + 1
    {
        for destinationBytes in (MaxSamples + 1) * #sizeof(s16)
        {
            for index in destination.count do
                destination[index] = Sentinel

            let progress      = try decoder.decode(destination.buffer!, destinationBytes, source.buffer!, sourceSamples * sampleSize)
            let expectedCount = Math.min(sourceSamples, destinationBytes / #sizeof(s16))
            Swag.assert(progress.bytesWritten == expectedCount * #sizeof(s16))
            Swag.assert(progress.bytesRead == expectedCount * sampleSize)

            for index in expectedCount
            {
                let expected = audioPcmReferenceSample(encoding, source.buffer! + index * sampleSize)
                Swag.assert((cast([*] s16) destination.buffer!)[index] == expected)
            }

            for index in expectedCount * #sizeof(s16) until destination.count do
                Swag.assert(destination[index] == Sentinel)
        }
    }
}

#test
{
    var codec: CodecPcmToPcm16
    let itf:   ICodec = &codec

    Swag.assert(itf.canEncode(.Pcm16))
    Swag.assert(!itf.canEncode(.Pcm8))
    Swag.assert(itf.canDecode(.Pcm8))
    Swag.assert(itf.canDecode(.Pcm16))
    Swag.assert(itf.canDecode(.Pcm24))
    Swag.assert(itf.canDecode(.Pcm32))
    Swag.assert(itf.canDecode(.Float32))
    Swag.assert(!itf.canDecode(.Unknown))
}

#test
{
    var src: [4] u8 = [0x34, 0x12, 0xFE, 0xFF]
    let decoded     = expect audioDecodePcmToPcm16(.Pcm16, src, 4)
    Swag.assert(decoded.progress.bytesWritten == 4)
    Swag.assert(decoded.progress.bytesRead == 4)
    Swag.assert(audioAssertBytes(decoded.destination.toSlice(), [0x34, 0x12, 0xFE, 0xFF]))
}

#test
{
    var src: [4] u8 = [0x34, 0x12, 0xFE, 0xFF]
    let decoded     = expect audioDecodePcmToPcm16(.Pcm16, src, 2)
    Swag.assert(decoded.progress.bytesWritten == 2)
    Swag.assert(decoded.progress.bytesRead == 2)
    Swag.assert(audioAssertBytes(decoded.destination.toSlice(), [0x34, 0x12]))
}

#test
{
    var src: [3] u8 = [0'u8, 128'u8, 255'u8]
    let decoded     = expect audioDecodePcmToPcm16(.Pcm8, src, 6)
    Swag.assert(decoded.progress.bytesWritten == 6)
    Swag.assert(decoded.progress.bytesRead == 3)
    audioAssertSamples(decoded.destination.toSlice(), [-32768's16, 0's16, 32512's16])
}

#test
{
    var src: [9] u8 = [0x00, 0x00, 0x80, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x7F]
    let decoded     = expect audioDecodePcmToPcm16(.Pcm24, src, 6)
    Swag.assert(decoded.progress.bytesWritten == 6)
    Swag.assert(decoded.progress.bytesRead == 9)
    audioAssertSamples(decoded.destination.toSlice(), [-32768's16, 0's16, 32767's16])
}

#test
{
    var src: [8] u8 = [0x00, 0x00, 0x00, 0x80, 0x00, 0x00, 0xFF, 0x7F]
    let decoded     = expect audioDecodePcmToPcm16(.Pcm32, src, 4)
    Swag.assert(decoded.progress.bytesWritten == 4)
    Swag.assert(decoded.progress.bytesRead == 8)
    audioAssertSamples(decoded.destination.toSlice(), [-32768's16, 32767's16])
}

#test
{
    var src: [12] f32 = [-1.0, 0.0, 0.5, 1.0, 2.0, -2.0, 0.25, -0.25, 0.9999, -0.9999, 0.0001, -0.0001]
    let decoded       = expect audioDecodePcmToPcm16(.Float32, cast([..] u8) src, src.count * #sizeof(s16))
    Swag.assert(decoded.progress.bytesWritten == src.count * #sizeof(s16))
    Swag.assert(decoded.progress.bytesRead == src.count * #sizeof(f32))
    audioAssertSamples(decoded.destination.toSlice(), [-32768's16, 0's16, 16384's16, 32767's16, 32767's16, -32768's16, 8192's16, -8192's16, 32764's16, -32764's16, 3's16, -3's16])
}

#test
{
    expect audioCheckPcmTails(.Pcm8, 1)
    expect audioCheckPcmTails(.Pcm24, 3)
    expect audioCheckPcmTails(.Pcm32, 4)
    expect audioCheckPcmTails(.Float32, 4)
}
