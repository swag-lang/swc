//! Format: Portable Network Graphics (PNG) decoder component.
//! Supported: Standard grayscale, true-color, indexed, grayscale-alpha, and true-color-alpha images, including Adam7 and supported metadata.
//! Not supported: Unknown critical chunks and images requiring more than 2 GiB of decoded storage.
//! Role: This file owns decoded sample expansion and pixel-format conversion.
//
// @LICENCE: BSD-2-Clause
// @ORIGIN: libspng, https://github.com/randy408/libspng
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#libspng

#global namespace Png

using Core, Core.Errors

const Swap16Bytes = cast(Math.Simd.U8x16, [1'u8, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 15, 14])
const ExpandRgb16Transparency = cast(Math.Simd.U8x16, [1'u8, 0, 3, 2, 5, 4, 0x80, 0x80, 7, 6, 9, 8, 11, 10, 0x80, 0x80])
const ExpandRgbTransparency   = cast(Math.Simd.U8x16, [0'u8, 1, 2, 0x80, 3, 4, 5, 0x80, 6, 7, 8, 0x80, 9, 10, 11, 0x80])

// Building the packed table breaks even at 512 pixels on the supported x64 baseline.
const PackedPaletteThreshold = 512'u64

// Keep tiny icon decode on the lower-overhead path; large images amortize packed expansion.
const PackedGrayscaleThreshold = 4096'u64

// A transparency lookup table pays for itself from 512 grayscale pixels.
const PackedGrayscaleTransparencyThreshold = 512'u64

// Direct grayscale-plus-alpha packing wins from 256 pixels.
const PackedGrayscaleAlphaThreshold = 256'u64

// RGB transparency expansion amortizes its shuffle and masks on image-sized inputs.
const SimdRgbTransparencyThreshold = 4096'u64

// PNG stores 16-bit samples big-endian; native image pixels use little-endian words.
func convert16Samples(source: const [*] u8, destination: [*] u8, sampleCount: u64)
{
    var src       = source
    var dst       = destination
    var remaining = sampleCount
    while remaining >= 8
    {
        Math.Simd.store(dst, Math.Simd.shuffle(Math.Simd.load(src), Swap16Bytes))
        src       += 16
        dst       += 16
        remaining -= 8
    }

    while remaining
    {
        dst[0]    = src[1]
        dst[1]    = src[0]
        src       += 2
        dst       += 2
        remaining -= 1
    }
}

// Expand each gray sample with an alpha derived from its full 16-bit key.
func convertGray16Transparency(source: const [*] u8, destination: [*] u8, sampleCount: u64, key: u16)
{
    var src       = source
    var dst       = destination
    var remaining = sampleCount
    let keys      = Math.Simd.splat(key)
    while remaining >= 8
    {
        let gray  = cast #bit(Math.Simd.U16x8, Math.Simd.shuffle(Math.Simd.load(src), Swap16Bytes))
        let alpha = ~(gray == keys)
        Math.Simd.store(cast([*] u16, dst), Math.Simd.interleaveLow(gray, alpha))
        Math.Simd.store(cast([*] u16, (dst + 16)), Math.Simd.interleaveHigh(gray, alpha))
        src       += 16
        dst       += 32
        remaining -= 8
    }

    while remaining
    {
        let gray = (cast(u16, src[0]) << 8) | src[1]
        cast([*] u16, dst)[0] = gray
        cast([*] u16, dst)[1] = gray == key ? 0'u16 : 65535'u16
        src                   += 2
        dst                   += 4
        remaining             -= 1
    }
}

// Expand two RGB16 pixels and compare each complete 48-bit color to the key.
func convertRgb16Transparency(source: const [*] u8, destination: [*] u8, pixelCount: u64, red, green, blue: u16)
{
    var src       = source
    var dst       = destination
    var remaining = pixelCount
    let key       = cast(u64, red) | (cast(u64, green) << 16) | (cast(u64, blue) << 32)
    let keys      = Math.Simd.splat(key)
    let alphaMask = Math.Simd.splat(0xFFFF_0000_0000_0000'u64)

    // The sixteen-byte load spans two pixels and four bytes of the next one.
    while remaining >= 3
    {
        let pixels = cast #bit(Math.Simd.U64x2, Math.Simd.shuffle(Math.Simd.load(src), ExpandRgb16Transparency))
        let alpha  = ~(pixels == keys) & alphaMask
        Math.Simd.store(cast([*] u64, dst), pixels | alpha)
        src       += 12
        dst       += 16
        remaining -= 2
    }

    while remaining
    {
        let r = (cast(u16, src[0]) << 8) | src[1]
        let g = (cast(u16, src[2]) << 8) | src[3]
        let b = (cast(u16, src[4]) << 8) | src[5]
        cast([*] u16, dst)[0] = r
        cast([*] u16, dst)[1] = g
        cast([*] u16, dst)[2] = b
        cast([*] u16, dst)[3] = r == red and g == green and b == blue ? 0'u16 : 65535'u16
        src                   += 6
        dst                   += 8
        remaining             -= 1
    }
}

func reduce16Samples(source: const [*] u8, destination: [*] u8, sampleCount: u64)
{
    var src   = source
    var dst   = destination
    var count = sampleCount
    while count >= 8
    {
        let words    = cast #bit(Math.Simd.U16x8, Math.Simd.shuffle(Math.Simd.load(src), Swap16Bytes))
        let low      = ((Math.Simd.widenLow(words) + 129'u32) * 255'u32) >> 16
        let high     = ((Math.Simd.widenHigh(words) + 129'u32) * 255'u32) >> 16
        let packed16 = Math.Simd.packUnsigned(cast #bit(Math.Simd.S32x4, low), cast #bit(Math.Simd.S32x4, high))
        let packed8  = Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8, packed16), cast #bit(Math.Simd.S16x8, packed16))
        Math.Simd.storeLow8(dst, packed8)
        src   += 16
        dst   += 8
        count -= 8
    }

    while count
    {
        let value = (cast(u16, src[0]) << 8) | src[1]
        dst[0] = cast(u8, ((cast(u32, value) + 128) / 257))
        src    += 2
        dst    += 1
        count  -= 1
    }
}

impl Decoder
{
    func read16(src: const [*] u8)->u16 => (cast(u16, src[0]) << 8) | src[1]

    func reduce16(value: u16)->u8 => cast(u8, ((cast(u32, value) + 128) / 257))

    mtd convertPaletteRgb(result: *Image)
    {
        let pixelCount = cast(u64, result.width) * result.height
        if pixelCount < PackedPaletteThreshold
        {
            var src = .safeDstPixels()
            var dst = cast([*] u8, result.pixels.storage())
            for pixelCount
            {
                let color = .palette[src[0]]
                dst[0] = cast(((color >> 16) & 0xFF))
                dst[1] = cast(((color >> 8) & 0xFF))
                dst[2] = cast((color & 0xFF))
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
        var dst       = cast([*] u8, result.pixels.storage())
        var remaining = pixelCount

        // The fourth byte lands on the next pixel and is overwritten there; four
        // independent lookups per step keep the table loads in flight together. Stop
        // before the final pixel so every wide store remains inside the image buffer.
        while remaining > 4
        {
            cast([*] u32, dst)[0]       = packedPalette[src[0]]
            cast([*] u32, (dst + 3))[0] = packedPalette[src[1]]
            cast([*] u32, (dst + 6))[0] = packedPalette[src[2]]
            cast([*] u32, (dst + 9))[0] = packedPalette[src[3]]
            src                         += 4
            dst                         += 12
            remaining                   -= 4
        }

        while remaining > 1
        {
            cast([*] u32, dst)[0] = packedPalette[src[0]]
            src       += 1
            dst       += 3
            remaining -= 1
        }

        let color = packedPalette[src[0]]
        dst[0] = cast(u8, (color & 0xFF))
        dst[1] = cast(u8, ((color >> 8) & 0xFF))
        dst[2] = cast(u8, ((color >> 16) & 0xFF))
    }

    mtd convertPaletteRgba(result: *Image)
    {
        let pixelCount = cast(u64, result.width) * result.height
        if pixelCount < PackedPaletteThreshold
        {
            var src = .safeDstPixels()
            var dst = cast([*] u8, result.pixels.storage())
            for pixelCount
            {
                let index = src[0]
                let color = .palette[index]
                dst[0] = cast(((color >> 16) & 0xFF))
                dst[1] = cast(((color >> 8) & 0xFF))
                dst[2] = cast((color & 0xFF))
                dst[3] = index < (.safeTRNSData()).count ? .safeTRNSData()[index] : 255
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
            let alphaValue = i < alpha.count ? cast(u32, alpha[i]) : 255'u32
            packedPalette[i] = ((color >> 16) & 0xFF) | (color & 0xFF00) | ((color & 0xFF) << 16) | (alphaValue << 24)
        }

        var src       = .safeDstPixels()
        var dst       = cast([*] u32, result.pixels.storage())
        var remaining = pixelCount
        while remaining >= 4
        {
            dst[0]    = packedPalette[src[0]]
            dst[1]    = packedPalette[src[1]]
            dst[2]    = packedPalette[src[2]]
            dst[3]    = packedPalette[src[3]]
            src       += 4
            dst       += 4
            remaining -= 4
        }

        for remaining
        {
            dst[0] = packedPalette[src[0]]
            src    += 1
            dst    += 1
        }
    }

    mtd convertGrayscaleRgb(result: *Image)
    {
        let pixelCount = cast(u64, result.width) * result.height
        if pixelCount < PackedGrayscaleThreshold
        {
            var src = .safeDstPixels()
            Memory.copy(result.pixels.storage(), src, pixelCount)

            return
        }

        var src = .safeDstPixels()
        Memory.copy(result.pixels.storage(), src, pixelCount)
    }

    mtd convertGrayscaleTransparencyRgba(result: *Image, key: u8)
    {
        let pixelCount = cast(u64, result.width) * result.height
        if pixelCount < PackedGrayscaleTransparencyThreshold
        {
            var src = .safeDstPixels()
            var dst = cast([*] u8, result.pixels.storage())
            for pixelCount
            {
                let gray = src[0]
                dst[0] = gray
                dst[1] = gray == key ? 0 : 255
                src    += 1
                dst    += 2
            }

            return
        }

        var packed: [256] u16
        for i in 256
        {
            let gray  = cast(u32, i)
            let alpha = i == key ? 0'u32 : 255'u32
            packed[i] = cast(u16, (gray | (alpha << 8)))
        }

        var src = .safeDstPixels()
        var dst = cast([*] u16, result.pixels.storage())
        for pixelCount
        {
            dst[0] = packed[src[0]]
            src    += 1
            dst    += 1
        }
    }

    mtd convertGrayscaleAlphaRgba(result: *Image)
    {
        let pixelCount = cast(u64, result.width) * result.height
        if pixelCount < PackedGrayscaleAlphaThreshold
        {
            var src = .safeDstPixels()
            var dst = cast([*] u8, result.pixels.storage())
            for pixelCount
            {
                dst[0] = src[0]
                dst[1] = src[1]
                src    += 2
                dst    += 2
            }

            return
        }

        var src = .safeDstPixels()
        Memory.copy(result.pixels.storage(), src, pixelCount * 2)
    }

    mtd convertRgbTransparencyRgba(result: *Image, key0, key1, key2: u8)
    {
        let key       = Math.Simd.splat(cast(u32, key0) | (cast(u32, key1) << 8) | (cast(u32, key2) << 16))
        let colorMask = Math.Simd.splat(0x00FFFFFF'u32)
        let alphaMask = Math.Simd.splat(0xFF000000'u32)
        var src       = .safeDstPixels()
        var dst       = cast([*] u8, result.pixels.storage())
        var remaining = cast(u64, result.width) * result.height
        if remaining >= SimdRgbTransparencyThreshold
        {
            while remaining >= 8
            {
                let pixels  = cast #bit(Math.Simd.U32x4, Math.Simd.shuffle(Math.Simd.load(src), ExpandRgbTransparency))
                let matches = (pixels & colorMask) == key
                Math.Simd.store(cast([*] u32, dst), pixels | (~matches & alphaMask))
                src       += 12
                dst       += 16
                remaining -= 4
            }
        }

        while remaining
        {
            dst[0]    = src[0]
            dst[1]    = src[1]
            dst[2]    = src[2]
            dst[3]    = src[0] == key0 and src[1] == key1 and src[2] == key2 ? 0 : 255
            src       += 3
            dst       += 4
            remaining -= 1
        }
    }

    mtd convert16(result: *Image)
    {
        var src = cast(const [*] u8, .safeDstPixels())
        var dst = cast([*] u8, result.pixels.storage())

        // Without a transparency key, each input word maps directly to one
        // output word, independent of the number of channels.
        if not .seenTRSN or (cast(u8, .header.colorType) & 4) != 0
        {
            let samples = cast(u64, result.width) * result.height * .inChannels
            convert16Samples(src, dst, samples)
            return
        }

        switch cast(u8, .header.colorType)
        {
        case 0:
            let transparent = read16((.safeTRNSData()).buffer)
            convertGray16Transparency(src, dst, cast(u64, result.width) * result.height, transparent)

        case 2:
            let key = cast(const [*] u8, (.safeTRNSData()).buffer)
            let transparentR = read16(key)
            let transparentG = read16(key + 2)
            let transparentB = read16(key + 4)

            convertRgb16Transparency(src, dst, cast(u64, result.width) * result.height, transparentR, transparentG, transparentB)
        }
    }

    mtd convert(result: *Image)
    {
        if .header.bitDepth == 16
        {
            .convert16(result)
            return
        }

        // Paletted, no transparency
        if .inChannels == 1 and .seenPLTE and not .seenTRSN
        {
            .convertPaletteRgb(result)
        }
        // Paletted, transparency
        elif .inChannels == 1 and .seenPLTE and .seenTRSN
        {
            .convertPaletteRgba(result)
        }
        // Grayscale without alpha channel, no transparency
        elif .inChannels == 1 and not .seenTRSN
        {
            .convertGrayscaleRgb(result)
        }
        // Grayscale without alpha channel, but transparency
        elif .inChannels == 1 and .seenTRSN
        {
            var key = .safeTRNSData()[1]
            var scale: u8
            switch .header.bitDepth
            {
            case 1:  scale = 255
            case 2:  scale = 85
            case 4:  scale = 17
            default: scale = 1
            }

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
            let key  = cast(const [*] u8, (.safeTRNSData()).buffer)
            let key0 = key[1]
            let key1 = key[3]
            let key2 = key[5]
            .convertRgbTransparencyRgba(result, key0, key1, key2)
        }
    }
}
