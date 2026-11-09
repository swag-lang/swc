#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A uniform 16x16 source has sixteen equal 4x4 DC values and no AC. Check the
// normative Hadamard/quantizer levels across QP and neighbour prediction edges.
#[Swag.TestTag("h264.quantize.intra.flat")]
#test
{
    const Sources: [7] u8 = [0, 1, 19, 37, 128, 254, 255]
    const Predictions: [5] u8 = [0, 16, 20, 128, 255]
    const Stride = 32'u64
    const SourceStride = 20'u64
    for qp in 52'u32
    {
        let qmod = cast(u64, qp % 6)
        let dcBits = 17 + qp / 6
        for sourceValue in Sources
        {
            for borderValue in Predictions
            {
                for border in 4'u64
                {
                    let hasLeft = (border & 1) != 0
                    let hasTop = (border & 2) != 0
                    var current: [32 * Stride] u8
                    var source: [16 * SourceStride] u8
                    for &value in current do
                        value[] = borderValue
                    for &value in source do
                        value[] = sourceValue
                    var result: H264.IntraLuma16x16Result
                    H264.quantizeIntraLuma16x16(source.buffer, SourceStride,
                                                current.buffer, Stride, 16, 16,
                                                hasLeft, hasTop, qp, &result)
                    let predictor = hasLeft or hasTop ? borderValue : 128'u8
                    Swag.require(result.prediction == predictor)
                    let coefficient = 256 * (cast(s32, sourceValue) - cast(s32, predictor))
                    let factor = cast(s64, H264.IntraLuma4x4QuantFactor[qmod, 0])
                    let magnitude = (cast(s64, Math.abs(coefficient)) * factor +
                                     (1's64 << (dcBits - 1))) >> dcBits
                    let expected = cast(s16, coefficient < 0 ? -magnitude : magnitude)
                    Swag.require(result.dc[0] == expected and result.cbpLuma == 0)
                    for index in 1'u64 until 16 do
                        Swag.require(result.dc[index] == 0)
                    for value in result.ac do
                        Swag.require(value == 0)
                    for value in result.nonZeroAc do
                        Swag.require(value == 0)
                }
            }
        }
    }
}
