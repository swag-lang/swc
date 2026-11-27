using Swag, Core

const CURVE_TAG_ON = 0x01_u8

// Marks an off-curve point as one of the two controls of a cubic Bézier. `glyf`
// outlines never carry it; PostScript outlines — CFF and Type 1 — are cubic
// throughout, and this is what lets both shapes share one point array.
const CURVE_TAG_CUBIC = 0x02_u8

const MAX_RECURSE = 16_u32

const CMP_ARG_1_AND_2_ARE_WORDS = 0x0001_u16
const CMP_ARGS_ARE_XY_VALUES    = 0x0002_u16
const CMP_WE_HAVE_A_SCALE       = 0x0008_u16
const CMP_MORE_COMPONENTS       = 0x0020_u16
const CMP_WE_HAVE_AN_XY_SCALE   = 0x0040_u16
const CMP_WE_HAVE_A_2X2         = 0x0080_u16
const CMP_WE_HAVE_INSTRUCTIONS  = 0x0100_u16

private struct GlyphAxisChunk
{
    // Low bytes select four deltas. High bytes mark the short deltas to negate.
    shuffle: [16] u8
    bytes:   u8
}

// The two flags for one axis encode a long delta, a negative short delta,
// a zero delta or a positive short delta. Each lookup describes four such deltas.
private const GlyphAxisChunks: [256] GlyphAxisChunk = #run
{
    var chunks: [256] GlyphAxisChunk
    for combination in chunks.count
    {
        var chunk: GlyphAxisChunk
        for lane in 4
        {
            let mode = (combination >> (lane * 2)) & 3
            let byte = cast(u8, lane * 2)
            chunk.shuffle[byte]     = 128
            chunk.shuffle[byte + 1] = 128
            switch mode
            {
            case 0:
                chunk.shuffle[byte]     = chunk.bytes + 1
                chunk.shuffle[byte + 1] = chunk.bytes
                chunk.bytes             += 2

            case 1, 3:
                chunk.shuffle[byte] = chunk.bytes
                chunk.bytes         += 1
            }

            if mode == 1
            {
                chunk.shuffle[byte + 8] = 255
                chunk.shuffle[byte + 9] = 255
            }
        }

        chunks[combination] = chunk
    }

    return chunks
}

