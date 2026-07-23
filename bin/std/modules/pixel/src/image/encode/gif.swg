#global namespace Gif

using Swag, Core, Core.Errors

private
{
    const MaxPaletteColors = 128'u32

    struct PaletteColor
    {
        r, g, b: u8
    }

    struct PaletteData
    {
        colors:           [256] PaletteColor
        count:            u32
        tableBits:        u8
        lzwMinCodeSize:   u8
        transparentIndex: s32 = -1
        indexes:          Array'u8
    }

    struct BitWriter
    {
        bytes:    Array'u8
        curBits:  u32
        bitCount: u32
    }

    struct LzwEncoder
    {
        bits:        BitWriter
        minCodeSize: u8
        codeSize:    u8
        clearCode:   u16
        endCode:     u16
    }
}

impl BitWriter
{
    mtd write(code: u16, codeSize: u8)
    {
        .curBits  |= cast(u32) code << .bitCount
        .bitCount += codeSize

        while .bitCount >= 8
        {
            .bytes.add(cast(u8) (.curBits & 0xFF))
            .curBits  >>= 8
            .bitCount -= 8
        }
    }

    mtd flush()
    {
        if .bitCount
        {
            .bytes.add(cast(u8) (.curBits & 0xFF))
            .curBits  = 0
            .bitCount = 0
        }
    }
}

impl LzwEncoder
{
    mtd resetDictionary()
    {
        .codeSize  = .minCodeSize + 1
        .clearCode = cast(u16) (1 << .minCodeSize)
        .endCode   = .clearCode + 1
    }

    mtd init(minCodeSize: u8)
    {
        .minCodeSize = minCodeSize
        .resetDictionary()
    }

    mtd writeCode(code: u16)
    {
        .bits.write(code, .codeSize)

        if code == .clearCode
        {
            .resetDictionary()
            return
        }
    }
}

public struct Encoder {}

impl Encoder
{
    func writeU16(result: *ConcatBuffer, value: u16)
    {
        result.addNative(cast(u8) (value & 0xFF))
        result.addNative(cast(u8) (value >> 8))
    }

    func colorKey(col: Color)->u32
    {
        return (cast(u32) col.r << 16) | (cast(u32) col.g << 8) | col.b
    }

    func tableBitsForColorCount(count: u32)->u8
    {
        var bits = 1'u8
        var size = 2'u32
        while size < count
        {
            bits += 1
            size <<= 1
        }

        return bits
    }

    func readPixelColor(image: Image, pix: const [*] u8)->Color
    {
        var result: retval = undefined

        switch image.pf
        {
        case BGR8:
            result.setArgb(255, pix[2], pix[1], pix[0])

        case BGRA8:
            result.setArgb(pix[3], pix[2], pix[1], pix[0])

        case RGB8:
            result.setArgb(255, pix[0], pix[1], pix[2])

        case RGBA8:
            result.setArgb(pix[3], pix[0], pix[1], pix[2])

        default:

            // Unsupported pixel format: opaque black rather than garbage.
            result.setArgb(255, 0, 0, 0)
        }

        return result
    }

    func imageHasTransparentPixels(image: Image)->bool
    {
        if !image.pf.hasAlpha() do
            return false

        var pix = cast([*] u8) (notnull image.pixels.buffer)
        for image.width * image.height
        {
            let col = readPixelColor(image, pix)
            if col.a < 128 do
                return true
            pix += image.bpp8
        }

        return false
    }

    func quantLevel(level, maxLevel: u32)->u8
    {
        if !maxLevel do
            return 0
        return cast(u8) ((level * 255 + maxLevel / 2) / maxLevel)
    }

    func quantizedOpaqueIndex(col: Color)->u8
    {
        let r = cast(u32) col.r * 3 / 255
        let g = cast(u32) col.g * 7 / 255
        let b = cast(u32) col.b * 3 / 255
        return cast(u8) (r * 32 + g * 4 + b)
    }

