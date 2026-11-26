//! Format: WebP still-image decoder component.
//! Supported: RIFF WebP containing lossy VP8 or lossless VP8L still images, including supported alpha chunks.
//! Not supported: Animated WebP and unsupported alpha preprocessing or compression methods.
//! Role: This file owns VP8 intra prediction.
//
#global namespace Webp

const VP8_PRED_DC      = 0_u8
const VP8_PRED_TM      = 1_u8
const VP8_PRED_VE      = 2_u8
const VP8_PRED_HE      = 3_u8
const VP8_PRED_RD      = 4_u8
const VP8_PRED_VR      = 5_u8
const VP8_PRED_LD      = 6_u8
const VP8_PRED_VL      = 7_u8
const VP8_PRED_HD      = 8_u8
const VP8_PRED_HU      = 9_u8
const VP8_PRED_DC_TOP  = 10_u8
const VP8_PRED_DC_LEFT = 11_u8
const VP8_PRED_DC_NONE = 12_u8

func vp8TopLeftPredictor(mbX, mbY: s32, predictor: u8)->u8
{
    if predictor != VP8_PRED_DC
    {
        return predictor
    }

    if mbX == 0
    {
        return mbY == 0 ? VP8_PRED_DC_NONE : VP8_PRED_DC_LEFT
    }

    return mbY == 0 ? VP8_PRED_DC_TOP : VP8_PRED_DC
}

func vp8Average2(a, b: s32)->u8 => cast(u8, ((a + b + 1) / 2))

func vp8Average3(a, b, c: s32)->u8 => cast(u8, ((a + 2 * b + c + 2) / 4))

