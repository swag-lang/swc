#global namespace Webp

using Core

const VP8_PLANE_Y1_WITH_Y2 = 0
const VP8_PLANE_Y2         = 1
const VP8_PLANE_UV         = 2
const VP8_PLANE_Y1         = 3

const VP8_B_COEFF_BASE   = 256
const VP8_R_COEFF_BASE   = 320
const VP8_WHT_COEFF_BASE = 384

const VP8_BANDS:         [17] u8 = [0, 1, 2, 3, 6, 4, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7, 0]
const VP8_ZIGZAG:        [16] u8 = [0, 1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15]
const VP8_CATEGORY_PROB: [48] u8 = [
    173, 148, 140, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    176, 155, 140, 135, 0, 0, 0, 0, 0, 0, 0, 0,
    180, 157, 141, 134, 130, 0, 0, 0, 0, 0, 0, 0,
    254, 254, 243, 230, 196, 177, 153, 140, 133, 130, 129, 0,
    ]

func vp8Pack4(values: *[4] u8, shift: s32)->u32
{
    let value = cast(u32) (dref values)[0] | (cast(u32) (dref values)[1] << 1) |
                (cast(u32) (dref values)[2] << 2) | (cast(u32) (dref values)[3] << 3)
    return value << shift
}

func vp8Clip8(value: s32)->u8
{
    return cast(u8) vp8Clip(value, 0, 255)
}

func vp8InverseDct4(decoder: *Vp8Decoder, y, x, coeffBase: s32)
{
    const C1 = 85627
    const C2 = 35468
    var matrix: [4][4] s32
    var base = coeffBase
    for [i] in 4
    {
        let a = decoder.coeff[base + 0] + decoder.coeff[base + 8]
        let b = decoder.coeff[base + 0] - decoder.coeff[base + 8]
        let c = (cast(s32) decoder.coeff[base + 4] * C2 >> 16) - (cast(s32) decoder.coeff[base + 12] * C1 >> 16)
        let d = (cast(s32) decoder.coeff[base + 4] * C1 >> 16) + (cast(s32) decoder.coeff[base + 12] * C2 >> 16)
        matrix[i][0] = a + d
        matrix[i][1] = b + c
        matrix[i][2] = b - c
        matrix[i][3] = a - d
        base         += 1
    }

    for [j] in 4
    {
        let dc = matrix[0][j] + 4
        let a  = dc + matrix[2][j]
        let b  = dc - matrix[2][j]
        let c  = (matrix[1][j] * C2 >> 16) - (matrix[3][j] * C1 >> 16)
        let d  = (matrix[1][j] * C1 >> 16) + (matrix[3][j] * C2 >> 16)
        decoder.ybr[y + j][x + 0] = vp8Clip8(decoder.ybr[y + j][x + 0] + ((a + d) >> 3))
        decoder.ybr[y + j][x + 1] = vp8Clip8(decoder.ybr[y + j][x + 1] + ((b + c) >> 3))
        decoder.ybr[y + j][x + 2] = vp8Clip8(decoder.ybr[y + j][x + 2] + ((b - c) >> 3))
        decoder.ybr[y + j][x + 3] = vp8Clip8(decoder.ybr[y + j][x + 3] + ((a - d) >> 3))
    }
}

func vp8InverseDct4Dc(decoder: *Vp8Decoder, y, x, coeffBase: s32)
{
    let dc = (cast(s32) decoder.coeff[coeffBase] + 4) >> 3
    for [j] in 4 do
        for [i] in 4 do
            decoder.ybr[y + j][x + i] = vp8Clip8(decoder.ybr[y + j][x + i] + dc)
}

func vp8InverseDct8(decoder: *Vp8Decoder, y, x, coeffBase: s32)
{
    vp8InverseDct4(decoder, y + 0, x + 0, coeffBase + 0)
    vp8InverseDct4(decoder, y + 0, x + 4, coeffBase + 16)
    vp8InverseDct4(decoder, y + 4, x + 0, coeffBase + 32)
    vp8InverseDct4(decoder, y + 4, x + 4, coeffBase + 48)
}