    func quantizedTransparentIndex(col: Color)->u8
    {
        let r = cast(u32) col.r * 4 / 255
        let g = cast(u32) col.g * 4 / 255
        let b = cast(u32) col.b * 4 / 255
        return cast(u8) (1 + r * 25 + g * 5 + b)
    }

    func fillOpaqueQuantizedPalette(data: *PaletteData)
    {
        data.count = 128
        for r in 4
        {
            for g in 8
            {
                for b in 4
                {
                    let idx = r * 32 + g * 4 + b
                    data.colors[idx].r = quantLevel(cast(u32) r, 3)
                    data.colors[idx].g = quantLevel(cast(u32) g, 7)
                    data.colors[idx].b = quantLevel(cast(u32) b, 3)
                }
            }
        }
    }

    func fillTransparentQuantizedPalette(data: *PaletteData)
    {
        data.transparentIndex = 0
        data.count            = 126
        data.colors[0]        = {}

        for r in 5
        {
            for g in 5
            {
                for b in 5
                {
                    let idx = 1 + r * 25 + g * 5 + b
                    data.colors[idx].r = quantLevel(cast(u32) r, 4)
                    data.colors[idx].g = quantLevel(cast(u32) g, 4)
                    data.colors[idx].b = quantLevel(cast(u32) b, 4)
                }
            }
        }
    }

