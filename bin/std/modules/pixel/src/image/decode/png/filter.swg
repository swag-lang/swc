//! Format: Portable Network Graphics (PNG) decoder component.
//! Supported: Standard grayscale, true-color, indexed, grayscale-alpha, and true-color-alpha images, including Adam7 and supported metadata.
//! Not supported: APNG animation, unknown critical chunks, and images requiring more than 2 GiB of decoded storage.
//! Role: This file owns PNG row unfiltering.
//
// @LICENCE: BSD-2-Clause
// @ORIGIN: libspng, https://github.com/randy408/libspng
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRD_PARTY_NOTICES.md#libspng

#global namespace Png

using Core, Core.Errors

const Expand4LowBytes  = cast(Math.Simd.U8x16) [0'u8, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7]
const Expand4HighBytes = cast(Math.Simd.U8x16) [8'u8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15]
const Expand4HighMask  = cast(Math.Simd.U8x16) [15'u8, 0, 15, 0, 15, 0, 15, 0, 15, 0, 15, 0, 15, 0, 15, 0]
const Expand4LowMask   = cast(Math.Simd.U8x16) [0'u8, 15, 0, 15, 0, 15, 0, 15, 0, 15, 0, 15, 0, 15, 0, 15]
const Expand1Bytes     = cast(Math.Simd.U8x16) [0'u8, 2, 4, 6, 8, 10, 12, 14, 1, 3, 5, 7, 9, 11, 13, 15]
const Expand1Bits      = cast(Math.Simd.U8x16) [128'u8, 64, 32, 16, 8, 4, 2, 1, 128, 64, 32, 16, 8, 4, 2, 1]
const Expand2Bytes     = cast(Math.Simd.U8x16) [0'u8, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15]
const ShiftBytes2      = cast(Math.Simd.U8x16) [0x80'u8, 0x80, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]
const ShiftBytes4      = cast(Math.Simd.U8x16) [0x80'u8, 0x80, 0x80, 0x80, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
const ShiftBytes8      = cast(Math.Simd.U8x16) [0x80'u8, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0x80, 0, 1, 2, 3, 4, 5, 6, 7]

#[Swag.Inline]
func expand4Half(value, table: Math.Simd.U8x16, multiplier: u8)->Math.Simd.U8x16
{
    let duplicated = Math.Simd.shuffle(value, table)
    let shifted    = cast #bit(Math.Simd.U8x16) (cast #bit(Math.Simd.U16x8) duplicated >> 4)
    let nibbles    = (shifted & Expand4HighMask) | (duplicated & Expand4LowMask)
    if multiplier == 1 do
        return nibbles
    return cast #bit(Math.Simd.U8x16) (cast #bit(Math.Simd.U16x8) nibbles * cast(u16) multiplier)
}

func defilterUpRow(source, previous: const [*] u8, destination: [*] u8, count: u64)
{
    const VectorBytes = #sizeof(Math.Simd.U8x16)
    const BatchBytes  = 4 * VectorBytes
    var offset = 0'u64
    while count - offset >= BatchBytes
    {
        Math.Simd.store(destination + offset, Math.Simd.load(source + offset) + Math.Simd.load(previous + offset))
        Math.Simd.store(destination + offset + VectorBytes, Math.Simd.load(source + offset + VectorBytes) + Math.Simd.load(previous + offset + VectorBytes))
        Math.Simd.store(destination + offset + 2 * VectorBytes, Math.Simd.load(source + offset + 2 * VectorBytes) + Math.Simd.load(previous + offset + 2 * VectorBytes))
        Math.Simd.store(destination + offset + 3 * VectorBytes, Math.Simd.load(source + offset + 3 * VectorBytes) + Math.Simd.load(previous + offset + 3 * VectorBytes))
        offset += BatchBytes
    }

    while count - offset >= VectorBytes
    {
        Math.Simd.store(destination + offset, Math.Simd.load(source + offset) + Math.Simd.load(previous + offset))
        offset += VectorBytes
    }

    while offset < count
    {
        destination[offset] = cast #bit(u8) (source[offset] + #wrap previous[offset])
        offset              += 1
    }
}

func expand4Row(source: const [*] u8, destination: [*] u8, sampleCount: u64, multiplier: u8)
{
    var src       = source
    var dst       = destination
    var remaining = sampleCount
    while remaining >= 32
    {
        let value = Math.Simd.load(src)
        Math.Simd.store(dst, expand4Half(value, Expand4LowBytes, multiplier))
        Math.Simd.store(dst + 16, expand4Half(value, Expand4HighBytes, multiplier))
        src       += 16
        dst       += 32
        remaining -= 32
    }

    while remaining >= 2
    {
        let value = src[0]
        dst[0]    = cast(u8) (value >> 4) * multiplier
        dst[1]    = cast(u8) (value & 15) * multiplier
        src       += 1
        dst       += 2
        remaining -= 2
    }

    if remaining do
        dst[0] = cast(u8) (src[0] >> 4) * multiplier
}

func expand1Row(source: const [*] u8, destination: [*] u8, sampleCount: u64, multiplier: u8)
{
    var src       = source
    var dst       = destination
    var remaining = sampleCount
    while remaining >= 16
    {
        let packed     = cast(u16) src[0] | (cast(u16) src[1] << 8)
        let duplicated = Math.Simd.shuffle(cast #bit(Math.Simd.U8x16) Math.Simd.splat(packed), Expand1Bytes)
        var expanded   = (duplicated & Expand1Bits) == Expand1Bits
        if multiplier == 1 do
            expanded &= Math.Simd.splat(1'u8)
        Math.Simd.store(dst, expanded)
        src       += 2
        dst       += 16
        remaining -= 16
    }

    while remaining >= 8
    {
        let value = src[0]
        dst[0]    = cast(u8) (value >> 7) * multiplier
        dst[1]    = cast(u8) ((value >> 6) & 1) * multiplier
        dst[2]    = cast(u8) ((value >> 5) & 1) * multiplier
        dst[3]    = cast(u8) ((value >> 4) & 1) * multiplier
        dst[4]    = cast(u8) ((value >> 3) & 1) * multiplier
        dst[5]    = cast(u8) ((value >> 2) & 1) * multiplier
        dst[6]    = cast(u8) ((value >> 1) & 1) * multiplier
        dst[7]    = cast(u8) (value & 1) * multiplier
        src       += 1
        dst       += 8
        remaining -= 8
    }

    if remaining
    {
        let value = src[0]
        for i in remaining do
            dst[i] = cast(u8) ((value >> (7 - i)) & 1) * multiplier
    }
}

func expand2Row(source: const [*] u8, destination: [*] u8, sampleCount: u64, multiplier: u8)
{
    var src       = source
    var dst       = destination
    var remaining = sampleCount
    while remaining >= 16
    {
        let packed   = cast(u32) src[0] | (cast(u32) src[1] << 8) | (cast(u32) src[2] << 16) | (cast(u32) src[3] << 24)
        let bytes    = cast #bit(Math.Simd.U8x16) Math.Simd.splat(packed)
        let words    = cast #bit(Math.Simd.U32x4) Math.Simd.shuffle(bytes, Expand2Bytes)
        var expanded = ((words >> 6) & 0x0000_0003'u32) |
                       ((words >> 4) & 0x0000_0300'u32) |
                       ((words >> 2) & 0x0003_0000'u32) |
                       (words & 0x0300_0000'u32)
        if multiplier != 1 do
            expanded *= cast(u32) multiplier
        Math.Simd.store(dst, cast #bit(Math.Simd.U8x16) expanded)
        src       += 4
        dst       += 16
        remaining -= 16
    }

    while remaining >= 4
    {
        let value = src[0]
        dst[0]    = cast(u8) (value >> 6) * multiplier
        dst[1]    = cast(u8) ((value >> 4) & 3) * multiplier
        dst[2]    = cast(u8) ((value >> 2) & 3) * multiplier
        dst[3]    = cast(u8) (value & 3) * multiplier
        src       += 1
        dst       += 4
        remaining -= 4
    }

    if remaining
    {
        let value = src[0]
        for i in remaining do
            dst[i] = cast(u8) ((value >> (6 - 2 * i)) & 3) * multiplier
    }
}

func defilterSubRow(source: const [*] u8, destination: [*] u8, count, bytesPerPixel: u64)
{
    var offset = 0'u64
    while offset < bytesPerPixel and offset < count
    {
        destination[offset] = source[offset]
        offset              += 1
    }

    switch bytesPerPixel
    {
    case 2:
        while count - offset >= 16
        {
            var values = Math.Simd.load(source + offset)
            values += Math.Simd.shuffle(values, ShiftBytes2)
            values += Math.Simd.shuffle(values, ShiftBytes4)
            values += Math.Simd.shuffle(values, ShiftBytes8)
            let carry = (cast(const [*] u16) (destination + offset - 2))[0]
            values += cast #bit(Math.Simd.U8x16) Math.Simd.splat(carry)
            Math.Simd.store(destination + offset, values)
            offset += 16
        }

    case 4:
        while count - offset >= 16
        {
            var values = Math.Simd.load(source + offset)
            values += Math.Simd.shuffle(values, ShiftBytes4)
            values += Math.Simd.shuffle(values, ShiftBytes8)
            let carry = (cast(const [*] u32) (destination + offset - 4))[0]
            values += cast #bit(Math.Simd.U8x16) Math.Simd.splat(carry)
            Math.Simd.store(destination + offset, values)
            offset += 16
        }

    case 8:
        while count - offset >= 16
        {
            var values = Math.Simd.load(source + offset)
            values += Math.Simd.shuffle(values, ShiftBytes8)
            let carry = (cast(const [*] u64) (destination + offset - 8))[0]
            values += cast #bit(Math.Simd.U8x16) Math.Simd.splat(carry)
            Math.Simd.store(destination + offset, values)
            offset += 16
        }
    }

    while offset < count
    {
        destination[offset] = cast #bit(u8) (source[offset] + #wrap destination[offset - bytesPerPixel])
        offset              += 1
    }
}

func filterPaeth(left, up, upLeft: u8)->u8
{
    let aa = cast(s16) left
    let bb = cast(s16) up
    let cc = cast(s16) upLeft
    let p  = aa + bb - cc
    let pa = Math.abs(cast(s16) (p - aa))
    let pb = Math.abs(cast(s16) (p - bb))
    let pc = Math.abs(cast(s16) (p - cc))
    if pa <= pb and pa <= pc do
        return left
    if pb <= pc do
        return up
    return upLeft
}

// Reads one pixel as sixteen-bit lanes, one lane per byte.
//
// A PNG pixel is at most eight bytes wide whatever the bit depth, so the low half of a
// vector always holds a whole one, and an eight-byte read never leaves the row.
#[Swag.Inline]
func loadPixelLanes(source: const [*] u8)->Math.Simd.S16x8
{
    let bytes = cast #bit(Math.Simd.U8x16) Math.Simd.splat((cast(const [*] u64) source)[0])
    return cast #bit(Math.Simd.S16x8) Math.Simd.widenLow(bytes)
}

// Adds two lane-per-byte pixels the way PNG reconstruction does, modulo 256.
//
// Every lane holds a byte in its low half and zero above it, so adding as bytes wraps each
// channel on its own and leaves the lanes in that same shape.
#[Swag.Inline]
func addPixelLanes(x, y: Math.Simd.S16x8)->Math.Simd.S16x8 => cast #bit(Math.Simd.S16x8) (cast #bit(Math.Simd.U8x16) x + cast #bit(Math.Simd.U8x16) y)

// Picks the Paeth predictor per lane, with the same ties as the scalar rule.
//
// The three distances reduce to differences of the neighbours, which keeps every lane inside
// 's16': 'p - left' is 'up - upLeft', 'p - up' is 'left - upLeft', and 'p - upLeft' is their
// sum. Taking the smallest and preferring left, then up, reproduces the ordered comparisons.
#[Swag.Inline]
func paethPredict(left, up, upLeft: Math.Simd.S16x8)->Math.Simd.S16x8
{
    let deltaUp        = up - upLeft
    let deltaLeft      = left - upLeft
    let distanceLeft   = Math.abs(deltaUp)
    let distanceUp     = Math.abs(deltaLeft)
    let distanceUpLeft = Math.abs(deltaUp + deltaLeft)
    let smallest       = Math.min(distanceUpLeft, Math.min(distanceLeft, distanceUp))
    return Math.Simd.select(smallest == distanceLeft, left, Math.Simd.select(smallest == distanceUp, up, upLeft))
}

// Reverses the Average predictor, carrying the reconstructed left pixel in a register.
//
// PNG filters a row byte by byte and every byte depends on the byte one pixel to its left,
// which the scalar form reads back from memory the instant it writes it. Widening a whole
// pixel to one lane per byte carries that dependency in a register instead, so a row costs
// one step per pixel rather than one per channel.
//
// A step writes eight bytes whatever the pixel is wide: the bytes past the current pixel are
// rewritten by the following step, and the scalar tail rewrites the last of them.
func defilterAverageRow(source, previous: const [*] u8, destination: [*] u8, count, bytesPerPixel: u64)
{
    var offset = 0'u64
    if bytesPerPixel >= 2
    {
        var left = Math.Simd.splat(0's16)
        while offset + 8 <= count
        {
            let up        = loadPixelLanes(previous + offset)
            let delta     = loadPixelLanes(source + offset)
            let recovered = addPixelLanes(delta, (left + up) >> 1)
            Math.Simd.storeLow8(destination + offset, Math.Simd.packUnsigned(recovered, recovered))
            left   = recovered
            offset += bytesPerPixel
        }
    }

    while offset < count
    {
        let left    = offset >= bytesPerPixel ? destination[offset - bytesPerPixel] : 0'u8
        let average = cast(u8) ((cast(u16) previous[offset] + left) >> 1)
        destination[offset] = cast #bit(u8) (source[offset] + #wrap average)
        offset              += 1
    }
}

// Reverses the Paeth predictor, carrying the reconstructed left pixel in a register.
//
// Same shape as [[Png.defilterAverageRow]], and for the same reason: the predictor of a byte
// needs the byte one pixel to its left, which the scalar form has only just stored.
func defilterPaethRow(source, previous: const [*] u8, destination: [*] u8, count, bytesPerPixel: u64)
{
    var offset = 0'u64
    if bytesPerPixel >= 2
    {
        var left   = Math.Simd.splat(0's16)
        var upLeft = Math.Simd.splat(0's16)
        while offset + 8 <= count
        {
            let up        = loadPixelLanes(previous + offset)
            let delta     = loadPixelLanes(source + offset)
            let recovered = addPixelLanes(delta, paethPredict(left, up, upLeft))
            Math.Simd.storeLow8(destination + offset, Math.Simd.packUnsigned(recovered, recovered))
            left   = recovered
            upLeft = up
            offset += bytesPerPixel
        }
    }

    while offset < count
    {
        let left      = offset >= bytesPerPixel ? destination[offset - bytesPerPixel] : 0'u8
        let upLeft    = offset >= bytesPerPixel ? previous[offset - bytesPerPixel] : 0'u8
        let predictor = filterPaeth(left, previous[offset], upLeft)
        destination[offset] = cast #bit(u8) (source[offset] + #wrap predictor)
        offset              += 1
    }
}

impl Decoder
{
    mtd expand8(width, height: u32, output: [*] u8)
    {
        let rowStrideIn  = .getStrideIn(width)
        let rowStrideOut = .inChannels * width

        var orgDest   = output
        let srcOffset = rowStrideOut - rowStrideIn

        // 1 bit => 8 bits
        if .header.bitDepth == 1
        {
            let mul = .paletteCount ? 1 : 255
            for height
            {
                let dest = orgDest
                orgDest += rowStrideOut
                expand1Row(dest + srcOffset, dest, rowStrideOut, cast(u8) mul)
            }
        }

        // 2 bits => 8 bits
        elif .header.bitDepth == 2
        {
            let mul = .paletteCount ? 1 : 85
            for height
            {
                let dest = orgDest
                orgDest += rowStrideOut
                expand2Row(dest + srcOffset, dest, rowStrideOut, cast(u8) mul)
            }
        }

        // 4 bits => 8 bits
        elif .header.bitDepth == 4
        {
            let mul = .paletteCount ? 1 : 17
            for height
            {
                let dest = orgDest
                orgDest += rowStrideOut
                expand4Row(dest + srcOffset, dest, rowStrideOut, cast(u8) mul)
            }
        }
    }

    mtd getStrideIn(width: u32)->u64
    {
        if .header.bitDepth < 8 do
            return cast(u64) ((.inChannels * width * .header.bitDepth) + 7) / 8
        return cast(u64) .inChannels * width * (.header.bitDepth / 8)
    }

    mtd defilter8(width, height: u32, input, output: [*] u8)
    {
        let rowStrideIn  = .getStrideIn(width)
        let rowStrideOut = .header.bitDepth < 8 ? cast(u64) .inChannels * width : rowStrideIn
        let destOffset   = rowStrideOut - rowStrideIn

        var src  = input
        var dest = output
        if !.orderDefilter do
            dest += rowStrideOut * (height - 1)

        // A temporary line "before" the first one, if filter needs one
        var tmpRow: Array'u8
        tmpRow.resize(rowStrideOut)
        let tmpRowBuffer = tmpRow.buffer!
        Memory.clear(tmpRowBuffer, rowStrideOut)
        var up = tmpRowBuffer

        // PNG filtering references the previous byte of the same pixel. Packed
        // samples (bit depths below 8) have an effective byte offset of 1, not
        // the number of channels; otherwise narrow Adam7 passes underflow here.
        let filterOffset = .header.bitDepth < 8 ? 1'u64 : cast(u64) .inChannels * (.header.bitDepth / 8)
        var row          = 0'u32
        while row < height
        {
            let filter = cast(RowFilter) src[0]
            src += 1

            var destOff = dest + destOffset
            switch filter
            {
            case .None:    Memory.copy(destOff, src, rowStrideIn)
            case .Sub:     defilterSubRow(src, destOff, rowStrideIn, filterOffset)
            case .Up:      defilterUpRow(src, up, destOff, rowStrideIn)
            case .Average: defilterAverageRow(src, up, destOff, rowStrideIn, filterOffset)
            case .Paeth:   defilterPaethRow(src, up, destOff, rowStrideIn, filterOffset)
            }

            src += rowStrideIn
            up  = destOff
            if .orderDefilter do
                dest += rowStrideOut
            else do
                dest -= rowStrideOut
            row += 1
        }
    }

    mtd defilter(width, height: u32, input, output: [*] u8)
    {
        if .header.bitDepth < 8
        {
            .defilter8(width, height, input, output)
            .expand8(width, height, output)
            return
        }

        if .header.bitDepth == 8 or .header.bitDepth == 16
        {
            .defilter8(width, height, input, output)
            return
        }
    }

    mtd adam7()
    {
        var tmpArr: Array'u8
        var input = .dcmpBuf.buffer!
        for p in 7
        {
            let x = (.header.width - Adam7OrigX[p] + Adam7SpacingX[p] - 1) / Adam7SpacingX[p]
            let y = (.header.height - Adam7OrigY[p] + Adam7SpacingY[p] - 1) / Adam7SpacingY[p]
            if x <= 0 or y <= 0 do
                continue

            let pixelBytes = cast(u64) .inChannels * (.header.bitDepth == 16 ? 2 : 1)
            tmpArr.resize(cast(u64) (x * y) * pixelBytes)
            let tmpBuffer = tmpArr.buffer!
            Memory.clear(tmpBuffer, tmpArr.count)

            .defilter(cast(u32) x, cast(u32) y, input, tmpBuffer)

            var t = tmpBuffer
            for j in y
            {
                for i in x
                {
                    let out_y   = .header.height - ((j * Adam7SpacingY[p]) + Adam7OrigY[p]) - 1
                    let out_x   = (i * Adam7SpacingX[p]) + Adam7OrigX[p]
                    var out_off = out_y * .header.width * pixelBytes
                    out_off += out_x * pixelBytes
                    let dstPixels = .safeDstPixels()
                    for z in pixelBytes do
                        dstPixels[out_off + z] = t[z]
                    t += pixelBytes
                }
            }

            let stride = (.getStrideIn(cast(u32) x) + 1) * y
            input += stride
        }
    }

    mtd defilter()
    {
        if .header.interlaceMethod != .Adam7
        {
            .orderDefilter = false
            let input = .dcmpBuf.buffer!
            .defilter(.header.width, .header.height, input, .safeDstPixels())
        }
        else
        {
            .orderDefilter = true
            .adam7()
        }
    }
}
