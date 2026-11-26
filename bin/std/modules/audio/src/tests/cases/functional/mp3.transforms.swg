#global if #command == Swag.CompilerCommand.Test

using Core

// Check each window against the defining cosine sum with energy in every spectral line.
#test
{
    for blockType in 4'u32
    {
        var lines:   Mp3.Granule576
        var overlap: [32, 18] f32
        for i in 18'u64
        {
            lines[i]      = cast(f32, cast(s32, (i * 13 % 23)) - 11) / 16
            overlap[0, i] = cast(f32, i) / 64
        }

        var expected: [36] f64
        let short   = blockType == 2
        let bins    = short ? 6'u64 : 18
        let windows = short ? 3'u64 : 1
        for window in windows
        {
            for sample in 2 * bins
            {
                var value = 0'f64
                for bin in bins
                {
                    let angle = Math.ConstF64.Pi * cast(f64, ((2 * sample + bins + 1) * (2 * bin + 1))) /
                                cast(f64, 4 * bins)
                    value += cast(f64, lines[window + windows * bin]) * Math.cos(angle)
                }

                let start = short ? 6 * (window + 1) : 0
                expected[start + sample] += value * cast(f64, Mp3.BlockWindow[blockType, sample])
            }
        }

        for i in 18'u64 do
            expected[i] += cast(f64, overlap[0, i])
        Mp3.inverseTransform(&lines, &overlap, 0, blockType)
        for i in 18'u64
        {
            Swag.require(Math.abs(cast(f64, lines[i]) - expected[i]) < 2e-5)
            Swag.require(Math.abs(cast(f64, overlap[0, i]) - expected[18 + i]) < 2e-5)
        }
    }
}

// Check the polyphase delay line past its first wrap with every subband active.
#test
{
    var state:   Mp3.ChannelState
    var history: [36, 64] f64
    for granule in 2'u64
    {
        var lines: Mp3.Granule576
        var pcm:   Mp3.Granule576
        for i in 576'u64 do
            lines[i] = cast(f32, cast(s32, ((i * 41 + granule * 53) % 97)) - 48) / 64
        Mp3.synthesizeGranule(&state, &lines, &pcm[0])

        for block in 18'u64
        {
            let time = granule * 18 + block
            for row in 64'u64
            {
                var value = 0'f64
                for band in 32'u64
                {
                    let angle = Math.ConstF64.Pi * cast(f64, ((16 + row) * (2 * band + 1))) / 64
                    value += cast(f64, lines[band * 18 + block]) * Math.cos(angle)
                }

                history[time, row] = value
            }

            for i in 32'u64
            {
                var expected = 0'f64
                for tap in Math.min(time + 1, 16) do
                    expected += history[time - tap, (tap & 1) * 32 + i] * cast(f64, Mp3.SynthesisWindow[32 * tap + i])
                Swag.require(Math.abs(cast(f64, pcm[block * 32 + i]) - expected) < 2e-5)
            }
        }
    }
}
