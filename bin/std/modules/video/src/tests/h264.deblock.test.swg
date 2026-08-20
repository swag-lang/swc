#global if #command == Swag.CompilerCommand.Test
#global internal

using Core

const DeblockTestStride = 16'u64

func referenceFilterLumaWeakHorizontal(pix: [*] u8, strengths: const *H264.EdgeStrength, indexA, alpha, beta: s32)
{
    for lane in 16'u64
    {
        let bs = strengths.bs[lane / 4]
        if bs == 0 do
            continue

        let sample = pix + lane
        let p0     = cast(s32) (sample - DeblockTestStride)[0]
        let q0     = cast(s32) sample[0]
        let p1     = cast(s32) (sample - 2 * DeblockTestStride)[0]
        let q1     = cast(s32) (sample + DeblockTestStride)[0]
        if Math.abs(p0 - q0) >= alpha or Math.abs(p1 - p0) >= beta or Math.abs(q1 - q0) >= beta do
            continue

        let p2    = cast(s32) (sample - 3 * DeblockTestStride)[0]
        let q2    = cast(s32) (sample + 2 * DeblockTestStride)[0]
        let ap    = Math.abs(p2 - p0) < beta
        let aq    = Math.abs(q2 - q0) < beta
        let tc0   = cast(s32) H264.DeblockTc0[cast(u64) indexA * 3 + cast(u64) (bs - 1)]
        let tc    = tc0 + cast(s32) ap + cast(s32) aq
        let delta = Math.clamp((((q0 - p0) << 2) + (p1 - q1) + 4) >> 3, -tc, tc)
        (sample - DeblockTestStride)[0] = H264.clampPixel(p0 + delta)
        sample[0] = H264.clampPixel(q0 - delta)

        if ap
        {
            let adjust = Math.clamp((p2 + ((p0 + q0 + 1) >> 1) - 2 * p1) >> 1, -tc0, tc0)
            (sample - 2 * DeblockTestStride)[0] = cast(u8) (p1 + adjust)
        }

        if aq
        {
            let adjust = Math.clamp((q2 + ((p0 + q0 + 1) >> 1) - 2 * q1) >> 1, -tc0, tc0)
            (sample + DeblockTestStride)[0] = cast(u8) (q1 + adjust)
        }
    }
}

func referenceFilterChromaWeakHorizontal(pix: [*] u8, strengths: const *H264.EdgeStrength, indexA, alpha, beta: s32)
{
    for lane in 8'u64
    {
        let bs = strengths.bs[lane / 2]
        if bs == 0 do
            continue

        let sample = pix + lane
        let p0     = cast(s32) (sample - DeblockTestStride)[0]
        let q0     = cast(s32) sample[0]
        let p1     = cast(s32) (sample - 2 * DeblockTestStride)[0]
        let q1     = cast(s32) (sample + DeblockTestStride)[0]
        if Math.abs(p0 - q0) >= alpha or Math.abs(p1 - p0) >= beta or Math.abs(q1 - q0) >= beta do
            continue

        let tc    = cast(s32) H264.DeblockTc0[cast(u64) indexA * 3 + cast(u64) (bs - 1)] + 1
        let delta = Math.clamp((((q0 - p0) << 2) + (p1 - q1) + 4) >> 3, -tc, tc)
        (sample - DeblockTestStride)[0] = H264.clampPixel(p0 + delta)
        sample[0] = H264.clampPixel(q0 - delta)
    }
}

func assertDeblockWeakCase(seed: u64, indexA: s32, strengths: const *H264.EdgeStrength)
{
    var expected: [128] u8
    var actual:   [128] u8
    for index in 128
    {
        let value = cast(u8) ((index * (seed * 14 + 1) + seed * 29 + 7) & 255)
        expected[index] = value
        actual[index]   = value
    }

    let alpha = cast(s32) H264.DeblockAlpha[cast(u64) indexA]
    let beta  = cast(s32) H264.DeblockBeta[cast(u64) indexA]
    referenceFilterLumaWeakHorizontal(@dataof(expected) + 3 * DeblockTestStride, strengths, indexA, alpha, beta)
    H264.filterLumaWeakHorizontal(@dataof(actual) + 3 * DeblockTestStride, DeblockTestStride, strengths, indexA, alpha, beta)
    @assert(Memory.compare(@dataof(expected), @dataof(actual), @countof(actual)) == 0)

    referenceFilterChromaWeakHorizontal(@dataof(expected) + 3 * DeblockTestStride, strengths, indexA, alpha, beta)
    H264.filterChromaWeakHorizontal(@dataof(actual) + 3 * DeblockTestStride, DeblockTestStride, strengths, indexA, alpha, beta)
    @assert(Memory.compare(@dataof(expected), @dataof(actual), @countof(actual)) == 0)
}

#test
{
    const Indices = [16's32, 24, 32, 40, 51]
    var strengths: H264.EdgeStrength
    for seed in 16'u64
    {
        for indexA in Indices
        {
            for bs0 in 4'u32
            {
                for bs1 in 4'u32
                {
                    for bs2 in 4'u32
                    {
                        for bs3 in 4'u32
                        {
                            strengths.bs = [bs0, bs1, bs2, bs3]
                            assertDeblockWeakCase(seed, indexA, &strengths)
                        }
                    }
                }
            }
        }
    }
}
