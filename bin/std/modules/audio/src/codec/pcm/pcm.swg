//! Format: Pulse-code modulation conversion codec.
//! Supported: Unsigned PCM8, signed little-endian PCM16/24/32, IEEE Float32, and G.711 converted to interleaved PCM16.
//! Not supported: Big-endian PCM, Float64, packet codecs, channel remixing, and sample-rate conversion.
//! Role: This file owns SIMD/scalar sample conversion and streaming progress accounting.
//
using Core, Core.Errors, Core.Math

struct CodecPcmToPcm16
{
    using base: Codec
}

// G.711 alternates the bits of the A-law code and complements the mu-law code on the wire.
private const ALawSamples: [256] s16 = #run
{
    var result: [256] s16
    for index in result.count
    {
        let code = cast(u32, index) ^ 0x55
        let segment = (code >> 4) & 7
        let quantized = cast(s32, code & 15) << 4
        let magnitude = segment == 0 ? quantized + 8 : (quantized + 264) << (segment - 1)
        result[index] = cast(s16, code & 0x80 ? magnitude : -magnitude)
    }
    return result
}

private const MuLawSamples: [256] s16 = #run
{
    var result: [256] s16
    for index in result.count
    {
        let code = cast(u32, index) ^ 0xFF
        let segment = (code >> 4) & 7
        let magnitude = (((cast(s32, code & 15) << 3) + 132) << segment) - 132
        result[index] = cast(s16, code & 0x80 ? -magnitude : magnitude)
    }
    return result
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
        let bias = Simd.splat(128_s16)
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
        const KeepHighBytes = cast(Simd.U8x16, [1_u8, 2, 4, 5, 7, 8, 10, 11, 128, 128, 128, 128, 128, 128, 128, 128])

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
        let scale = Simd.splat(32768.0_f32)
        while remainingSamples >= 8
        {
            let minValue    = Simd.splat(-32768.0_f32)
            let maxValue    = Simd.splat(32767.0_f32)
            let lowSamples  = Math.min(Math.max(Simd.load(cast(const [*] f32, sourceBytes)) * scale, minValue), maxValue)
            let highSamples = Math.min(Math.max(Simd.load(cast(const [*] f32, sourceBytes) + 4) * scale, minValue), maxValue)
            let low         = Simd.truncateToS32(lowSamples)
            let high        = Simd.truncateToS32(highSamples)
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

        case .ALaw:
            outputSamples[0] = ALawSamples[sourceBytes[0]]

        case .MuLaw:
            outputSamples[0] = MuLawSamples[sourceBytes[0]]

        case .Pcm24:
            let low    = sourceBytes[0]
            let middle = sourceBytes[1]
            let high   = sourceBytes[2]
            var sample = Math.make32(0, high, middle, low)
            if sample & 0x00800000
            {
                sample |= 0xFF000000
            }

            outputSamples[0] = cast(s16, (cast #wrap (s32, sample) >> 8))

        case .Pcm32:
            let input = cast(const [*] s32, sourceBytes)
            outputSamples[0] = cast(s16, (input[0] >> 16))

        case .Float32:
            let input         = cast(const [*] f32, sourceBytes)
            let sample        = Math.clamp(input[0] * 32768.0, -32768.0, 32767.0)
            let clampedSample = cast #wrap (s32, sample)
            outputSamples[0] = cast(s16, clampedSample)

        default:
            #assert(false)
        }

        outputSamples += 1
        sourceBytes   += SampleBytes
    }

    return CodecProgress{sampleCount * #sizeof(s16), sampleCount * SampleBytes}
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
        case .Pcm8, .Pcm16, .Pcm24, .Pcm32, .Float32, .ALaw, .MuLaw: return true
        default: return false
        }
    }

    mtd impl initialize(_: const [*] void, _: u64)->u64 fail => 0

    mtd impl decode(destination: [*] void, destinationSize: u64, source: const [*] void, sourceSize: u64)->CodecProgress fail
    {
        if .sourceEncoding == .destinationEncoding
        {
            let length = Math.min(sourceSize, destinationSize)
            Memory.copy(destination, source, length)
            return CodecProgress{length, length}
        }

        switch .sourceEncoding
        {
        case .Pcm8:    return convertSamples!{1, Pcm8}(destination, destinationSize, source, sourceSize)
        case .ALaw:    return convertSamples!{1, ALaw}(destination, destinationSize, source, sourceSize)
        case .MuLaw:   return convertSamples!{1, MuLaw}(destination, destinationSize, source, sourceSize)
        case .Pcm24:   return convertSamples!{3, Pcm24}(destination, destinationSize, source, sourceSize)
        case .Pcm32:   return convertSamples!{4, Pcm32}(destination, destinationSize, source, sourceSize)
        case .Float32: return convertSamples!{4, Float32}(destination, destinationSize, source, sourceSize)
        default:       fail UnsupportedFormatError{"invalid encoding"}
        }
    }
}
