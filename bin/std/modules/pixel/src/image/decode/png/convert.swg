//! Format: Portable Network Graphics (PNG) decoder component.
//! Supported: Standard grayscale, true-color, indexed, grayscale-alpha, and true-color-alpha images, including Adam7 and supported metadata.
//! Not supported: APNG animation, unknown critical chunks, and images requiring more than 2 GiB of decoded storage.
//! Role: This file owns decoded sample expansion and pixel-format conversion.
//
// @LICENCE: BSD-2-Clause
// @ORIGIN: libspng, https://github.com/randy408/libspng
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#libspng

#global namespace Png

using Core, Core.Errors

const Swap16Bytes           = cast(Math.Simd.U8x16) [1'u8, 0, 3, 2, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 15, 14]
const ExpandRgbTransparency = cast(Math.Simd.U8x16) [0'u8, 1, 2, 0x80, 3, 4, 5, 0x80, 6, 7, 8, 0x80, 9, 10, 11, 0x80]

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
            let alphaValue = i < alpha.count ? cast(u32) alpha[i] : 255'u32
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
            Memory.copy(result.pixels.buffer, src, pixelCount)

            return
        }

        var src = .safeDstPixels()
        Memory.copy(result.pixels.buffer, src, pixelCount)
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
                dst[1] = gray == key ? 0 : 255
                src    += 1
                dst    += 2
            }

            return
        }

        var packed: [256] u16
        for i in 256
        {
            let gray  = cast(u32) i
            let alpha = i == key ? 0'u32 : 255'u32
            packed[i] = cast(u16) (gray | (alpha << 8))
        }

        var src = .safeDstPixels()
        var dst = cast([*] u16) result.pixels.buffer!
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
                dst[1] = src[1]
                src    += 2
                dst    += 2
            }

            return
        }

        var src = .safeDstPixels()
        Memory.copy(result.pixels.buffer, src, pixelCount * 2)
    }

    mtd convertRgbTransparencyRgba(result: *Image, key0, key1, key2: u8)
    {
        let key       = Math.Simd.splat(cast(u32) key0 | (cast(u32) key1 << 8) | (cast(u32) key2 << 16))
        let colorMask = Math.Simd.splat(0x00FFFFFF'u32)
        let alphaMask = Math.Simd.splat(0xFF000000'u32)
        var src       = .safeDstPixels()
        var dst       = cast([*] u8) result.pixels.buffer!
        var remaining = cast(u64) result.width * result.height
        if remaining >= SimdRgbTransparencyThreshold
        {
            while remaining >= 8
            {
                let pixels  = cast #bit(Math.Simd.U32x4) Math.Simd.shuffle(Math.Simd.load(src), ExpandRgbTransparency)
                let matches = (pixels & colorMask) == key
                Math.Simd.store(cast([*] u32) dst, pixels | (~matches & alphaMask))
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
        var src = cast(const [*] u8) .safeDstPixels()
        var dst = cast([*] u8) result.pixels.buffer!

        switch cast(u8) .header.colorType
        {
        case 0:
            var transparent: u16
            if .seenTRSN do
                transparent = read16((.safeTRNSData()).buffer)

            for result.width * result.height
            {
                let gray = read16(src)
                dst[as u16] = gray
                if .seenTRSN do
                    (dst + 2)[as u16] = gray == transparent ? 0'u16 : 65535'u16
                src += 2
                dst += result.bytesPerPixel
            }

        case 2:
            var transparentR, transparentG, transparentB: u16
            if .seenTRSN
            {
                let key = cast(const [*] u8) (.safeTRNSData()).buffer
                transparentR = read16(key)
                transparentG = read16(key + 2)
                transparentB = read16(key + 4)
            }

            for result.width * result.height
            {
                let r = read16(src)
                let g = read16(src + 2)
                let b = read16(src + 4)
                dst[as u16]       = r
                (dst + 2)[as u16] = g
                (dst + 4)[as u16] = b
                if .seenTRSN do
                    (dst + 6)[as u16] = r == transparentR and g == transparentG and b == transparentB ? 0'u16 : 65535'u16
                src += 6
                dst += result.bytesPerPixel
            }

        case 4:
            for result.width * result.height
            {
                dst[as u16]       = read16(src)
                (dst + 2)[as u16] = read16(src + 2)
                src               += 4
                dst               += 4
            }

        case 6:
            for result.width * result.height
            {
                dst[as u16]       = read16(src)
                (dst + 2)[as u16] = read16(src + 2)
                (dst + 4)[as u16] = read16(src + 4)
                (dst + 6)[as u16] = read16(src + 6)
                src               += 8
                dst               += 8
            }
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
            let key  = cast(const [*] u8) (.safeTRNSData()).buffer
            let key0 = key[1]
            let key1 = key[3]
            let key2 = key[5]
            .convertRgbTransparencyRgba(result, key0, key1, key2)
        }
    }
}
