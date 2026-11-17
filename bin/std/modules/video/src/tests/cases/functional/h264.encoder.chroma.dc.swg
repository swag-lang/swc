#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// The syntax may lose DC levels only when the decoder's inverse transform produces the same
// samples. Check the actual inverse kernel, including negative rounding and all chroma QPs.
#test
{
    var reduced = 0'u32
    for qp in 40'u64
    {
        let scale = cast(s64, H264.Dequant4Scale[(qp % 6) * 3]) * 16 << cast(u32, qp / 6)
        for seed in 256'u64
        {
            var levels: [4] s16
            for index in 4'u64 do
                levels[index] = cast(s16, cast(s32, (seed * (index * 13 + 7) + index * 19) % 33) - 16)
            let original = levels
            H264.lossyOptimizeChromaDc(levels.buffer, scale)

            var before = original
            var after  = levels
            H264.hadamard2x2(before.buffer)
            H264.hadamard2x2(after.buffer)
            for block in 4'u64
            {
                var expected: [64] u8
                var actual:   [64] u8
                for pixel in expected.count
                {
                    expected[pixel] = cast(u8, (pixel * 37 + seed) & 255)
                    actual[pixel]   = expected[pixel]
                }

                var beforeDc: [16] s16
                var afterDc:  [16] s16
                beforeDc[0] = cast(s16, Math.clamp((cast(s64, before[block]) * scale) >> 5, -32768, 32767))
                afterDc[0]  = cast(s16, Math.clamp((cast(s64, after[block]) * scale) >> 5, -32768, 32767))
                H264.addIdct4x4(expected.buffer, 16, beforeDc.buffer)
                H264.addIdct4x4(actual.buffer, 16, afterDc.buffer)
                Swag.require(Memory.compare(expected.buffer, actual.buffer, expected.count) == 0,
                             "chroma DC optimization changes decoded samples")
            }

            for index in 4'u64
            {
                Swag.require(Math.abs(cast(s32, levels[index])) <= Math.abs(cast(s32, original[index])))
                if levels[index] != original[index] do
                    reduced += 1
            }
        }
    }

    Swag.require(reduced > 0, "chroma DC optimization removed no redundant level")
}