func vp8Predict4(decoder: *Vp8Decoder, y, x: s32, predictor: u8)
{
    using Math.Simd

    #[Swag.Inline]
    func writeRow(row: [*] u8, a, b, c, d: u8)
    {
        cast([*] u32, row)[0] = cast(u32, a) | cast(u32, b) << 8 | cast(u32, c) << 16 | cast(u32, d) << 24
    }

    let a    = cast(s32, decoder.ybr[y - 1][x - 1])
    let b    = cast(s32, decoder.ybr[y - 1][x + 0])
    let c    = cast(s32, decoder.ybr[y - 1][x + 1])
    let d    = cast(s32, decoder.ybr[y - 1][x + 2])
    let e    = cast(s32, decoder.ybr[y - 1][x + 3])
    let f    = cast(s32, decoder.ybr[y - 1][x + 4])
    let g    = cast(s32, decoder.ybr[y - 1][x + 5])
    let h    = cast(s32, decoder.ybr[y - 1][x + 6])
    let top7 = cast(s32, decoder.ybr[y - 1][x + 7])
    let p    = cast(s32, decoder.ybr[y + 0][x - 1])
    let q    = cast(s32, decoder.ybr[y + 1][x - 1])
    let r    = cast(s32, decoder.ybr[y + 2][x - 1])
    let s    = cast(s32, decoder.ybr[y + 3][x - 1])

    switch predictor
    {
    case VP8_PRED_DC:
        var sum   = 4 + b + c + d + e + p + q + r + s
        let value = cast(u8, (sum / 8))
        for j in 4
        {
            for i in 4
            {
                decoder.ybr[y + j][x + i] = value
            }
        }

    case VP8_PRED_TM:
        for j in 4
        {
            for i in 4
            {
                decoder.ybr[y + j][x + i] = cast(u8, vp8Clip(cast(s32, decoder.ybr[y + j][x - 1]) + decoder.ybr[y - 1][x + i] - a, 0, 255))
            }
        }

    case VP8_PRED_VE:
        let abc = vp8Average3(a, b, c)
        let bcd = vp8Average3(b, c, d)
        let cde = vp8Average3(c, d, e)
        let def = vp8Average3(d, e, f)
        for j in 4 {
            writeRow(&decoder.ybr[y + j][x], abc, bcd, cde, def)

        }
    case VP8_PRED_HE:
        let apq = vp8Average3(a, p, q)
        let pqr = vp8Average3(p, q, r)
        let qrs = vp8Average3(q, r, s)
        let rss = vp8Average3(r, s, s)
        cast([*] u32, &decoder.ybr[y + 0][x])[0] = cast(u32, apq) * 0x01010101_u32
        cast([*] u32, &decoder.ybr[y + 1][x])[0] = cast(u32, pqr) * 0x01010101_u32
        cast([*] u32, &decoder.ybr[y + 2][x])[0] = cast(u32, qrs) * 0x01010101_u32
        cast([*] u32, &decoder.ybr[y + 3][x])[0] = cast(u32, rss) * 0x01010101_u32

    case VP8_PRED_RD:
        let srq = vp8Average3(s, r, q)
        let rqp = vp8Average3(r, q, p)
        let qpa = vp8Average3(q, p, a)
        let pab = vp8Average3(p, a, b)
        let abc = vp8Average3(a, b, c)
        let bcd = vp8Average3(b, c, d)
        let cde = vp8Average3(c, d, e)
        writeRow(&decoder.ybr[y + 0][x], pab, abc, bcd, cde)
        writeRow(&decoder.ybr[y + 1][x], qpa, pab, abc, bcd)
        writeRow(&decoder.ybr[y + 2][x], rqp, qpa, pab, abc)
        writeRow(&decoder.ybr[y + 3][x], srq, rqp, qpa, pab)

    case VP8_PRED_VR:
        let ab  = vp8Average2(a, b)
        let bc  = vp8Average2(b, c)
        let cd  = vp8Average2(c, d)
        let de  = vp8Average2(d, e)
        let rqp = vp8Average3(r, q, p)
        let qpa = vp8Average3(q, p, a)
        let pab = vp8Average3(p, a, b)
        let abc = vp8Average3(a, b, c)
        let bcd = vp8Average3(b, c, d)
        let cde = vp8Average3(c, d, e)
        writeRow(&decoder.ybr[y + 0][x], ab, bc, cd, de)
        writeRow(&decoder.ybr[y + 1][x], pab, abc, bcd, cde)
        writeRow(&decoder.ybr[y + 2][x], qpa, ab, bc, cd)
        writeRow(&decoder.ybr[y + 3][x], rqp, pab, abc, bcd)

    case VP8_PRED_LD:
        let abc = vp8Average3(b, c, d)
        let bcd = vp8Average3(c, d, e)
        let cde = vp8Average3(d, e, f)
        let def = vp8Average3(e, f, g)
        let efg = vp8Average3(f, g, h)
        let fgh = vp8Average3(g, h, top7)
        let ghh = vp8Average3(h, top7, top7)
        writeRow(&decoder.ybr[y + 0][x], abc, bcd, cde, def)
        writeRow(&decoder.ybr[y + 1][x], bcd, cde, def, efg)
        writeRow(&decoder.ybr[y + 2][x], cde, def, efg, fgh)
        writeRow(&decoder.ybr[y + 3][x], def, efg, fgh, ghh)

    case VP8_PRED_VL:
        let ab  = vp8Average2(b, c)
        let bc  = vp8Average2(c, d)
        let cd  = vp8Average2(d, e)
        let de  = vp8Average2(e, f)
        let abc = vp8Average3(b, c, d)
        let bcd = vp8Average3(c, d, e)
        let cde = vp8Average3(d, e, f)
        let def = vp8Average3(e, f, g)
        let efg = vp8Average3(f, g, h)
        let fgh = vp8Average3(g, h, top7)
        writeRow(&decoder.ybr[y + 0][x], ab, bc, cd, de)
        writeRow(&decoder.ybr[y + 1][x], abc, bcd, cde, def)
        writeRow(&decoder.ybr[y + 2][x], bc, cd, de, efg)
        writeRow(&decoder.ybr[y + 3][x], bcd, cde, def, fgh)

    case VP8_PRED_HD:
        let sr  = vp8Average2(s, r)
        let rq  = vp8Average2(r, q)
        let qp  = vp8Average2(q, p)
        let pa  = vp8Average2(p, a)
        let srq = vp8Average3(s, r, q)
        let rqp = vp8Average3(r, q, p)
        let qpa = vp8Average3(q, p, a)
        let pab = vp8Average3(p, a, b)
        let abc = vp8Average3(a, b, c)
        let bcd = vp8Average3(b, c, d)
        writeRow(&decoder.ybr[y + 0][x], pa, pab, abc, bcd)
        writeRow(&decoder.ybr[y + 1][x], qp, qpa, pa, pab)
        writeRow(&decoder.ybr[y + 2][x], rq, rqp, qp, qpa)
        writeRow(&decoder.ybr[y + 3][x], sr, srq, rq, rqp)

    case VP8_PRED_HU:
        let pq  = vp8Average2(p, q)
        let qr  = vp8Average2(q, r)
        let rs  = vp8Average2(r, s)
        let pqr = vp8Average3(p, q, r)
        let qrs = vp8Average3(q, r, s)
        let rss = vp8Average3(r, s, s)
        decoder.ybr[y + 0][x + 0] = pq
        decoder.ybr[y + 0][x + 1] = pqr
        decoder.ybr[y + 0][x + 2] = qr
        decoder.ybr[y + 0][x + 3] = qrs
        decoder.ybr[y + 1][x + 0] = qr
        decoder.ybr[y + 1][x + 1] = qrs
        decoder.ybr[y + 1][x + 2] = rs
        decoder.ybr[y + 1][x + 3] = rss
        decoder.ybr[y + 2][x + 0] = rs
        decoder.ybr[y + 2][x + 1] = rss
        decoder.ybr[y + 2][x + 2] = cast(u8, s)
        decoder.ybr[y + 2][x + 3] = cast(u8, s)
        for i in 4
        {
            decoder.ybr[y + 3][x + i] = cast(u8, s)
        }
    }
}

