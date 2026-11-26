//! Format: GPU block-compression reconstruction shared by texture containers.
//! Supported: BC1, BC2, BC3, BC4 unsigned, and BC5 unsigned blocks.
//! Not supported: Signed BC4/BC5, BC6H, BC7, ETC, ASTC, or encoder-side compression.
//! Role: This file turns independently stored 4x4 GPU blocks into displayable RGBA pixels.
//
#global namespace TextureBlocks

using Core, Core.Errors, Core.Math

internal enum Format
{
    None
    BC1
    BC2
    BC3
    BC4
    BC5
}

internal func blockBytes(format: Format)->u64
{
    switch #complete format
    {
    case .None:            unreachable
    case .BC1, .BC4:       return 8
    case .BC2, .BC3, .BC5: return 16
    }
}

#[Swag.Inline]
func readEndpoint(source: const [*] u8)->u16
{
    let value = cast(const *u16, source)[]
    return Core.BIG_ENDIAN ? Swag.byteSwap(value) : value
}

#[Swag.Inline]
func expandRgb565(value: u16)->u32
{
    let red   = cast(u32, value >> 11)
    let green = cast(u32, ((value >> 5) & 63))
    let blue  = cast(u32, (value & 31))
    return 0xFF000000 | (red << 3) | (red >> 2) |
           (green << 10) | ((green >> 4) << 8) |
           (blue << 19) | ((blue >> 2) << 16)
}

#[Swag.Inline]
func loadColorIndices(source: const [*] u8)->u32
{
    let indices = cast(const *u32, source)[]
    return Core.BIG_ENDIAN ? Swag.byteSwap(indices) : indices
}

#[Swag.Inline]
func colorPalette(result: *[4] u32, source: const [*] u8, forceFourColors: bool)
{
    let endpointA = readEndpoint(source)
    let endpointB = readEndpoint(source + 2)
    let a         = expandRgb565(endpointA)
    let b         = expandRgb565(endpointB)
    result[][0] = a
    result[][1] = b
    if forceFourColors or endpointA > endpointB
    {
        let first  = Simd.splat(a)
        let second = Simd.splat(b)
        let zero   = Simd.splat(0_u8)
        let ab     = cast #bit(Simd.U8x16, Simd.interleaveLow(first, second))
        let ba     = cast #bit(Simd.U8x16, Simd.interleaveLow(second, first))
        let words  = cast #bit(Simd.U16x8, Simd.interleaveLow(ab, zero))
        let other  = cast #bit(Simd.U16x8, Simd.interleaveLow(ba, zero))
        let sums   = words + words + other

        // The high product divides both RGB sums by three exactly through 765.
        let values       = cast #bit(Simd.S16x8, Simd.mulHigh(sums, Simd.splat(21846_u16)))
        let interpolated = cast #bit(Simd.U32x4, Simd.packUnsigned(values, values))
        result[][2] = interpolated[0]
        result[][3] = interpolated[1]
    }
    else
    {
        result[][2] = (a & b) + (((a ^ b) & 0xFEFEFEFE_u32) >> 1)
        result[][3] = 0
    }
}

#[Swag.Inline]
func alphaPalette(result: *[8] u8, source: const [*] u8)
{
    const WeightsA7 = cast(Simd.U16x8, [7_u16, 0, 6, 5, 4, 3, 2, 1])
    const WeightsB7 = cast(Simd.U16x8, [0_u16, 7, 1, 2, 3, 4, 5, 6])
    const WeightsA5 = cast(Simd.U16x8, [5_u16, 0, 4, 3, 2, 1, 0, 0])
    const WeightsB5 = cast(Simd.U16x8, [0_u16, 5, 1, 2, 3, 4, 0, 0])
    const LastValue = cast(Simd.U16x8, [0_u16, 0, 0, 0, 0, 0, 0, 255])
    let a = Simd.splat(cast(u16, source[0]))
    let b = Simd.splat(cast(u16, source[1]))

    // The high half of the scaled product divides exactly over these byte sums.
    let words = source[0] > source[1]
                ? Simd.mulHigh(a * WeightsA7 + b * WeightsB7, Simd.splat(9363_u16))
                : Simd.mulHigh(a * WeightsA5 + b * WeightsB5, Simd.splat(13108_u16)) | LastValue
    let values = cast #bit(Simd.S16x8, words)
    cast(*u64, result)[] = cast #bit(Simd.U64x2, Simd.packUnsigned(values, values))[0]
}

