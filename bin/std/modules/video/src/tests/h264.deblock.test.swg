#global if #command == Swag.CompilerCommand.Test
#global internal

using Core

const DeblockTestStride = 16'u64

func referenceFilterLumaHorizontal(pix: [*] u8, strengths: const *H264.EdgeStrength, indexA, alpha, beta: s32)
{
    for lane in 16'u64
    {
        let bs = strengths.bs[lane / 4]
        if bs == 0 do
            continue
        H264.filterLuma(pix + lane, DeblockTestStride, 1, bs, indexA, alpha, beta)
    }
}

func referenceFilterChromaHorizontal(pix: [*] u8, strengths: const *H264.EdgeStrength, indexA, alpha, beta: s32)
{
    for lane in 8'u64
    {
        let bs = strengths.bs[lane / 2]
        if bs == 0 do
            continue
        H264.filterChroma(pix + lane, DeblockTestStride, 1, bs, indexA, alpha, beta)
    }
}

func assertDeblockHorizontalCase(seed: u64, indexA: s32, strengths: const *H264.EdgeStrength)
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
    referenceFilterLumaHorizontal(expected.buffer + 4 * DeblockTestStride, strengths, indexA, alpha, beta)
    if strengths.bs[0] == 4 or strengths.bs[1] == 4 or strengths.bs[2] == 4 or strengths.bs[3] == 4 do
        H264.filterLumaStrongHorizontal(actual.buffer + 4 * DeblockTestStride, DeblockTestStride, strengths, indexA, alpha, beta)
    else do
        H264.filterLumaWeakHorizontal(actual.buffer + 4 * DeblockTestStride, DeblockTestStride, strengths, indexA, alpha, beta)
    Swag.assert(Memory.compare(expected.buffer, actual.buffer, actual.count) == 0)

    referenceFilterChromaHorizontal(expected.buffer + 4 * DeblockTestStride, strengths, indexA, alpha, beta)
    if strengths.bs[0] == 4 or strengths.bs[1] == 4 or strengths.bs[2] == 4 or strengths.bs[3] == 4 do
        H264.filterChromaStrongHorizontal(actual.buffer + 4 * DeblockTestStride, DeblockTestStride, strengths, indexA, alpha, beta)
    else do
        H264.filterChromaWeakHorizontal(actual.buffer + 4 * DeblockTestStride, DeblockTestStride, strengths, indexA, alpha, beta)
    Swag.assert(Memory.compare(expected.buffer, actual.buffer, actual.count) == 0)
}

#test
{
    const Indices = [16's32, 24, 32, 40, 51]
    var strengths: H264.EdgeStrength
    for seed in 16'u64
    {
        for indexA in Indices
        {
            for bs0 in 5'u32
            {
                for bs1 in 5'u32
                {
                    for bs2 in 5'u32
                    {
                        for bs3 in 5'u32
                        {
                            strengths.bs = [bs0, bs1, bs2, bs3]
                            assertDeblockHorizontalCase(seed, indexA, &strengths)
                        }
                    }
                }
            }
        }
    }
}

// The vertical kernels filter sixteen (eight for chroma) lines across a vertical edge; the
// scalar per-line filters of the decoder are the reference. The buffer is a small plane with
// sixteen lines of the test stride, the edge sitting in the middle of each line.
func assertDeblockVerticalCase(seed: u64, indexA: s32, strengths: const *H264.EdgeStrength)
{
    const Lines  = 16'u64
    const Stride = 32'u64
    var expected: [Lines * Stride] u8
    var actual:   [Lines * Stride] u8
    for index in Lines * Stride
    {
        let value = cast(u8) ((index * (seed * 11 + 3) + seed * 17 + 5) & 255)
        expected[index] = value
        actual[index]   = value
    }

    let alpha = cast(s32) H264.DeblockAlpha[cast(u64) indexA]
    let beta  = cast(s32) H264.DeblockBeta[cast(u64) indexA]

    // Luma: four strengths, four lines each.
    var reference = expected.buffer + 8
    for segment in 4'u64
    {
        let bs = strengths.bs[segment]
        for 4
        {
            if bs != 0 do
                H264.filterLuma(reference, 1, Stride, bs, indexA, alpha, beta)
            reference += Stride
        }
    }

    H264.filterLumaVertical(actual.buffer + 8, Stride, strengths, indexA, alpha, beta)
    Swag.assert(Memory.compare(expected.buffer, actual.buffer, actual.count) == 0)

    // Chroma: four strengths, two lines each, on the same samples.
    reference = expected.buffer + 8
    for segment in 4'u64
    {
        let bs = strengths.bs[segment]
        for 2
        {
            if bs != 0 do
                H264.filterChroma(reference, 1, Stride, bs, indexA, alpha, beta)
            reference += Stride
        }
    }

    if strengths.bs[0] < 4 and strengths.bs[1] < 4 and strengths.bs[2] < 4 and strengths.bs[3] < 4
    {
        H264.filterChromaWeakVertical(actual.buffer + 8, Stride, strengths, indexA, alpha, beta)
        Swag.assert(Memory.compare(expected.buffer, actual.buffer, actual.count) == 0)
    }
}

#test
{
    const Indices = [16's32, 24, 32, 40, 51]
    var strengths: H264.EdgeStrength
    for seed in 16'u64
    {
        for indexA in Indices
        {
            for bs0 in 5'u32
            {
                for bs1 in 5'u32
                {
                    for bs2 in 5'u32
                    {
                        for bs3 in 5'u32
                        {
                            strengths.bs = [bs0, bs1, bs2, bs3]
                            assertDeblockVerticalCase(seed, indexA, &strengths)
                        }
                    }
                }
            }
        }
    }
}