private func(horizontal: bool) decodeGlyphAxis(data: const [..] u8, first: u64, flags: [*] u8, points: [*] Vector, count: u32, scaler: const *PointScale)->u64 fail
{
    const ShortShift = horizontal ? 1 : 2
    const SameShift  = horizontal ? 3 : 4
    const ShortBit   = 1_u8 << ShortShift
    const SameBit    = 2_u8 << SameShift
    var offset = first
    var index  = 0_u32
    var value  = 0_s32

    #static if Math.nativeToBigEndian(1_u16) != 1
    {
        if count >= 16
        {
            let zero = Math.Simd.splat(0_u32)
            while count - index >= 4 and data.count - offset >= 16
            {
                let packed = cast(const [*] u32, flags + index)[0]
                let modes  = ((packed >> ShortShift) & 0x0101_0101) | ((packed >> SameShift) & 0x0202_0202)

                // Collect the low pair of bits from each flag byte into one table index.
                let key   = cast(u32, ((cast(u64, modes) * 0x0104_1040) >> 24) & 255)
                let chunk = &GlyphAxisChunks[key]
                let table = Math.Simd.load(&chunk.shuffle[0])
                let bytes = Math.Simd.load(data.buffer + offset)
                let words = cast #bit(Math.Simd.S16x8, Math.Simd.shuffle(bytes, table))
                let signs = cast #bit(Math.Simd.S16x8, Math.Simd.align(table, table, 8))
                let delta = cast #bit(Math.Simd.U32x4, Math.Simd.widenLow((words ^ signs) - signs))

                // A simple glyph has at most 65,536 signed 16-bit deltas per axis.
                // Both partial sums and the final coordinates fit in signed 32 bits.
                let pairs  = delta + Math.Simd.align(zero, delta, 12)
                let sums   = cast #bit(Math.Simd.S32x4, pairs + Math.Simd.align(zero, pairs, 8)) + value
                let scaled = cast #bit(Math.Simd.U32x4, try scaler.applyFour(sums))
                let target = cast([*] u32, points + index)
                #static if horizontal
                {
                    Math.Simd.store(target, Math.Simd.interleaveLow(scaled, zero))
                    Math.Simd.store(target + 4, Math.Simd.interleaveHigh(scaled, zero))
                }
                else
                {
                    const MaskY = cast(Math.Simd.U32x4, [0_u32, 0xFFFF_FFFF, 0, 0xFFFF_FFFF])
                    let low  = Math.Simd.interleaveLow(zero, scaled)
                    let high = Math.Simd.interleaveHigh(zero, scaled)
                    Math.Simd.store(target, Math.Simd.select(MaskY, low, Math.Simd.load(target)))
                    Math.Simd.store(target + 4, Math.Simd.select(MaskY, high, Math.Simd.load(target + 4)))
                    cast([*] u32, flags + index)[0] = packed & 0x0101_0101
                }

                value  = sums[3]
                offset += chunk.bytes
                index  += 4
            }
        }
    }

    var input = data.buffer + offset
    for point in index until count
    {
        let flag = flags[point]
        if (flag & ShortBit) != 0
        {
            let delta = cast(s32, input[0])
            input += 1
            value += (flag & SameBit) != 0 ? delta : -delta
        }
        else if (flag & SameBit) == 0
        {
            value += cast #bit(s16, Math.make16(input[0], input[1]))
            input += 2
        }

        #static if horizontal
        {
            points[point] = {x: try scaler.apply(value), y: 0}
        }
        else
        {
            points[point].y = try scaler.apply(value)
            flags[point]    = flag & CURVE_TAG_ON
        }
    }

    return cast(u64, input - data.buffer)
}

private const GlyfCoordinateBytes: [64] u8 = #run
{
    var sizes: [64] u8
    for flag in sizes.count
    {
        let x = (flag & 0x02) != 0 ? 1_u8 : ((flag & 0x10) != 0 ? 0 : 2)
        let y = (flag & 0x04) != 0 ? 1_u8 : ((flag & 0x20) != 0 ? 0 : 2)
        sizes[flag] = cast(u8, x + y)
    }

    return sizes
}

