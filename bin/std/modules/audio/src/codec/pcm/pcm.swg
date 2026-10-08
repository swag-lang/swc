//! Format: Pulse-code modulation conversion codec.
//! Supported: Little-endian unsigned PCM8, signed PCM16/24/32, and IEEE Float32 input converted incrementally to interleaved PCM16.
//! Not supported: Big-endian PCM, Float64, compressed audio, channel remixing, and sample-rate conversion.
//! Role: This file owns SIMD/scalar sample conversion and streaming progress accounting.
//
using Core, Core.Errors, Core.Math

struct CodecPcmToPcm16
{
    using base: Codec
}

private func(SampleBytes: s32, SourceEncoding: SoundFileEncoding) convertSamples(destination: [*] void,
                                                                                 destinationSize: u64,
                                                                                 source: const [*] void,
                                                                                 sourceSize: u64)->CodecProgress
{
    var outputSamples    = cast([*] s16, destination)
    var sourceBytes      = cast(const [*] u8, source)
    let sampleCount      = Math.min(sourceSize / SampleBytes, destinationSize / #sizeof(s16))
    var remainingSamples = sampleCount

    #static switch SourceEncoding
    {
    case .Pcm8:
        let bias = Simd.splat(128's16)
        while remainingSamples >= 16
        {
            let bytes = Simd.load(sourceBytes)
            Simd.store(outputSamples, (cast #bit(Simd.S16x8, Simd.widenLow(bytes)) - bias) << 8)
            Simd.store(outputSamples + 8, (cast #bit(Simd.S16x8, Simd.widenHigh(bytes)) - bias) << 8)
            outputSamples    += 16
            sourceBytes      += 16
            remainingSamples -= 16
        }

    case .Pcm24:
        const KeepHighBytes = cast(Simd.U8x16, [1'u8, 2, 4, 5, 7, 8, 10, 11, 128, 128, 128, 128, 128, 128, 128, 128])

        // A 16-byte load needs six available samples; the shuffle converts four.
        while remainingSamples >= 6
        {
            Simd.storeLow8(cast([*] u8, outputSamples), Simd.shuffle(Simd.load(sourceBytes), KeepHighBytes))
            outputSamples    += 4
            sourceBytes      += 12
            remainingSamples -= 4
        }

    case .Pcm32:
        while remainingSamples >= 8
        {
            let low  = Simd.load(cast(const [*] s32, sourceBytes)) >> 16
            let high = Simd.load(cast(const [*] s32, sourceBytes) + 4) >> 16
            Simd.store(outputSamples, Simd.packSigned(low, high))
            outputSamples    += 8
            sourceBytes      += 32
            remainingSamples -= 8
        }

    case .Float32:
        let scale = Simd.splat(32768.0'f32)
        while remainingSamples >= 8
        {
            let low  = Simd.truncateToS32(Simd.load(cast(const [*] f32, sourceBytes)) * scale)
            let high = Simd.truncateToS32(Simd.load(cast(const [*] f32, sourceBytes) + 4) * scale)
            Simd.store(outputSamples, Simd.packSigned(low, high))
            outputSamples    += 8
            sourceBytes      += 32
            remainingSamples -= 8
        }
    }

    // Finish the samples that do not fit a complete SIMD load.
    for remainingSamples
    {
        #static switch SourceEncoding
        {
        case .Pcm8:
            outputSamples[0] = cast(s16, ((cast(s32, sourceBytes[0]) - 128) << 8))

        case .Pcm24:
            let low    = sourceBytes[0]
            let middle = sourceBytes[1]
            let high   = sourceBytes[2]
            var sample = Math.make32(0, high, middle, low)
            if sample & 0x00800000 do
                sample |= 0xFF000000
            outputSamples[0] = cast(s16, (cast #wrap (s32, sample) >> 8))

        case .Pcm32:
            let input = cast(const [*] s32, sourceBytes)
            outputSamples[0] = cast(s16, (input[0] >> 16))

        case .Float32:
            let input         = cast(const [*] f32, sourceBytes)
            let sample        = input[0] * 32768.0
            let clampedSample = Math.clamp(cast #wrap (s32, sample), -32768, 32767)
            outputSamples[0] = cast(s16, clampedSample)

        default:
            #assert(false)
        }

        outputSamples += 1
        sourceBytes   += SampleBytes
    }

    return {sampleCount * #sizeof(s16), sampleCount * SampleBytes}
}

impl ICodec for CodecPcmToPcm16
{
    mtd impl canEncode(encoding: SoundFileEncoding)->bool
    {
        return encoding == .Pcm16
    }

    mtd impl canDecode(encoding: SoundFileEncoding)->bool
    {
        switch encoding
        {
        case .Pcm8, .Pcm16, .Pcm24, .Pcm32, .Float32: return true
        }

        return false
    }

    mtd impl initialize(?: const [*] void, ?: u64)->u64 fail => 0

    mtd impl decode(destination: [*] void, destinationSize: u64, source: const [*] void, sourceSize: u64)->CodecProgress fail
    {
        if .sourceEncoding == .destinationEncoding
        {
            let length = Math.min(sourceSize, destinationSize)
            Memory.copy(destination, source, length)
            return {length, length}
        }

        switch .sourceEncoding
        {
        case .Pcm8:    return convertSamples'(1, Pcm8)(destination, destinationSize, source, sourceSize)
        case .Pcm24:   return convertSamples'(3, Pcm24)(destination, destinationSize, source, sourceSize)
        case .Pcm32:   return convertSamples'(4, Pcm32)(destination, destinationSize, source, sourceSize)
        case .Float32: return convertSamples'(4, Float32)(destination, destinationSize, source, sourceSize)
        }

        fail UnsupportedFormatError{"invalid encoding"}
    }
}
