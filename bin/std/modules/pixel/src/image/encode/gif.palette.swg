#global namespace Gif

using Swag, Core, Core.Errors

impl Encoder
{
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
        case .BGR8:
            result.setArgb(255, pix[2], pix[1], pix[0])

        case .BGRA8:
            result.setArgb(pix[3], pix[2], pix[1], pix[0])

        case .RGB8:
            result.setArgb(255, pix[0], pix[1], pix[2])

        case .RGBA8:
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
        for [r] in 4
        {
            for [g] in 8
            {
                for [b] in 4
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

        for [r] in 5
        {
            for [g] in 5
            {
                for [b] in 5
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
        for [y] in image.height
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
                    let key   = colorKey(col)
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
        for [y] in image.height
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

    func writeColorTable(result: *ConcatBuffer, palette: PaletteData)
    {
        let tableSize = 1'u32 << palette.tableBits
        for [i] in tableSize
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
}

