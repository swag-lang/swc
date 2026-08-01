using Core, Core.Errors

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

    mtd impl initialize(source: [*] void, sourceSize: u64)->u64 fail
    {
        return 0
    }

    mtd impl decode(destination: [*] void, destinationSize: u64, source: [*] void, sourceSize: u64)->CodecProgress fail
    {
        if .sourceEncoding == .destinationEncoding
        {
            let length = Math.min(sourceSize, destinationSize)
            Memory.copy(destination, source, length)
            return {length, length}
        }

        func(TS: s32, EN: SoundFileEncoding) doIt(destination: [*] void, destinationSize: u64, source: [*] void, sourceSize: u64)->CodecProgress
        {
            var dst = cast([*] s16) destination
            var src = cast([*] u8) source

            var bytesWritten, bytesRead = 0
            for [i] in sourceSize / TS
            {
                if bytesWritten + #sizeof(s16) > destinationSize do
                    break

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
                    let input = cast([*] s32) src
                    dst[0] = cast(s16) (input[0] >> 16)

                case .Float32:
                    let input  = cast([*] f32) src
                    let sample = input[0] * 32768.0
                    let intS   = Math.clamp(cast #wrap (s32) sample, -32768, 32767)
                    dst[0] = cast(s16) intS

                default:
                    #assert(false)
                }

                dst          += 1
                src          += TS
                bytesWritten += #sizeof(s16)
                bytesRead    += TS
            }

            return {bytesWritten, bytesRead}
        }

        switch .sourceEncoding
        {
        case .Pcm8:    return doIt'(1, Pcm8)(destination, destinationSize, source, sourceSize)
        case .Pcm24:   return doIt'(3, Pcm24)(destination, destinationSize, source, sourceSize)
        case .Pcm32:   return doIt'(4, Pcm32)(destination, destinationSize, source, sourceSize)
        case .Float32: return doIt'(4, Float32)(destination, destinationSize, source, sourceSize)
        }

        fail UnsupportedFormatError{"invalid encoding"}
        return {0, 0}
    }
}
