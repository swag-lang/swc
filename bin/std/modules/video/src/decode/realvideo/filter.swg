// @LICENCE: LGPL-2.1-or-later
// @ORIGIN: FFmpeg n7.1, libavcodec/rv40.c and rv40dsp.c
// @MODIFIED: 2026-10-27, Swag scalar filter over owned picture planes.
// @NOTICE: THIRDPARTY.md#ffmpeg-realvideo-decoder
#global namespace RealVideo
#global internal

using Core

private func edgeFilter(src: [*] u8, stride, dither, limitQ, limitP, alpha, beta, beta2: s32, chroma, edge, vertical: bool)
{
    let step  = vertical ? 1 : stride
    let along = vertical ? stride : 1
    var sumP:   s32
    var sumQ:   s32
    var outerP: s32
    var outerQ: s32
    for i in 4's32
    {
        let p = src + i * along
        sumP   += cast(s32, p[-2 * step]) - cast(s32, p[-step])
        sumQ   += cast(s32, p[step]) - cast(s32, p[0])
        outerP += cast(s32, p[-2 * step]) - cast(s32, p[-3 * step])
        outerQ += cast(s32, p[step]) - cast(s32, p[2 * step])
    }

    let filterP = Math.abs(sumP) < beta * 4
    let filterQ = Math.abs(sumQ) < beta * 4
    if not filterP and not filterQ do
        return
    let strong = edge and filterP and filterQ and Math.abs(outerP) < beta2 and Math.abs(outerQ) < beta2
    var limit  = cast(s32, filterP) + cast(s32, filterQ) + ((limitP + limitQ) >> 1) + 1
    let both   = filterP and filterQ
    if not strong and not both do
        limit >>= 1
    const DitherP = [64, 80, 32, 96, 48, 80, 64, 48, 80, 64, 80, 48, 96, 32, 80, 64]
    const DitherQ = [64, 48, 96, 32, 80, 48, 48, 64, 64, 64, 80, 48, 32, 96, 48, 64]
    for i in 4's32
    {
        let p     = src + i * along
        let delta = cast(s32, p[0]) - cast(s32, p[-step])
        if not delta do
            continue
        let flag = (alpha * Math.abs(delta)) >> 7
        if strong
        {
            if flag > 1 do
                continue
            var p0 = (25 * cast(s32, p[-3 * step]) + 26 * cast(s32, p[-2 * step]) + 26 * cast(s32, p[-step]) + 26 * cast(s32, p[0]) + 25 * cast(s32, p[step]) + DitherP[dither + i]) >> 7
            var q0 = (25 * cast(s32, p[-2 * step]) + 26 * cast(s32, p[-step]) + 26 * cast(s32, p[0]) + 26 * cast(s32, p[step]) + 25 * cast(s32, p[2 * step]) + DitherQ[dither + i]) >> 7
            if flag != 0
            {
                p0 = Math.clamp(p0, cast(s32, p[-step]) - limit, cast(s32, p[-step]) + limit)
                q0 = Math.clamp(q0, cast(s32, p[0]) - limit, cast(s32, p[0]) + limit)
            }

            var p1 = (25 * cast(s32, p[-4 * step]) + 26 * cast(s32, p[-3 * step]) + 26 * cast(s32, p[-2 * step]) + 26 * p0 + 25 * cast(s32, p[0]) + DitherP[dither + i]) >> 7
            var q1 = (25 * cast(s32, p[-step]) + 26 * q0 + 26 * cast(s32, p[step]) + 26 * cast(s32, p[2 * step]) + 25 * cast(s32, p[3 * step]) + DitherQ[dither + i]) >> 7
            if flag != 0
            {
                p1 = Math.clamp(p1, cast(s32, p[-2 * step]) - limit, cast(s32, p[-2 * step]) + limit)
                q1 = Math.clamp(q1, cast(s32, p[step]) - limit, cast(s32, p[step]) + limit)
            }

            p[-2 * step] = cast(u8, p1)
            p[-step]     = cast(u8, p0)
            p[0]         = cast(u8, q0)
            p[step]      = cast(u8, q1)
            if not chroma
            {
                p[-3 * step] = cast(u8, ((25 * p0 + 26 * p1 + 51 * cast(s32, p[-3 * step]) + 26 * cast(s32, p[-4 * step]) + 64) >> 7))
                p[2 * step]  = cast(u8, ((25 * q0 + 26 * q1 + 51 * cast(s32, p[2 * step]) + 26 * cast(s32, p[3 * step]) + 64) >> 7))
            }
        }
        else
        {
            if flag > 3 - cast(s32, both) do
                continue
            let p10  = cast(s32, p[-2 * step]) - cast(s32, p[-step])
            let q10  = cast(s32, p[step]) - cast(s32, p[0])
            let p12  = cast(s32, p[-2 * step]) - cast(s32, p[-3 * step])
            let q12  = cast(s32, p[step]) - cast(s32, p[2 * step])
            let t    = delta * 4 + (both ? cast(s32, p[-2 * step]) - cast(s32, p[step]) : 0)
            let diff = Math.clamp((t + 4) >> 3, -limit, limit)
            p[-step] = clipped(cast(s32, p[-step]) + diff)
            p[0]     = clipped(cast(s32, p[0]) - diff)
            let lp = both ? limitP : limitP >> 1
            let lq = both ? limitQ : limitQ >> 1
            if filterP and Math.abs(p12) <= beta do
                p[-2 * step] = clipped(cast(s32, p[-2 * step]) - Math.clamp((p10 + p12 - diff) >> 1, -lp, lp))
            if filterQ and Math.abs(q12) <= beta do
                p[step] = clipped(cast(s32, p[step]) - Math.clamp((q10 + q12 + diff) >> 1, -lq, lq))
        }
    }
}