func vp8InverseDct8Dc(decoder: *Vp8Decoder, y, x, coeffBase: s32)
{
    vp8InverseDct4Dc(decoder, y + 0, x + 0, coeffBase + 0)
    vp8InverseDct4Dc(decoder, y + 0, x + 4, coeffBase + 16)
    vp8InverseDct4Dc(decoder, y + 4, x + 0, coeffBase + 32)
    vp8InverseDct4Dc(decoder, y + 4, x + 4, coeffBase + 48)
}

func vp8InverseWht(decoder: *Vp8Decoder)
{
    var matrix: [16] s32
    for [i] in 4
    {
        let a0 = decoder.coeff[VP8_WHT_COEFF_BASE + i] + decoder.coeff[VP8_WHT_COEFF_BASE + 12 + i]
        let a1 = decoder.coeff[VP8_WHT_COEFF_BASE + 4 + i] + decoder.coeff[VP8_WHT_COEFF_BASE + 8 + i]
        let a2 = decoder.coeff[VP8_WHT_COEFF_BASE + 4 + i] - decoder.coeff[VP8_WHT_COEFF_BASE + 8 + i]
        let a3 = decoder.coeff[VP8_WHT_COEFF_BASE + i] - decoder.coeff[VP8_WHT_COEFF_BASE + 12 + i]
        matrix[i + 0]  = a0 + a1
        matrix[i + 8]  = a0 - a1
        matrix[i + 4]  = a3 + a2
        matrix[i + 12] = a3 - a2
    }

    var output: s32
    for [i] in 4
    {
        let dc = matrix[i * 4] + 3
        let a0 = dc + matrix[i * 4 + 3]
        let a1 = matrix[i * 4 + 1] + matrix[i * 4 + 2]
        let a2 = matrix[i * 4 + 1] - matrix[i * 4 + 2]
        let a3 = dc - matrix[i * 4 + 3]
        decoder.coeff[output + 0]  = cast(s16) ((a0 + a1) >> 3)
        decoder.coeff[output + 16] = cast(s16) ((a3 + a2) >> 3)
        decoder.coeff[output + 32] = cast(s16) ((a0 - a1) >> 3)
        decoder.coeff[output + 48] = cast(s16) ((a3 - a2) >> 3)
        output                     += 64
    }
}

func vp8ParseResidual4(decoder: *Vp8Decoder, partition: *Vp8Partition, plane: s32, context: u8, dcQuant, acQuant: u16, skipFirst: bool, coeffBase: s32)->u8
{
    var coefficient     = skipFirst ? 1 : 0
    var band            = cast(s32) VP8_BANDS[coefficient]
    var probabilityBase = vp8TokenIndex(plane, band, context, 0)
    if !partition.readBit(decoder.tokenProb[probabilityBase]) do
        return 0

    while coefficient != 16
    {
        coefficient += 1
        if !partition.readBit(decoder.tokenProb[probabilityBase + 1])
        {
            band            = VP8_BANDS[coefficient]
            probabilityBase = vp8TokenIndex(plane, band, 0, 0)
            continue
        }

        var value: u32
        if !partition.readBit(decoder.tokenProb[probabilityBase + 2])
        {
            value           = 1
            band            = VP8_BANDS[coefficient]
            probabilityBase = vp8TokenIndex(plane, band, 1, 0)
        }
        else
        {
            if !partition.readBit(decoder.tokenProb[probabilityBase + 3])
            {
                if !partition.readBit(decoder.tokenProb[probabilityBase + 4]) do
                    value = 2
                else do
                    value = 3 + partition.readUint(decoder.tokenProb[probabilityBase + 5], 1)
            }
            elif !partition.readBit(decoder.tokenProb[probabilityBase + 6])
            {
                if !partition.readBit(decoder.tokenProb[probabilityBase + 7]) do
                    value = 5 + partition.readUint(159, 1)
                else do
                    value = 7 + 2 * partition.readUint(165, 1) + partition.readUint(145, 1)
            }
            else
            {
                let bit1     = partition.readUint(decoder.tokenProb[probabilityBase + 8], 1)
                let bit0     = partition.readUint(decoder.tokenProb[probabilityBase + 9 + bit1], 1)
                let category = 2 * bit1 + bit0
                var index    = category * 12
                while VP8_CATEGORY_PROB[index]
                {
                    value = value * 2 + partition.readUint(VP8_CATEGORY_PROB[index], 1)
                    index += 1
                }

                value += 3 + (8 << category)
            }

            band            = VP8_BANDS[coefficient]
            probabilityBase = vp8TokenIndex(plane, band, 2, 0)
        }

        let zigzag  = VP8_ZIGZAG[coefficient - 1]
        var decoded = cast(s32) value * (zigzag ? acQuant : dcQuant)
        if partition.readBit(VP8_UNIFORM_PROB) do
            decoded = -decoded
        decoder.coeff[coeffBase + zigzag] = cast(s16) decoded
        if coefficient == 16 or !partition.readBit(decoder.tokenProb[probabilityBase]) do
            return 1
    }

    return 1
}

