//! Format: Graphics Interchange Format (GIF89a) encoder component.
//! Supported: One indexed frame with generated palette, LZW compression, and binary transparency.
//! Not supported: Interlaced output and partial alpha; animations are written by [[Gif.AnimationWriter]].
//! Role: This file owns palette construction and pixel quantization.
//
#global namespace Gif

using Swag, Core, Core.Errors

// Balanced 4x4 ordered offsets avoid a directional bias in smooth gradients.
// Each offset moves a color by at most one five-bit histogram bin per channel.
private const Dither: [16] s32 = [-8, 0, -6, 2, 4, -4, 6, -2, -5, 3, -7, 1, 7, -1, 5, -3]

private const PaletteMapSize = 512'u32

impl Encoder
{
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

    func pixelChannelOffsets(image: Image)->{ red, green, blue, alpha: u8 }
    {
        let gray = image.pixelFormat == .Gray8 or image.pixelFormat == .GrayAlpha8
        let bgr  = image.pixelFormat == .BGR8 or image.pixelFormat == .BGRA8
        return {gray or not bgr ? 0 : 2,
                gray ? 0 : 1,
                gray or bgr ? 0 : 2,
                image.bytesPerPixel - 1}
    }

    func imageHasTransparentPixels(image: Image)->bool
    {
        if not image.pixelFormat.hasAlpha() do
            return false

        // Alpha is the last byte of each two- or four-byte pixel. Its sign bit
        // is set exactly when that pixel is opaque in GIF.
        let step = image.bytesPerPixel
        let mask = step == 2 ? 0xAAAA'u32 : 0x8888'u32
        let end  = image.pixels.storage() + image.byteCount
        var pix  = image.pixels.storage()
        while end - pix >= 16
        {
            if (Math.Simd.bitmask(Math.Simd.load(pix)) & mask) != mask do
                return true
            pix += 16
        }

        while pix < end
        {
            if pix[step - 1] < 128 do
                return true
            pix += step
        }

        return false
    }

