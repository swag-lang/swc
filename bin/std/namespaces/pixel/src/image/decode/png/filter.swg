//! Format: Portable Network Graphics (PNG) decoder component.
//! Supported: Standard grayscale, true-color, indexed, grayscale-alpha, and true-color-alpha images, including Adam7 and supported metadata.
//! Not supported: Unknown critical chunks and images requiring more than 2 GiB of decoded storage.
//! Role: This file owns PNG row unfiltering.
//
// @LICENCE: BSD-2-Clause
// @ORIGIN: libspng, https://github.com/randy408/libspng
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#libspng

#global namespace Png

using Core, Core.Errors

const Expand4LowBytes  = cast(Math.Simd.U8x16, [0_u8, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7])
const Expand4HighBytes = cast(Math.Simd.U8x16, [8_u8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13, 14, 14, 15, 15])
const Expand4HighMask  = cast(Math.Simd.U8x16, [15_u8, 0, 15, 0, 15, 0, 15, 0, 15, 0, 15, 0, 15, 0, 15, 0])
const Expand4LowMask   = cast(Math.Simd.U8x16, [0_u8, 15, 0, 15, 0, 15, 0, 15, 0, 15, 0, 15, 0, 15, 0, 15])
const Expand1Bytes     = cast(Math.Simd.U8x16, [0_u8, 2, 4, 6, 8, 10, 12, 14, 1, 3, 5, 7, 9, 11, 13, 15])
const Expand1Bits      = cast(Math.Simd.U8x16, [128_u8, 64, 32, 16, 8, 4, 2, 1, 128, 64, 32, 16, 8, 4, 2, 1])
const Expand2Bytes     = cast(Math.Simd.U8x16, [0_u8, 4, 8, 12, 1, 5, 9, 13, 2, 6, 10, 14, 3, 7, 11, 15])

#[Swag.Inline]
func expand4Half(value, table: Math.Simd.U8x16, multiplier: u8)->Math.Simd.U8x16
{
    let duplicated = Math.Simd.shuffle(value, table)
    let shifted    = cast #bit(Math.Simd.U8x16, (cast #bit(Math.Simd.U16x8, duplicated) >> 4))
    let nibbles    = (shifted & Expand4HighMask) | (duplicated & Expand4LowMask)
    if multiplier == 1
    {
        return nibbles
    }

    return cast #bit(Math.Simd.U8x16, (cast #bit(Math.Simd.U16x8, nibbles) * cast(u16, multiplier)))
}

func defilterUpRow(source, previous: const [*] u8, destination: [*] u8, count: u64)
{
    const VectorBytes = #sizeof(Math.Simd.U8x16)
    const BatchBytes  = 4 * VectorBytes
    var offset = 0_u64
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
        destination[offset] = cast #bit(u8, (source[offset] + #wrap previous[offset]))
        offset += 1
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
        dst[0]    = cast(u8, (value >> 4)) * multiplier
        dst[1]    = cast(u8, (value & 15)) * multiplier
        src       += 1
        dst       += 2
        remaining -= 2
    }

    if remaining
    {
        dst[0] = cast(u8, (src[0] >> 4)) * multiplier
    }
}

