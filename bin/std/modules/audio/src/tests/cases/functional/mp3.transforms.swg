#global if #command == Swag.CompilerCommand.Test

using Core

// Check every window against the defining cosine sum for both vector groups and scalar tails.
#test
{
    for bands in [4_u32, 2]
    {
        for blockType in 4_u32
        {
            let short   = blockType == 2
            let bins    = short ? 6_u64 : 18
            let windows = short ? 3_u64 : 1
            var lines:    Mp3.Granule576
            var overlap:  Mp3.SubbandOverlap
            var expected: [4, 36] f64
            for band in bands
            {
                let base = cast(u64, band) * 18
                for i in 18_u64
                {
                    lines[base + i]  = cast(f32, cast(s32, ((base + i) * 13 % 23)) - 11) / 16
                    overlap[i, band] = cast(f32, (base + i)) / 64
                }

                for window in windows
                {
                    for sample in 2 * bins
                    {
                        var value = 0_f64
                        for bin in bins
                        {
                            let angle = Math.ConstF64.Pi * cast(f64, ((2 * sample + bins + 1) * (2 * bin + 1))) /
                                        cast(f64, 4 * bins)
                            value += cast(f64, lines[base + window + windows * bin]) * Math.cos(angle)
                        }

                        let start = short ? 6 * (window + 1) : 0
                        expected[band, start + sample] += value * cast(f64, Mp3.BlockWindow[blockType, sample])
                    }
                }

                for i in 18_u64
                {
                    expected[band, i] += cast(f64, overlap[i, band])
                }
            }

            discard Mp3.inverseTransformBands(&lines, &overlap, 0, bands, blockType)
            for band in bands
            {
                let base = cast(u64, band) * 18
                for i in 18_u64
                {
                    Swag.require(Math.abs(cast(f64, lines[base + i]) - expected[band, i]) < 2e-5)
                    Swag.require(Math.abs(cast(f64, overlap[i, band]) - expected[band, 18 + i]) < 2e-5)
                }
            }
        }
    }
}

// Expanding and shrinking the spectrum must still drain the preceding granule's overlap.
#test
{
    const Bounds: [6] u32 = [12, 4, 0, 9, 1, 0]
    var fullOverlap, boundedOverlap: Mp3.SubbandOverlap
    var previousEnd = 0_u32
    for frame in Bounds.count
    {
        var expected: Mp3.Granule576
        for i in cast(u64, Bounds[frame]) * 18
        {
            expected[i] = cast(f32, cast(s32, ((i * 13) % 23)) - 11) / 16
        }

        var actual = expected

        let mixed        = (frame & 1) != 0
        let longSubbands = mixed ? 2_u32 : 32_u32
        discard Mp3.inverseTransformBands(&expected, &fullOverlap, 0, longSubbands, 0)
        discard Mp3.inverseTransformBands(&expected, &fullOverlap, longSubbands, 32, 2)

        let longEnd  = Mp3.inverseTransformBands(&actual, &boundedOverlap, 0, longSubbands, 0, previousEnd)
        let shortEnd = Mp3.inverseTransformBands(&actual, &boundedOverlap, longSubbands, 32, 2, previousEnd)
        previousEnd = Math.max(longEnd, shortEnd)
        Swag.require(previousEnd == Bounds[frame])

        for band in 32_u64
        {
            for i in 18_u64
            {
                let at = band * 18 + i
                Swag.require(actual[at] == expected[at])
                Swag.require(boundedOverlap[i, band] == fullOverlap[i, band])
            }
        }
    }
}

// Check the polyphase delay line past its first wrap with every subband active.
#test
{
    var state:   Mp3.ChannelState
    var history: [36, 64] f64
    for granule in 2_u64
    {
        var lines: Mp3.Granule576
        var pcm:   Mp3.Granule576
        for i in 576_u64
        {
            lines[i] = cast(f32, cast(s32, ((i * 41 + granule * 53) % 97)) - 48) / 64
        }

        Mp3.synthesizeGranule(&state, &lines, &pcm[0])

        for block in 18_u64
        {
            let time = granule * 18 + block
            for row in 64_u64
            {
                var value = 0_f64
                for band in 32_u64
                {
                    let angle = Math.ConstF64.Pi * cast(f64, ((16 + row) * (2 * band + 1))) / 64
                    value += cast(f64, lines[band * 18 + block]) * Math.cos(angle)
                }

                history[time, row] = value
            }

            for i in 32_u64
            {
                var expected = 0_f64
                for tap in Math.min(time + 1, 16)
                {
                    expected += history[time - tap, (tap & 1) * 32 + i] * cast(f64, Mp3.SynthesisWindow[32 * tap + i])
                }

                Swag.require(Math.abs(cast(f64, pcm[block * 32 + i]) - expected) < 2e-5)
            }
        }
    }
}

// Equal logical filter histories must stay equal at different physical ring
// positions, as happens when a worker reconstructs the history before a chunk.
#test
{
    var serial, rotated: Mp3.ChannelState
    serial.reset()
    rotated.reset()
    rotated.filterAt = 2
    for granule in 3'u64
    {
        var lines, actual, expected: Mp3.Granule576
        for index in 576'u64 do
            lines[index] = cast(f32, cast(s32, ((index * 41 + granule * 53) % 97)) - 48) / 64

        Mp3.synthesizeGranule(&serial, &lines, &expected[0])
        Mp3.synthesizeGranule(&rotated, &lines, &actual[0])
        for index in 576'u64 do
            Swag.require(actual[index] == expected[index])
    }
}
