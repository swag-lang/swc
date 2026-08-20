using Core, Core.Errors, Core.Math

struct CodecPcmToPcm16
{
    using base: Codec
}

impl ICodec for CodecPcmToPcm16
{
    mtd impl canEncode(encoding: SoundFileEncoding)->bool
    {
        switch encoding
        {
        case .Pcm16: return true
        }

        return false
    }

    mtd impl canDecode(encoding: SoundFileEncoding)->bool
    {
        switch encoding
        {
        case .Pcm8, .Pcm16, .Pcm24, .Pcm32, .Float32: return true
        }

        return false
    }

    mtd impl initialize(source: const [*] void, sourceSize: u64)->u64 fail
    {
        return 0
    }

    mtd impl decode(destination: [*] void, destinationSize: u64, source: const [*] void, sourceSize: u64)->CodecProgress fail
    {
        if .sourceEncoding == .destinationEncoding
        {
            let length = Math.min(sourceSize, destinationSize)
            Memory.copy(destination, source, length)
            return {length, length}
        }

        func(TS: s32, EN: SoundFileEncoding) doIt(destination: [*] void, destinationSize: u64, source: const [*] void, sourceSize: u64)->CodecProgress
        {
            var dst         = cast([*] s16) destination
            var src         = cast(const [*] u8) source
            let sampleCount = Math.min(sourceSize / TS, destinationSize / #sizeof(s16))
            var remaining   = sampleCount

            #static switch EN
            {
            case .Pcm8:
                let bias = Simd.splat(128's16)
                while remaining >= 16
                {
                    let bytes = Simd.load(src)
                    Simd.store(dst, (cast #bit(Simd.S16x8) Simd.widenLow(bytes) - bias) << 8)
                    Simd.store(dst + 8, (cast #bit(Simd.S16x8) Simd.widenHigh(bytes) - bias) << 8)
                    dst       += 16
                    src       += 16
                    remaining -= 16
                }

            case .Pcm24:
                const KeepHighBytes = cast(Simd.U8x16) [1'u8, 2, 4, 5, 7, 8, 10, 11, 128, 128, 128, 128, 128, 128, 128, 128]
                while remaining >= 6
                {
                    Simd.storeLow8(cast([*] u8) dst, Simd.shuffle(Simd.load(src), KeepHighBytes))
                    dst       += 4
                    src       += 12
                    remaining -= 4
                }

            case .Pcm32:
                while remaining >= 8
                {
                    let low  = Simd.load(cast(const [*] s32) src) >> 16
                    let high = Simd.load(cast(const [*] s32) src + 4) >> 16
                    Simd.store(dst, Simd.packSigned(low, high))
                    dst       += 8
                    src       += 32
                    remaining -= 8
                }

            case .Float32:
                let scale = Simd.splat(32768.0'f32)
                while remaining >= 8
                {
                    let low  = Simd.truncateToS32(Simd.load(cast(const [*] f32) src) * scale)
                    let high = Simd.truncateToS32(Simd.load(cast(const [*] f32) src + 4) * scale)
                    Simd.store(dst, Simd.packSigned(low, high))
                    dst       += 8
                    src       += 32
                    remaining -= 8
                }
            }

            for remaining
            {
                #static switch EN
                {
                case .Pcm8:
                    dst[0] = cast(s16) ((cast(s32) src[0] - 128) << 8)

                case .Pcm24:
                    var sample = cast(u32) src[0] | (cast(u32) src[1] << 8) | (cast(u32) src[2] << 16)
                    if sample & 0x00800000 do
                        sample |= 0xFF000000
                    dst[0] = cast(s16) (cast #wrap (s32) sample >> 8)

                case .Pcm32:
                    let input = cast(const [*] s32) src
                    dst[0] = cast(s16) (input[0] >> 16)

                case .Float32:
                    let input  = cast(const [*] f32) src
                    let sample = input[0] * 32768.0
                    let intS   = Math.clamp(cast #wrap (s32) sample, -32768, 32767)
                    dst[0] = cast(s16) intS

                default:
                    #assert(false)
                }

                dst += 1
                src += TS
            }

            return {sampleCount * #sizeof(s16), sampleCount * TS}
        }

        switch .sourceEncoding
        {
        case .Pcm8:    return doIt'(1, Pcm8)(destination, destinationSize, source, sourceSize)
        case .Pcm24:   return doIt'(3, Pcm24)(destination, destinationSize, source, sourceSize)
        case .Pcm32:   return doIt'(4, Pcm32)(destination, destinationSize, source, sourceSize)
        case .Float32: return doIt'(4, Float32)(destination, destinationSize, source, sourceSize)
        }

        fail UnsupportedFormatError{"invalid encoding"}
    }
}