#[Swag.Inline]
func loadAlphaBits(source: const [*] u8)->u64
{
    let indices = cast(const *u64, source)[]
    return Core.BIG_ENDIAN ? Swag.byteSwap(indices) : indices
}

// Map the four two-bit color indices in each encoded row to RGBA byte offsets.
#[Swag.ConstExpr]
func bc1RowShuffles()->[256] Simd.U8x16
{
    var result: #returntype
    for row in result.count
    {
        var shuffle: [16] u8
        for lane in shuffle.count
        {
            let index = (row >> ((lane / 4) * 2)) & 3
            shuffle[lane] = cast(u8, (index * 4 + lane % 4))
        }

        result[row] = cast(Simd.U8x16, shuffle)
    }

    return result
}

const ColorRowShuffles = bc1RowShuffles()

#[Swag.Inline]
func alphaRow(palette: *[8] u8, indices: u16)->Simd.U32x4
{
    // Bring each three-bit index to bit 9 in two lanes and replicate the key over RGBA.
    const Shift = cast(Simd.U16x8, [512_u16, 512, 64, 64, 8, 8, 1, 1])
    let keys   = ((Simd.splat(indices) * Shift) >> 9) & 7_u16
    let lookup = cast #bit(Simd.U8x16, Simd.splat(cast(*u64, palette)[]))
    return cast #bit(Simd.U32x4, Simd.shuffle(lookup, cast #bit(Simd.U8x16, (keys * 257_u16))))
}

#[Swag.Inline]
private func alphaBlock(palette: const *[8] u8, indices: u64)->Simd.U8x16
{
    // Each group uses the same three source bytes, laid out as eight little-endian words.
    const FirstWords  = cast(Simd.U8x16, [0_u8, 1, 0, 1, 0, 1, 1, 2, 1, 2, 1, 2, 2, 3, 2, 3])
    const SecondWords = cast(Simd.U8x16, [3_u8, 4, 3, 4, 3, 4, 4, 5, 4, 5, 4, 5, 5, 6, 5, 6])
    const Shifts      = cast(Simd.U16x8, [8192_u16, 1024, 128, 4096, 512, 64, 2048, 256])
    let packed = cast #bit(Simd.U8x16, Simd.splat(indices))
    let first  = cast #bit(Simd.U16x8, Simd.shuffle(packed, FirstWords))
    let second = cast #bit(Simd.U16x8, Simd.shuffle(packed, SecondWords))
    let low    = cast #bit(Simd.S16x8, ((first * Shifts) >> 13))
    let high   = cast #bit(Simd.S16x8, ((second * Shifts) >> 13))
    let lookup = cast #bit(Simd.U8x16, Simd.splat(cast(const *u64, palette)[]))
    return Simd.shuffle(lookup, Simd.packUnsigned(low, high))
}