    func resetPaletteResult(data: *PaletteData, pixelCount: u64)
    {
        data.count            = 0
        data.tableBits        = 0
        data.lzwMinCodeSize   = 0
        data.transparentIndex = -1
        data.indexes.resize(pixelCount)
        Memory.clear(&data.colors, #sizeof(data.colors))
    }

    func finishPaletteResult(data: *PaletteData)
    {
        data.tableBits      = tableBitsForColorCount(Math.max(data.count, 2'u32))
        data.lzwMinCodeSize = Math.max(data.tableBits, 2'u8)
    }

    func tryBuildExactPalette(data: *PaletteData, image: Image, hasTransparent: bool)->bool
    {
        let pixelCount = cast(u64) image.width * image.height
        resetPaletteResult(data, pixelCount)

        var colorMap: HashTable'(u32, u8)
        colorMap.reserve(257)

        if hasTransparent
        {
            data.transparentIndex = 0
            data.count            = 1
        }

        var dstIndex = 0'u64
        for y in image.height
        {
            var pix = cast([*] u8) (notnull image.pixels.buffer) + cast(u64) (image.height - y - 1) * image.width8
            for image.width
            {
                let col = readPixelColor(image, pix)
                var paletteIndex: u8

                if hasTransparent and col.a < 128
                {
                    paletteIndex = cast(u8) data.transparentIndex
                }
                else
                {
                    let key = colorKey(col)
                    let found = colorMap.tryFind(key)
                    if found
                    {
                        paletteIndex = found.value
                    }
                    else
                    {
                        if data.count == MaxPaletteColors do
                            return false

                        paletteIndex              = cast(u8) data.count
                        data.colors[paletteIndex] = {col.r, col.g, col.b}
                        colorMap.add(key, paletteIndex)
                        data.count += 1
                    }
                }

                data.indexes[dstIndex] = paletteIndex
                dstIndex               += 1
                pix                    += image.bpp8
            }
        }

        finishPaletteResult(data)
        return true
    }

    func buildQuantizedPalette(data: *PaletteData, image: Image, hasTransparent: bool)
    {
        let pixelCount = cast(u64) image.width * image.height
        resetPaletteResult(data, pixelCount)

        if hasTransparent do
            fillTransparentQuantizedPalette(data)
        else do
            fillOpaqueQuantizedPalette(data)

        var dstIndex = 0'u64
        for y in image.height
        {
            var pix = cast([*] u8) (notnull image.pixels.buffer) + cast(u64) (image.height - y - 1) * image.width8
            for image.width
            {
                let col = readPixelColor(image, pix)
                if hasTransparent and col.a < 128 do
                    data.indexes[dstIndex] = cast(u8) data.transparentIndex
                elif hasTransparent do
                    data.indexes[dstIndex] = quantizedTransparentIndex(col)
                else do
                    data.indexes[dstIndex] = quantizedOpaqueIndex(col)

                dstIndex += 1
                pix      += image.bpp8
            }
        }

        finishPaletteResult(data)
    }

    func buildPalette(image: Image)->PaletteData
    {
        let hasTransparent = imageHasTransparentPixels(image)
        var result: retval
        if !tryBuildExactPalette(&result, image, hasTransparent) do
            buildQuantizedPalette(&result, image, hasTransparent)
        return result
    }

    func lzwCompress(indexes: const [..] u8, minCodeSize: u8)->Array'u8
    {
        var enc: LzwEncoder
        enc.init(minCodeSize)
        enc.writeCode(enc.clearCode)

        for i in @countof(indexes)
        {
            if i do
                enc.writeCode(enc.clearCode)
            enc.writeCode(cast(u16) indexes[i])
        }

        enc.writeCode(enc.endCode)
        enc.bits.flush()
        return enc.bits.bytes
    }

    func writeColorTable(result: *ConcatBuffer, palette: PaletteData)
    {
        let tableSize = 1'u32 << palette.tableBits
        for i in tableSize
        {
            if i < palette.count
            {
                result.addNative(palette.colors[i].r)
                result.addNative(palette.colors[i].g)
                result.addNative(palette.colors[i].b)
            }
            else
            {
                result.addNative(0'u8)
                result.addNative(0'u8)
                result.addNative(0'u8)
            }
        }
    }

    func writeSubBlocks(result: *ConcatBuffer, bytes: const [..] u8)
    {
        var offset = 0'u64
        while offset < @countof(bytes)
        {
            let blockSize = Math.min(255'u64, @countof(bytes) - offset)
            result.addNative(cast(u8) blockSize)
            result.addBytes(@mkslice(@dataof(bytes) + offset, blockSize))
            offset += blockSize
        }

        result.addNative(0'u8)
    }
}

public impl IImageEncoder for Encoder
{
    mtd impl canEncode(fileName: string)->bool
    {
        return Path.getExtensionLowerCase(fileName) == ".gif"
    }

    mtd impl encode(result: *ConcatBuffer, image: Image, options: #null any) throw
    {
        if image.width <= 0 or image.height <= 0 or !image.pixels.buffer do
            throw InvalidFormatError{"invalid image"}
        if image.width > Swag.U16.Max do
            throw UnsupportedFormatError{"width is too big"}
        if image.height > Swag.U16.Max do
            throw UnsupportedFormatError{"height is too big"}

        let palette = buildPalette(image)
        let packed = 0x80'u8 | ((palette.tableBits - 1) << 4) | (palette.tableBits - 1)

        result.addBytes("GIF89a")
        Encoder.writeU16(result, cast(u16) image.width)
        Encoder.writeU16(result, cast(u16) image.height)
        result.addNative(packed)
        result.addNative(0'u8)
        result.addNative(0'u8)
        Encoder.writeColorTable(result, palette)

        if palette.transparentIndex >= 0
        {
            result.addNative(0x21'u8)
            result.addNative(0xF9'u8)
            result.addNative(0x04'u8)
            result.addNative(0x01'u8)
            Encoder.writeU16(result, 0)
            result.addNative(cast(u8) palette.transparentIndex)
            result.addNative(0'u8)
        }

        result.addNative(0x2C'u8)
        Encoder.writeU16(result, 0)
        Encoder.writeU16(result, 0)
        Encoder.writeU16(result, cast(u16) image.width)
        Encoder.writeU16(result, cast(u16) image.height)
        result.addNative(0'u8)
        result.addNative(palette.lzwMinCodeSize)

        let compressed = lzwCompress(palette.indexes.toSlice(), palette.lzwMinCodeSize)
        Encoder.writeSubBlocks(result, compressed.toSlice())

        result.addNative(0x3B'u8)
    }
}