func vp8PredictLarge(decoder: *Vp8Decoder, y, x, size: s32, predictor: u8)
{
    using Math.Simd

    #[Swag.Inline]
    func storeRow(destination: [*] u8, pixels: U8x16, size: s32)
    {
        if size == 16 {
            store(destination, pixels)
        }
        else {
            storeLow8(destination, pixels)
        }
    }

    #[Swag.Inline]
    func fillBlock(decoder: *Vp8Decoder, y, x, size: s32, value: u8)
    {
        let pixels = splat(value)
        for row in size {
            storeRow(&decoder.ybr[y + row][x], pixels, size)
        }
    }

    switch predictor
    {
    case VP8_PRED_DC:
        var sum = size
        for i in size
        {
            sum += decoder.ybr[y - 1][x + i]
        }

        for i in size
        {
            sum += decoder.ybr[y + i][x - 1]
        }

        let value = cast(u8, (sum / (2 * size)))
        for j in size
        {
            for i in size
            {
                decoder.ybr[y + j][x + i] = value
            }
        }

    case VP8_PRED_TM:
        let corner = cast(s32, decoder.ybr[y - 1][x - 1])
        for j in size
        {
            for i in size
            {
                decoder.ybr[y + j][x + i] = cast(u8, vp8Clip(cast(s32, decoder.ybr[y + j][x - 1]) + decoder.ybr[y - 1][x + i] - corner, 0, 255))
            }
        }

    case VP8_PRED_VE:
        for j in size
        {
            for i in size
            {
                decoder.ybr[y + j][x + i] = decoder.ybr[y - 1][x + i]
            }
        }

    case VP8_PRED_HE:
        for j in size
        {
            for i in size
            {
                decoder.ybr[y + j][x + i] = decoder.ybr[y + j][x - 1]
            }
        }

    case VP8_PRED_DC_TOP:
        var sum = size / 2
        for i in size
        {
            sum += decoder.ybr[y + i][x - 1]
        }

        let value = cast(u8, (sum / size))
        for j in size
        {
            for i in size
            {
                decoder.ybr[y + j][x + i] = value
            }
        }

    case VP8_PRED_DC_LEFT:
        var sum = size / 2
        for i in size
        {
            sum += decoder.ybr[y - 1][x + i]
        }

        let value = cast(u8, (sum / size))
        for j in size
        {
            for i in size
            {
                decoder.ybr[y + j][x + i] = value
            }
        }

    case VP8_PRED_DC_NONE:
        for j in size
        {
            for i in size
            {
                decoder.ybr[y + j][x + i] = 0x80
            }
        }
    }
}