#[Swag.Inline]
private func(FMT: Format) storeChannelBlock(target: [*] u32, rowStep: s64, red, green: Simd.U8x16)
{
    let opaque = Simd.splat(255_u8)
    let blue   = FMT == .BC4 ? red : Simd.splat(0_u8)
    let lowRG  = cast #bit(Simd.U16x8, Simd.interleaveLow(red, green))
    let highRG = cast #bit(Simd.U16x8, Simd.interleaveHigh(red, green))
    let lowBA  = cast #bit(Simd.U16x8, Simd.interleaveLow(blue, opaque))
    let highBA = cast #bit(Simd.U16x8, Simd.interleaveHigh(blue, opaque))
    Simd.store(target, cast #bit(Simd.U32x4, Simd.interleaveLow(lowRG, lowBA)))
    Simd.store(target + rowStep, cast #bit(Simd.U32x4, Simd.interleaveHigh(lowRG, lowBA)))
    Simd.store(target + 2 * rowStep, cast #bit(Simd.U32x4, Simd.interleaveLow(highRG, highBA)))
    Simd.store(target + 3 * rowStep, cast #bit(Simd.U32x4, Simd.interleaveHigh(highRG, highBA)))
}

#[Swag.Inline]
private func explicitAlphaBlock(indices: u64)->Simd.U8x16
{
    let bytes   = cast #bit(Simd.U8x16, Simd.splat(indices))
    let low     = bytes & 15_u8
    let high    = cast #bit(Simd.U8x16, (cast #bit(Simd.U16x8, bytes) >> 4)) & 15_u8
    let nibbles = Simd.interleaveLow(low, high)
    return nibbles | cast #bit(Simd.U8x16, (cast #bit(Simd.U16x8, nibbles) << 4))
}

private func(FMT: Format) decodeBlockRange(image: *Image, source: const [*] u8, columns, first, end, oneBlock: u64, sourceTopDown: bool)
{
    let width     = cast(u64, image.width)
    let height    = cast(u64, image.height)
    let pixels    = cast([*] u32, image.pixels.storage())
    let rowStride = cast(s64, (image.rowStride / 4))
    let rowStep   = sourceTopDown ? -rowStride : rowStride
    for blockY in first until end
    {
        let firstY    = blockY * 4
        let countY    = Math.min(4_u64, height - firstY)
        let sourceRow = source + blockY * columns * oneBlock
        let targetY   = sourceTopDown ? height - firstY - 1 : firstY
        let targetRow = pixels + targetY * rowStride
        for blockX in columns
        {
            let firstX = blockX * 4
            let countX = Math.min(4_u64, width - firstX)
            let block  = sourceRow + blockX * oneBlock

            var colors:                      [4] u32
            var firstPalette, secondPalette: [8] u8
            var firstIndices, secondIndices: u64
            var colorIndices:                u32
            #static if FMT == .BC1 or FMT == .BC2 or FMT == .BC3
            {
                let colorBlock = FMT == .BC1 ? block : block + 8
                colorPalette(&colors, colorBlock, FMT != .BC1)
                colorIndices = loadColorIndices(colorBlock + 4)
            }

            #static if FMT == .BC2
            {
                firstIndices = loadAlphaBits(block)
            }
            else if FMT == .BC3 or FMT == .BC4 or FMT == .BC5
            {
                alphaPalette(&firstPalette, block)
                firstIndices = loadAlphaBits(block) >> 16
            }

            #static if FMT == .BC5
            {
                alphaPalette(&secondPalette, block + 8)
                secondIndices = loadAlphaBits(block + 8) >> 16
            }

            #static if FMT == .BC4 or FMT == .BC5
            {
                if countX == 4 and countY == 4
                {
                    let red = alphaBlock(&firstPalette, firstIndices)
                    #static if FMT == .BC4
                    {
                        storeChannelBlock!{Format.BC4}(targetRow + firstX, rowStep, red, red)
                    }
                    else
                    {
                        let green = alphaBlock(&secondPalette, secondIndices)
                        storeChannelBlock!{Format.BC5}(targetRow + firstX, rowStep, red, green)
                    }

                    continue
                }
            }

            var blockAlpha: Simd.U8x16
            #static if FMT == .BC2 or FMT == .BC3
            {
                if countX == 4
                {
                    #static if FMT == .BC2
                    {
                        blockAlpha = explicitAlphaBlock(firstIndices)
                    }
                    else
                    {
                        blockAlpha = alphaBlock(&firstPalette, firstIndices)
                    }
                }
            }

            // Clip partial blocks once and write each visible row as packed RGBA words.
            for row in countY
            {
                let target = targetRow + cast(s64, row) * rowStep + firstX
                if countX == 4
                {
                    var rgba: Simd.U32x4
                    #static if FMT == .BC4 or FMT == .BC5
                    {
                        let red = alphaRow(&firstPalette, cast(u16, ((firstIndices >> (row * 12)) & 0xFFF)))
                        #static if FMT == .BC4
                        {
                            rgba = red | 0xFF000000_u32
                        }
                        else
                        {
                            let green = alphaRow(&secondPalette, cast(u16, ((secondIndices >> (row * 12)) & 0xFFF)))
                            rgba = (red & 255_u32) | (green & 0xFF00_u32) | 0xFF000000_u32
                        }
                    }
                    else
                    {
                        let palette = Simd.load(cast(const [*] u8, &colors[0]))
                        let indices = (colorIndices >> (row * 8)) & 255
                        rgba = cast #bit(Simd.U32x4, Simd.shuffle(palette, ColorRowShuffles[indices]))
                        #static if FMT == .BC2 or FMT == .BC3
                        {
                            const AlphaByteOffsets = cast(Simd.U8x16, [128_u8, 128, 128, 0, 128, 128, 128, 1, 128, 128, 128, 2, 128, 128, 128, 3])
                            let offsets = AlphaByteOffsets + Simd.splat(cast(u8, row * 4))
                            let alpha   = cast #bit(Simd.U32x4, Simd.shuffle(blockAlpha, offsets))
                            rgba = (rgba & 0x00FFFFFF_u32) | alpha
                        }
                    }

                    Simd.store(target, rgba)
                    continue
                }

                for column in countX
                {
                    let pixel = row * 4 + column
                    #static if FMT == .BC4
                    {
                        let value = cast(u32, firstPalette[(firstIndices >> (pixel * 3)) & 7])
                        target[column] = 0xFF000000 | (value * 0x010101)
                    }
                    else if FMT == .BC5
                    {
                        let red   = cast(u32, firstPalette[(firstIndices >> (pixel * 3)) & 7])
                        let green = cast(u32, secondPalette[(secondIndices >> (pixel * 3)) & 7])
                        target[column] = 0xFF000000 | red | (green << 8)
                    }
                    else
                    {
                        let rgb = colors[(colorIndices >> (pixel * 2)) & 3]
                        #static if FMT == .BC2
                        {
                            let alpha = cast(u32, ((firstIndices >> (pixel * 4)) & 15)) * 17
                            target[column] = (rgb & 0x00FFFFFF) | (alpha << 24)
                        }
                        else if FMT == .BC3
                        {
                            let alpha = cast(u32, firstPalette[(firstIndices >> (pixel * 3)) & 7])
                            target[column] = (rgb & 0x00FFFFFF) | (alpha << 24)
                        }
                        else
                        {
                            target[column] = rgb
                        }
                    }
                }
            }
        }
    }
}

private const ParallelOutputBytes = 64_u64 * 1024 * 1024

private func repeatedTextureBlock(source: const [*] u8, blockCount, blockSize: u64)->bool
{
    let size    = blockCount * blockSize
    let last    = source + size - blockSize
    var pattern = Simd.load(source)
    if blockSize == 8
    {
        let word = cast(const *u64, source)[]
        if cast(const *u64, last)[] != word
        {
            return false
        }

        pattern = cast #bit(Simd.U8x16, Simd.splat(word))
    }
    else if not Simd.allTrue(Simd.load(last) == pattern)
    {
        return false
    }

    var offset = blockSize == 8 ? 0_u64 : 16_u64
    while size - offset >= 16
    {
        if not Simd.allTrue(Simd.load(source + offset) == pattern)
        {
            return false
        }

        offset += 16
    }

    // A remaining eight-byte block was compared with the pattern above.
    return true
}

private func(FMT: Format) fillRepeatedTexture(image: *Image, source: const [*] u8, blockSize: u64, sourceTopDown: bool)
{
    var tile = Image.create(4, 4, .RGBA8)
    decodeBlockRange!{FMT}(&tile, source, 1, 0, 1, blockSize, false)
    let width     = cast(u64, image.width)
    let height    = cast(u64, image.height)
    let rowBytes  = cast(u64, image.rowStride)
    let pixels    = image.pixels.storage()
    let firstRows = Math.min(height, 4_u64)
    for y in firstRows
    {
        let tileRow = sourceTopDown ? (height - y - 1) & 3 : y
        let sample  = tile.pixels.storage() + tileRow * 16
        let pattern = Simd.load(sample)
        let target  = pixels + y * rowBytes
        for i in width / 4
        {
            Simd.store(target + i * 16, pattern)
        }

        if width & 3
        {
            Memory.copy(target + (width & ~3_u64) * 4, sample, (width & 3) * 4)
        }
    }

    let workers = image.byteCount >= ParallelOutputBytes ? cast(u64, Swag.workerCount()) : 0
    if workers > 1 and height - firstRows >= 8
    {
        let remaining = height - firstRows
        let batchRows = (remaining + workers - 1) / workers
        let batches   = (remaining + batchRows - 1) / batchRows
        parallel for |pixels, rowBytes, firstRows, height, batchRows| batch in batches
        {
            let start = firstRows + batch * batchRows
            let end   = Math.min(start + batchRows, height)
            for y in start until end
            {
                Memory.copy(pixels + y * rowBytes, pixels + (y & 3) * rowBytes, rowBytes)
            }
        }
    }
    else
    {
        for y in firstRows until height
        {
            Memory.copy(pixels + y * rowBytes, pixels + (y & 3) * rowBytes, rowBytes)
        }
    }
}

private func(FMT: Format) decodeBlocks(image: *Image, source: const [*] u8, columns, rows, oneBlock: u64, sourceTopDown: bool)
{
    // Scanning encoded blocks costs much less than reconstructing identical rows.
    if image.byteCount >= 1024 * 1024 and repeatedTextureBlock(source, columns * rows, oneBlock)
    {
        fillRepeatedTexture!{FMT}(image, source, oneBlock, sourceTopDown)
        return
    }

    if image.byteCount >= ParallelOutputBytes and rows >= 8
    {
        let workers = cast(u64, Swag.workerCount())
        if workers > 1
        {
            // Each batch writes separate rows in either storage orientation.
            let rowsPerBatch = (rows + workers - 1) / workers
            let batches      = (rows + rowsPerBatch - 1) / rowsPerBatch
            parallel for |image, source, columns, rows, oneBlock, sourceTopDown, rowsPerBatch| batch in batches
            {
                let first = batch * rowsPerBatch
                let end   = Math.min(first + rowsPerBatch, rows)
                decodeBlockRange!{FMT}(image, source, columns, first, end, oneBlock, sourceTopDown)
            }

            return
        }
    }

    decodeBlockRange!{FMT}(image, source, columns, 0, rows, oneBlock, sourceTopDown)
}

internal func decode(image: *Image, source: const [..] u8, format: Format, sourceTopDown = true) fail
{
    let columns  = (cast(u64, image.width) + 3) / 4
    let rows     = (cast(u64, image.height) + 3) / 4
    let oneBlock = blockBytes(format)
    if columns > Swag.U64.Max / rows or columns * rows > source.count / oneBlock
    {
        fail InvalidFormatError{"block-compressed texture data is truncated"}
    }

    switch #complete format
    {
    case .None: unreachable
    case .BC1:  decodeBlocks!{.BC1}(image, source.buffer, columns, rows, oneBlock, sourceTopDown)
    case .BC2:  decodeBlocks!{.BC2}(image, source.buffer, columns, rows, oneBlock, sourceTopDown)
    case .BC3:  decodeBlocks!{.BC3}(image, source.buffer, columns, rows, oneBlock, sourceTopDown)
    case .BC4:  decodeBlocks!{.BC4}(image, source.buffer, columns, rows, oneBlock, sourceTopDown)
    case .BC5:  decodeBlocks!{.BC5}(image, source.buffer, columns, rows, oneBlock, sourceTopDown)
    }
}