func vp8ParseResiduals(decoder: *Vp8Decoder, mbX, mbY: s32)->bool
{
    let partition = &decoder.otherParts[mbY & (decoder.otherPartCount - 1)]
    var plane     = VP8_PLANE_Y1
    let quant     = &decoder.quant[decoder.segment]

    if decoder.usePredY16
    {
        let context = decoder.leftMb.nzY16 + decoder.upMb[mbX].nzY16
        let nz      = vp8ParseResidual4(decoder, partition, VP8_PLANE_Y2, context, quant.y2[0], quant.y2[1], false, VP8_WHT_COEFF_BASE)
        decoder.leftMb.nzY16    = nz
        decoder.upMb[mbX].nzY16 = nz
        vp8InverseWht(decoder)
        plane = VP8_PLANE_Y1_WITH_Y2
    }

    var nzDc:      [4] u8
    var nzAc:      [4] u8
    var nzDcMask:  u32
    var nzAcMask:  u32
    var coeffBase: s32
    var leftNz:    [4] u8
    var upperNz:   [4] u8
    for [i] in 4
    {
        leftNz[i]  = (decoder.leftMb.nzMask >> i) & 1
        upperNz[i] = (decoder.upMb[mbX].nzMask >> i) & 1
    }

    for [y] in 4
    {
        var nz = leftNz[y]
        for [x] in 4
        {
            nz         = vp8ParseResidual4(decoder, partition, plane, nz + upperNz[x], quant.y1[0], quant.y1[1], decoder.usePredY16, coeffBase)
            upperNz[x] = nz
            nzAc[x]    = nz
            nzDc[x]    = decoder.coeff[coeffBase] != 0 ? 1 : 0
            coeffBase  += 16
        }

        leftNz[y] = nz
        nzDcMask  |= vp8Pack4(&nzDc, y * 4)
        nzAcMask  |= vp8Pack4(&nzAc, y * 4)
    }

    let leftMask  = vp8Pack4(&leftNz, 0)
    var upperMask = vp8Pack4(&upperNz, 0)

    for [i] in 4
    {
        leftNz[i]  = (decoder.leftMb.nzMask >> (i + 4)) & 1
        upperNz[i] = (decoder.upMb[mbX].nzMask >> (i + 4)) & 1
    }

    var chroma = 0
    while chroma < 4
    {
        for [y] in 2
        {
            var nz = leftNz[y + chroma]
            for [x] in 2
            {
                nz                  = vp8ParseResidual4(decoder, partition, VP8_PLANE_UV, nz + upperNz[x + chroma], quant.uv[0], quant.uv[1], false, coeffBase)
                upperNz[x + chroma] = nz
                nzAc[y * 2 + x]     = nz
                nzDc[y * 2 + x]     = decoder.coeff[coeffBase] != 0 ? 1 : 0
                coeffBase           += 16
            }

            leftNz[y + chroma] = nz
        }

        nzDcMask |= vp8Pack4(&nzDc, 16 + chroma * 2)
        nzAcMask |= vp8Pack4(&nzAc, 16 + chroma * 2)
        chroma   += 2
    }

    decoder.leftMb.nzMask    = cast(u8) (leftMask | (vp8Pack4(&leftNz, 4)))
    decoder.upMb[mbX].nzMask = cast(u8) (upperMask | vp8Pack4(&upperNz, 4))
    decoder.nzDcMask         = nzDcMask
    decoder.nzAcMask         = nzAcMask
    return nzDcMask == 0 and nzAcMask == 0
}

