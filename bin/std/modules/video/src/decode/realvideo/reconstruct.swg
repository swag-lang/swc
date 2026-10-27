// @LICENCE: LGPL-2.1-or-later
// @ORIGIN: FFmpeg n7.1, libavcodec/rv34dsp.c, rv40dsp.c and h264pred.c
// @MODIFIED: 2026-10-27, Scalar Swag reconstruction over bounded picture planes.
// @NOTICE: THIRDPARTY.md#ffmpeg-realvideo-decoder
#global namespace RealVideo
#global internal

using Core

func clipped(value: s32)->u8 => cast(u8, Math.clamp(value, 0, 255))

func inverseTransform(block: *[16] s32, dc: bool)
{
    var temp: [16] s32
    for i in 4's32
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

    for i in 4's32
    {
        let scale    = dc ? 3 : 1
        let rounding = dc ? 0 : 512
        let shift    = dc ? 11'u32 : 10'u32
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
    for y in 4's32
    {
        for x in 4's32 do
            dst[y * stride + x] = clipped(cast(s32, dst[y * stride + x]) + block[][y * 4 + x])
    }
}

func predictLarge(dst: [*] u8, stride, size, mode: s32, top, left: bool)
{
    var actual = mode
    if not top and not left do
        actual = 0
    elif not top and (actual == 1 or actual == 3) do
        actual = 2
    elif not left and (actual == 2 or actual == 3) do
        actual = 1
    if size == 8 and actual == 3 do
        actual = 0
    var dc = 128's32
    var h: s32
    var v: s32
    var a: s32
    if actual == 0 and (top or left)
    {
        var sum: s32
        for i in size
        {
            if top do
                sum += cast(s32, (dst - stride)[i])
            if left do
                sum += cast(s32, (dst - 1)[i * stride])
        }

        let count = size * (cast(s32, top) + cast(s32, left))
        dc = (sum + count / 2) / count
    }

    if actual == 3
    {
        for k in 1's32 until 9
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
    if not top and not left do
        actual = 0
    elif not top and actual == 1 do
        actual = 2
    elif not left and actual == 2 do
        actual = 1
    if actual != 4 and actual != 6 and actual != 7
    {
        const Modes: [9] u32 = [2, 0, 1, 4, 3, 5, 7, 8, 6]
        H264.intraPredict4x4(Modes[actual], dst, cast(u64, stride), left, top, left and top, right and top)
        return
    }

    var t: [8] s32
    var l: [8] s32
    for i in 8's32
    {
        t[i] = cast(s32, (dst - stride)[i < 4 or right ? i : 3])
        l[i] = cast(s32, (dst - 1)[(i < 4 or down ? i : 3) * stride])
    }

    for y in 4's32
    {
        for x in 4's32
        {
            var value: s32
            if actual == 4
            {
                let d = x + y
                value = d == 6 ? (t[6] + t[7] + l[6] + l[7] + 2) >> 2 :
                        (t[d] + 2 * t[d + 1] + t[d + 2] + l[d] + 2 * l[d + 1] + l[d + 2] + 4) >> 3
            }
            elif actual == 6
            {
                let d = x + y / 2
                value = (y & 1) != 0 ? (t[d] + 2 * t[d + 1] + t[d + 2] + 2) >> 2 : (t[d] + t[d + 1] + 1) >> 1
                if x == 0 and y == 0 do
                    value = (2 * t[0] + 2 * t[1] + l[1] + 2 * l[2] + l[3] + 4) >> 3
                if x == 0 and y == 1 do
                    value = (t[0] + 2 * t[1] + t[2] + l[2] + 2 * l[3] + l[4] + 4) >> 3
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

func filtered(a, b, c, d, e, f, fraction: s32)->s32
{
    let c1    = fraction == 1 ? 52 : 20
    let c2    = fraction == 3 ? 52 : 20
    let shift = fraction == 2 ? 5'u32 : 6'u32
    return Math.clamp((a + f - 5 * (b + e) + c * c1 + d * c2 + (1 << (shift - 1))) >> shift, 0, 255)
}

func horizontal(plane: const *Plane, x, y, fraction: s32)->s32
{
    if not fraction do
        return plane.sample(x, y)
    return filtered(plane.sample(x - 2, y), plane.sample(x - 1, y), plane.sample(x, y), plane.sample(x + 1, y), plane.sample(x + 2, y), plane.sample(x + 3, y), fraction)
}

func motionPixel(plane: const *Plane, x, y: s32, motion: Motion, chroma: bool)->s32
{
    if chroma
    {
        let cx = motion.x / 2
        let cy = motion.y / 2
        let sx = x + (cx >> 2)
        let sy = y + (cy >> 2)
        var fx = (cx & 3) * 2
        var fy = (cy & 3) * 2
        if fx == 6 and fy == 6
        {
            fx = 4
            fy = 4
        }

        const Bias = [0, 16, 32, 16, 32, 28, 32, 28, 0, 32, 16, 32, 32, 28, 32, 28]
        return ((8 - fx) * (8 - fy) * plane.sample(sx, sy) + fx * (8 - fy) * plane.sample(sx + 1, sy) +
                (8 - fx) * fy * plane.sample(sx, sy + 1) + fx * fy * plane.sample(sx + 1, sy + 1) + Bias[fy / 2 * 4 + fx / 2]) >> 6
    }

    let sx = x + (motion.x >> 2)
    let sy = y + (motion.y >> 2)
    let fx = motion.x & 3
    let fy = motion.y & 3
    if fx == 3 and fy == 3 do
        return (plane.sample(sx, sy) + plane.sample(sx + 1, sy) + plane.sample(sx, sy + 1) + plane.sample(sx + 1, sy + 1) + 2) >> 2
    if not fy do
        return horizontal(plane, sx, sy, fx)
    return filtered(horizontal(plane, sx, sy - 2, fx),
                    horizontal(plane, sx, sy - 1, fx),
                    horizontal(plane, sx, sy, fx),
                    horizontal(plane, sx, sy + 1, fx),
                    horizontal(plane, sx, sy + 2, fx),
                    horizontal(plane, sx, sy + 3, fx),
                    fy)
}
