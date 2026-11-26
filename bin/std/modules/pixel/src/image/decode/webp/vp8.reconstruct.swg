//! Format: WebP still-image decoder component.
//! Supported: RIFF WebP containing lossy VP8 or lossless VP8L still images, including supported alpha chunks.
//! Not supported: Animated WebP and unsupported alpha preprocessing or compression methods.
//! Role: This file owns VP8 coefficient transforms and block reconstruction.
//
#global namespace Webp

using Core

const VP8_PLANE_Y1_WITH_Y2 = 0
const VP8_PLANE_Y2         = 1
const VP8_PLANE_UV         = 2
const VP8_PLANE_Y1         = 3

const VP8_WHT_COEFF_BASE = 384

const VP8_BAND_STRIDE = VP8_TOKEN_CONTEXTS * VP8_TOKEN_PROBS
const VP8_BAND_OFFSETS: [17] u8 = [
    0, VP8_BAND_STRIDE, 2 * VP8_BAND_STRIDE, 3 * VP8_BAND_STRIDE, 6 * VP8_BAND_STRIDE,
    4 * VP8_BAND_STRIDE, 5 * VP8_BAND_STRIDE, 6 * VP8_BAND_STRIDE,
    6 * VP8_BAND_STRIDE, 6 * VP8_BAND_STRIDE, 6 * VP8_BAND_STRIDE, 6 * VP8_BAND_STRIDE,
    6 * VP8_BAND_STRIDE, 6 * VP8_BAND_STRIDE, 6 * VP8_BAND_STRIDE, 7 * VP8_BAND_STRIDE, 0]
const VP8_ZIGZAG:        [16] u8 = [0, 1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15]
const VP8_CATEGORY_PROB: [48] u8 = [
    173, 148, 140, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    176, 155, 140, 135, 0, 0, 0, 0, 0, 0, 0, 0,
    180, 157, 141, 134, 130, 0, 0, 0, 0, 0, 0, 0,
    254, 254, 243, 230, 196, 177, 153, 140, 133, 130, 129, 0]

func vp8Pack4(values: *[4] u8, shift: s32)->u32
{
    let value = cast(u32, values[][0]) | (cast(u32, values[][1]) << 1) |
                (cast(u32, values[][2]) << 2) | (cast(u32, values[][3]) << 3)
    return value << shift
}

func vp8Clip8(value: s32)->u8 => cast(u8, vp8Clip(value, 0, 255))