func vp8ParsePredY16(decoder: *Vp8Decoder, mbX: s32)
{
    let partition = &decoder.firstPart
    var predictor: u8
    if not partition.readBit(156)
    {
        predictor = partition.readBit(163) ? VP8_PRED_VE : VP8_PRED_DC
    }
    else if not decoder.firstPart.readBit(128)
    {
        predictor = VP8_PRED_HE
    }
    else
    {
        predictor = VP8_PRED_TM
    }

    let modes = cast(u32, predictor) * 0x01010101_u32
    cast([*] u32, &decoder.upMb[mbX].predictor[0])[0] = modes
    cast([*] u32, &decoder.leftMb.predictor[0])[0]    = modes

    decoder.predY16 = predictor
}

func vp8ParsePredC8(decoder: *Vp8Decoder)
{
    if not decoder.firstPart.readBit(142)
    {
        decoder.predC8 = VP8_PRED_DC
    }
    else if not decoder.firstPart.readBit(114)
    {
        decoder.predC8 = VP8_PRED_VE
    }
    else if not decoder.firstPart.readBit(183)
    {
        decoder.predC8 = VP8_PRED_HE
    }
    else
    {
        decoder.predC8 = VP8_PRED_TM
    }
}

#[Swag.Inline]
private func vp8ReadPredY4(partition: *Vp8Partition, probability: const [*] u8)->u8
{
    if not partition.readBit(probability[0]) {
        return VP8_PRED_DC
    }
    if not partition.readBit(probability[1]) {
        return VP8_PRED_TM
    }
    if not partition.readBit(probability[2]) {
        return VP8_PRED_VE

    }
    if not partition.readBit(probability[3])
    {
        if not partition.readBit(probability[4]) {
            return VP8_PRED_HE
        }
        return partition.readBit(probability[5]) ? VP8_PRED_VR : VP8_PRED_RD
    }

    if not partition.readBit(probability[6]) {
        return VP8_PRED_LD
    }
    if not partition.readBit(probability[7]) {
        return VP8_PRED_VL
    }
    return partition.readBit(probability[8]) ? VP8_PRED_HU : VP8_PRED_HD
}

func vp8ParsePredY4(decoder: *Vp8Decoder, mbX: s32)
{
    for j in 4
    {
        var predictor = decoder.leftMb.predictor[j]
        for i in 4
        {
            let probability = cast(u64, (decoder.upMb[mbX].predictor[i] * 10 + predictor)) * 9
            if not decoder.firstPart.readBit(VP8_PRED_PROB[probability + 0])
            {
                predictor = VP8_PRED_DC
            }
            else if not decoder.firstPart.readBit(VP8_PRED_PROB[probability + 1])
            {
                predictor = VP8_PRED_TM
            }
            else if not decoder.firstPart.readBit(VP8_PRED_PROB[probability + 2])
            {
                predictor = VP8_PRED_VE
            }
            else if not decoder.firstPart.readBit(VP8_PRED_PROB[probability + 3])
            {
                if not decoder.firstPart.readBit(VP8_PRED_PROB[probability + 4])
                {
                    predictor = VP8_PRED_HE
                }
                else if not decoder.firstPart.readBit(VP8_PRED_PROB[probability + 5])
                {
                    predictor = VP8_PRED_RD
                }
                else
                {
                    predictor = VP8_PRED_VR
                }
            }
            else if not decoder.firstPart.readBit(VP8_PRED_PROB[probability + 6])
            {
                predictor = VP8_PRED_LD
            }
            else if not decoder.firstPart.readBit(VP8_PRED_PROB[probability + 7])
            {
                predictor = VP8_PRED_VL
            }
            else if not decoder.firstPart.readBit(VP8_PRED_PROB[probability + 8])
            {
                predictor = VP8_PRED_HD
            }
            else
            {
                predictor = VP8_PRED_HU
            }

    // Each top mode has ten left contexts of nine probabilities.
    let table = cast(const [*] u8, &VP8_PRED_PROB[0])

    for row in 4
    {
        var predictor = left[row]
        for column in 4
        {
            let probability = table + cast(u64, above[column]) * 90 + cast(u64, predictor) * 9
            predictor     = vp8ReadPredY4(partition, probability)
            above[column] = predictor
        }

        modes[row] = cast(const [*] u32, above)[0]
        left[row]  = predictor
    }
}
