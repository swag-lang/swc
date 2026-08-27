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

    case H264.Intra16Plane:
        var h = cast(s32) (dst - IntraTestStride)[8] - cast(s32) (dst - IntraTestStride)[6]
        var v = cast(s32) (dst - 1)[8 * IntraTestStride] - cast(s32) (dst - 1)[6 * IntraTestStride]
        for k in 2 to 8
        {
            let topRight = cast(s32) (dst - IntraTestStride)[cast(u64) (7 + k)]
            let topLeft  = k == 8 ? cast(s32) (dst - IntraTestStride - 1)[0] : cast(s32) (dst - IntraTestStride)[cast(u64) (7 - k)]
            h += k * (topRight - topLeft)
            let leftDown = cast(s32) (dst - 1)[cast(u64) (7 + k) * IntraTestStride]
            let leftUp   = k == 8 ? cast(s32) (dst - IntraTestStride - 1)[0] : cast(s32) (dst - 1)[cast(u64) (7 - k) * IntraTestStride]
            v += k * (leftDown - leftUp)
        }

        h = (5 * h + 32) >> 6
        v = (5 * v + 32) >> 6
        var a = 16 * (cast(s32) (dst - 1)[15 * IntraTestStride] + cast(s32) (dst - IntraTestStride)[15] + 1) - 7 * (v + h)
        for row in 16'u64
        {
            var b = a
            a += v
            for column in 16'u64
            {
                dst[row * IntraTestStride + column] = H264.clampPixel(b >> 5)
                b += h
            }
        }

    default:
        Debug.assert(false)
    }
}

func referenceIntraChroma(mode: u32, dst: [*] u8, hasLeft, hasTop: bool)
{
    switch mode
    {
    case H264.IntraChromaDc:
        var sumTopLeft    = 0's32
        var sumTopRight   = 0's32
        var sumBottomLeft = 0's32
        for index in 4'u64
        {
            if hasTop
            {
                sumTopLeft  += cast(s32) (dst - IntraTestStride)[index]
                sumTopRight += cast(s32) (dst - IntraTestStride)[4 + index]
            }

            if hasLeft
            {
                sumTopLeft    += cast(s32) (dst - 1)[index * IntraTestStride]
                sumBottomLeft += cast(s32) (dst - 1)[(4 + index) * IntraTestStride]
            }
        }

        var dc0, dc1, dc2, dc3: s32
        if hasTop and hasLeft
        {
            dc0 = (sumTopLeft + 4) >> 3
            dc1 = (sumTopRight + 2) >> 2
            dc2 = (sumBottomLeft + 2) >> 2
            dc3 = (sumTopRight + sumBottomLeft + 4) >> 3
        }
        elif hasTop
        {
            dc0 = (sumTopLeft + 2) >> 2
            dc1 = (sumTopRight + 2) >> 2
            dc2 = dc0
            dc3 = dc1
        }
        elif hasLeft
        {
            dc0 = (sumTopLeft + 2) >> 2
            dc1 = dc0
            dc2 = (sumBottomLeft + 2) >> 2
            dc3 = dc2
        }
        else
        {
            dc0 = 128
            dc1 = 128
            dc2 = 128
            dc3 = 128
        }

        for row in 8'u64
        {
            for column in 8'u64
            {
                var value = dc3
                if row < 4 and column < 4 do
                    value = dc0
                elif row < 4 do
                    value = dc1
                elif column < 4 do
                    value = dc2
                dst[row * IntraTestStride + column] = cast(u8) value
            }
        }

    case H264.IntraChromaHorizontal:
        for row in 8'u64
        {
            for column in 8'u64 do
                dst[row * IntraTestStride + column] = (dst - 1)[row * IntraTestStride]
        }

    case H264.IntraChromaVertical:
        for row in 8'u64
        {
            for column in 8'u64 do
                dst[row * IntraTestStride + column] = (dst - IntraTestStride)[column]
        }

    case H264.IntraChromaPlane:
        var h = cast(s32) (dst - IntraTestStride)[4] - cast(s32) (dst - IntraTestStride)[2]
        var v = cast(s32) (dst - 1)[4 * IntraTestStride] - cast(s32) (dst - 1)[2 * IntraTestStride]
        for k in 2 to 4
        {
            let topRight = cast(s32) (dst - IntraTestStride)[cast(u64) (3 + k)]
            let topLeft  = k == 4 ? cast(s32) (dst - IntraTestStride - 1)[0] : cast(s32) (dst - IntraTestStride)[cast(u64) (3 - k)]
            h += k * (topRight - topLeft)
            let leftDown = cast(s32) (dst - 1)[cast(u64) (3 + k) * IntraTestStride]
            let leftUp   = k == 4 ? cast(s32) (dst - IntraTestStride - 1)[0] : cast(s32) (dst - 1)[cast(u64) (3 - k) * IntraTestStride]
            v += k * (leftDown - leftUp)
        }

        h = (17 * h + 16) >> 5
        v = (17 * v + 16) >> 5
        var a = 16 * (cast(s32) (dst - 1)[7 * IntraTestStride] + cast(s32) (dst - IntraTestStride)[7] + 1) - 3 * (v + h)
        for row in 8'u64
        {
            var b = a
            a += v
            for column in 8'u64
            {
                dst[row * IntraTestStride + column] = H264.clampPixel(b >> 5)
                b += h
            }
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
    const Modes        = [H264.Intra16Vertical, H264.Intra16Horizontal, H264.Intra16Dc, H264.Intra16Plane]
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

    const ChromaModes = [H264.IntraChromaDc, H264.IntraChromaHorizontal, H264.IntraChromaVertical, H264.IntraChromaPlane]
    for mode in ChromaModes
    {
        for hasLeft in Availability
        {
            for hasTop in Availability
            {
                initializeIntraBuffers(@dataof(expected), @dataof(actual))
                referenceIntraChroma(mode, @dataof(expected) + 33, hasLeft, hasTop)
                H264.intraPredictChroma(mode, @dataof(actual) + 33, IntraTestStride, hasLeft, hasTop)
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
