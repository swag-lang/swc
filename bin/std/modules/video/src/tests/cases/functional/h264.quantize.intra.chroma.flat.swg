#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Flat intra chroma has a different constant prediction in each quadrant. The
// generic inter chroma quantizer is the reference for DC levels and pixels.
#[Swag.TestTag("h264.quantize.intra.chroma.flat")]
#test
{
    const SourceStride = 20'u64
    const ReferenceStride = 32'u64
    const Offsets: [3] s32 = [-12, 0, 12]
    const Sources: [7] u8 = [0, 1, 19, 37, 128, 254, 255]
    for qp in 52'u32
    {
        for offset in Offsets
        {
            for seed in 7'u64
            {
                let a = cast(u8, (seed * 29 + 5) & 255)
                let b = cast(u8, (seed * 47 + 37) & 255)
                let c = cast(u8, (seed * 17 + 109) & 255)
                let d = cast(u8, (seed * 61 + 211) & 255)
                var source: [8 * SourceStride] u8
                var reference: [16 * ReferenceStride] u8
                for plane in 2'u64
                {
                    for row in 8'u64
                    {
                        for column in 8'u64 do
                            source[row * SourceStride + column * 2 + plane] =
                                Sources[(seed + plane) % Sources.count]
                    }
                    for index in 4'u64
                    {
                        reference[7 * ReferenceStride + 16 + index * 2 + plane] = a
                        reference[7 * ReferenceStride + 16 + (4 + index) * 2 + plane] = b
                        reference[(8 + index) * ReferenceStride + 14 + plane] = c
                        reference[(12 + index) * ReferenceStride + 14 + plane] = d
                    }
                }
                for border in 4'u64
                {
                    let hasLeft = (border & 1) != 0
                    let hasTop = (border & 2) != 0
                    var predictors: [4] u8
                    if hasLeft and hasTop
                    {
                        predictors[0] = cast(u8, (cast(u32, a) + cast(u32, c) + 1) / 2)
                        predictors[1] = b
                        predictors[2] = d
                        predictors[3] = cast(u8, (cast(u32, b) + cast(u32, d) + 1) / 2)
                    }
                    elif hasTop
                    {
                        predictors[0] = a
                        predictors[1] = b
                        predictors[2] = a
                        predictors[3] = b
                    }
                    elif hasLeft
                    {
                        predictors[0] = c
                        predictors[1] = c
                        predictors[2] = d
                        predictors[3] = d
                    }
                    else
                    {
                        for &value in predictors do
                            value[] = 128
                    }
                    var prediction: [8 * 16] u8
                    for row in 8'u64
                    {
                        for column in 8'u64
                        {
                            let quadrant = (row >= 4 ? 2'u64 : 0'u64) +
                                           (column >= 4 ? 1'u64 : 0'u64)
                            for plane in 2'u64 do
                                prediction[row * 16 + column * 2 + plane] = predictors[quadrant]
                        }
                    }
                    for plane in 2'u32
                    {
                        var actual: H264.InterChroma8x8Result
                        var expected: H264.InterChroma8x8Result
                        H264.quantizeIntraChroma8x8(source.buffer, SourceStride,
                            reference.buffer, ReferenceStride, 16, 16, plane,
                            hasLeft, hasTop, qp, offset, &actual)
                        H264.quantizeInterChroma8x8(source.buffer + plane,
                            prediction.buffer + plane, SourceStride, 16, qp, offset, &expected)
                        Swag.require(actual.qpc == expected.qpc and actual.cbp == expected.cbp)
                        Swag.require(Memory.compare(actual.dc.buffer, expected.dc.buffer, 8) == 0)
                        Swag.require(Memory.compare(actual.ac.buffer, expected.ac.buffer, 128) == 0)
                        Swag.require(Memory.compare(actual.nonZeroAc.buffer,
                                                    expected.nonZeroAc.buffer, 4) == 0)
                        Swag.require(Memory.compare(actual.reconstructed.buffer,
                                                    expected.reconstructed.buffer, 64) == 0)
                    }
                }
            }
        }
    }
}