func vp8PrepareYbr(decoder: *Vp8Decoder, mbX, mbY: s32)
{
    if mbX == 0
    {
        for [y] in 17 do
            decoder.ybr[y][7] = 0x81
        var y = 17
        while y < 26
        {
            decoder.ybr[y][7]  = 0x81
            decoder.ybr[y][23] = 0x81
            y                  += 1
        }
    }
    else
    {
        for [y] in 17 do
            decoder.ybr[y][7] = decoder.ybr[y][23]
        var y = 17
        while y < 26
        {
            decoder.ybr[y][7]  = decoder.ybr[y][15]
            decoder.ybr[y][23] = decoder.ybr[y][31]
            y                  += 1
        }
    }

    if mbY == 0
    {
        var x = 7
        while x < 28
        {
            decoder.ybr[0][x] = 0x7F
            x                 += 1
        }

        x = 7
        while x < 16
        {
            decoder.ybr[17][x] = 0x7F
            x                  += 1
        }

        x = 23
        while x < 32
        {
            decoder.ybr[17][x] = 0x7F
            x                  += 1
        }
    }
    else
    {
        let yData   = cast([*] u8) notnull decoder.y.buffer
        let cbData  = cast([*] u8) notnull decoder.cb.buffer
        let crData  = cast([*] u8) notnull decoder.cr.buffer
        let yOffset = (16 * mbY - 1) * decoder.yStride + 16 * mbX
        let cOffset = (8 * mbY - 1) * decoder.cStride + 8 * mbX
        for [i] in 16 do
            decoder.ybr[0][8 + i] = yData[yOffset + i]
        for [i] in 8
        {
            decoder.ybr[17][8 + i]  = cbData[cOffset + i]
            decoder.ybr[17][24 + i] = crData[cOffset + i]
        }

        for [i] in 4
        {
            let sourceX = mbX == decoder.mbWidth - 1 ? 15 : 16 + i
            decoder.ybr[0][24 + i] = yData[yOffset + sourceX]
        }
    }

    var y = 4
    while y < 16
    {
        decoder.ybr[y][24] = decoder.ybr[0][24]
        decoder.ybr[y][25] = decoder.ybr[0][25]
        decoder.ybr[y][26] = decoder.ybr[0][26]
        decoder.ybr[y][27] = decoder.ybr[0][27]
        y                  += 4
    }
}