func appendSimpleGlyph(faceData: *FaceImpl, glyphData: const [..] u8, xPpem, yPpem: u16) fail
{
    if glyphData.count < 10
    {
        try fault(0x14)
    }

    let signedContourCount = peekS16(glyphData, 0)
    if signedContourCount < 0
    {
        try fault(0x14)
    }

    let contourCount = cast(u32, signedContourCount)
    var offset       = 10_u64
    if cast(u64, contourCount) > (glyphData.count - offset) / 2
    {
        try fault(0x14)
    }

    let contourEnds = glyphData.buffer + offset
    var previousEnd = 0_u32
    for index in contourCount
    {
        let end = readPackedOffset(contourEnds + cast(u64, index) * 2, 2)
        if index and end <= previousEnd
        {
            try fault(0x14)
        }

        previousEnd = end
    }

    offset += cast(u64, contourCount) * 2
    let pointCount = contourCount ? previousEnd + 1 : 0
    if offset > glyphData.count or glyphData.count - offset < 2
    {
        try fault(0x14)
    }

    let instructionLength = peekU16(glyphData, offset)
    offset += 2
    if instructionLength > glyphData.count - offset
    {
        try fault(0x14)
    }

    offset += instructionLength

    if pointCount and offset >= glyphData.count
    {
        try fault(0x14)
    }

    let startPoint = faceData.outlinePoints.count
    let startTag   = faceData.outlineTags.count
    defer #fail
    {
        faceData.outlinePoints.resize(startPoint)
        faceData.outlineTags.resize(startTag)
    }

    // The output tags hold expanded flags until their coordinate deltas have been read.
    let flags = faceData.outlineTags.emplaceAddress(pointCount)
    let input = glyphData.buffer
    var coordinateBytes = 0_u64
    var i     = 0_u32
    while i < pointCount
    {
        if pointCount - i >= 4 and glyphData.count - offset >= 4
        {
            let packed = cast(const [*] u32, input + offset)[0]
            if (packed & 0x0808_0808) == 0
            {
                // Each axis uses one byte for a short delta, two for a long delta,
                // and none when the short bit is clear and the same bit is set.
                const ShortBits = 0x0606_0606_u32
                let shortDeltas = packed & ShortBits
                let longDeltas  = ~(packed | (packed >> 3)) & ShortBits
                coordinateBytes += Math.countOnes(shortDeltas) + 2 * Math.countOnes(longDeltas)
                cast([*] u32, flags + i)[0] = packed
                i      += 4
                offset += 4
                continue
            }
        }

        if offset >= glyphData.count
        {
            try fault(0x14)
        }

        let flag = input[offset]
        offset   += 1
        flags[i] = flag
        i        += 1
        var repeat = 0_u32
        if (flag & 0x08) != 0
        {
            if offset >= glyphData.count
            {
                try fault(0x14)
            }

            repeat = input[offset]
            offset += 1
            if repeat > pointCount - i
            {
                try fault(0x14)
            }

            Memory.set(flags + i, flag, repeat)
            i += repeat
        }

        coordinateBytes += cast(u64, GlyfCoordinateBytes[flag & 0x3F]) * (repeat + 1)
    }

    if coordinateBytes > glyphData.count - offset
    {
        try fault(0x14)
    }

    if not pointCount
    {
        return
    }

    let scaleKey = (cast(u64, faceData.unitsPerEm) << 32) | (cast(u64, xPpem) << 16) | yPpem
    if faceData.pointScaleKey != scaleKey
    {
        let xScale = try PointScale.create(faceData.unitsPerEm, xPpem)
        let yScale = xPpem == yPpem ? xScale : (try PointScale.create(faceData.unitsPerEm, yPpem))
        faceData.pointScaleX   = xScale
        faceData.pointScaleY   = yScale
        faceData.pointScaleKey = scaleKey
    }

    let points  = faceData.outlinePoints.emplaceAddress(pointCount)
    let yOffset = try decodeGlyphAxis!{true}(glyphData, offset, flags, points, pointCount, &faceData.pointScaleX)
    discard try decodeGlyphAxis!{false}(glyphData, yOffset, flags, points, pointCount, &faceData.pointScaleY)

    let contours = faceData.outlineContours.emplaceAddress(contourCount)
    for index in contourCount
    {
        contours[index] = cast(s16, startPoint + readPackedOffset(contourEnds + cast(u64, index) * 2, 2))
    }
}

private func translateGlyphPoints(points: [*] Vector, count: u64, dx, dy: f64)
{
    var index = 0_u64
    #static if Math.nativeToBigEndian(1_u32) != 1
    {
        if count >= 2 and
           dx >= Swag.S32.Min and
           dx <= Swag.S32.Max and
           dy >= Swag.S32.Min and
           dy <= Swag.S32.Max
        {
            let x      = cast #bit(u32, cast(s32, dx))
            let y      = cast #bit(u32, cast(s32, dy))
            let offset = cast(Math.Simd.U32x4, [x, y, x, y])
            while count - index >= 2
            {
                let target  = cast([*] u32, points + index)
                let old     = Math.Simd.load(target)
                let shifted = old + offset

                // Any signed overflow falls back to the existing checked conversions.
                if Swag.vecMask((old ^ shifted) & (offset ^ shifted))
                {
                    break
                }

                Math.Simd.store(target, shifted)
                index += 2
            }
        }
    }

    for point in index until count
    {
        points[point].x = cast(s32, points[point].x + dx)
        points[point].y = cast(s32, points[point].y + dy)
    }
}

