//! Format: Graphics Interchange Format (GIF89a) encoder component.
//! Supported: One indexed frame with generated palette, LZW compression, and binary transparency.
//! Not supported: Interlaced output and partial alpha; animations are written by [[Gif.AnimationWriter]].
//! Role: This file owns palette construction and pixel quantization.
//
#global namespace Gif

using Swag, Core, Core.Errors

// Balanced 4x4 ordered offsets avoid a directional bias in smooth gradients.
private const Dither: [16] s32 = [-8, 0, -6, 2, 4, -4, 6, -2, -5, 3, -7, 1, 7, -1, 5, -3]

impl Encoder
{
    func colorKey(col: Color)->u32 => (cast(u32, col.r) << 16) | (cast(u32, col.g) << 8) | col.b

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
        var result: #returntype

        switch image.pixelFormat
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
        if not image.pixelFormat.hasAlpha() do
            return false

        for y in image.height
        {
            var pix = image.pixels.storage() + cast(u64, y) * image.rowStride
            for image.width
            {
                let col = readPixelColor(image, pix)
                if col.a < 128 do
                    return true
                pix += image.bytesPerPixel
            }
        }

        return false
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
        let pixelCount = cast(u64, image.width) * image.height
        resetPaletteResult(data, pixelCount)

        var colorMap: HashTable'(u32, u8)
        colorMap.reserve(257)

        if hasTransparent
        {
            data.transparentIndex = 0
            data.count = 1
        }

