#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Fingerprints levels and local reconstruction over every QP and both nearly
// smooth and strongly changing residuals. The fingerprint is recorded before
// the shortcut is enabled and must remain unchanged afterwards.
#[Swag.TestTag("h264.quantize.inter.zero-bound")]
#test
{
    const SourceStride = 11'u64
    const PredictionStride = 9'u64
    const Expected: [52] u64 = [
        137009783, 194583880, 289792867, 38629090, 187937523, 91432102,
        739306458, 718274657, 982489454, 506252987, 265431542, 818148332,
        198369202, 497040063, 226635208, 39936095, 255425158, 877721713,
        844593964, 811496155, 36453606, 130608090, 16200580, 840303154,
        784329268, 733075286, 460304016, 307939025, 119202652, 240851765,
        480980350, 786866782, 972598628, 524721593, 586236208, 588776057,
        619741626, 34593263, 320090190, 700394487, 271276409, 807770668,
        30462986, 321440921, 224066331, 836910807, 527880446, 927699892,
        128856738, 248087203, 341576215, 575292433]
    var checksums: [52] u64
    for qp in 52'u32
    {
        var checksum = 0'u64
        for seed in 128'u64
        {
            var source: [4 * SourceStride] u8
            var prediction: [4 * PredictionStride] u8
            for row in 4'u64
            {
                for column in 4'u64
                {
                    let base = cast(s32, 32 + (seed * 37 + row * 31 + column * 19) % 192)
                    let residue = cast(s32, (seed * 17 + row * 11 + column * 29) % 25) - 12
                    var delta = residue
                    switch seed % 4
                    {
                    case 0: delta = residue / 4
                    case 1: delta = 4
                    case 2: delta = residue
                    case 3: delta = residue * 5
                    }
                    prediction[row * PredictionStride + column] = cast(u8, base)
                    source[row * SourceStride + column] =
                        cast(u8, Math.clamp(base + delta, 0, 255))
                }
            }
            var result: H264.InterLuma4x4Result
            H264.quantizeInterLuma4x4(source.buffer, prediction.buffer,
                                      SourceStride, PredictionStride, qp, &result)
            checksum = (checksum * 65_599 + cast(u64, result.nonZero)) % 1_000_000_007
            for level in result.levels do
                checksum = (checksum * 65_599 + cast(u64, cast(s32, level) + 32_768)) %
                           1_000_000_007
            for pixel in result.reconstructed do
                checksum = (checksum * 65_599 + cast(u64, pixel)) % 1_000_000_007
        }
        checksums[qp] = checksum
    }
    for qp in 52'u32 do
        Swag.require(checksums[qp] == Expected[qp])
}

// A one-pixel impulse gives exact transform coefficients with known weights.
// Sweep all signed amplitudes so every QP crosses its zero-rounding boundary.
#[Swag.TestTag("h264.quantize.inter.zero-bound")]
#test
{
    const Gains: [4] s32 = [1, 2, 1, 1]
    for qp in 52'u32
    {
        let qmod = cast(u64, qp % 6)
        let qbits = 15 + qp / 6
        for amplitude in 256'u32
        {
            let delta = cast(s32, amplitude) - 128
            var source: [16] u8
            var prediction: [16] u8
            for index in 16'u64
            {
                source[index] = 128
                prediction[index] = 128
            }
            source[0] = cast(u8, 128 + delta)
            var result: H264.InterLuma4x4Result
            H264.quantizeInterLuma4x4(source.buffer, prediction.buffer, 4, 4, qp, &result)
            var nonZero = 0'u8
            for row in 4'u64
            {
                for column in 4'u64
                {
                    let coefficient = delta * Gains[row] * Gains[column]
                    let class = (row & 1) + (column & 1)
                    let factor = cast(s64, H264.InterLuma4x4QuantFactor[qmod, class])
                    let magnitude = (cast(s64, Math.abs(coefficient)) * factor +
                                     (1's64 << (qbits - 1))) >> qbits
                    let level = cast(s16, coefficient < 0 ? -magnitude : magnitude)
                    let scan = H264.InterLuma4x4ScanPosition[row * 4 + column]
                    Swag.require(result.levels[scan] == level)
                    if level do
                        nonZero += 1
                }
            }
            Swag.require(result.nonZero == nonZero)
        }
    }
}