func appendCompositeGlyph(faceData: *FaceImpl, glyphData: const [..] u8, xPpem, yPpem: u16, depth: u32) fail
{
    if depth >= MAX_RECURSE
    {
        try fault(0x15)
    }

    let compositePointStart = faceData.outlinePoints.count
    var offset  = 10_u64
    var hasMore = true
    while hasMore
    {
        let flags        = peekU16(glyphData, offset + 0)
        let componentIdx = peekU16(glyphData, offset + 2)
        offset += 4

        var arg1 = 0_s32
        var arg2 = 0_s32
        if (flags & CMP_ARG_1_AND_2_ARE_WORDS) != 0
        {
            if (flags & CMP_ARGS_ARE_XY_VALUES) != 0
            {
                arg1 = peekS16(glyphData, offset + 0)
                arg2 = peekS16(glyphData, offset + 2)
            }
            else
            {
                arg1 = cast(s32, peekU16(glyphData, offset + 0))
                arg2 = cast(s32, peekU16(glyphData, offset + 2))
            }

            offset += 4
        }
        else
        {
            if (flags & CMP_ARGS_ARE_XY_VALUES) != 0
            {
                arg1 = cast #bit (s8, peekU8(glyphData, offset + 0))
                arg2 = cast #bit (s8, peekU8(glyphData, offset + 1))
            }
            else
            {
                arg1 = cast(s32, peekU8(glyphData, offset + 0))
                arg2 = cast(s32, peekU8(glyphData, offset + 1))
            }

            offset += 2
        }

        var xx: f64 = 1.0
        var xy: f64 = 0.0
        var yx: f64 = 0.0
        var yy: f64 = 1.0
        if (flags & CMP_WE_HAVE_A_SCALE) != 0
        {
            xx     = peekF2Dot14(glyphData, offset)
            yy     = xx
            offset += 2
        }
        else if (flags & CMP_WE_HAVE_AN_XY_SCALE) != 0
        {
            xx     = peekF2Dot14(glyphData, offset + 0)
            yy     = peekF2Dot14(glyphData, offset + 2)
            offset += 4
        }
        else if (flags & CMP_WE_HAVE_A_2X2) != 0
        {
            xx     = peekF2Dot14(glyphData, offset + 0)
            yx     = peekF2Dot14(glyphData, offset + 2)
            xy     = peekF2Dot14(glyphData, offset + 4)
            yy     = peekF2Dot14(glyphData, offset + 6)
            offset += 8
        }

        let basePointCount = faceData.outlinePoints.count

        try appendGlyph(faceData, componentIdx, xPpem, yPpem, depth + 1)

        let addedPointCount = faceData.outlinePoints.count - basePointCount
        if (flags & CMP_ARGS_ARE_XY_VALUES) == 0 and
           (arg1 < 0 or
            arg2 < 0 or
            cast(u32, arg1) >= basePointCount - compositePointStart or
            cast(u32, arg2) >= addedPointCount)
        {
            try fault(0x14)
        }

        if addedPointCount
        {
            let points = faceData.outlinePoints.storage() + basePointCount
            var dx     = 0.0
            var dy     = 0.0
            if (flags & CMP_ARGS_ARE_XY_VALUES) != 0
            {
                // A nonempty component has already prepared the two point scales.
                dx = try faceData.pointScaleX.apply(arg1)
                dy = try faceData.pointScaleY.apply(arg2)
            }

            if xx != 1.0 or yy != 1.0 or xy != 0.0 or yx != 0.0
            {
                for index in addedPointCount
                {
                    let src = points[index]
                    let tx  = cast(f64, src.x)
                    let ty  = cast(f64, src.y)
                    points[index].x = cast(s32, Math.round(tx * xx + ty * xy))
                    points[index].y = cast(s32, Math.round(tx * yx + ty * yy))
                }
            }

            if (flags & CMP_ARGS_ARE_XY_VALUES) == 0
            {
                let anchorParent = faceData.outlinePoints[compositePointStart + cast(u32, arg1)]
                let anchorChild  = points[arg2]
                dx = anchorParent.x - anchorChild.x
                dy = anchorParent.y - anchorChild.y
            }

            // The scaled offsets and both anchors are already integer 26.6 coordinates.
            if dx != 0 or dy != 0
            {
                translateGlyphPoints(points, addedPointCount, dx, dy)
            }
        }

        hasMore = (flags & CMP_MORE_COMPONENTS) != 0
    }

    if hasMore and (peekU16(glyphData, offset) & CMP_WE_HAVE_INSTRUCTIONS) != 0 {}
}

