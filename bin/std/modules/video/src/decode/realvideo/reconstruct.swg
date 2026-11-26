// @LICENCE: LGPL-2.1-or-later
// @ORIGIN: FFmpeg n7.1, libavcodec/rv34dsp.c, rv40dsp.c and h264pred.c
// @MODIFIED: 2026-10-27, Scalar Swag reconstruction over bounded picture planes.
// @NOTICE: THIRDPARTY.md#ffmpeg-realvideo-decoder
#global namespace RealVideo
#global internal

using Core, Core.Math

func clipped(value: s32)->u8 => cast(u8, Math.clamp(value, 0, 255))

#[Swag.Inline]
private func transformColumns(rows: *[4] Simd.U32x4, scale, rounding: s32, shift: u32)
{
    let row0 = cast #bit(Simd.S32x4, rows[][0])
    let row1 = cast #bit(Simd.S32x4, rows[][1])
    let row2 = cast #bit(Simd.S32x4, rows[][2])
    let row3 = cast #bit(Simd.S32x4, rows[][3])
    let a    = (row0 + row2) * (13 * scale) + rounding
    let b    = (row0 - row2) * (13 * scale) + rounding
    let c    = row1 * (7 * scale) - row3 * (17 * scale)
    let d    = row1 * (17 * scale) + row3 * (7 * scale)
    rows[][0] = cast #bit(Simd.U32x4, (a + d) >> shift)
    rows[][1] = cast #bit(Simd.U32x4, (b + c) >> shift)
    rows[][2] = cast #bit(Simd.U32x4, (b - c) >> shift)
    rows[][3] = cast #bit(Simd.U32x4, (a - d) >> shift)
}

func inverseTransform(block: *[16] s32, dc: bool)
{
    var temp: [16] s32
    for i in 4_s32
    {
        let a = 13 * (block[][i] + block[][i + 8])
        let b = 13 * (block[][i] - block[][i + 8])
        let c = 7 * block[][i + 4] - 17 * block[][i + 12]
        let d = 17 * block[][i + 4] + 7 * block[][i + 12]
        temp[i * 4]     = a + d
        temp[i * 4 + 1] = b + c
        temp[i * 4 + 2] = b - c
        temp[i * 4 + 3] = a - d
    }

    for i in 4_s32
    {
        let scale    = dc ? 3 : 1
        let rounding = dc ? 0 : 512
        let shift    = dc ? 11_u32 : 10_u32
        let a        = 13 * scale * (temp[i] + temp[i + 8]) + rounding
        let b        = 13 * scale * (temp[i] - temp[i + 8]) + rounding
        let c        = scale * (7 * temp[i + 4] - 17 * temp[i + 12])
        let d        = scale * (17 * temp[i + 4] + 7 * temp[i + 12])
        block[][i * 4]     = (a + d) >> shift
        block[][i * 4 + 1] = (b + c) >> shift
        block[][i * 4 + 2] = (b - c) >> shift
        block[][i * 4 + 3] = (a - d) >> shift
    }
}

func addResidual(dst: [*] u8, stride: s32, block: *[16] s32)
{
    inverseTransform(block, false)
    for y in 4_s32
    {
        for x in 4_s32
        {
            dst[y * stride + x] = clipped(cast(s32, dst[y * stride + x]) + block[][y * 4 + x])
        }
    }
}

func predictLarge(dst: [*] u8, stride, size, mode: s32, top, left: bool)
{
    var actual = mode
    if not top and not left
    {
        actual = 0
    }
    else if not top and (actual == 1 or actual == 3)
    {
        actual = 2
    }
    else if not left and (actual == 2 or actual == 3)
    {
        actual = 1
    }

    if size == 8 and actual == 3
    {
        actual = 0
    }

    var dc = 128_s32
    var h: s32
    var v: s32
    var a: s32
    if actual == 0 and (top or left)
    {
        var sum: s32
        for i in size
        {
            if top
            {
                sum += cast(s32, (dst - stride)[i])
            }

            if left
            {
                sum += cast(s32, (dst - 1)[i * stride])
            }
        }

        let count = size * (cast(s32, top) + cast(s32, left))
        dc = (sum + count / 2) / count
    }

    if actual == 3
    {
        for k in 1_s32 until 9
        {
            h += k * (cast(s32, (dst - stride)[7 + k]) - cast(s32, (dst - stride)[7 - k]))
            v += k * (cast(s32, (dst - 1)[(7 + k) * stride]) - cast(s32, (dst - 1)[(7 - k) * stride]))
        }

        h = (h + (h >> 2)) >> 4
        v = (v + (v >> 2)) >> 4
        a = 16 * (cast(s32, (dst - 1)[15 * stride]) + cast(s32, (dst - stride)[15]) + 1) - 7 * (v + h)
    }

    for y in size
    {
        for x in size
        {
            var value = dc
            switch actual
            {
            case 1: value = cast(s32, (dst - stride)[x])
            case 2: value = cast(s32, (dst - 1)[y * stride])
            case 3: value = (a + y * v + x * h) >> 5
            }

            dst[y * stride + x] = clipped(value)
        }
    }
}