func vp8ReconstructMacroblock(decoder: *Vp8Decoder, mbX, mbY: s32)
{
    if decoder.usePredY16
    {
        vp8PredictLarge(decoder, 1, 8, 16, vp8TopLeftPredictor(mbX, mbY, decoder.predY16))
        for [j] in 4
        {
            for [i] in 4
            {
                let n    = 4 * j + i
                let mask = 1'u32 << n
                if decoder.nzAcMask & mask do
                    vp8InverseDct4(decoder, 4 * j + 1, 4 * i + 8, 16 * n)
                elif decoder.nzDcMask & mask do
                    vp8InverseDct4Dc(decoder, 4 * j + 1, 4 * i + 8, 16 * n)
            }
        }
    }
    else
    {
        for [j] in 4
        {
            for [i] in 4
            {
                let n = 4 * j + i
                let y = 4 * j + 1
                let x = 4 * i + 8
                vp8Predict4(decoder, y, x, decoder.predY4[j][i])
                let mask = 1'u32 << n
                if decoder.nzAcMask & mask do
                    vp8InverseDct4(decoder, y, x, 16 * n)
                elif decoder.nzDcMask & mask do
                    vp8InverseDct4Dc(decoder, y, x, 16 * n)
            }
        }
    }

    let predictor = vp8TopLeftPredictor(mbX, mbY, decoder.predC8)
    vp8PredictLarge(decoder, 18, 8, 8, predictor)
    if decoder.nzAcMask & 0x0F0000 do
        vp8InverseDct8(decoder, 18, 8, VP8_B_COEFF_BASE)
    elif decoder.nzDcMask & 0x0F0000 do
        vp8InverseDct8Dc(decoder, 18, 8, VP8_B_COEFF_BASE)

    vp8PredictLarge(decoder, 18, 24, 8, predictor)
    if decoder.nzAcMask & 0xF00000 do
        vp8InverseDct8(decoder, 18, 24, VP8_R_COEFF_BASE)
    elif decoder.nzDcMask & 0xF00000 do
        vp8InverseDct8Dc(decoder, 18, 24, VP8_R_COEFF_BASE)
}

func vp8Reconstruct(decoder: *Vp8Decoder, mbX, mbY: s32)->bool
{
    if decoder.segmentHeader.updateMap
    {
        if !decoder.firstPart.readBit(decoder.segmentHeader.probability[0]) do
            decoder.segment = cast(s32) decoder.firstPart.readUint(decoder.segmentHeader.probability[1], 1)
        else do
            decoder.segment = cast(s32) decoder.firstPart.readUint(decoder.segmentHeader.probability[2], 1) + 2
    }

    var skip = decoder.useSkipProb and decoder.firstPart.readBit(decoder.skipProb)
    Memory.clear(&decoder.coeff[0], #sizeof(decoder.coeff))
    vp8PrepareYbr(decoder, mbX, mbY)
    decoder.usePredY16 = decoder.firstPart.readBit(145)
    if decoder.usePredY16 do
        vp8ParsePredY16(decoder, mbX)
    else do
        vp8ParsePredY4(decoder, mbX)
    vp8ParsePredC8(decoder)

    if !skip
    {
        skip = vp8ParseResiduals(decoder, mbX, mbY)
    }
    else
    {
        if decoder.usePredY16
        {
            decoder.leftMb.nzY16    = 0
            decoder.upMb[mbX].nzY16 = 0
        }

        decoder.leftMb.nzMask    = 0
        decoder.upMb[mbX].nzMask = 0
        decoder.nzDcMask         = 0
        decoder.nzAcMask         = 0
    }

    vp8ReconstructMacroblock(decoder, mbX, mbY)
    let yData   = cast([*] u8) notnull decoder.y.buffer
    let cbData  = cast([*] u8) notnull decoder.cb.buffer
    let crData  = cast([*] u8) notnull decoder.cr.buffer
    var yOffset = (mbY * decoder.yStride + mbX) * 16
    for [row] in 16
    {
        for [i] in 16 do
            yData[yOffset + i] = decoder.ybr[row + 1][i + 8]
        yOffset += decoder.yStride
    }

    var cOffset = (mbY * decoder.cStride + mbX) * 8
    for [row] in 8
    {
        for [i] in 8
        {
            cbData[cOffset + i] = decoder.ybr[row + 18][i + 8]
            crData[cOffset + i] = decoder.ybr[row + 18][i + 24]
        }

        cOffset += decoder.cStride
    }

    return skip
}