func appendGlyph(faceData: *FaceImpl, glyphIndex: u32, xPpem, yPpem: u16, depth: u32 = 0) fail
{
    if glyphIndex >= faceData.face.glyphCount
    {
        try fault(0x10)
    }

    let range = faceData.glyphByteRange(glyphIndex)
    if range.stop <= range.start
    {
        return
    }

    // Both offsets were checked against this table when the face opened.
    let data  = Swag.makeSlice(faceData.glyphOutlines.buffer + range.start, range.stop - range.start)
    let count = peekS16(data, 0)
    if count >= 0
    {
        try appendSimpleGlyph(faceData, data, xPpem, yPpem)
    }
    else
    {
        try appendCompositeGlyph(faceData, data, xPpem, yPpem, depth)
    }
}

// Runs the charstring of a PostScript glyph into the face's reusable point arrays.
func appendCharstringGlyph(faceData: *FaceImpl, glyphIndex: u32, xPpem, yPpem: u32) fail
{
    var builder = OutlineBuilder.create(faceData, xPpem, yPpem, faceData.unitsPerEm)
    if faceData.outlineSource == .Cff
    {
        discard try runType2Charstring(faceData.cffFont(), glyphIndex, &builder)
    }
    else
    {
        discard try runType1Charstring(faceData.type1Font(), glyphIndex, &builder)
    }
}

func loadGlyphInternal(face: *Face, glyphIndex: u32) fail
{
    let faceData = try getFaceImpl(face)
    let slot     = &face.glyph
    clearOutline(slot)
    clearBitmap(slot)

    faceData.outlinePoints.clear()
    faceData.outlineTags.clear()
    faceData.outlineContours.clear()

    slot.beginLoad(glyphIndex)

    let xPpem = Math.max(1_u16, face.size.metrics.xPpem)
    let yPpem = Math.max(1_u16, face.size.metrics.yPpem)
    if faceData.outlineSource == .Glyf
    {
        try appendGlyph(faceData, glyphIndex, xPpem, yPpem)
    }
    else
    {
        try appendCharstringGlyph(faceData, glyphIndex, xPpem, yPpem)
    }

    faceData.emptyOutlineSize = faceData.outlinePoints.count ? 0 : (cast(u32, xPpem) << 16) | yPpem

    slot.outline.setView(faceData.outlinePoints.count ? faceData.outlinePoints.buffer : null,
                         faceData.outlineTags.count ? faceData.outlineTags.buffer : null,
                         faceData.outlineContours.count ? faceData.outlineContours.buffer : null,
                         cast(s16, faceData.outlinePoints.count),
                         cast(s16, faceData.outlineContours.count))

    let advance = faceData.glyphAdvance(glyphIndex)
    slot.setAdvance(try scale26_6(advance, xPpem, faceData.unitsPerEm))
    if let metrics = faceData.verticalMetrics
    {
        let vertical = metrics.glyph(glyphIndex)
        slot.setVerticalMetrics(try scale26_6(vertical.advanceHeight, yPpem, faceData.unitsPerEm),
                                try scale26_6(vertical.topSideBearing, yPpem, faceData.unitsPerEm))
    }
    else
    {
        slot.setVerticalMetrics(0, 0)
    }

    updateSlotMetrics(slot)
}