func expand1Row(source: const [*] u8, destination: [*] u8, sampleCount: u64, multiplier: u8)
{
    var src       = source
    var dst       = destination
    var remaining = sampleCount
    while remaining >= 16
    {
        let packed     = cast(u16, src[0]) | (cast(u16, src[1]) << 8)
        let duplicated = Math.Simd.shuffle(cast #bit(Math.Simd.U8x16, Math.Simd.splat(packed)), Expand1Bytes)
        var expanded   = (duplicated & Expand1Bits) == Expand1Bits
        if multiplier == 1
        {
            expanded &= Math.Simd.splat(1_u8)
        }

        Math.Simd.store(dst, expanded)
        src       += 2
        dst       += 16
        remaining -= 16
    }

    while remaining >= 8
    {
        let value = src[0]
        dst[0]    = cast(u8, (value >> 7)) * multiplier
        dst[1]    = cast(u8, ((value >> 6) & 1)) * multiplier
        dst[2]    = cast(u8, ((value >> 5) & 1)) * multiplier
        dst[3]    = cast(u8, ((value >> 4) & 1)) * multiplier
        dst[4]    = cast(u8, ((value >> 3) & 1)) * multiplier
        dst[5]    = cast(u8, ((value >> 2) & 1)) * multiplier
        dst[6]    = cast(u8, ((value >> 1) & 1)) * multiplier
        dst[7]    = cast(u8, (value & 1)) * multiplier
        src       += 1
        dst       += 8
        remaining -= 8
    }

    if remaining
    {
        let value = src[0]
        for i in remaining
        {
            dst[i] = cast(u8, ((value >> (7 - i)) & 1)) * multiplier
        }
    }
}

func expand2Row(source: const [*] u8, destination: [*] u8, sampleCount: u64, multiplier: u8)
{
    var src       = source
    var dst       = destination
    var remaining = sampleCount
    while remaining >= 16
    {
        let packed = cast(u32, src[0]) |
                     (cast(u32, src[1]) << 8) |
                     (cast(u32, src[2]) << 16) |
                     (cast(u32, src[3]) << 24)
        let bytes    = cast #bit(Math.Simd.U8x16, Math.Simd.splat(packed))
        let words    = cast #bit(Math.Simd.U32x4, Math.Simd.shuffle(bytes, Expand2Bytes))
        var expanded = ((words >> 6) & 0x0000_0003_u32) |
                       ((words >> 4) & 0x0000_0300_u32) |
                       ((words >> 2) & 0x0003_0000_u32) |
                       (words & 0x0300_0000_u32)
        if multiplier != 1
        {
            expanded *= cast(u32, multiplier)
        }

        Math.Simd.store(dst, cast #bit(Math.Simd.U8x16, expanded))
        src       += 4
        dst       += 16
        remaining -= 16
    }

    while remaining >= 4
    {
        let value = src[0]
        dst[0]    = cast(u8, (value >> 6)) * multiplier
        dst[1]    = cast(u8, ((value >> 4) & 3)) * multiplier
        dst[2]    = cast(u8, ((value >> 2) & 3)) * multiplier
        dst[3]    = cast(u8, (value & 3)) * multiplier
        src       += 1
        dst       += 4
        remaining -= 4
    }

    if remaining
    {
        let value = src[0]
        for i in remaining
        {
            dst[i] = cast(u8, ((value >> (6 - 2 * i)) & 3)) * multiplier
        }
    }
}

func filterPaeth(left, up, upLeft: u8)->u8
{
    let aa = cast(s16, left)
    let bb = cast(s16, up)
    let cc = cast(s16, upLeft)
    let p  = aa + bb - cc
    let pa = Math.abs(cast(s16, (p - aa)))
    let pb = Math.abs(cast(s16, (p - bb)))
    let pc = Math.abs(cast(s16, (p - cc)))
    if pa <= pb and pa <= pc
    {
        return left
    }

    if pb <= pc
    {
        return up
    }

    return upLeft
}

// Widens the low half of one in-bounds vector, one lane per pixel byte.
#[Swag.Inline]
func loadPixelLanes(source: const [*] u8)->Math.Simd.S16x8
{
    return cast #bit(Math.Simd.S16x8, Math.Simd.widenLow(Math.Simd.load(source)))
}

// Adds two lane-per-byte pixels the way PNG reconstruction does, modulo 256.
//
// Every lane holds a byte in its low half and zero above it, so adding as bytes wraps each
// channel on its own and leaves the lanes in that same shape.
#[Swag.Inline]
func addPixelLanes(x, y: Math.Simd.S16x8)->Math.Simd.S16x8 => cast #bit(Math.Simd.S16x8, (cast #bit(Math.Simd.U8x16, x) + cast #bit(Math.Simd.U8x16, y)))

// Picks the Paeth predictor per lane, with the same ties as the scalar rule.
//
// The three distances reduce to differences of the neighbours, which keeps every lane inside
// 's16': 'p - left' is 'up - upLeft', 'p - up' is 'left - upLeft', and 'p - upLeft' is their
// sum. Two strict comparisons reproduce the ordered scalar rule — a tie keeps the earlier
// candidate — and keep the dependency chain on 'left' two steps shorter than picking the
// minimum of the three distances first.
#[Swag.Inline]
func paethPredict(left, up, upLeft: Math.Simd.S16x8)->Math.Simd.S16x8
{
    let deltaUp        = up - upLeft
    let deltaLeft      = left - upLeft
    let distanceLeft   = Math.abs(deltaUp)
    let distanceUp     = Math.abs(deltaLeft)
    let distanceUpLeft = Math.abs(deltaUp + deltaLeft)
    let nearer         = Math.Simd.select(distanceUp < distanceLeft, up, left)
    let nearest        = Math.min(distanceUp, distanceLeft)
    return Math.Simd.select(distanceUpLeft < nearest, upLeft, nearer)
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
    var offset = 0_u64
    scope
    {
        var left = Math.Simd.splat(0_s16)
        while offset + 16 <= count
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
        let left    = offset >= bytesPerPixel ? destination[offset - bytesPerPixel] : 0_u8
        let average = cast(u8, ((cast(u16, previous[offset]) + left) >> 1))
        destination[offset] = cast #bit(u8, (source[offset] + #wrap average))
        offset += 1
    }
}

// Reverses the Paeth predictor, carrying the reconstructed left pixel in a register.
//
// Same shape as [[Png.defilterAverageRow]], and for the same reason: the predictor of a byte
// needs the byte one pixel to its left, which the scalar form has only just stored.
func defilterPaethRow(source, previous: const [*] u8, destination: [*] u8, count, bytesPerPixel: u64)
{
    var offset = 0_u64
    scope
    {
        var left   = Math.Simd.splat(0_s16)
        var upLeft = Math.Simd.splat(0_s16)
        while offset + 16 <= count
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
        let left      = offset >= bytesPerPixel ? destination[offset - bytesPerPixel] : 0_u8
        let upLeft    = offset >= bytesPerPixel ? previous[offset - bytesPerPixel] : 0_u8
        let predictor = filterPaeth(left, previous[offset], upLeft)
        destination[offset] = cast #bit(u8, (source[offset] + #wrap predictor))
        offset += 1
    }
}

func isZeroScanline(source: const [*] u8, count: u64)->bool
{
    let zero   = Math.Simd.splat(0_u8)
    var offset = 0_u64
    while count - offset >= 16
    {
        if Math.Simd.anyTrue(Math.Simd.load(source + offset) != zero)
        {
            return false
        }

        offset += 16
    }

    while offset < count
    {
        if source[offset] != 0
        {
            return false
        }

        offset += 1
    }

    return true
}

// With both neighbours on the same side of the corner, its distance
// cannot beat either. With opposite signs the distances subtract, so
// the comparison stays in byte lanes and ties still favour Left, then Up.
#[Swag.Inline]
func paethPredictBytes(left, up, upLeft: Math.Simd.U8x16)->Math.Simd.U8x16
{
    let lowerLeft = Math.min(left, upLeft)
    let lowerUp   = Math.min(up, upLeft)
    let distanceLeft = Math.max(up, upLeft) - lowerUp
    let distanceUp   = Math.max(left, upLeft) - lowerLeft
    let nearest      = Math.min(distanceLeft, distanceUp)
    let diagonal     = Math.max(distanceLeft, distanceUp) - nearest
    let crosses      = (lowerLeft == upLeft) ^ (lowerUp == upLeft)
    let nearby       = Math.Simd.select(distanceLeft == nearest, left, up)
    let cornerLoses  = Math.min(diagonal, nearest) == nearest
    return Math.Simd.select(crosses & ~cornerLoses, upLeft, nearby)
}

// Paeth-filter two rows along a diagonal. The second row trails one pixel
// behind the first, making both rows' left, above, and upper-left pixels available.
func defilterPaethPair(firstSource, secondSource, previous: const [*] u8, first, second: [*] u8, count, bytesPerPixel: u64)
{
    using Core, Math.Simd

    // The first pixel's predictor is Up. For RGB8 the fourth byte of each
    // store is provisional, and the next pixel or scalar tail replaces it.
    let initialSource = cast #bit(U8x16, interleaveLow(splat(cast(const [*] u32, firstSource)[0]), splat(0_u32)))
    let initialUp     = cast #bit(U8x16, interleaveLow(splat(cast(const [*] u32, previous)[0]), splat(0_u32)))
    var packed        = cast #bit(U32x4, (initialSource + initialUp))
    cast([*] u32, first)[0] = packed[0]
    var left   = cast #bit(U8x16, packed)
    var upLeft = initialUp

    var offset = bytesPerPixel
    while offset + 4 <= count
    {
        let above  = splat(cast(const [*] u32, (previous + offset))[0])
        let up     = cast #bit(U8x16, interleaveLow(above, packed))
        let top    = splat(cast(const [*] u32, (firstSource + offset))[0])
        let bottom = splat(cast(const [*] u32, (secondSource + offset - bytesPerPixel))[0])
        let delta  = cast #bit(U8x16, interleaveLow(top, bottom))

        left   = delta + paethPredictBytes(left, up, upLeft)
        upLeft = up
        packed = cast #bit(U32x4, left)
        cast([*] u32, (first + offset))[0] = packed[0]
        cast([*] u32, (second + offset - bytesPerPixel))[0] = packed[1]
        offset += bytesPerPixel
    }

    for i in offset until count
    {
        let prediction = filterPaeth(first[i - bytesPerPixel], previous[i], previous[i - bytesPerPixel])
        first[i] = cast #bit(u8, (firstSource[i] + #wrap prediction))
    }

    for i in offset - bytesPerPixel until count
    {
        let prediction = filterPaeth(second[i - bytesPerPixel], first[i], first[i - bytesPerPixel])
        second[i] = cast #bit(u8, (secondSource[i] + #wrap prediction))
    }
}

// Pack one pixel per dword so the four rows fit into a byte-lane predictor.
#[Swag.Inline]
func packPaethPixels(p0, p1, p2, p3: u32)->Math.Simd.U32x4
{
    using Core.Math.Simd
    let first  = cast(u64, p0) | (cast(u64, p1) << 32)
    let second = cast(u64, p2) | (cast(u64, p3) << 32)
    return cast #bit(U32x4, interleaveLow(splat(first), splat(second)))
}

#[Swag.Inline]
func startingPaethPixel(source: const [*] u8, pixelBytes: u64)->u32
{
    var sample = 0_u32
    Memory.copy(&sample, source, pixelBytes)
    return sample
}

// Four rows share the predictor while trailing their preceding row by one pixel.
// Resolve the starting ramp and the right edge one row at a time.
func defilterPaethFourRows(input, previous: const [*] u8, output: [*] u8, count: u64, rowStep: s64, pixelBytes: u64)
{
    using Core, Math.Simd
    let inputStep = count + 1
    let second    = output + rowStep
    let third     = second + rowStep
    let fourth    = third + rowStep

    for row in 3
    {
        let source = input + row * inputStep
        let dest   = output + cast(s64, row) * rowStep
        let above  = row ? cast(const [*] u8, dest - rowStep) : previous
        for offset in (3 - row) * pixelBytes
        {
            let left = offset >= pixelBytes ? dest[offset - pixelBytes] : 0_u8
            let diag = offset >= pixelBytes ? above[offset - pixelBytes] : 0_u8
            dest[offset] = cast #bit(u8, (source[offset] + #wrap filterPaeth(left, above[offset], diag)))
        }
    }

    #[Swag.Mixin]
    func word(source: const [*] u8)->u32
    {
        return cast(const [*] u32, source)[0]
    }

    var left = packPaethPixels(startingPaethPixel(output + 2 * pixelBytes, pixelBytes), startingPaethPixel(second + pixelBytes, pixelBytes), startingPaethPixel(third, pixelBytes), 0)
    var upLeft = packPaethPixels(startingPaethPixel(previous + 2 * pixelBytes, pixelBytes), startingPaethPixel(output + pixelBytes, pixelBytes), startingPaethPixel(second, pixelBytes), 0)
    var offset = 3 * pixelBytes
    while offset + 4 <= count
    {
        let above = align(splat(word(previous + offset)), left, 12)
        let delta = packPaethPixels(word(input + offset),
                                    word(input + inputStep + offset - pixelBytes),
                                    word(input + 2 * inputStep + offset - 2 * pixelBytes),
                                    word(input + 3 * inputStep + offset - 3 * pixelBytes))
        let predictor = paethPredictBytes(cast #bit(U8x16, left), cast #bit(U8x16, above), cast #bit(U8x16, upLeft))
        left   = cast #bit(U32x4, (cast #bit(U8x16, delta) + predictor))
        upLeft = above

        cast([*] u32, output + offset)[0] = left[0]
        cast([*] u32, second + offset - pixelBytes)[0] = left[1]
        cast([*] u32, third + offset - 2 * pixelBytes)[0] = left[2]
        cast([*] u32, fourth + offset - 3 * pixelBytes)[0] = left[3]
        offset += pixelBytes
    }

    for row in 4
    {
        let source = input + row * inputStep
        let dest   = output + cast(s64, row) * rowStep
        let above  = row ? cast(const [*] u8, dest - rowStep) : previous
        for index in offset - row * pixelBytes until count
        {
            let leftPixel = index >= pixelBytes ? dest[index - pixelBytes] : 0_u8
            let diagonal  = index >= pixelBytes ? above[index - pixelBytes] : 0_u8
            dest[index] = cast #bit(u8, (source[index] + #wrap filterPaeth(leftPixel, above[index], diagonal)))
        }
    }
}

func(PIXEL_BYTES: u64) scatterAdam7Row(source: const [*] u8, target: [*] u8, width: u32, targetStep: u64)
{
    var src = source
    var dst = target
    for width
    {
        Memory.copy(dst, src, PIXEL_BYTES)
        src += PIXEL_BYTES
        dst += targetStep
    }
}

// Restores packed scanlines whose leading byte selects the PNG row predictor.
//
// The caller provides disjoint input and output slices. The input contains one
// filter byte and `rowBytes` bytes per row. `pixelBytes` is the byte distance to
// the left sample, one for packed samples below eight bits. Returns false when
// the dimensions, slice lengths, or a filter byte are invalid. Rows preceding an
// invalid filter may already have been restored.
public func restorePredictorRows(input: const [..] u8, output: [..] u8, rowBytes, pixelBytes: u64)->bool
{
    if not rowBytes or rowBytes > Swag.S64.Max or not pixelBytes or pixelBytes > rowBytes
    {
        return false
    }

    let encodedRow = rowBytes + 1
    let count      = input.count / encodedRow
    if input.count % encodedRow or output.count != count * rowBytes
    {
        return false
    }

    if not count
    {
        return true
    }

    return defilterRowsInto(count, input.buffer, output.buffer, rowBytes, cast(s64, rowBytes), pixelBytes)
}

private func defilterRowsInto(height: u64, input: const [*] u8, output: [*] u8, rowBytes: u64, rowStep: s64, filterOffset: u64, previous: const [*] u8? = null)->bool
{
    var src  = input
    var dest = output

    var zeroRow: Array!{u8}
    var up:      const [*] u8
    if let above = previous
    {
        up = above
    }
    else
    {
        // The first row of each pass sees all-zero bytes above it.
        zeroRow.resize(rowBytes)
        up = zeroRow.storage()
    }

    let pairPaeth = rowBytes >= 16 and (filterOffset == 3 or filterOffset == 4)
    var row       = 0_u64
    while row < height
    {
        let filter = src[0]
        src += 1

        // With zero residuals, the first pixel equals Up, and each
        // following pixel has Left equal to UpLeft, so Paeth selects Up.
        let copyPaeth = filter == 4 and isZeroScanline(src, rowBytes)
        if filter == 4 and not copyPaeth and pairPaeth and row + 1 < height and src[rowBytes] == 4
        {
            let stride = rowBytes + 1
            let zero = Math.Simd.splat(0_u8)
            // Keep zero rows on the cheaper copy path when a batch starts
            // with no residuals in any of its following rows.
            if rowBytes >= 24 and row + 3 < height and
               src[2 * stride - 1] == 4 and src[3 * stride - 1] == 4 and
               Math.Simd.anyTrue(Math.Simd.load(src + stride) != zero) and
               Math.Simd.anyTrue(Math.Simd.load(src + 2 * stride) != zero) and
               Math.Simd.anyTrue(Math.Simd.load(src + 3 * stride) != zero)
            {
                defilterPaethFourRows(src, up, dest, rowBytes, rowStep, filterOffset)
                src  += 4 * rowBytes + 3
                let last = dest + 3 * rowStep
                up = last
                dest = last + rowStep
                row  += 4
                continue
            }

            let next = dest + rowStep
            defilterPaethPair(src, src + rowBytes + 1, up, dest, next, rowBytes, filterOffset)
            src  += 2 * rowBytes + 1
            up   = next
            dest = next + rowStep
            row  += 2
            continue
        }

        switch filter
        {
        case 0:
            Memory.copy(dest, src, rowBytes)

        case 1:
            PackedPixel.restoreHorizontalDeltas(src, dest, rowBytes, filterOffset)

        case 2:
            defilterUpRow(src, up, dest, rowBytes)

        case 3:
            defilterAverageRow(src, up, dest, rowBytes, filterOffset)

        case 4:
            if copyPaeth
            {
                Memory.copy(dest, up, rowBytes)
            }
            else
            {
                defilterPaethRow(src, up, dest, rowBytes, filterOffset)
            }

        default:
            return false
        }

        src  += rowBytes
        up   = dest
        dest += rowStep
        row  += 1
    }

    return true
}

impl Decoder
{
    mtd expand8(width, height: u32, output: [*] u8, rowStep: s64)
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
                orgDest += rowStep
                expand1Row(dest + srcOffset, dest, rowStrideOut, cast(u8, mul))
            }
        }
        // 2 bits => 8 bits
        else if .header.bitDepth == 2
        {
            let mul = .paletteCount ? 1 : 85
            for height
            {
                let dest = orgDest
                orgDest += rowStep
                expand2Row(dest + srcOffset, dest, rowStrideOut, cast(u8, mul))
            }
        }
        // 4 bits => 8 bits
        else if .header.bitDepth == 4
        {
            let mul = .paletteCount ? 1 : 17
            for height
            {
                let dest = orgDest
                orgDest += rowStep
                expand4Row(dest + srcOffset, dest, rowStrideOut, cast(u8, mul))
            }
        }
    }

    mtd getStrideIn(width: u32)->u64
    {
        if .header.bitDepth < 8
        {
            return cast(u64, ((.inChannels * width * .header.bitDepth) + 7)) / 8
        }

        return cast(u64, .inChannels) * width * (.header.bitDepth / 8)
    }

    mtd getStrideOut(width: u32)->u64 => cast(u64, .inChannels) * width * (.header.bitDepth == 16 ? 2 : 1)

    mtd defilterRows(height: u32, input, output: [*] u8, rowBytes: u64, rowStep: s64, previous: const [*] u8? = null)->bool
    {
        // Packed samples still reference the previous byte of the row.
        let pixelBytes = .header.bitDepth < 8 ? 1_u64 : cast(u64, .inChannels) * (.header.bitDepth / 8)
        return defilterRowsInto(height, input, output, rowBytes, rowStep, pixelBytes, previous)
    }

    mtd defilter(width, height: u32, input, firstRow: [*] u8, rowStep: s64)->bool
    {
        let packedBytes = .getStrideIn(width)
        let offset      = .getStrideOut(width) - packedBytes
        if not .defilterRows(height, input, firstRow + offset, packedBytes, rowStep)
        {
            return false
        }

        if .header.bitDepth < 8
        {
            .expand8(width, height, firstRow, rowStep)
        }

        return true
    }

    mtd adam7(dstPixels: [*] u8)->bool
    {
        var tmpArr: Array!{u8}
        var input      = .dcmpBuf.storage()
        let rowStride  = .getStrideOut(.header.width)
        let pixelBytes = cast(u64, .inChannels) * (.header.bitDepth == 16 ? 2 : 1)
        for p in 7
        {
            let x = (.header.width - Adam7OrigX[p] + Adam7SpacingX[p] - 1) / Adam7SpacingX[p]
            let y = (.header.height - Adam7OrigY[p] + Adam7SpacingY[p] - 1) / Adam7SpacingY[p]
            if x <= 0 or y <= 0
            {
                continue
            }

            let passWidth  = cast(u32, x)
            let passHeight = cast(u32, y)
            let rowBytes   = cast(u64, passWidth) * pixelBytes
            if Adam7SpacingX[p] == 1
            {
                // The last pass owns whole rows and can reconstruct them in place.
                let firstRow = cast(u64, (.header.height - Adam7OrigY[p] - 1)) * rowStride
                let rowStep  = -cast(s64, rowStride) * Adam7SpacingY[p]
                return .defilter(passWidth, passHeight, input, dstPixels + firstRow, rowStep)
            }

            // Keep only a small span of rows for strided passes. Save the last
            // packed row before expansion so the next batch has the right predictor.
            const BatchRows = 32_u32
            let packedBytes = .getStrideIn(passWidth)
            let frontBytes  = rowBytes - packedBytes
            let targetStep  = cast(u64, Adam7SpacingX[p]) * pixelBytes
            let targetStart = cast(u64, Adam7OrigX[p]) * pixelBytes
            tmpArr.reserve(rowBytes * (Math.min(BatchRows, passHeight) + 1))
            let storage = tmpArr.storage()
            let batch   = storage + rowBytes
            var first   = 0_u32
            while first < passHeight
            {
                let count = Math.min(BatchRows, passHeight - first)
                let prior = first ? cast(const [*] u8, storage) : null
                if not .defilterRows(count, input, batch + frontBytes, packedBytes, cast(s64, rowBytes), prior)
                {
                    return false
                }

                if first + count < passHeight
                {
                    Memory.copy(storage, batch + (count - 1) * rowBytes + frontBytes, packedBytes)
                }

                if .header.bitDepth < 8
                {
                    .expand8(passWidth, count, batch, cast(s64, rowBytes))
                }

                var source = batch
                for j in first until first + count
                {
                    let outY   = .header.height - (j * Adam7SpacingY[p] + Adam7OrigY[p]) - 1
                    let target = dstPixels + outY * rowStride + targetStart
                    switch pixelBytes
                    {
                    case 1:  scatterAdam7Row!{1}(source, target, passWidth, targetStep)
                    case 2:  scatterAdam7Row!{2}(source, target, passWidth, targetStep)
                    case 3:  scatterAdam7Row!{3}(source, target, passWidth, targetStep)
                    case 4:  scatterAdam7Row!{4}(source, target, passWidth, targetStep)
                    case 6:  scatterAdam7Row!{6}(source, target, passWidth, targetStep)
                    case 8:  scatterAdam7Row!{8}(source, target, passWidth, targetStep)
                    default: return false
                    }

                    source += rowBytes
                }

                input += (packedBytes + 1) * count
                first += count
            }
        }

        return true
    }

    // Defilters the decompressed rows into `dstPixels`, which holds the whole image.
    mtd defilter(dstPixels: [*] u8)->bool
    {
        if .header.interlaceMethod == .Adam7
        {
            return .adam7(dstPixels)
        }

        let rowBytes = .getStrideOut(.header.width)
        let firstRow = dstPixels + rowBytes * (.header.height - 1)
        return .defilter(.header.width, .header.height, .dcmpBuf.storage(), firstRow, -cast(s64, rowBytes))
    }
}
