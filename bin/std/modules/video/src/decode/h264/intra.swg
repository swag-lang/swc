#global namespace H264
#global internal

//! Format: H.264/AVC decoder component.
//! Supported: Progressive 8-bit 4:2:0 Baseline, Main, and High-profile streams with CAVLC/CABAC, I/P/B slices, weighted prediction, cropping, reordering, and deblocking.
//! Not supported: Interlacing, non-4:2:0 chroma, bit depths above 8, slice groups, data partitioning, scalable/multiview extensions, and lossless transform bypass.
//! Role: This file owns intra luma and chroma prediction.
//

using Core

// Intra prediction, section 8.3. Every routine predicts straight into the picture plane,
// reading the already reconstructed neighboring samples from it. The diagonal modes follow
// one shared scheme: reference arrays are stored with two lead-in slots, so that index -1 is
// the corner sample and index -2 the first sample of the opposite edge, which is exactly the
// reach of the specification's formulas.

// Luma 4x4 and 8x8 prediction modes.
const IntraVertical       = 0'u32
const IntraHorizontal     = 1'u32
const IntraDc             = 2'u32
const IntraDownLeft       = 3'u32
const IntraDownRight      = 4'u32
const IntraVerticalRight  = 5'u32
const IntraHorizontalDown = 6'u32
const IntraVerticalLeft   = 7'u32
const IntraHorizontalUp   = 8'u32

// Intra 16x16 prediction modes.
const Intra16Vertical   = 0'u32
const Intra16Horizontal = 1'u32
const Intra16Dc         = 2'u32
const Intra16Plane      = 3'u32

// Intra chroma prediction modes.
const IntraChromaDc         = 0'u32
const IntraChromaHorizontal = 1'u32
const IntraChromaVertical   = 2'u32
const IntraChromaPlane      = 3'u32

#[Swag.Inline]
private func fillIntra16x16(dst: [*] u8, stride: u64, value: u8)
{
    let pixels = Simd.splat(value)
    for row in 16'u64 do
        Simd.store(dst + row * stride, pixels)
}

#[Swag.Inline]
private func copyIntra16x16(dst: [*] u8, stride: u64, pixels: Simd.U8x16)
{
    for row in 16'u64 do
        Simd.store(dst + row * stride, pixels)
}

#[Swag.Inline]
func storeIntra8Vertical(dst: [*] u8, stride: u64, top: const [*] s32)
{
    for column in 8'u64 do
        dst[column] = cast(u8) top[column]
    let pixels = Simd.load(dst)
    for row in 1'u64 until 8 do
        Simd.storeLow8(dst + row * stride, pixels)
}

