#global if #command == Swag.CompilerCommand.Test
#global private

using Core

const WeightWidths  = [2's32, 4, 8, 16]
const WeightHeights = [2's32, 4, 8, 16]
const WeightDenoms  = [0's32, 1, 3, 7]
const WeightValues  = [-128's32, -1, 0, 1, 23, 127, 128]
const WeightOffsets = [-128's32, -1, 0, 1, 127]
const WeightStride  = 19'u64

func referenceWeightUni(dst: [*] u8, src: [*] u8, width, height, logDenom, weight, offset: s32)
{
    let rounding = logDenom > 0 ? 1's32 << cast(u32) (logDenom - 1) : 0's32
    for row in cast(u64) height
    {
        for column in cast(u64) width do
            dst[row * WeightStride + column] = H264.clampPixel(((cast(s32) src[row * 16 + column] * weight + rounding) >> cast(u32) logDenom) + offset)
    }
}

func referenceWeightBi(dst: [*] u8, src0, src1: [*] u8, width, height, logDenom, weight0, weight1, offset0, offset1: s32)
{
    let rounding = 1's32 << cast(u32) logDenom
    let offset   = (offset0 + offset1 + 1) >> 1
    for row in cast(u64) height
    {
        for column in cast(u64) width do
            dst[row * WeightStride + column] = H264.clampPixel(((cast(s32) src0[row * 16 + column] * weight0 + cast(s32) src1[row * 16 + column] * weight1 + rounding) >> cast(u32) (logDenom + 1)) + offset)
    }
}

func assertWeightUni(src: [*] u8, width, height, logDenom, weight, offset: s32)
{
    var expected: [304] u8
    var actual:   [304] u8
    for index in 304
    {
        expected[index] = 0xA5
        actual[index]   = 0xA5
    }

    referenceWeightUni(@dataof(expected), src, width, height, logDenom, weight, offset)
    H264.weightUni(@dataof(actual), WeightStride, src, 16, width, height, logDenom, weight, offset)
    @assert(Memory.compare(@dataof(expected), @dataof(actual), @countof(actual)) == 0)
}

func assertWeightBi(src0, src1: [*] u8, width, height, logDenom, weight0, weight1, offset0, offset1: s32)
{
    var expected: [304] u8
    var actual:   [304] u8
    for index in 304
    {
        expected[index] = 0x5A
        actual[index]   = 0x5A
    }

    referenceWeightBi(@dataof(expected), src0, src1, width, height, logDenom, weight0, weight1, offset0, offset1)
    H264.weightBi(@dataof(actual), WeightStride, src0, src1, 16, width, height, logDenom, weight0, weight1, offset0, offset1)
    @assert(Memory.compare(@dataof(expected), @dataof(actual), @countof(actual)) == 0)
}

#test
{
    var src0: [256] u8
    var src1: [256] u8
    for index in 256
    {
        src0[index] = cast(u8) ((index * 37 + 11) & 255)
        src1[index] = cast(u8) ((index * 19 + 73) & 255)
    }

    for width in WeightWidths
    {
        for height in WeightHeights
        {
            for logDenom in WeightDenoms
            {
                for weight in WeightValues
                {
                    for offset in WeightOffsets
                    {
                        assertWeightUni(@dataof(src0), width, height, logDenom, weight, offset)
                        assertWeightBi(@dataof(src0), @dataof(src1), width, height, logDenom, weight, -weight, offset, -offset)
                    }
                }
            }
        }
    }
}