    func resetPaletteResult(data: *PaletteData, pixelCount: u64)
    {
        data.count            = 0
        data.tableBits        = 0
        data.lzwMinCodeSize   = 0
        data.transparentIndex = -1
        data.indexes.grow(pixelCount)
        data.indexes.count = pixelCount
        Memory.clear(&data.colors, #sizeof(data.colors))
    }

    func finishPaletteResult(data: *PaletteData)
    {
        data.tableBits      = tableBitsForColorCount(Math.max(data.count, 2'u32))
        data.lzwMinCodeSize = Math.max(data.tableBits, 2'u8)
    }

    func allGrayBytesEqual(pixels: const [*] u8, count: u64)->bool
    {
        let gray    = pixels[0]
        let pattern = Math.Simd.splat(gray)
        var i       = 0'u64
        while count - i >= 16
        {
            if not Math.Simd.allTrue(Math.Simd.load(pixels + i) == pattern) do
                return false
            i += 16
        }

        for tail in i until count
        {
            if pixels[tail] != gray do
                return false
        }

        return true
    }

    // A single color needs no index buffer; its only palette index is zero.
    func tryBuildUniformPalette(data: *PaletteData, image: Image, count: u64)->bool
    {
        let pixels = image.pixels.storage()
        let step   = image.bytesPerPixel
        let last   = pixels + (count - 1) * step
        switch step
        {
        case 1:
            if last[0] != pixels[0] or not allGrayBytesEqual(pixels, count) do
                return false
        case 3:
            if cast(const *u16, last)[] != cast(const *u16, pixels)[] or last[2] != pixels[2] or
               PackedPixel.countSame24(pixels, pixels + 3, count - 1) != count - 1 do
                return false
        case 4:
            if cast(const *u32, last)[] != cast(const *u32, pixels)[] or
               PackedPixel.countSame32(pixels, pixels + 4, count - 1) != count - 1 do
                return false
        default:
            return false
        }

        let offsets = pixelChannelOffsets(image)
        if step == 4 and pixels[3] < 128 do
            data.transparentIndex = 0
        else do
            data.colors[0] = {pixels[offsets.red], pixels[offsets.green], pixels[offsets.blue]}
        data.count = 1
        finishPaletteResult(data)
        return true
    }

    // If the first row used every gray value, it determines the entire palette. The image's
    // bytes can serve as LZW dictionary literals; only literal codes written to the file need
    // translating to the palette order.
    func tryBuildFullGrayPalette(data: *PaletteData, image: Image, order: *[256] u8)->bool
    {
        let first = image.pixels.storage() + cast(u64, image.height - 1) * image.rowStride
        var seen:  [256] bool
        var count: u32
        for x in image.width
        {
            let gray = first[x]
            if seen[gray] do
                continue

            seen[gray]         = true
            order[][gray]      = cast(u8, count)
            data.colors[count] = {gray, gray, gray}
            count              += 1
            if count == MaxPaletteColors do
                break
        }

        if count != MaxPaletteColors do
            return false

        data.count = count
        data.indexes.grow(image.byteCount)
        data.indexes.count = image.byteCount
        var destination = data.indexes.storage()
        for y in image.height
        {
            let source = image.pixels.storage() + cast(u64, image.height - 1 - y) * image.rowStride
            Memory.copy(destination, source, image.rowStride)
            destination += image.rowStride
        }

        finishPaletteResult(data)
        return true
    }

    func(PixelBytes: u8, ReverseChannels: bool) tryBuildExactPalettePacked(data: *PaletteData, image: Image, hasTransparent: bool)->bool
    {
        let pixelCount = cast(u64, image.width) * image.height
        resetPaletteResult(data, pixelCount)

        // The entry stores a 24-bit RGB key and a one-based palette index.
        var colorMap: [PaletteMapSize] u64

        if hasTransparent
        {
            data.transparentIndex = 0
            data.count = 1
        }

        var target = data.indexes.storage()
        for y in image.height
        {
            var pix = image.pixels.storage() + cast(u64, (image.height - y - 1)) * image.rowStride
            for image.width
            {
                var paletteIndex: u8

                if (PixelBytes == 2 or PixelBytes == 4) and
                   hasTransparent and
                   pix[PixelBytes - 1] < 128
                {
                    paletteIndex = cast(u8, data.transparentIndex)
                }
                else
                {
                    // Keep RGB keys in the same order for RGB and BGR inputs.
                    var key: u32
                    #static if PixelBytes == 4
                    {
                        let packed = cast(const *u32, pix)[]
                        key = ReverseChannels ? Math.byteSwap(packed) >> 8 : packed & 0x00FFFFFF
                    }
                    elif PixelBytes == 3
                    {
                        let first = cast(const *u16, pix)[]
                        key = ReverseChannels ? (cast(u32, Math.byteSwap(first)) << 8) | pix[2] :
                                                cast(u32, first) | (cast(u32, pix[2]) << 16)
                    }
                    else do
                        key = pix[0]

                    var slot  = PixelBytes < 3 ? key : (key * #wrap 0x9E3779B9'u32) >> 23
                    var entry = colorMap[slot]
                    #static if PixelBytes >= 3
                    {
                        while entry and (entry >> 9) != key
                        {
                            slot  = (slot + 1) & (PaletteMapSize - 1)
                            entry = colorMap[slot]
                        }
                    }

                    if entry
                    {
                        paletteIndex = cast(u8, (entry & 0x1FF) - 1)
                    }
                    else
                    {
                        if data.count == MaxPaletteColors do
                            return false

                        paletteIndex = cast(u8, data.count)
                        #static if PixelBytes < 3
                        {
                            let gray = cast(u8, key)
                            data.colors[paletteIndex] = {gray, gray, gray}
                        }
                        else do
                            data.colors[paletteIndex] = {cast(u8, key >> 16), cast #wrap(u8, key >> 8), cast #wrap(u8, key)}
                        colorMap[slot] = (cast(u64, key) << 9) | (data.count + 1)
                        data.count    += 1
                    }
                }

                target[0] = paletteIndex
                target    += 1
                pix       += PixelBytes
            }
        }

        finishPaletteResult(data)
        return true
    }

    func tryBuildExactPalette(data: *PaletteData, image: Image, hasTransparent: bool)->bool
    {
        switch image.pixelFormat
        {
        case .Gray8:      return tryBuildExactPalettePacked'(1, false)(data, image, hasTransparent)
        case .GrayAlpha8: return tryBuildExactPalettePacked'(2, false)(data, image, hasTransparent)
        case .BGR8:       return tryBuildExactPalettePacked'(3, false)(data, image, hasTransparent)
        case .RGB8:       return tryBuildExactPalettePacked'(3, true)(data, image, hasTransparent)
        case .BGRA8:      return tryBuildExactPalettePacked'(4, false)(data, image, hasTransparent)
        default:         return tryBuildExactPalettePacked'(4, true)(data, image, hasTransparent)
        }
    }

    func histogramIndex(red, green, blue: u8)->u32 =>
        (cast(u32, red >> 3) << 10) | (cast(u32, green >> 3) << 5) | (blue >> 3)

    func(T) occupiedBox(region: ColorBox, histogram: const [*] HistogramCell'T)->ColorBox
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
                    result.pixels     += cast(u64, cell.count)
                    result.redTotal   += cast(u64, cell.red)
                    result.greenTotal += cast(u64, cell.green)
                    result.blueTotal  += cast(u64, cell.blue)
                }
            }
        }

        return result
    }

    func(T) splitBox(boxes: *[256] ColorBox, boxCount: u32, histogram: const [*] HistogramCell'T)->bool
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
                    slices[axisValue] += cast(u64, histogram[(red << 10) | (green << 5) | blue].count)
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

        boxes[][selected] = occupiedBox'T(left, histogram)
        boxes[][boxCount] = occupiedBox'T(right, histogram)
        return true
    }

    func(T) buildQuantizedPalette(data: *PaletteData, image: Image, hasTransparent, dither: bool)
    {
        let pixelCount = cast(u64, image.width) * image.height
        resetPaletteResult(data, pixelCount)

        // Five bits per channel keep the histogram bounded independently of image size.
        var histogram: Array'(HistogramCell'T)
        histogram.resize(32 * 32 * 32)
        let offsets = pixelChannelOffsets(image)
        for y in image.height
        {
            var pix = image.pixels.storage() + cast(u64, image.height - 1 - y) * image.rowStride
            for image.width
            {
                if not hasTransparent or pix[offsets.alpha] >= 128
                {
                    let r    = pix[offsets.red]
                    let g    = pix[offsets.green]
                    let b    = pix[offsets.blue]
                    let cell = &histogram[histogramIndex(r, g, b)]
                    #static if T == u32
                    {
                        let counters = cast([*] u32, cell)
                        let add      = cast(Math.Simd.U32x4, [1'u32, cast(u32, r), cast(u32, g), cast(u32, b)])
                        Math.Simd.store(counters, Math.Simd.load(counters) + add)
                    }
                    else
                    {
                        cell.count += 1
                        cell.red   += r
                        cell.green += g
                        cell.blue  += b
                    }
                }

                pix += image.bytesPerPixel
            }
        }

        var boxes: [256] ColorBox
        boxes[0] = occupiedBox'T(ColorBox{0, 31, 0, 31, 0, 31}, histogram.storage())
        var boxCount  = 1'u32
        let maxColors = MaxPaletteColors - (hasTransparent ? 1'u32 : 0'u32)
        while boxCount < maxColors and splitBox'T(&boxes, boxCount, histogram.storage()) do
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

        // A distance takes the high bits and the palette index breaks equal-distance ties.
        // Precompute each channel's contribution for four palette colors at a time.
        const Groups = MaxPaletteColors / 4
        var redCosts, greenCosts, blueCosts: [32, Groups] Math.Simd.S32x4
        let groups = (data.count - firstColor + 3) / 4
        for group in groups
        {
            var reds, greens, blues, indices: [4] s32
            for lane in 4
            {
                let index = Math.min(firstColor + group * 4 + lane, data.count - 1)
                let color = data.colors[index]
                reds[lane]    = color.r
                greens[lane]  = color.g
                blues[lane]   = color.b
                indices[lane] = cast(s32, index)
            }

            for coordinate in 32
            {
                let center = Math.Simd.splat(cast(s32, coordinate * 8 + 4))
                let dr     = center - cast(Math.Simd.S32x4, reds)
                let dg     = center - cast(Math.Simd.S32x4, greens)
                let db     = center - cast(Math.Simd.S32x4, blues)
                redCosts[coordinate, group]   = dr * dr * 256 + cast(Math.Simd.S32x4, indices)
                greenCosts[coordinate, group] = dg * dg * 256
                blueCosts[coordinate, group]  = db * db * 256
            }
        }

        // Each row of the grid tracks occupied blue bins for one red/green pair.
        // A zero border also makes reads outside the color cube empty.
        var occupied: [34, 34] u32
        if dither
        {
            for red in 32
            {
                for green in 32
                {
                    let index = (red << 10) | (green << 5)
                    var bits: u32
                    for blue in 32 do
                        bits |= cast(u32, histogram[index + blue].count != 0) << blue
                    occupied[red + 1, green + 1] = bits
                }
            }
        }

        var mapping: Array'u8
        mapping.resize(histogram.count)
        for red in 32
        {
            for green in 32
            {
                var needed: u32
                if dither
                {
                    let own = occupied[red + 1, green + 1]
                    // The same offset in [-8, 7] applies to all three channels. Each output
                    // bin can also be reached from the adjoining bins in either direction.
                    let lighter = own | occupied[red, green + 1] | occupied[red + 1, green] | occupied[red, green]
                    let darker  = own | occupied[red + 2, green + 1] | occupied[red + 1, green + 2] | occupied[red + 2, green + 2]
                    needed = lighter | (lighter << 1) | darker | (darker >> 1)
                    if not needed do
                        continue
                }

                var rgCosts: [Groups] Math.Simd.S32x4
                for group in groups do
                    rgCosts[group] = redCosts[red, group] + greenCosts[green, group]

                for blue in 32
                {
                    let index = (red << 10) | (green << 5) | blue
                    if dither ? not (needed & (1'u32 << blue)) : not histogram[index].count do
                        continue

                    var best = Math.Simd.splat(Swag.S32.Max)
                    for group in groups
                    {
                        let cost = rgCosts[group] + blueCosts[blue, group]
                        best = Math.Simd.select(cost < best, cost, best)
                    }

                    mapping[index] = cast #wrap(u8, Math.Simd.minimum(best))
                }
            }
        }

        var destination = 0'u64
        for y in image.height
        {
            var pix = image.pixels.storage() + cast(u64, image.height - 1 - y) * image.rowStride
            for x in image.width
            {
                if hasTransparent and pix[offsets.alpha] < 128
                {
                    data.indexes[destination] = 0
                }
                else
                {
                    let shift = dither ? Dither[((y & 3) << 2) | (x & 3)] : 0
                    let red   = cast(u8, Math.clamp(cast(s32, pix[offsets.red]) + shift, 0, 255))
                    let green = cast(u8, Math.clamp(cast(s32, pix[offsets.green]) + shift, 0, 255))
                    let blue  = cast(u8, Math.clamp(cast(s32, pix[offsets.blue]) + shift, 0, 255))
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
        if not tryBuildExactPalette(&result, image, hasTransparent)
        {
            // An individual cell's channel totals are bounded by 255 per pixel.
            if cast(u64, image.width) * image.height <= Swag.U32.Max / 255 do
                buildQuantizedPalette'u32(&result, image, hasTransparent, dither)
            else do
                buildQuantizedPalette'u64(&result, image, hasTransparent, dither)
        }
        return result
    }

    #[Inline]
    func rgbKey(red, green, blue: u8)->u32 =>
        (cast(u32, red) << 16) | (cast(u32, green) << 8) | blue

    #[Inline]
    func findColorSlot(table: const [*] u64, key: u32)->u32
    {
        var slot  = (key * #wrap 0x9E3779B9'u32) >> 23
        var entry = table[slot]
        while entry and (entry >> 9) != key
        {
            slot  = (slot + 1) & (PaletteMapSize - 1)
            entry = table[slot]
        }

        return slot
    }

    // Caches the first index for each color in the animation's global table.
    func buildColorIndexMap(table: const [..] u8)->Array'u64
    {
        var result: #returntype
        result.resize(PaletteMapSize)
        let storage = result.storage()
        for globalIndex in table.count / 3
        {
            let at   = globalIndex * 3
            let key  = rgbKey(table[at], table[at + 1], table[at + 2])
            let slot = findColorSlot(storage, key)
            if not storage[slot] do
                storage[slot] = (cast(u64, key) << 9) | (globalIndex + 1)
        }

        return result
    }

    // Rewrites frame indexes only when every frame colour exists in the shared colour table.
    func remapToColorTable(palette: *PaletteData, table: const [..] u8, colorIndices: const [..] u64)->bool
    {
        var mapping: [256] u8
        if colorIndices.count
        {
            let storage = colorIndices.buffer
            for local in palette.count
            {
                let color = palette.colors[local]
                let key   = rgbKey(color.r, color.g, color.b)
                let entry = storage[findColorSlot(storage, key)]
                if not entry do
                    return false
                mapping[local] = cast(u8, (entry & 0x1FF) - 1)
            }
        }
        else
        {
            let globalCount = table.count / 3
            for local in palette.count
            {
                let color = palette.colors[local]
                var found = false
                for globalIndex in globalCount
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
        }

        for local in palette.count
        {
            if mapping[local] == local do
                continue
            for i in palette.indexes.count do
                palette.indexes[i] = mapping[palette.indexes[i]]
            break
        }

        return true
    }

    func writeColorTable(result: *ConcatBuffer, palette: PaletteData)
    {
        let tableSize = 1'u32 << palette.tableBits
        var output    = result.reserveInPlace(cast(u64, tableSize) * 3)
        for i in palette.count
        {
            let color = palette.colors[i]
            output[0] = color.r
            output[1] = color.g
            output[2] = color.b
            output    += 3
        }

        Memory.clear(output, cast(u64, tableSize - palette.count) * 3)
    }
}