func vp8InverseDct4(decoder: *Vp8Decoder, y, x, coeffBase: s32)
{
    using Math.Simd

    // Transform four columns together, then transpose the results for the next pass.
    #[Swag.Inline]
    func transform(sumEven, differenceEven, odd1, odd3: S32x4, destination: [*] S32x4)
    {
        let cosine = splat(85627's32)
        let sine   = splat(35468's32)
        let c      = ((odd1 * sine) >> 16) - ((odd3 * cosine) >> 16)
        let d      = ((odd1 * cosine) >> 16) + ((odd3 * sine) >> 16)
        let r0     = cast #bit(U32x4, sumEven + d)
        let r1     = cast #bit(U32x4, differenceEven + c)
        let r2     = cast #bit(U32x4, differenceEven - c)
        let r3     = cast #bit(U32x4, sumEven - d)
        let low01  = cast #bit(U64x2, interleaveLow(r0, r1))
        let high01 = cast #bit(U64x2, interleaveHigh(r0, r1))
        let low23  = cast #bit(U64x2, interleaveLow(r2, r3))
        let high23 = cast #bit(U64x2, interleaveHigh(r2, r3))
        destination[0] = cast #bit(S32x4, interleaveLow(low01, low23))
        destination[1] = cast #bit(S32x4, interleaveHigh(low01, low23))
        destination[2] = cast #bit(S32x4, interleaveLow(high01, high23))
        destination[3] = cast #bit(S32x4, interleaveHigh(high01, high23))
    }

    let coefficients = cast(const [*] s16, &decoder.coeff[coeffBase])
    let top          = load(coefficients)
    let bottom       = load(coefficients + 8)
    var columns: [4] S32x4
    var rows:    [4] S32x4

    // The scalar first pass combines the even coefficients as s16 before widening.
    transform(widenLow(top + bottom), widenLow(top - bottom), widenHigh(top), widenHigh(bottom), columns)
    let rounded = columns[0] + 4
    transform(rounded + columns[2], rounded - columns[2], columns[1], columns[3], rows)

    // Read and write four bytes per row, including the chroma blocks at the right edge.
    const Stride = #sizeof(decoder.ybr[0]) / #sizeof(u32)
    let output  = cast([*] u32, &decoder.ybr[y][x])
    let predicted: [4] u32 = [output[0], output[Stride], output[2 * Stride], output[3 * Stride]]
    let pixels  = cast #bit(U8x16, predicted)
    let delta01 = packSigned(rows[0] >> 3, rows[1] >> 3)
    let delta23 = packSigned(rows[2] >> 3, rows[3] >> 3)
    let pair01  = addSaturating(cast #bit(S16x8, widenLow(pixels)), delta01)
    let pair23  = addSaturating(cast #bit(S16x8, widenHigh(pixels)), delta23)
    let result  = cast #bit(U32x4, packUnsigned(pair01, pair23))
    output[0]          = result[0]
    output[Stride]     = result[1]
    output[2 * Stride] = result[2]
    output[3 * Stride] = result[3]
}

func vp8InverseDct4Dc(decoder: *Vp8Decoder, y, x, coeffBase: s32)
{
    using Math.Simd

    let dc    = (cast(s32, decoder.coeff[coeffBase]) + 4) >> 3
    let delta = splat(cast(s16, dc))
    let zero  = splat(0's16)
    for j in 4
    {
        // Load exactly four bytes so the last chroma block can use the same path.
        let row    = &decoder.ybr[y + j][x]
        let bytes  = cast #bit(U8x16, splat(cast(const [*] u32, row)[0]))
        let pixels = cast #bit(S16x8, widenLow(bytes))
        storeLow4(row, packUnsigned(pixels + delta, zero))
    }
}

func vp8InverseWht(decoder: *Vp8Decoder)
{
    var matrix: [16] s32
    for i in 4
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
    for i in 4
    {
        let dc = matrix[i * 4] + 3
        let a0 = dc + matrix[i * 4 + 3]
        let a1 = matrix[i * 4 + 1] + matrix[i * 4 + 2]
        let a2 = matrix[i * 4 + 1] - matrix[i * 4 + 2]
        let a3 = dc - matrix[i * 4 + 3]
        decoder.coeff[output + 0]  = cast(s16, ((a0 + a1) >> 3))
        decoder.coeff[output + 16] = cast(s16, ((a3 + a2) >> 3))
        decoder.coeff[output + 32] = cast(s16, ((a0 - a1) >> 3))
        decoder.coeff[output + 48] = cast(s16, ((a3 - a2) >> 3))
        output += 64
    }
}

// Magnitudes above four share the less frequent category subtree.
private func vp8ReadCoefficientCategory(partition: *Vp8Partition, probabilities: const [*] u8)->s32
{
    if not partition.readBit(probabilities[6])
    {
        if not partition.readBit(probabilities[7]) do
            return 5 + cast(s32, partition.readBit(159))
        let high = cast(s32, partition.readBit(165))
        let low  = cast(s32, partition.readBit(145))
        return 7 + 2 * high + low
    }

    let high     = cast(s32, partition.readBit(probabilities[8]))
    let low      = cast(s32, partition.readBit(probabilities[9 + high]))
    let category = 2 * high + low
    var index    = category * 12
    var value: s32
    while VP8_CATEGORY_PROB[index]
    {
        value = value * 2 + cast(s32, partition.readBit(VP8_CATEGORY_PROB[index]))
        index += 1
    }

    return value + 3 + (8 << category)
}

// The first token normally ends the block. Enter the value loop only for coded blocks.
#[Swag.Inline]
func vp8ParseResidual4(decoder: *Vp8Decoder, partition: *Vp8Partition, plane: s32, context: u8, dcQuant, acQuant: u16, skipFirst: bool, coeffBase: s32)->u8
{
    let probabilities = cast(const [*] u8, &decoder.tokenProb[plane * VP8_TOKEN_BANDS * VP8_BAND_STRIDE])
    let first         = skipFirst ? 1 : 0
    let probability   = probabilities + VP8_BAND_OFFSETS[first] + (context * VP8_TOKEN_PROBS)
    if not partition.readBit(probability[0]) do
        return 0

    let coefficients = cast([*] s16, &decoder.coeff[coeffBase])
    return vp8ParseResidualValues(partition, probabilities, probability, coefficients, dcQuant, acQuant, first)
}

// Returns the position past the last coded coefficient, with one as the coded-block minimum.
private func vp8ParseResidualValues(partition: *Vp8Partition, probabilities, firstProbability: const [*] u8, coefficients: [*] s16, dcQuant, acQuant: u16, first: s32)->u8
{
    // Keep the arithmetic state in local scalars until the loop needs to
    // refill or decode the less frequent large-magnitude branch.
    var rangeM1  = partition.rangeM1
    var bits     = partition.bits
    var bitCount = partition.bitCount

    #[Swag.Mixin]
    func saveLocal()
    {
        partition.rangeM1  = rangeM1
        partition.bits     = bits
        partition.bitCount = bitCount
    }

    #[Swag.Mixin]
    func loadLocal()
    {
        rangeM1  = partition.rangeM1
        bits     = partition.bits
        bitCount = partition.bitCount
    }

    #[Swag.Mixin]
    func refillLocal()->bool
    {
        partition.bits     = bits
        partition.bitCount = bitCount
        let #uniq0 = partition.refill()
        bits     = partition.bits
        bitCount = partition.bitCount
        return #uniq0
    }

    #[Swag.Mixin]
    func readLocalBit(chance: u8)->bool
    {
        if bitCount < 8 and not refillLocal() do
            return false

        return vp8AdvanceBit(chance)
    }

    #[Swag.Mixin]
    func readLocalSign(magnitude: s32)->s32
    {
        if bitCount < 8 and not refillLocal() do
            return magnitude

        return vp8AdvanceSign(magnitude)
    }

    defer
    {
        saveLocal()
    }

    var coefficient  = first
    var probability  = firstProbability
    var decodedCount = 1'u8
    while coefficient < 16
    {
        // A zero uses context zero and is followed by a value token, without an end token.
        while not readLocalBit(probability[1])
        {
            coefficient += 1
            if coefficient == 16 do
                return decodedCount
            probability = probabilities + VP8_BAND_OFFSETS[coefficient]
        }

        let nextBand = probabilities + VP8_BAND_OFFSETS[coefficient + 1]
        var value    = 1
        if readLocalBit(probability[2])
        {
            if readLocalBit(probability[3])
            {
                saveLocal()
                value = vp8ReadCoefficientCategory(partition, probability)
                loadLocal()
            }
            elif readLocalBit(probability[4])
            {
                value = 3 + cast(s32, readLocalBit(probability[5]))
            }
            else
            {
                value = 2
            }

            probability = nextBand + 2 * VP8_TOKEN_PROBS
        }
        else
        {
            probability = nextBand + VP8_TOKEN_PROBS
        }

        let zigzag  = VP8_ZIGZAG[coefficient]
        let decoded = value * (coefficient ? acQuant : dcQuant)
        coefficients[zigzag] = cast(s16, readLocalSign(decoded))
        coefficient          += 1
        decodedCount         = cast(u8, coefficient)
        if coefficient == 16 or not readLocalBit(probability[0]) do
            break
    }

    return decodedCount
}

func vp8ParseResiduals(decoder: *Vp8Decoder, mbX, mbY: s32)->bool
{
    let partition = &decoder.otherParts[mbY & (decoder.otherPartCount - 1)]
    var plane     = VP8_PLANE_Y1
    let quant     = &decoder.quant[decoder.segment]

    if decoder.usePredY16
    {
        let context = decoder.leftMb.nzY16 + decoder.upMb[mbX].nzY16
        let count   = vp8ParseResidual4(decoder, partition, VP8_PLANE_Y2, context, quant.y2[0], quant.y2[1], false, VP8_WHT_COEFF_BASE)
        let nz      = count == 0 ? 0'u8 : 1'u8
        decoder.leftMb.nzY16    = nz
        decoder.upMb[mbX].nzY16 = nz
        if count > 1
        {
            vp8InverseWht(decoder)
        }
        elif count
        {
            let dc = cast(s16, ((cast(s32, decoder.coeff[VP8_WHT_COEFF_BASE]) + 3) >> 3))
            for block in 16 do
                decoder.coeff[block * 16] = dc
        }

        plane = VP8_PLANE_Y1_WITH_Y2
    }

    var nzDc:      [4] u8
    var nzAc:      [4] u8
    var nzDcMask:  u32
    var nzAcMask:  u32
    var coeffBase: s32
    var coded:     u8
    var leftNz:    [4] u8
    var upperNz:   [4] u8
    for i in 4
    {
        leftNz[i]  = (decoder.leftMb.nzMask >> i) & 1
        upperNz[i] = (decoder.upMb[mbX].nzMask >> i) & 1
    }

    for y in 4
    {
        var nz = leftNz[y]
        for x in 4
        {
            let count = vp8ParseResidual4(decoder, partition, plane, nz + upperNz[x], quant.y1[0], quant.y1[1], decoder.usePredY16, coeffBase)
            nz         = count == 0 ? 0 : 1
            coded      = coded | nz
            upperNz[x] = nz
            nzAc[x]    = count > 1 ? 1 : 0
            nzDc[x]    = decoder.coeff[coeffBase] != 0 ? 1 : 0
            coeffBase  += 16
        }

        leftNz[y] = nz
        nzDcMask  |= vp8Pack4(&nzDc, y * 4)
        nzAcMask  |= vp8Pack4(&nzAc, y * 4)
    }

    let leftMask  = vp8Pack4(&leftNz, 0)
    var upperMask = vp8Pack4(&upperNz, 0)

    for i in 4
    {
        leftNz[i]  = (decoder.leftMb.nzMask >> (i + 4)) & 1
        upperNz[i] = (decoder.upMb[mbX].nzMask >> (i + 4)) & 1
    }

    var chroma = 0
    while chroma < 4
    {
        for y in 2
        {
            var nz = leftNz[y + chroma]
            for x in 2
            {
                let count = vp8ParseResidual4(decoder, partition, VP8_PLANE_UV, nz + upperNz[x + chroma], quant.uv[0], quant.uv[1], false, coeffBase)
                nz                  = count == 0 ? 0 : 1
                coded               = coded | nz
                upperNz[x + chroma] = nz
                nzAc[y * 2 + x]     = count > 1 ? 1 : 0
                nzDc[y * 2 + x]     = decoder.coeff[coeffBase] != 0 ? 1 : 0
                coeffBase           += 16
            }

            leftNz[y + chroma] = nz
        }

        nzDcMask |= vp8Pack4(&nzDc, 16 + chroma * 2)
        nzAcMask |= vp8Pack4(&nzAc, 16 + chroma * 2)
        chroma   += 2
    }

    decoder.leftMb.nzMask    = cast(u8, (leftMask | (vp8Pack4(&leftNz, 4))))
    decoder.upMb[mbX].nzMask = cast(u8, (upperMask | vp8Pack4(&upperNz, 4)))
    decoder.nzDcMask         = nzDcMask
    decoder.nzAcMask         = nzAcMask
    return nzDcMask == 0 and coded == 0
}

func vp8PrepareYbr(decoder: *Vp8Decoder, mbX, mbY: s32)
{
    if mbX == 0
    {
        for y in 17 do
            decoder.ybr[y][7] = 0x81
        var y = 17
        while y < 26
        {
            decoder.ybr[y][7]  = 0x81
            decoder.ybr[y][23] = 0x81
            y += 1
        }
    }
    else
    {
        for y in 17 do
            decoder.ybr[y][7] = decoder.ybr[y][23]
        var y = 17
        while y < 26
        {
            decoder.ybr[y][7]  = decoder.ybr[y][15]
            decoder.ybr[y][23] = decoder.ybr[y][31]
            y += 1
        }
    }

    if mbY == 0
    {
        var x = 7
        while x < 28
        {
            decoder.ybr[0][x] = 0x7F
            x += 1
        }

        x = 7
        while x < 16
        {
            decoder.ybr[17][x] = 0x7F
            x += 1
        }

        x = 23
        while x < 32
        {
            decoder.ybr[17][x] = 0x7F
            x += 1
        }
    }
    else
    {
        let yData   = cast([*] u8, decoder.y.storage())
        let cbData  = cast([*] u8, decoder.cb.storage())
        let crData  = cast([*] u8, decoder.cr.storage())
        let yOffset = (16 * mbY - 1) * decoder.yStride + 16 * mbX
        let cOffset = (8 * mbY - 1) * decoder.cStride + 8 * mbX
        Math.Simd.store(&decoder.ybr[0][8], Math.Simd.load(yData + yOffset))
        cast([*] u64, &decoder.ybr[17][8])[0]  = cast(const [*] u64, cbData + cOffset)[0]
        cast([*] u64, &decoder.ybr[17][24])[0] = cast(const [*] u64, crData + cOffset)[0]

        for i in 4
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
        y += 4
    }
}

func vp8ReconstructMacroblock(decoder: *Vp8Decoder, mbX, mbY: s32)
{
    #[Swag.Inline]
    func applyResidual(decoder: *Vp8Decoder, y, x, block: s32)
    {
        let mask = 1'u32 << block
        if decoder.nzAcMask & mask do
            vp8InverseDct4(decoder, y, x, 16 * block)
        elif decoder.nzDcMask & mask do
            vp8InverseDct4Dc(decoder, y, x, 16 * block)
    }

    if decoder.usePredY16 do
        vp8PredictLarge(decoder, 1, 8, 16, vp8TopLeftPredictor(mbX, mbY, decoder.predY16))
    for j in 4
    {
        for i in 4
        {
            let y = 4 * j + 1
            let x = 4 * i + 8
            if not decoder.usePredY16 do
                vp8Predict4(decoder, y, x, decoder.predY4[j][i])
            applyResidual(decoder, y, x, 4 * j + i)
        }
    }

    let predictor = vp8TopLeftPredictor(mbX, mbY, decoder.predC8)
    for plane in 2
    {
        let x = 8 + 16 * plane
        vp8PredictLarge(decoder, 18, x, 8, predictor)
        for j in 2 do
            for i in 2 do
                applyResidual(decoder, 18 + 4 * j, x + 4 * i, 16 + 4 * plane + 2 * j + i)
    }
}

func vp8Reconstruct(decoder: *Vp8Decoder, mbX, mbY, storedRow: s32)->bool
{
    if decoder.segmentHeader.updateMap
    {
        if not decoder.firstPart.readBit(decoder.segmentHeader.probability[0]) do
            decoder.segment = cast(s32, decoder.firstPart.readUint(decoder.segmentHeader.probability[1], 1))
        else do
            decoder.segment = cast(s32, decoder.firstPart.readUint(decoder.segmentHeader.probability[2], 1)) + 2
    }

    var skip = decoder.useSkipProb and decoder.firstPart.readBit(decoder.skipProb)
    vp8PrepareYbr(decoder, mbX, storedRow)
    decoder.usePredY16 = decoder.firstPart.readBit(145)
    if decoder.usePredY16 do
        vp8ParsePredY16(decoder, mbX)
    else do
        vp8ParsePredY4(decoder, mbX)
    vp8ParsePredC8(decoder)

    if not skip
    {
        Memory.clear(&decoder.coeff[0], #sizeof(decoder.coeff))
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
    let yData   = cast([*] u8, decoder.y.storage())
    let cbData  = cast([*] u8, decoder.cb.storage())
    let crData  = cast([*] u8, decoder.cr.storage())
    var yOffset = (storedRow * decoder.yStride + mbX) * 16
    for row in 16
    {
        Math.Simd.store(yData + yOffset, Math.Simd.load(&decoder.ybr[row + 1][8]))
        yOffset += decoder.yStride
    }

    var cOffset = (storedRow * decoder.cStride + mbX) * 8
    for row in 8
    {
        cast([*] u64, cbData + cOffset)[0] = cast(const [*] u64, &decoder.ybr[row + 18][8])[0]
        cast([*] u64, crData + cOffset)[0] = cast(const [*] u64, &decoder.ybr[row + 18][24])[0]
        cOffset += decoder.cStride
    }

    return skip
}
