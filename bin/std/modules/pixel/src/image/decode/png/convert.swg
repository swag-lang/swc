/*
    :LICENCE
    This code is based on the libspng library by Randy (https://libspng.org/)
    The original code has been modified for Swag
    See LICENCE.md for the corresponding licence.
*/

#global namespace Png

using Core, Core.Errors

const Swap16Bytes = cast(Math.Simd.U8x16) [1'u8, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 15, 14]

// Building the packed table breaks even at 512 pixels on the supported x64 baseline.
const PackedPaletteThreshold = 512'u64

// Keep tiny icon decode on the lower-overhead path; large images amortize packed expansion.
const PackedGrayscaleThreshold = 4096'u64

// A transparency lookup table pays for itself from 512 grayscale pixels.
const PackedGrayscaleTransparencyThreshold = 512'u64

// Direct grayscale-plus-alpha packing wins from 256 pixels.
const PackedGrayscaleAlphaThreshold = 256'u64

func reduce16Samples(source: const [*] u8, destination: [*] u8, sampleCount: u64)
{
    var src   = source
    var dst   = destination
    var count = sampleCount
    while count >= 8
    {
        let words    = cast #bit(Math.Simd.U16x8) Math.Simd.shuffle(Math.Simd.load(src), Swap16Bytes)
        let low      = ((Math.Simd.widenLow(words) + 129'u32) * 255'u32) >> 16
        let high     = ((Math.Simd.widenHigh(words) + 129'u32) * 255'u32) >> 16
        let packed16 = Math.Simd.packUnsigned(cast #bit(Math.Simd.S32x4) low, cast #bit(Math.Simd.S32x4) high)
        let packed8  = Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) packed16, cast #bit(Math.Simd.S16x8) packed16)
        Math.Simd.storeLow8(dst, packed8)
        src   += 16
        dst   += 8
        count -= 8
    }

    while count
    {
        let value = (cast(u16) src[0] << 8) | src[1]
        dst[0] = cast(u8) ((cast(u32) value + 128) / 257)
        src    += 2
        dst    += 1
        count  -= 1
    }
}

impl Decoder
{
    func read16(src: const [*] u8)->u16
    {
        return (cast(u16) src[0] << 8) | src[1]
    }

    func reduce16(value: u16)->u8
    {
        return cast(u8) ((cast(u32) value + 128) / 257)
    }

    mtd convertPaletteRgb(result: *Image)
    {
        let pixelCount = cast(u64) result.width * result.height
        if pixelCount < PackedPaletteThreshold
        {
            var src = .safeDstPixels()
            var dst = cast([*] u8) result.pixels.buffer!
            for pixelCount
            {
                let color = .palette[src[0]]
                dst[0] = cast() ((color >> 16) & 0xFF)
                dst[1] = cast() ((color >> 8) & 0xFF)
                dst[2] = cast() (color & 0xFF)
                src    += 1
                dst    += 3
            }

            return
        }

        var packedPalette: [256] u32
        for i in 256
        {
            let color = .palette[i]
            packedPalette[i] = ((color >> 16) & 0xFF) | (color & 0xFF00) | ((color & 0xFF) << 16)
        }

        var src       = .safeDstPixels()
        var dst       = cast([*] u8) result.pixels.buffer!
        var remaining = pixelCount

        // The fourth byte lands on the next pixel and is overwritten there. Stop before
        // the final pixel so every wide store remains inside the exact-size image buffer.
        while remaining > 1
        {
            (cast([*] u32) dst)[0] = packedPalette[src[0]]
            src                    += 1
            dst                    += 3
            remaining              -= 1
        }

        let color = packedPalette[src[0]]
        dst[0] = cast(u8) (color & 0xFF)
        dst[1] = cast(u8) ((color >> 8) & 0xFF)
        dst[2] = cast(u8) ((color >> 16) & 0xFF)
    }

    mtd convertPaletteRgba(result: *Image)
    {
        let pixelCount = cast(u64) result.width * result.height
        if pixelCount < PackedPaletteThreshold
        {
            var src = .safeDstPixels()
            var dst = cast([*] u8) result.pixels.buffer!
            for pixelCount
            {
                let index = src[0]
                let color = .palette[index]
                dst[0] = cast() ((color >> 16) & 0xFF)
                dst[1] = cast() ((color >> 8) & 0xFF)
                dst[2] = cast() (color & 0xFF)
                dst[3] = index < @countof(.safeTRNSData()) ? .safeTRNSData()[index] : 255
                src    += 1
                dst    += 4
            }

            return
        }

        let alpha = .safeTRNSData()
        var packedPalette: [256] u32
        for i in 256
        {
            let color      = .palette[i]
            let alphaValue = i < @countof(alpha) ? cast(u32) alpha[i] : 255'u32
            packedPalette[i] = ((color >> 16) & 0xFF) | (color & 0xFF00) | ((color & 0xFF) << 16) | (alphaValue << 24)
        }

        var src = .safeDstPixels()
        var dst = cast([*] u32) result.pixels.buffer!
        for pixelCount
        {
            dst[0] = packedPalette[src[0]]
            src    += 1
            dst    += 1
        }
    }

    mtd convertGrayscaleRgb(result: *Image)
    {
        let pixelCount = cast(u64) result.width * result.height
        if pixelCount < PackedGrayscaleThreshold
        {
            var src = .safeDstPixels()
            var dst = cast([*] u8) result.pixels.buffer!
            for pixelCount
            {
                dst[0] = src[0]
                dst[1] = src[0]
                dst[2] = src[0]
                src    += 1
                dst    += 3
            }

            return
        }

        var src       = .safeDstPixels()
        var dst       = cast([*] u8) result.pixels.buffer!
        var remaining = pixelCount

        // The fourth byte is overwritten by the next pixel. Leave the final pixel scalar
        // so no wide store reaches beyond the exact-size RGB buffer.
        while remaining > 1
        {
            (cast([*] u32) dst)[0] = cast(u32) src[0] * 0x010101
            src                    += 1
            dst                    += 3
            remaining              -= 1
        }

        dst[0] = src[0]
        dst[1] = src[0]
        dst[2] = src[0]
    }

    mtd convertGrayscaleTransparencyRgba(result: *Image, key: u8)
    {
        let pixelCount = cast(u64) result.width * result.height
        if pixelCount < PackedGrayscaleTransparencyThreshold
        {
            var src = .safeDstPixels()
            var dst = cast([*] u8) result.pixels.buffer!
            for pixelCount
            {
                let gray = src[0]
                dst[0] = gray
                dst[1] = gray
                dst[2] = gray
                dst[3] = gray == key ? 0 : 255
                src    += 1
                dst    += 4
            }

            return
        }

        var packed: [256] u32
        for i in 256
        {
            let gray  = cast(u32) i
            let alpha = i == key ? 0'u32 : 255'u32
            packed[i] = gray * 0x010101 | (alpha << 24)
        }

        var src = .safeDstPixels()
        var dst = cast([*] u32) result.pixels.buffer!
        for pixelCount
        {
            dst[0] = packed[src[0]]
            src    += 1
            dst    += 1
        }
    }

    mtd convertGrayscaleAlphaRgba(result: *Image)
    {
        let pixelCount = cast(u64) result.width * result.height
        if pixelCount < PackedGrayscaleAlphaThreshold
        {
            var src = .safeDstPixels()
            var dst = cast([*] u8) result.pixels.buffer!
            for pixelCount
            {
                dst[0] = src[0]
                dst[1] = src[0]
                dst[2] = src[0]
                dst[3] = src[1]
                src    += 2
                dst    += 4
            }

            return
        }

        var src = .safeDstPixels()
        var dst = cast([*] u32) result.pixels.buffer!
        for pixelCount
        {
            dst[0] = cast(u32) src[0] * 0x010101 | (cast(u32) src[1] << 24)
            src    += 2
            dst    += 1
        }
    }

    mtd convert16(result: *Image)
    {
        var src = cast(const [*] u8) .safeDstPixels()
        var dst = cast([*] u8) result.pixels.buffer!

        switch cast(u8) .header.colorType
        {
        case 0:
            var transparent: u16
            if .seenTRSN do
                transparent = read16(@dataof(.safeTRNSData()))

            for result.width * result.height
            {
                let gray  = read16(src)
                let gray8 = reduce16(gray)
                dst[0] = gray8
                dst[1] = gray8
                dst[2] = gray8
                if .seenTRSN do
                    dst[3] = gray == transparent ? 0'u8 : 255'u8
                src += 2
                dst += result.bytesPerPixel
            }

        case 2:
            var transparentR, transparentG, transparentB: u16
            if .seenTRSN
            {
                let key = cast(const [*] u8) @dataof(.safeTRNSData())
                transparentR = read16(key)
                transparentG = read16(key + 2)
                transparentB = read16(key + 4)
            }

            if !.seenTRSN
            {
                reduce16Samples(src, dst, cast(u64) result.width * result.height * 3)
            }
            else
            {
                for result.width * result.height
                {
                    let r = read16(src)
                    let g = read16(src + 2)
                    let b = read16(src + 4)
                    dst[0] = reduce16(r)
                    dst[1] = reduce16(g)
                    dst[2] = reduce16(b)
                    dst[3] = r == transparentR and g == transparentG and b == transparentB ? 0'u8 : 255'u8
                    src    += 6
                    dst    += result.bytesPerPixel
                }
            }

        case 4:
            for result.width * result.height
            {
                let gray8 = reduce16(read16(src))
                dst[0] = gray8
                dst[1] = gray8
                dst[2] = gray8
                dst[3] = reduce16(read16(src + 2))
                src    += 4
                dst    += 4
            }

        case 6:
            reduce16Samples(src, dst, cast(u64) result.width * result.height * 4)
        }
    }

    mtd convert(result: *Image)
    {
        defer Memory.free(.safeDstPixels(), .dstPixelsSize)

        if .header.bitDepth == 16
        {
            .convert16(result)
            return
        }

        // Paletted, no transparency
        if .inChannels == 1 and .seenPLTE and !.seenTRSN
        {
            .convertPaletteRgb(result)
        }

        // Paletted, transparency
        elif .inChannels == 1 and .seenPLTE and .seenTRSN
        {
            .convertPaletteRgba(result)
        }

        // Grayscale without alpha channel, no transparency
        elif .inChannels == 1 and !.seenTRSN
        {
            .convertGrayscaleRgb(result)
        }

        // Grayscale without alpha channel, but transparency
        elif .inChannels == 1 and .seenTRSN
        {
            var key   = .safeTRNSData()[1]
            let scale = .header.bitDepth == 1 ? 255'u8 : .header.bitDepth == 2 ? 85'u8 : .header.bitDepth == 4 ? 17'u8 : 1'u8
            key *= scale
            .convertGrayscaleTransparencyRgba(result, key)
        }

        // Grayscale with alpha channel
        elif .inChannels == 2
        {
            .convertGrayscaleAlphaRgba(result)
        }

        // Color without alpha but transparency
        elif .inChannels == 3 and .seenTRSN
        {
            let key  = cast(const [*] u8) @dataof(.safeTRNSData())
            let key0 = key[1]
            let key1 = key[3]
            let key2 = key[5]
            var src  = .safeDstPixels()
            var dst  = cast([*] u8) result.pixels.buffer!
            for result.width * result.height
            {
                dst[0] = src[0]
                dst[1] = src[1]
                dst[2] = src[2]
                if src[0] == key0 and src[1] == key1 and src[2] == key2 do
                    dst[3] = 0
                else do
                    dst[3] = 255
                src += 3
                dst += result.bytesPerPixel
            }
        }
    }
}
