#global if #command == Swag.CompilerCommand.Test
#global internal

using Core

const IntraTestStride = 32'u64

func referenceIntra4x4(mode: u32, dst: [*] u8, hasLeft, hasTop, hasTopRight: bool)
{
    var top:  [8] u8
    var left: [4] u8
    for index in 4'u64
    {
        top[index]  = hasTop ? (dst - IntraTestStride)[index] : 128
        left[index] = hasLeft ? (dst - 1)[index * IntraTestStride] : 128
    }

    for index in 4'u64 until 8
    {
        if hasTopRight do
            top[index] = (dst - IntraTestStride)[index]
        elif hasTop do
            top[index] = top[3]
        else do
            top[index] = 128
    }

    switch mode
    {
    case H264.IntraVertical:
        for row in 4'u64
        {
            for column in 4'u64 do
                dst[row * IntraTestStride + column] = top[column]
        }

    case H264.IntraHorizontal:
        for row in 4'u64
        {
            for column in 4'u64 do
                dst[row * IntraTestStride + column] = left[row]
        }

    case H264.IntraDc:
        var sum   = 0'u32
        var count = 0'u32
        if hasTop
        {
            for index in 4'u64 do
                sum += top[index]
            count += 4
        }

        if hasLeft
        {
            for index in 4'u64 do
                sum += left[index]
            count += 4
        }

        let value = count == 8 ? cast(u8) ((sum + 4) >> 3) : (count == 4 ? cast(u8) ((sum + 2) >> 2) : 128)
        for row in 4'u64
        {
            for column in 4'u64 do
                dst[row * IntraTestStride + column] = value
        }

    case H264.IntraDownLeft:
        for row in 4'u64
        {
            for column in 4'u64
            {
                let diag  = row + column
                let value = diag == 6 ? (cast(s32) top[6] + 3 * cast(s32) top[7] + 2) >> 2 : (cast(s32) top[diag] + 2 * cast(s32) top[1 + diag] + cast(s32) top[2 + diag] + 2) >> 2
                dst[row * IntraTestStride + column] = cast(u8) value
            }
        }

    case H264.IntraVerticalLeft:
        for row in 4'u64
        {
            for column in 4'u64
            {
                let k     = column + (row >> 1)
                let value = row & 1 == 0 ? (cast(s32) top[k] + cast(s32) top[1 + k] + 1) >> 1 : (cast(s32) top[k] + 2 * cast(s32) top[1 + k] + cast(s32) top[2 + k] + 2) >> 2
                dst[row * IntraTestStride + column] = cast(u8) value
            }
        }

    case H264.IntraHorizontalUp:
        for row in 4'u64
        {
            for column in 4'u64
            {
                let z = column + 2 * row
                var value: s32
                if z > 5 do
                    value = left[3]
                elif z == 5 do
                    value = (cast(s32) left[2] + 3 * cast(s32) left[3] + 2) >> 2
                elif z & 1 == 0 do
                    value = (cast(s32) left[row + (column >> 1)] + cast(s32) left[1 + row + (column >> 1)] + 1) >> 1
                else do
                    value = (cast(s32) left[row + (column >> 1)] + 2 * cast(s32) left[1 + row + (column >> 1)] + cast(s32) left[2 + row + (column >> 1)] + 2) >> 2
                dst[row * IntraTestStride + column] = cast(u8) value
            }
        }

    default:
        Debug.assert(false)
    }
}

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