        var dstIndex = 0'u64
        for y in image.height
        {
            var pix = cast([*] u8, image.pixels.storage()) + cast(u64, (image.height - y - 1)) * image.rowStride
            for image.width
            {
                let col = readPixelColor(image, pix)
                var paletteIndex: u8

                if hasTransparent and col.a < 128
                {
                    paletteIndex = cast(u8, data.transparentIndex)
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

                        paletteIndex = cast(u8, data.count)
                        data.colors[paletteIndex] = PaletteColor{col.r, col.g, col.b}
                        colorMap.add(key, paletteIndex)
                        data.count += 1
                    }
                }

                data.indexes[dstIndex] = paletteIndex
                dstIndex += 1
                pix      += image.bytesPerPixel
            }
        }

        finishPaletteResult(data)
        return true
    }

    func histogramIndex(red, green, blue: u8)->u32 =>
        (cast(u32, red >> 3) << 10) | (cast(u32, green >> 3) << 5) | (blue >> 3)

    func occupiedBox(region: ColorBox, histogram: const [*] HistogramCell)->ColorBox
    {
        var result = ColorBox{32, -1, 32, -1, 32, -1}

        for red in region.minRed to region.maxRed
        {
            for green in region.minGreen to region.maxGreen
            {
                for blue in region.minBlue to region.maxBlue
                {
                    let cell = histogram[(red << 10) | (green << 5) | blue]
                    if not cell.count do
                        continue
                    result.minRed     = Math.min(result.minRed, red)
                    result.maxRed     = Math.max(result.maxRed, red)
                    result.minGreen   = Math.min(result.minGreen, green)
                    result.maxGreen   = Math.max(result.maxGreen, green)
                    result.minBlue    = Math.min(result.minBlue, blue)
                    result.maxBlue    = Math.max(result.maxBlue, blue)
                    result.pixels     += cell.count
                    result.redTotal   += cell.red
                    result.greenTotal += cell.green
                    result.blueTotal  += cell.blue
                }
            }
        }

        return result
    }

    func splitBox(boxes: *[256] ColorBox, boxCount: u32, histogram: const [*] HistogramCell)->bool
    {
        var selected = -1
        var best     = 0'u64

        // Split the occupied region with the most pixels and the widest colour range.
        for i in boxCount
        {
            let box   = boxes[][i]
            let span  = Math.max(box.maxRed - box.minRed, Math.max(box.maxGreen - box.minGreen, box.maxBlue - box.minBlue))
            let score = cast(u64, span) * box.pixels
            if span > 0 and score > best
            {
                selected = cast(s32, i)
                best     = score
            }
        }

        if selected < 0 do
            return false

        let box       = boxes[][selected]
        let redSpan   = box.maxRed - box.minRed
        let greenSpan = box.maxGreen - box.minGreen
        let blueSpan  = box.maxBlue - box.minBlue
        var axis      = 0
        var first     = box.minRed
        var last      = box.maxRed
        if greenSpan > redSpan and greenSpan >= blueSpan
        {
            axis  = 1
            first = box.minGreen
            last  = box.maxGreen
        }
        elif blueSpan > redSpan and blueSpan > greenSpan
        {
            axis  = 2
            first = box.minBlue
            last  = box.maxBlue
        }

        var slices: [32] u64
        Memory.clear(&slices, #sizeof(slices))

        for red in box.minRed to box.maxRed
        {
            for green in box.minGreen to box.maxGreen
            {
                for blue in box.minBlue to box.maxBlue
                {
                    let axisValue = axis == 0 ? red : axis == 1 ? green : blue
                    slices[axisValue] += histogram[(red << 10) | (green << 5) | blue].count
                }
            }
        }

        var cumulative = 0'u64
        var cut        = first
        for value in first to last - 1
        {
            cumulative += slices[value]
            if cumulative >= box.pixels / 2 and cumulative < box.pixels
            {
                cut = value
                break
            }
        }

        var left  = box
        var right = box
        switch axis
        {
        case 0:
            left.maxRed  = cut
            right.minRed = cut + 1

        case 1:
            left.maxGreen  = cut
            right.minGreen = cut + 1

        default:
            left.maxBlue  = cut
            right.minBlue = cut + 1
        }

        boxes[][selected] = occupiedBox(left, histogram)
        boxes[][boxCount] = occupiedBox(right, histogram)
        return true
    }

    func buildQuantizedPalette(data: *PaletteData, image: Image, hasTransparent, dither: bool)
    {
        let pixelCount = cast(u64, image.width) * image.height
        resetPaletteResult(data, pixelCount)

        // Five bits per channel keep the histogram bounded independently of image size.
        var histogram: Array'HistogramCell
        histogram.resize(32 * 32 * 32)
        Memory.clear(histogram.storage(), histogram.count * #sizeof(HistogramCell))
        for y in image.height
        {
            var pix = image.pixels.storage() + cast(u64, image.height - 1 - y) * image.rowStride
            for image.width
            {
                let color = readPixelColor(image, pix)
                if not hasTransparent or color.a >= 128
                {
                    let cell = &histogram[histogramIndex(color.r, color.g, color.b)]
                    cell.count += 1
                    cell.red   += color.r
                    cell.green += color.g
                    cell.blue  += color.b
                }

                pix += image.bytesPerPixel
            }
        }

        var boxes: [256] ColorBox
        boxes[0] = occupiedBox(ColorBox{0, 31, 0, 31, 0, 31}, histogram.storage())
        var boxCount  = 1'u32
        let maxColors = MaxPaletteColors - (hasTransparent ? 1'u32 : 0'u32)
        while boxCount < maxColors and splitBox(&boxes, boxCount, histogram.storage()) do
            boxCount += 1

        let firstColor = hasTransparent ? 1'u32 : 0'u32
        if hasTransparent do
            data.transparentIndex = 0
        data.count = boxCount + firstColor
        for i in boxCount
        {
            let box = boxes[i]
            data.colors[i + firstColor] = {
                cast(u8, (box.redTotal + box.pixels / 2) / box.pixels),
                cast(u8, (box.greenTotal + box.pixels / 2) / box.pixels),
                cast(u8, (box.blueTotal + box.pixels / 2) / box.pixels)}
        }

        // Map every histogram cell, including empty ones a dithered pixel may reach.
        var mapping: Array'u8
        mapping.resize(histogram.count)
        for red in 32
        {
            for green in 32
            {
                for blue in 32
                {
                    let index        = (red << 10) | (green << 5) | blue
                    var bestDistance = Swag.U32.Max
                    var bestIndex    = firstColor
                    for i in firstColor to data.count - 1
                    {
                        let color    = data.colors[i]
                        let dr       = cast(s32, red * 8 + 4) - cast(s32, color.r)
                        let dg       = cast(s32, green * 8 + 4) - cast(s32, color.g)
                        let db       = cast(s32, blue * 8 + 4) - cast(s32, color.b)
                        let distance = cast(u32, dr * dr + dg * dg + db * db)
                        if distance < bestDistance
                        {
                            bestDistance = distance
                            bestIndex    = i
                        }
                    }

                    mapping[index] = cast(u8, bestIndex)
                }
            }
        }

        var destination = 0'u64
        for y in image.height
        {
            var pix = image.pixels.storage() + cast(u64, image.height - 1 - y) * image.rowStride
            for x in image.width
            {
                let color = readPixelColor(image, pix)
                if hasTransparent and color.a < 128
                {
                    data.indexes[destination] = 0
                }
                else
                {
                    let shift = dither ? Dither[((y & 3) << 2) | (x & 3)] : 0
                    let red   = cast(u8, Math.clamp(cast(s32, color.r) + shift, 0, 255))
                    let green = cast(u8, Math.clamp(cast(s32, color.g) + shift, 0, 255))
                    let blue  = cast(u8, Math.clamp(cast(s32, color.b) + shift, 0, 255))
                    data.indexes[destination] = mapping[histogramIndex(red, green, blue)]
                }

                destination += 1
                pix         += image.bytesPerPixel
            }
        }

        finishPaletteResult(data)
    }

    func buildPalette(image: Image, dither: bool = false)->PaletteData
    {
        let hasTransparent = imageHasTransparentPixels(image)
        var result: #returntype
        if not tryBuildExactPalette(&result, image, hasTransparent) do
            buildQuantizedPalette(&result, image, hasTransparent, dither)
        return result
    }

    // Rewrites frame indexes only when every frame colour exists in a shared GIF colour table.
    func remapToColorTable(palette: *PaletteData, table: const [..] u8)->bool
    {
        var mapping: [256] u8
        for local in palette.count
        {
            let color = palette.colors[local]
            var found = false
            for globalIndex in table.count / 3
            {
                let at = globalIndex * 3
                if table[at] == color.r and table[at + 1] == color.g and table[at + 2] == color.b
                {
                    mapping[local] = cast(u8, globalIndex)
                    found = true
                    break
                }
            }

            if not found do
                return false
        }

        for i in palette.indexes.count do
            palette.indexes[i] = mapping[palette.indexes[i]]
        return true
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
}