func filterFrame(frame: *Frame)
{
    for row in frame.rows
    {
        for column in frame.columns
        {
            let block = &frame.blocks[row * frame.columns + column]
            if block.kind <= Intra16 or block.kind == Mixed16
            {
                block.cbp     |= 65535
                block.deblock = 65535
            }

            if block.kind <= Intra16 do
                block.cbp |= 0xFF0000
        }

        for column in frame.columns
        {
            let index      = row * frame.columns + column
            let quant      = frame.blocks[index].quant
            let alpha      = Alpha[quant]
            let beta       = Beta[quant]
            let betaY      = beta * (frame.planes[0].width * frame.planes[0].height <= 176 * 144 ? 4 : 3)
            var strong: [4] bool
            var clips:  [4] s32
            var cbp:    [4] u32
            var masks:  [4] u32
            var chroma: [4][2] u32
            let neighbours = [index, index - frame.columns, index - 1, index + frame.columns]
            let available  = [true, row > 0, column > 0, row + 1 < frame.rows]
            for i in 4'u32
            {
                let kind = available[i] ? frame.blocks[neighbours[i]].kind : frame.blocks[index].kind
                strong[i] = kind <= Intra16 or kind == Mixed16
                clips[i]  = FilterClip[(strong[i] ? 64 : 32) + quant]
                if available[i]
                {
                    let block = &frame.blocks[neighbours[i]]
                    cbp[i]       = block.cbp & 65535
                    masks[i]     = block.deblock
                    chroma[i][0] = (block.cbp >> 16) & 15
                    chroma[i][1] = (block.cbp >> 20) & 15
                }
            }

            let all = masks[0] | (masks[3] << 16)
            var horizontalMask = all | ((cbp[0] << 4) & ~15'u32) | ((cbp[1] & 0xF000) >> 12)
            var verticalMask   = all | ((cbp[0] << 1) & ~0x1111'u32) | ((cbp[2] & 0x8888) >> 3)
            if column == 0 do
                verticalMask &= ~0x1111'u32
            if row == 0 do
                horizontalMask &= ~15'u32
            if row + 1 == frame.rows or strong[0] or strong[3] do
                horizontalMask &= ~(15'u32 << 16)
            for y in 4's32
            {
                for x in 4's32
                {
                    let bit         = cast(u32, (y * 4 + x))
                    let currentClip = (all & (1 << bit)) != 0 ? clips[0] : 0
                    let dither      = y > 0 ? y * 4 + x : x * 4
                    let plane       = &frame.planes[0]
                    let dst         = plane.at(cast(s32, column) * 16 + x * 4, cast(s32, row) * 16 + y * 4)
                    if (horizontalMask & (16 << bit)) != 0 do
                        edgeFilter(dst + 4 * plane.stride, plane.stride, dither, (all & (16 << bit)) != 0 ? clips[0] : 0, currentClip, alpha, beta, betaY, false, false, false)
                    if (verticalMask & (1 << bit)) != 0 and (x > 0 or not (strong[0] or strong[2]))
                    {
                        let leftClip = x == 0 ? ((masks[2] & (8 << cast(u32, (y * 4)))) != 0 ? clips[2] : 0) : ((all & (1 << (bit - 1))) != 0 ? clips[0] : 0)
                        edgeFilter(dst, plane.stride, dither, currentClip, leftClip, alpha, beta, betaY, false, false, true)
                    }

                    if y == 0 and (horizontalMask & (1 << bit)) != 0 and (strong[0] or strong[1]) do
                        edgeFilter(dst, plane.stride, dither, currentClip, (masks[1] & (4096 << bit)) != 0 ? clips[1] : 0, alpha, beta, betaY, false, true, false)
                    if x == 0 and (verticalMask & (1 << bit)) != 0 and (strong[0] or strong[2]) do
                        edgeFilter(dst, plane.stride, dither, currentClip, (masks[2] & (8 << cast(u32, (y * 4)))) != 0 ? clips[2] : 0, alpha, beta, betaY, false, true, true)
                }
            }

            for channel in 2'u32
            {
                let allChroma = (chroma[3][channel] << 4) | chroma[0][channel]
                var vm        = allChroma | ((chroma[0][channel] << 1) & ~5'u32) | ((chroma[2][channel] & 10) >> 1)
                var hm        = allChroma | ((chroma[1][channel] & 12) >> 2) | (chroma[0][channel] << 2)
                if column == 0 do
                    vm &= ~5'u32
                if row == 0 do
                    hm &= ~3'u32
                if row + 1 == frame.rows or strong[0] or strong[3] do
                    hm &= ~(3'u32 << 4)
                let plane = &frame.planes[channel + 1]
                for y in 2's32
                {
                    for x in 2's32
                    {
                        let bit  = cast(u32, (x + y * 2))
                        let dst  = plane.at(cast(s32, column) * 8 + x * 4, cast(s32, row) * 8 + y * 4)
                        let clip = (allChroma & (1 << bit)) != 0 ? clips[0] : 0
                        if (hm & (4 << bit)) != 0 do
                            edgeFilter(dst + 4 * plane.stride, plane.stride, x * 8, (allChroma & (4 << bit)) != 0 ? clips[0] : 0, clip, alpha, beta, beta * 3, true, false, false)
                        if (vm & (1 << bit)) != 0 and (x > 0 or not (strong[0] or strong[2]))
                        {
                            let leftClip = x == 0 ? ((chroma[2][channel] & (1 << cast(u32, (2 * y + 1)))) != 0 ? clips[2] : 0) : ((allChroma & (1 << (bit - 1))) != 0 ? clips[0] : 0)
                            edgeFilter(dst, plane.stride, y * 8, clip, leftClip, alpha, beta, beta * 3, true, false, true)
                        }

                        if y == 0 and (hm & (1 << bit)) != 0 and (strong[0] or strong[1]) do
                            edgeFilter(dst, plane.stride, x * 8, clip, (chroma[1][channel] & (4 << bit)) != 0 ? clips[1] : 0, alpha, beta, beta * 3, true, true, false)
                        if x == 0 and (vm & (1 << bit)) != 0 and (strong[0] or strong[2]) do
                            edgeFilter(dst, plane.stride, y * 8, clip, (chroma[2][channel] & (1 << cast(u32, (2 * y + 1)))) != 0 ? clips[2] : 0, alpha, beta, beta * 3, true, true, true)
                    }
                }
            }
        }
    }
}