func referenceIntra8x8(mode: u32, dst: [*] u8, hasLeft, hasTop, hasTopLeft, hasTopRight: bool)
{
    var rawTop:  [16] s32
    var rawLeft: [8] s32
    let rawCorner = hasTopLeft ? cast(s32) (dst - IntraTestStride - 1)[0] : 128
    for row in 8'u64 do
        rawLeft[row] = hasLeft ? cast(s32) (dst - 1)[row * IntraTestStride] : 128
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

    var top:  [16] u8
    var left: [8] u8
    let corner = cast(u8) ((rawLeft[0] + 2 * rawCorner + rawTop[0] + 2) >> 2)
    top[0] = cast(u8) (((hasTopLeft ? rawCorner : rawTop[0]) + 2 * rawTop[0] + rawTop[1] + 2) >> 2)
    for column in 1'u64 until 15 do
        top[column] = cast(u8) ((rawTop[column - 1] + 2 * rawTop[column] + rawTop[column + 1] + 2) >> 2)
    top[15] = cast(u8) ((rawTop[14] + 3 * rawTop[15] + 2) >> 2)
    left[0] = cast(u8) (((hasTopLeft ? rawCorner : rawLeft[0]) + 2 * rawLeft[0] + rawLeft[1] + 2) >> 2)
    for row in 1'u64 until 7 do
        left[row] = cast(u8) ((rawLeft[row - 1] + 2 * rawLeft[row] + rawLeft[row + 1] + 2) >> 2)
    left[7] = cast(u8) ((rawLeft[6] + 3 * rawLeft[7] + 2) >> 2)

    switch mode
    {
    case H264.IntraVertical:
        for row in 8'u64
        {
            for column in 8'u64 do
                dst[row * IntraTestStride + column] = top[column]
        }

    case H264.IntraHorizontal:
        for row in 8'u64
        {
            for column in 8'u64 do
                dst[row * IntraTestStride + column] = left[row]
        }

    case H264.IntraDc:
        var sum   = 0'u32
        var count = 0'u32
        if hasTop
        {
            for index in 8'u64 do
                sum += top[index]
            count += 8
        }

        if hasLeft
        {
            for index in 8'u64 do
                sum += left[index]
            count += 8
        }

        let value = count == 16 ? cast(u8) ((sum + 8) >> 4) : (count == 8 ? cast(u8) ((sum + 4) >> 3) : 128)
        for row in 8'u64
        {
            for column in 8'u64 do
                dst[row * IntraTestStride + column] = value
        }

    case H264.IntraDownLeft:
        for row in 8'u64
        {
            for column in 8'u64
            {
                let diag  = row + column
                let value = diag == 14 ? (cast(s32) top[14] + 3 * cast(s32) top[15] + 2) >> 2 : (cast(s32) top[diag] + 2 * cast(s32) top[1 + diag] + cast(s32) top[2 + diag] + 2) >> 2
                dst[row * IntraTestStride + column] = cast(u8) value
            }
        }

    case H264.IntraDownRight:
        for row in 8's64
        {
            for column in 8's64
            {
                let diag = column - row
                var value: s32
                if diag >= 1
                {
                    let first  = diag == 1 ? corner : top[cast(u64) diag - 2]
                    let second = top[cast(u64) diag - 1]
                    let third  = top[cast(u64) diag]
                    value = (cast(s32) first + 2 * cast(s32) second + cast(s32) third + 2) >> 2
                }
                elif diag == 0 do
                    value = (cast(s32) left[0] + 2 * cast(s32) corner + cast(s32) top[0] + 2) >> 2
                else
                {
                    let distance = cast(u64) -diag
                    let first    = left[distance]
                    let second   = left[distance - 1]
                    let third    = distance == 1 ? corner : left[distance - 2]
                    value = (cast(s32) first + 2 * cast(s32) second + cast(s32) third + 2) >> 2
                }

                dst[cast(u64) row * IntraTestStride + cast(u64) column] = cast(u8) value
            }
        }

    case H264.IntraHorizontalDown:
        var topRef:  [18] s32
        var leftRef: [10] s32
        topRef[0]  = left[0]
        topRef[1]  = corner
        leftRef[0] = top[0]
        leftRef[1] = corner
        for index in 16'u64 do
            topRef[2 + index] = top[index]
        for index in 8'u64 do
            leftRef[2 + index] = left[index]

        for row in 8's64
        {
            for column in 8's64
            {
                let z = 2 * row - column
                var value: s32
                if z >= 0 and z & 1 == 0
                {
                    let k = cast(u64) (row - (column >> 1))
                    value = (leftRef[k + 1] + leftRef[k + 2] + 1) >> 1
                }
                elif z >= -1
                {
                    let k = cast(u64) (row - (column >> 1))
                    value = (leftRef[k] + 2 * leftRef[k + 1] + leftRef[k + 2] + 2) >> 2
                }
                else
                {
                    let e = cast(u64) (column - 2 * row)
                    value = (topRef[e + 1] + 2 * topRef[e] + topRef[e - 1] + 2) >> 2
                }

                dst[cast(u64) row * IntraTestStride + cast(u64) column] = cast(u8) value
            }
        }

    case H264.IntraVerticalLeft:
        for row in 8'u64
        {
            for column in 8'u64
            {
                let k     = column + (row >> 1)
                let value = row & 1 == 0 ? (cast(s32) top[k] + cast(s32) top[1 + k] + 1) >> 1 : (cast(s32) top[k] + 2 * cast(s32) top[1 + k] + cast(s32) top[2 + k] + 2) >> 2
                dst[row * IntraTestStride + column] = cast(u8) value
            }
        }

    case H264.IntraHorizontalUp:
        for row in 8'u64
        {
            for column in 8'u64
            {
                let z = column + 2 * row
                var value: s32
                if z > 13 do
                    value = left[7]
                elif z == 13 do
                    value = (cast(s32) left[6] + 3 * cast(s32) left[7] + 2) >> 2
                elif z & 1 == 0 do
                    value = (cast(s32) left[row + (column >> 1)] + cast(s32) left[1 + row + (column >> 1)] + 1) >> 1
                else do
                    value = (cast(s32) left[row + (column >> 1)] + 2 * cast(s32) left[1 + row + (column >> 1)] + cast(s32) left[2 + row + (column >> 1)] + 2) >> 2
                dst[row * IntraTestStride + column] = cast(u8) value
            }
        }

    default:
        Debug.assert(false)
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
    const Intra4Modes  = [H264.IntraVertical, H264.IntraHorizontal, H264.IntraDc, H264.IntraDownLeft, H264.IntraVerticalLeft, H264.IntraHorizontalUp]
    const Intra8Modes  = [H264.IntraVertical, H264.IntraHorizontal, H264.IntraDc, H264.IntraDownLeft, H264.IntraDownRight, H264.IntraHorizontalDown, H264.IntraVerticalLeft, H264.IntraHorizontalUp]
    const Modes        = [H264.Intra16Vertical, H264.Intra16Horizontal, H264.Intra16Dc, H264.Intra16Plane]
    var expected: [1024] u8
    var actual:   [1024] u8

    for mode in Intra4Modes
    {
        for hasLeft in Availability
        {
            for hasTop in Availability
            {
                for hasTopRight in Availability
                {
                    initializeIntraBuffers(expected.buffer, actual.buffer)
                    referenceIntra4x4(mode, expected.buffer + 33, hasLeft, hasTop, hasTopRight)
                    H264.intraPredict4x4(mode, actual.buffer + 33, IntraTestStride, hasLeft, hasTop, true, hasTopRight)
                    Swag.assert(Memory.compare(expected.buffer, actual.buffer, actual.count) == 0)
                }
            }
        }
    }

    for mode in Modes
    {
        for hasLeft in Availability
        {
            for hasTop in Availability
            {
                initializeIntraBuffers(expected.buffer, actual.buffer)
                referenceIntra16x16(mode, expected.buffer + 33, hasLeft, hasTop)
                H264.intraPredict16x16(mode, actual.buffer + 33, IntraTestStride, hasLeft, hasTop)
                Swag.assert(Memory.compare(expected.buffer, actual.buffer, actual.count) == 0)
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
                initializeIntraBuffers(expected.buffer, actual.buffer)
                referenceIntraChroma(mode, expected.buffer + 33, hasLeft, hasTop)
                H264.intraPredictChroma(mode, actual.buffer + 33, IntraTestStride, hasLeft, hasTop)
                Swag.assert(Memory.compare(expected.buffer, actual.buffer, actual.count) == 0)
            }
        }
    }

    for mode in Intra8Modes
    {
        for hasLeft in Availability
        {
            for hasTop in Availability
            {
                for hasTopLeft in Availability
                {
                    for hasTopRight in Availability
                    {
                        initializeIntraBuffers(expected.buffer, actual.buffer)
                        referenceIntra8x8(mode, expected.buffer + 33, hasLeft, hasTop, hasTopLeft, hasTopRight)
                        H264.intraPredict8x8(mode, actual.buffer + 33, IntraTestStride, hasLeft, hasTop, hasTopLeft, hasTopRight)
                        Swag.assert(Memory.compare(expected.buffer, actual.buffer, actual.count) == 0)
                    }
                }
            }
        }
    }
}
