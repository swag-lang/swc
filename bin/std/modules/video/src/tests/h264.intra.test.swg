#global if #command == Swag.CompilerCommand.Test
#global internal

using Core

const IntraTestStride = 32'u64

func referenceIntra16x16(mode: u32, dst: [*] u8, hasLeft, hasTop: bool)
{
    switch mode
    {
    case H264.Intra16Vertical:
        for row in 16'u64
        {
            for column in 16'u64 do
                dst[row * IntraTestStride + column] = (dst - IntraTestStride)[column]
        }

    case H264.Intra16Horizontal:
        for row in 16'u64
        {
            for column in 16'u64 do
                dst[row * IntraTestStride + column] = (dst - 1)[row * IntraTestStride]
        }

    case H264.Intra16Dc:
        var sum   = 0's32
        var count = 0's32
        if hasLeft
        {
            for row in 16'u64 do
                sum += cast(s32) (dst - 1)[row * IntraTestStride]
            count += 16
        }

        if hasTop
        {
            for column in 16'u64 do
                sum += cast(s32) (dst - IntraTestStride)[column]
            count += 16
        }

        let value = count == 32 ? (sum + 16) >> 5 : (count == 16 ? (sum + 8) >> 4 : 128)
        for row in 16'u64
        {
            for column in 16'u64 do
                dst[row * IntraTestStride + column] = cast(u8) value
        }

    default:
        Debug.assert(false)
    }
}

func referenceIntra8x8Vertical(dst: [*] u8, hasTop, hasTopLeft, hasTopRight: bool)
{
    var rawTop: [16] s32
    let rawCorner = hasTopLeft ? cast(s32) (dst - IntraTestStride - 1)[0] : 128
    for column in 8'u64 do
        rawTop[column] = hasTop ? cast(s32) (dst - IntraTestStride)[column] : 128
    for column in 8'u64 until 16
    {
        if hasTopRight do
            rawTop[column] = cast(s32) (dst - IntraTestStride)[column]
        elif hasTop do
            rawTop[column] = rawTop[7]
        else do
            rawTop[column] = 128
    }

    var top: [8] u8
    top[0] = cast(u8) (((hasTopLeft ? rawCorner : rawTop[0]) + 2 * rawTop[0] + rawTop[1] + 2) >> 2)
    for column in 1'u64 until 8 do
        top[column] = cast(u8) ((rawTop[column - 1] + 2 * rawTop[column] + rawTop[column + 1] + 2) >> 2)
    for row in 8'u64
    {
        for column in 8'u64 do
            dst[row * IntraTestStride + column] = top[column]
    }
}

func initializeIntraBuffers(expected, actual: [*] u8)
{
    for index in 1024
    {
        let value = cast(u8) ((index * 37 + 11) & 255)
        expected[index] = value
        actual[index]   = value
    }
}

#test
{
    const Availability = [false, true]
    const Modes        = [H264.Intra16Vertical, H264.Intra16Horizontal, H264.Intra16Dc]
    var expected: [1024] u8
    var actual:   [1024] u8

    for mode in Modes
    {
        for hasLeft in Availability
        {
            for hasTop in Availability
            {
                initializeIntraBuffers(@dataof(expected), @dataof(actual))
                referenceIntra16x16(mode, @dataof(expected) + 33, hasLeft, hasTop)
                H264.intraPredict16x16(mode, @dataof(actual) + 33, IntraTestStride, hasLeft, hasTop)
                @assert(Memory.compare(@dataof(expected), @dataof(actual), @countof(actual)) == 0)
            }
        }
    }

    for hasLeft in Availability
    {
        for hasTopLeft in Availability
        {
            for hasTopRight in Availability
            {
                initializeIntraBuffers(@dataof(expected), @dataof(actual))
                referenceIntra8x8Vertical(@dataof(expected) + 33, true, hasTopLeft, hasTopRight)
                H264.intraPredict8x8(H264.IntraVertical, @dataof(actual) + 33, IntraTestStride, hasLeft, true, hasTopLeft, hasTopRight)
                @assert(Memory.compare(@dataof(expected), @dataof(actual), @countof(actual)) == 0)
            }
        }
    }
}