func predictSmall(dst: [*] u8, stride, mode: s32, top, left, down, right: bool)
{
    var actual = mode
    if not top and not left
    {
        actual = 0
    }
    else if not top and actual == 1
    {
        actual = 2
    }
    else if not left and actual == 2
    {
        actual = 1
    }

    if actual != 4 and actual != 6 and actual != 7
    {
        const Modes: [9] u32 = [2, 0, 1, 4, 3, 5, 7, 8, 6]
        H264.intraPredict4x4(Modes[actual], dst, cast(u64, stride), left, top, left and top, right and top)
        return
    }

    var t: [8] s32
    var l: [8] s32
    for i in 8_s32
    {
        t[i] = cast(s32, (dst - stride)[i < 4 or right ? i : 3])
        l[i] = cast(s32, (dst - 1)[(i < 4 or down ? i : 3) * stride])
    }

    for y in 4_s32
    {
        for x in 4_s32
        {
            var value: s32
            if actual == 4
            {
                let d = x + y
                value = d == 6 ? (t[6] + t[7] + l[6] + l[7] + 2) >> 2 :
                        (t[d] + 2 * t[d + 1] + t[d + 2] + l[d] + 2 * l[d + 1] + l[d + 2] + 4) >> 3
            }
            else if actual == 6
            {
                let d = x + y / 2
                value = (y & 1) != 0 ? (t[d] + 2 * t[d + 1] + t[d + 2] + 2) >> 2 : (t[d] + t[d + 1] + 1) >> 1
                if x == 0 and y == 0
                {
                    value = (2 * t[0] + 2 * t[1] + l[1] + 2 * l[2] + l[3] + 4) >> 3
                }

                if x == 0 and y == 1
                {
                    value = (t[0] + 2 * t[1] + t[2] + l[2] + 2 * l[3] + l[4] + 4) >> 3
                }
            }
            else
            {
                let d = x + y * 2
                switch d
                {
                case 0:  value = (t[1] + 2 * t[2] + t[3] + 2 * l[0] + 2 * l[1] + 4) >> 3
                case 1:  value = (t[2] + 2 * t[3] + t[4] + l[0] + 2 * l[1] + l[2] + 4) >> 3
                case 2:  value = (t[3] + 2 * t[4] + t[5] + 2 * l[1] + 2 * l[2] + 4) >> 3
                case 3:  value = (t[4] + 2 * t[5] + t[6] + l[1] + 2 * l[2] + l[3] + 4) >> 3
                case 4:  value = (t[5] + 2 * t[6] + t[7] + 2 * l[2] + 2 * l[3] + 4) >> 3
                case 5:  value = (t[6] + 3 * t[7] + l[2] + 3 * l[3] + 4) >> 3
                case 6:  value = (t[6] + t[7] + l[3] + l[4] + 2) >> 2
                case 7:  value = (l[3] + 2 * l[4] + l[5] + 2) >> 2
                case 8:  value = (l[4] + l[5] + 1) >> 1
                default: value = (l[4] + 2 * l[5] + l[6] + 2) >> 2
                }
            }

            dst[y * stride + x] = clipped(value)
        }
    }
}

private struct MotionFilter
{
    let c1    = fraction == 1 ? 52 : 20
    let c2    = fraction == 3 ? 52 : 20
    let shift = fraction == 2 ? 5_u32 : 6_u32
    return Math.clamp((a + f - 5 * (b + e) + c * c1 + d * c2 + (1 << (shift - 1))) >> shift, 0, 255)
}

private const MotionFilters: [4] MotionFilter = [
    {0, 0, 0, 0}, {52, 20, 32, 6}, {20, 20, 16, 5}, {20, 52, 32, 6}]

#[Swag.Inline]
private func filterMotion(a, b, c, d, e, f: s32, filter: MotionFilter)->u8
{
    if not fraction
    {
        return plane.sample(x, y)
    }

    return filtered(plane.sample(x - 2, y), plane.sample(x - 1, y), plane.sample(x, y), plane.sample(x + 1, y), plane.sample(x + 2, y), plane.sample(x + 3, y), fraction)
}

#[Swag.Inline]
private func motionTaps(source: const [*] u8)->Simd.S16x8
{
    let bytes = cast #bit(Simd.U8x16, Simd.splat(cast(const [*] u64, source)[0]))
    return cast #bit(Simd.S16x8, Simd.widenLow(bytes))
}

#[Swag.Inline]
private func filterMotionRow(a, b, c, d, e, f: Simd.S16x8, filter: MotionFilter)->Simd.U8x16
{
    // The largest positive tap sum is 74 and every input is a byte.
    let sum = a + f - (b + e) * 5's16 +
              c * cast(s16, filter.centerLeft) + d * cast(s16, filter.centerRight) + cast(s16, filter.bias)
    let samples = sum >> filter.shift
    return Simd.packUnsigned(samples, samples)
}

#[Swag.Inline]
private func rowSample(row: const [*] u8, x, width: s32)->s32
{
    return cast(s32, row[Math.clamp(x, 0, width - 1)])
}

private func horizontalMotion(into: [*] u8, source: const [*] u8, x, size, width, fraction: s32)
{
    if not fraction
    {
        if x >= 0 and x + size <= width
        {
            Memory.copy(into, source + x, cast(u64, size))
            return
        }

        for i in size do
            into[i] = cast(u8, rowSample(source, x + i, width))
        return
    }

    let sx = x + (motion.x >> 2)
    let sy = y + (motion.y >> 2)
    let fx = motion.x & 3
    let fy = motion.y & 3
    if fx == 3 and fy == 3
    {
        return (plane.sample(sx, sy) + plane.sample(sx + 1, sy) + plane.sample(sx, sy + 1) + plane.sample(sx + 1, sy + 1) + 2) >> 2
    }

    if not fy
    {
        return horizontal(plane, sx, sy, fx)
    }

    return filtered(horizontal(plane, sx, sy - 2, fx),
                    horizontal(plane, sx, sy - 1, fx),
                    horizontal(plane, sx, sy, fx),
                    horizontal(plane, sx, sy + 1, fx),
                    horizontal(plane, sx, sy + 2, fx),
                    horizontal(plane, sx, sy + 3, fx),
                    fy)
}