#[Swag.Inline]
private func storeIntra8Filtered(dst: [*] u8, low, high: Simd.S32x4)
{
    let words = Simd.packUnsigned(low, high)
    Simd.storeLow8(dst, Simd.packUnsigned(cast #bit(Simd.S16x8) words, cast #bit(Simd.S16x8) words))
}

// Predicts one 4x4 luma block, section 8.3.1.2.
//
// `hasTopRight` covers the four samples above and to the right; when they are missing but the
// top ones exist, the last top sample substitutes for them.
func intraPredict4x4(mode: u32, dst: [*] u8, stride: u64, hasLeft, hasTop, hasTopLeft, hasTopRight: bool)
{
    // tp[2 + i] is the top reference t(i); tp[1] the corner, tp[0] the first left sample.
    // lp mirrors it for the left edge.
    var tp: [10] s32 = undefined
    var lp: [6] s32  = undefined
    let corner       = hasTopLeft ? cast(s32) (dst - stride - 1)[0] : 128

    for row in 4'u64 do
        lp[2 + row] = hasLeft ? cast(s32) (dst - 1)[row * stride] : 128
    for column in 4'u64 do
        tp[2 + column] = hasTop ? cast(s32) (dst - stride)[column] : 128
    for column in 4'u64 until 8
    {
        if hasTopRight do
            tp[2 + column] = cast(s32) (dst - stride)[column]
        elif hasTop do
            tp[2 + column] = tp[5]
        else do
            tp[2 + column] = 128
    }

    tp[1] = corner
    tp[0] = lp[2]
    lp[1] = corner
    lp[0] = tp[2]

    switch mode
    {
    case IntraVertical:
        for row in 4'u64
        {
            for column in 4'u64 do
                dst[row * stride + column] = cast(u8) tp[2 + column]
        }

    case IntraHorizontal:
        for row in 4'u64
        {
            for column in 4'u64 do
                dst[row * stride + column] = cast(u8) lp[2 + row]
        }

    case IntraDc:
        var sum   = 0's32
        var count = 0's32
        if hasLeft
        {
            sum   += lp[2] + lp[3] + lp[4] + lp[5]
            count += 4
        }

        if hasTop
        {
            sum   += tp[2] + tp[3] + tp[4] + tp[5]
            count += 4
        }

        let value = count == 8 ? (sum + 4) >> 3 : (count == 4 ? (sum + 2) >> 2 : 128)
        for row in 4'u64
        {
            for column in 4'u64 do
                dst[row * stride + column] = cast(u8) value
        }

    case IntraDownLeft:
        for row in 4'u64
        {
            for column in 4'u64
            {
                let diag  = row + column
                let value = diag == 6 ? (tp[8] + 3 * tp[9] + 2) >> 2 : (tp[2 + diag] + 2 * tp[3 + diag] + tp[4 + diag] + 2) >> 2
                dst[row * stride + column] = cast(u8) value
            }
        }

    case IntraDownRight:
        for row in 4's64
        {
            for column in 4's64
            {
                let diag = column - row
                var value: s32
                if diag >= 1 do
                    value = (tp[cast(u64) diag] + 2 * tp[cast(u64) diag + 1] + tp[cast(u64) diag + 2] + 2) >> 2
                elif diag == 0 do
                    value = (lp[2] + 2 * lp[1] + tp[2] + 2) >> 2
                else do
                    value = (lp[cast(u64) (2 - diag)] + 2 * lp[cast(u64) (1 - diag)] + lp[cast(u64) (0 - diag)] + 2) >> 2
                dst[cast(u64) row * stride + cast(u64) column] = cast(u8) value
            }
        }

    case IntraVerticalRight:
        for row in 4's64
        {
            for column in 4's64
            {
                let z = 2 * column - row
                var value: s32
                if z >= 0 and z & 1 == 0
                {
                    let k = cast(u64) (column - (row >> 1))
                    value = (tp[k + 1] + tp[k + 2] + 1) >> 1
                }
                elif z >= -1
                {
                    let k = cast(u64) (column - (row >> 1))
                    value = (tp[k] + 2 * tp[k + 1] + tp[k + 2] + 2) >> 2
                }
                else
                {
                    let e = cast(u64) (row - 2 * column)
                    value = (lp[e + 1] + 2 * lp[e] + lp[e - 1] + 2) >> 2
                }

                dst[cast(u64) row * stride + cast(u64) column] = cast(u8) value
            }
        }

    case IntraHorizontalDown:
        for row in 4's64
        {
            for column in 4's64
            {
                let z = 2 * row - column
                var value: s32
                if z >= 0 and z & 1 == 0
                {
                    let k = cast(u64) (row - (column >> 1))
                    value = (lp[k + 1] + lp[k + 2] + 1) >> 1
                }
                elif z >= -1
                {
                    let k = cast(u64) (row - (column >> 1))
                    value = (lp[k] + 2 * lp[k + 1] + lp[k + 2] + 2) >> 2
                }
                else
                {
                    let e = cast(u64) (column - 2 * row)
                    value = (tp[e + 1] + 2 * tp[e] + tp[e - 1] + 2) >> 2
                }

                dst[cast(u64) row * stride + cast(u64) column] = cast(u8) value
            }
        }

    case IntraVerticalLeft:
        for row in 4'u64
        {
            for column in 4'u64
            {
                let k     = column + (row >> 1)
                let value = row & 1 == 0 ? (tp[2 + k] + tp[3 + k] + 1) >> 1 : (tp[2 + k] + 2 * tp[3 + k] + tp[4 + k] + 2) >> 2
                dst[row * stride + column] = cast(u8) value
            }
        }

    case IntraHorizontalUp:
        for row in 4'u64
        {
            for column in 4'u64
            {
                let z = column + 2 * row
                var value: s32
                if z > 5 do
                    value = lp[5]
                elif z == 5 do
                    value = (lp[4] + 3 * lp[5] + 2) >> 2
                elif z & 1 == 0 do
                    value = (lp[2 + row + (column >> 1)] + lp[3 + row + (column >> 1)] + 1) >> 1
                else do
                    value = (lp[2 + row + (column >> 1)] + 2 * lp[3 + row + (column >> 1)] + lp[4 + row + (column >> 1)] + 2) >> 2
                dst[row * stride + column] = cast(u8) value
            }
        }
    }
}

// Predicts one 8x8 luma block, sections 8.3.2.2.1 and 8.3.2.2.
//
// The references are low-pass filtered first, as every 8x8 mode requires.
func intraPredict8x8(mode: u32, dst: [*] u8, stride: u64, hasLeft, hasTop, hasTopLeft, hasTopRight: bool)
{
    // Raw references.
    var rawTop:  [16] s32 = undefined
    var rawLeft: [8] s32  = undefined
    let rawCorner         = hasTopLeft ? cast(s32) (dst - stride - 1)[0] : 128
    for row in 8'u64 do
        rawLeft[row] = hasLeft ? cast(s32) (dst - 1)[row * stride] : 128
    for column in 8'u64 do
        rawTop[column] = hasTop ? cast(s32) (dst - stride)[column] : 128
    for column in 8'u64 until 16
    {
        if hasTopRight do
            rawTop[column] = cast(s32) (dst - stride)[column]
        elif hasTop do
            rawTop[column] = rawTop[7]
        else do
            rawTop[column] = 128
    }

    // Filtered references, with the same two-slot lead-in as the 4x4 arrays.
    var tp: [19] s32 = undefined
    var lp: [10] s32 = undefined
    let corner       = (rawLeft[0] + 2 * rawCorner + rawTop[0] + 2) >> 2

    tp[2] = ((hasTopLeft ? rawCorner : rawTop[0]) + 2 * rawTop[0] + rawTop[1] + 2) >> 2
    for column in 1'u64 until 15 do
        tp[2 + column] = (rawTop[column - 1] + 2 * rawTop[column] + rawTop[column + 1] + 2) >> 2
    tp[17] = (rawTop[14] + 3 * rawTop[15] + 2) >> 2
    tp[18] = tp[17]

    lp[2] = ((hasTopLeft ? rawCorner : rawLeft[0]) + 2 * rawLeft[0] + rawLeft[1] + 2) >> 2
    for row in 1'u64 until 7 do
        lp[2 + row] = (rawLeft[row - 1] + 2 * rawLeft[row] + rawLeft[row + 1] + 2) >> 2
    lp[9] = (rawLeft[6] + 3 * rawLeft[7] + 2) >> 2

    tp[1] = corner
    tp[0] = lp[2]
    lp[1] = corner
    lp[0] = tp[2]

    switch mode
    {
    case IntraVertical:
        storeIntra8Vertical(dst, stride, tp.buffer + 2)

    case IntraHorizontal:
        for row in 8'u64
        {
            for column in 8'u64 do
                dst[row * stride + column] = cast(u8) lp[2 + row]
        }

    case IntraDc:
        var sum   = 0's32
        var count = 0's32
        if hasLeft
        {
            for row in 8'u64 do
                sum += lp[2 + row]
            count += 8
        }

        if hasTop
        {
            for column in 8'u64 do
                sum += tp[2 + column]
            count += 8
        }

        let value = count == 16 ? (sum + 8) >> 4 : (count == 8 ? (sum + 4) >> 3 : 128)
        for row in 8'u64
        {
            for column in 8'u64 do
                dst[row * stride + column] = cast(u8) value
        }

    case IntraDownLeft:
        for row in 8'u64
        {
            let low  = (Simd.load(tp.buffer + 2 + row) + Simd.load(tp.buffer + 3 + row) * 2 + Simd.load(tp.buffer + 4 + row) + Simd.splat(2's32)) >> 2
            let high = (Simd.load(tp.buffer + 6 + row) + Simd.load(tp.buffer + 7 + row) * 2 + Simd.load(tp.buffer + 8 + row) + Simd.splat(2's32)) >> 2
            storeIntra8Filtered(dst + row * stride, low, high)
        }

    case IntraDownRight:
        for row in 8's64
        {
            for column in 8's64
            {
                let diag = column - row
                var value: s32
                if diag >= 1 do
                    value = (tp[cast(u64) diag] + 2 * tp[cast(u64) diag + 1] + tp[cast(u64) diag + 2] + 2) >> 2
                elif diag == 0 do
                    value = (lp[2] + 2 * lp[1] + tp[2] + 2) >> 2
                else do
                    value = (lp[cast(u64) (2 - diag)] + 2 * lp[cast(u64) (1 - diag)] + lp[cast(u64) (0 - diag)] + 2) >> 2
                dst[cast(u64) row * stride + cast(u64) column] = cast(u8) value
            }
        }

    case IntraVerticalRight:
        for row in 8's64
        {
            for column in 8's64
            {
                let z = 2 * column - row
                var value: s32
                if z >= 0 and z & 1 == 0
                {
                    let k = cast(u64) (column - (row >> 1))
                    value = (tp[k + 1] + tp[k + 2] + 1) >> 1
                }
                elif z >= -1
                {
                    let k = cast(u64) (column - (row >> 1))
                    value = (tp[k] + 2 * tp[k + 1] + tp[k + 2] + 2) >> 2
                }
                else
                {
                    let e = cast(u64) (row - 2 * column)
                    value = (lp[e + 1] + 2 * lp[e] + lp[e - 1] + 2) >> 2
                }

                dst[cast(u64) row * stride + cast(u64) column] = cast(u8) value
            }
        }

    case IntraHorizontalDown:
        for row in 8's64
        {
            for column in 8's64
            {
                let z = 2 * row - column
                var value: s32
                if z >= 0 and z & 1 == 0
                {
                    let k = cast(u64) (row - (column >> 1))
                    value = (lp[k + 1] + lp[k + 2] + 1) >> 1
                }
                elif z >= -1
                {
                    let k = cast(u64) (row - (column >> 1))
                    value = (lp[k] + 2 * lp[k + 1] + lp[k + 2] + 2) >> 2
                }
                else
                {
                    let e = cast(u64) (column - 2 * row)
                    value = (tp[e + 1] + 2 * tp[e] + tp[e - 1] + 2) >> 2
                }

                dst[cast(u64) row * stride + cast(u64) column] = cast(u8) value
            }
        }

    case IntraVerticalLeft:
        for row in 8'u64
        {
            let start = 2 + (row >> 1)
            if row & 1 == 0
            {
                let low  = (Simd.load(tp.buffer + start) + Simd.load(tp.buffer + start + 1) + Simd.splat(1's32)) >> 1
                let high = (Simd.load(tp.buffer + start + 4) + Simd.load(tp.buffer + start + 5) + Simd.splat(1's32)) >> 1
                storeIntra8Filtered(dst + row * stride, low, high)
            }
            else
            {
                let low  = (Simd.load(tp.buffer + start) + Simd.load(tp.buffer + start + 1) * 2 + Simd.load(tp.buffer + start + 2) + Simd.splat(2's32)) >> 2
                let high = (Simd.load(tp.buffer + start + 4) + Simd.load(tp.buffer + start + 5) * 2 + Simd.load(tp.buffer + start + 6) + Simd.splat(2's32)) >> 2
                storeIntra8Filtered(dst + row * stride, low, high)
            }
        }

    case IntraHorizontalUp:
        var predicted: [22] u8 = undefined
        for z in 13'u64
        {
            let index    = z >> 1
            let filtered = z & 1 == 0 ? (lp[2 + index] + lp[3 + index] + 1) >> 1 : (lp[2 + index] + 2 * lp[3 + index] + lp[4 + index] + 2) >> 2
            predicted[z] = cast(u8) filtered
        }

        predicted[13] = cast(u8) ((lp[8] + 3 * lp[9] + 2) >> 2)
        for z in 14'u64 until 22 do
            predicted[z] = cast(u8) lp[9]
        for row in 8'u64 do
            Simd.storeLow8(dst + row * stride, Simd.load(predicted.buffer + 2 * row))
    }
}

// Predicts one 16x16 luma macroblock, section 8.3.3.
func intraPredict16x16(mode: u32, dst: [*] u8, stride: u64, hasLeft, hasTop: bool)
{
    switch mode
    {
    case Intra16Vertical:
        copyIntra16x16(dst, stride, Simd.load(dst - stride))

    case Intra16Horizontal:
        for row in 16'u64 do
            Simd.store(dst + row * stride, Simd.splat((dst - 1)[row * stride]))

    case Intra16Dc:
        var sum   = 0's32
        var count = 0's32
        if hasLeft
        {
            for row in 16'u64 do
                sum += cast(s32) (dst - 1)[row * stride]
            count += 16
        }

        if hasTop
        {
            for column in 16'u64 do
                sum += cast(s32) (dst - stride)[column]
            count += 16
        }

        let value = count == 32 ? (sum + 16) >> 5 : (count == 16 ? (sum + 8) >> 4 : 128)
        fillIntra16x16(dst, stride, cast(u8) value)

    case Intra16Plane:
        const Offsets0 = cast(Simd.S32x4) [0's32, 1, 2, 3]
        const Offsets1 = cast(Simd.S32x4) [4's32, 5, 6, 7]
        const Offsets2 = cast(Simd.S32x4) [8's32, 9, 10, 11]
        const Offsets3 = cast(Simd.S32x4) [12's32, 13, 14, 15]
        var h = cast(s32) (dst - stride)[8] - cast(s32) (dst - stride)[6]
        var v = cast(s32) (dst - 1)[8 * stride] - cast(s32) (dst - 1)[6 * stride]
        for k in 2 to 8
        {
            let topRight = cast(s32) (dst - stride)[cast(u64) (7 + k)]
            let topLeft  = k == 8 ? cast(s32) (dst - stride - 1)[0] : cast(s32) (dst - stride)[cast(u64) (7 - k)]
            h += k * (topRight - topLeft)
            let leftDown = cast(s32) (dst - 1)[cast(u64) (7 + k) * stride]
            let leftUp   = k == 8 ? cast(s32) (dst - stride - 1)[0] : cast(s32) (dst - 1)[cast(u64) (7 - k) * stride]
            v += k * (leftDown - leftUp)
        }

        h = (5 * h + 32) >> 6
        v = (5 * v + 32) >> 6
        var a = 16 * (cast(s32) (dst - 1)[15 * stride] + cast(s32) (dst - stride)[15] + 1) - 7 * (v + h)
        for row in 16'u64
        {
            let base = Simd.splat(a)
            a += v
            let values0 = Math.max(Math.min((base + Offsets0 * h) >> 5, Simd.splat(255's32)), Simd.splat(0's32))
            let values1 = Math.max(Math.min((base + Offsets1 * h) >> 5, Simd.splat(255's32)), Simd.splat(0's32))
            let values2 = Math.max(Math.min((base + Offsets2 * h) >> 5, Simd.splat(255's32)), Simd.splat(0's32))
            let values3 = Math.max(Math.min((base + Offsets3 * h) >> 5, Simd.splat(255's32)), Simd.splat(0's32))
            let low     = Simd.packUnsigned(values0, values1)
            let high    = Simd.packUnsigned(values2, values3)
            Simd.store(dst + row * stride, Simd.packUnsigned(cast #bit(Simd.S16x8) low, cast #bit(Simd.S16x8) high))
        }
    }
}

// Predicts one 8x8 chroma plane of a macroblock, section 8.3.4.
func intraPredictChroma(mode: u32, dst: [*] u8, stride: u64, hasLeft, hasTop: bool)
{
    switch mode
    {
    case IntraChromaDc:

        // Each 4x4 quadrant has its own average: the corner ones prefer their aligned edge,
        // the top-left and bottom-right ones average both edges when both exist.
        var sumTopLeft    = 0's32
        var sumTopRight   = 0's32
        var sumBottomLeft = 0's32
        for index in 4'u64
        {
            if hasTop
            {
                sumTopLeft  += cast(s32) (dst - stride)[index]
                sumTopRight += cast(s32) (dst - stride)[4 + index]
            }

            if hasLeft
            {
                sumTopLeft    += cast(s32) (dst - 1)[index * stride]
                sumBottomLeft += cast(s32) (dst - 1)[(4 + index) * stride]
            }
        }

        var dc0, dc1, dc2, dc3: s32
        if hasTop and hasLeft
        {
            dc0 = (sumTopLeft + 4) >> 3
            dc1 = (sumTopRight + 2) >> 2
            dc2 = (sumBottomLeft + 2) >> 2
            dc3 = (sumTopRight + sumBottomLeft + 4) >> 3
        }
        elif hasTop
        {
            dc0 = (sumTopLeft + 2) >> 2
            dc1 = (sumTopRight + 2) >> 2
            dc2 = dc0
            dc3 = dc1
        }
        elif hasLeft
        {
            dc0 = (sumTopLeft + 2) >> 2
            dc1 = dc0
            dc2 = (sumBottomLeft + 2) >> 2
            dc3 = dc2
        }
        else
        {
            dc0 = 128
            dc1 = 128
            dc2 = 128
            dc3 = 128
        }

        let top    = cast #bit(Simd.U8x16) cast(Simd.U32x4) [cast(u32) dc0 * 0x01010101, cast(u32) dc1 * 0x01010101, 0, 0]
        let bottom = cast #bit(Simd.U8x16) cast(Simd.U32x4) [cast(u32) dc2 * 0x01010101, cast(u32) dc3 * 0x01010101, 0, 0]
        for row in 4'u64 do
            Simd.storeLow8(dst + row * stride, top)
        for row in 4'u64 until 8 do
            Simd.storeLow8(dst + row * stride, bottom)

    case IntraChromaHorizontal:
        for row in 8'u64 do
            Simd.storeLow8(dst + row * stride, Simd.splat((dst - 1)[row * stride]))

    case IntraChromaVertical:
        let pixels = Simd.load(dst - stride)
        for row in 8'u64 do
            Simd.storeLow8(dst + row * stride, pixels)

    case IntraChromaPlane:
        var h = cast(s32) (dst - stride)[4] - cast(s32) (dst - stride)[2]
        var v = cast(s32) (dst - 1)[4 * stride] - cast(s32) (dst - 1)[2 * stride]
        for k in 2 to 4
        {
            let topRight = cast(s32) (dst - stride)[cast(u64) (3 + k)]
            let topLeft  = k == 4 ? cast(s32) (dst - stride - 1)[0] : cast(s32) (dst - stride)[cast(u64) (3 - k)]
            h += k * (topRight - topLeft)
            let leftDown = cast(s32) (dst - 1)[cast(u64) (3 + k) * stride]
            let leftUp   = k == 4 ? cast(s32) (dst - stride - 1)[0] : cast(s32) (dst - 1)[cast(u64) (3 - k) * stride]
            v += k * (leftDown - leftUp)
        }

        h = (17 * h + 16) >> 5
        v = (17 * v + 16) >> 5
        var a = 16 * (cast(s32) (dst - 1)[7 * stride] + cast(s32) (dst - stride)[7] + 1) - 3 * (v + h)
        for row in 8'u64
        {
            var b = a
            a += v
            for column in 8'u64
            {
                dst[row * stride + column] = clampPixel(b >> 5)
                b += h
            }
        }
    }
}
