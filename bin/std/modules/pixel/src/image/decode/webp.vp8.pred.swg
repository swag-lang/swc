#global namespace Webp

const VP8_PRED_DC      = 0'u8
const VP8_PRED_TM      = 1'u8
const VP8_PRED_VE      = 2'u8
const VP8_PRED_HE      = 3'u8
const VP8_PRED_RD      = 4'u8
const VP8_PRED_VR      = 5'u8
const VP8_PRED_LD      = 6'u8
const VP8_PRED_VL      = 7'u8
const VP8_PRED_HD      = 8'u8
const VP8_PRED_HU      = 9'u8
const VP8_PRED_DC_TOP  = 10'u8
const VP8_PRED_DC_LEFT = 11'u8
const VP8_PRED_DC_NONE = 12'u8

func vp8TopLeftPredictor(mbX, mbY: s32, predictor: u8)->u8
{
    if predictor != VP8_PRED_DC do
        return predictor
    if mbX == 0 do
        return mbY == 0 ? VP8_PRED_DC_NONE : VP8_PRED_DC_LEFT
    return mbY == 0 ? VP8_PRED_DC_TOP : VP8_PRED_DC
}

func vp8Average2(a, b: s32)->u8
{
    return cast(u8) ((a + b + 1) / 2)
}

func vp8Average3(a, b, c: s32)->u8
{
    return cast(u8) ((a + 2 * b + c + 2) / 4)
}

func vp8Predict4(decoder: *Vp8Decoder, y, x: s32, predictor: u8)
{
    let a    = cast(s32) decoder.ybr[y - 1][x - 1]
    let b    = cast(s32) decoder.ybr[y - 1][x + 0]
    let c    = cast(s32) decoder.ybr[y - 1][x + 1]
    let d    = cast(s32) decoder.ybr[y - 1][x + 2]
    let e    = cast(s32) decoder.ybr[y - 1][x + 3]
    let f    = cast(s32) decoder.ybr[y - 1][x + 4]
    let g    = cast(s32) decoder.ybr[y - 1][x + 5]
    let h    = cast(s32) decoder.ybr[y - 1][x + 6]
    let top7 = cast(s32) decoder.ybr[y - 1][x + 7]
    let p    = cast(s32) decoder.ybr[y + 0][x - 1]
    let q    = cast(s32) decoder.ybr[y + 1][x - 1]
    let r    = cast(s32) decoder.ybr[y + 2][x - 1]
    let s    = cast(s32) decoder.ybr[y + 3][x - 1]

    switch predictor
    {
    case VP8_PRED_DC:
        var sum   = 4 + b + c + d + e + p + q + r + s
        let value = cast(u8) (sum / 8)
        for j in 4 do
            for i in 4 do
                decoder.ybr[y + j][x + i] = value

    case VP8_PRED_TM:
        for j in 4 do
            for i in 4 do
                decoder.ybr[y + j][x + i] = cast(u8) vp8Clip(cast(s32) decoder.ybr[y + j][x - 1] + decoder.ybr[y - 1][x + i] - a, 0, 255)

    case VP8_PRED_VE:
        let abc = vp8Average3(a, b, c)
        let bcd = vp8Average3(b, c, d)
        let cde = vp8Average3(c, d, e)
        let def = vp8Average3(d, e, f)
        for j in 4
        {
            decoder.ybr[y + j][x + 0] = abc
            decoder.ybr[y + j][x + 1] = bcd
            decoder.ybr[y + j][x + 2] = cde
            decoder.ybr[y + j][x + 3] = def
        }

    case VP8_PRED_HE:
        let apq = vp8Average3(a, p, q)
        let pqr = vp8Average3(p, q, r)
        let qrs = vp8Average3(q, r, s)
        let rss = vp8Average3(r, s, s)
        for i in 4
        {
            decoder.ybr[y + 0][x + i] = apq
            decoder.ybr[y + 1][x + i] = pqr
            decoder.ybr[y + 2][x + i] = qrs
            decoder.ybr[y + 3][x + i] = rss
        }

    case VP8_PRED_RD:
        let srq = vp8Average3(s, r, q)
        let rqp = vp8Average3(r, q, p)
        let qpa = vp8Average3(q, p, a)
        let pab = vp8Average3(p, a, b)
        let abc = vp8Average3(a, b, c)
        let bcd = vp8Average3(b, c, d)
        let cde = vp8Average3(c, d, e)
        decoder.ybr[y + 0][x + 0] = pab
        decoder.ybr[y + 0][x + 1] = abc
        decoder.ybr[y + 0][x + 2] = bcd
        decoder.ybr[y + 0][x + 3] = cde
        decoder.ybr[y + 1][x + 0] = qpa
        decoder.ybr[y + 1][x + 1] = pab
        decoder.ybr[y + 1][x + 2] = abc
        decoder.ybr[y + 1][x + 3] = bcd
        decoder.ybr[y + 2][x + 0] = rqp
        decoder.ybr[y + 2][x + 1] = qpa
        decoder.ybr[y + 2][x + 2] = pab
        decoder.ybr[y + 2][x + 3] = abc
        decoder.ybr[y + 3][x + 0] = srq
        decoder.ybr[y + 3][x + 1] = rqp
        decoder.ybr[y + 3][x + 2] = qpa
        decoder.ybr[y + 3][x + 3] = pab

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
        decoder.ybr[y + 0][x + 0] = ab
        decoder.ybr[y + 0][x + 1] = bc
        decoder.ybr[y + 0][x + 2] = cd
        decoder.ybr[y + 0][x + 3] = de
        decoder.ybr[y + 1][x + 0] = pab
        decoder.ybr[y + 1][x + 1] = abc
        decoder.ybr[y + 1][x + 2] = bcd
        decoder.ybr[y + 1][x + 3] = cde
        decoder.ybr[y + 2][x + 0] = qpa
        decoder.ybr[y + 2][x + 1] = ab
        decoder.ybr[y + 2][x + 2] = bc
        decoder.ybr[y + 2][x + 3] = cd
        decoder.ybr[y + 3][x + 0] = rqp
        decoder.ybr[y + 3][x + 1] = pab
        decoder.ybr[y + 3][x + 2] = abc
        decoder.ybr[y + 3][x + 3] = bcd

    case VP8_PRED_LD:
        let abc = vp8Average3(b, c, d)
        let bcd = vp8Average3(c, d, e)
        let cde = vp8Average3(d, e, f)
        let def = vp8Average3(e, f, g)
        let efg = vp8Average3(f, g, h)
        let fgh = vp8Average3(g, h, top7)
        let ghh = vp8Average3(h, top7, top7)
        decoder.ybr[y + 0][x + 0] = abc
        decoder.ybr[y + 0][x + 1] = bcd
        decoder.ybr[y + 0][x + 2] = cde
        decoder.ybr[y + 0][x + 3] = def
        decoder.ybr[y + 1][x + 0] = bcd
        decoder.ybr[y + 1][x + 1] = cde
        decoder.ybr[y + 1][x + 2] = def
        decoder.ybr[y + 1][x + 3] = efg
        decoder.ybr[y + 2][x + 0] = cde
        decoder.ybr[y + 2][x + 1] = def
        decoder.ybr[y + 2][x + 2] = efg
        decoder.ybr[y + 2][x + 3] = fgh
        decoder.ybr[y + 3][x + 0] = def
        decoder.ybr[y + 3][x + 1] = efg
        decoder.ybr[y + 3][x + 2] = fgh
        decoder.ybr[y + 3][x + 3] = ghh

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
        decoder.ybr[y + 0][x + 0] = ab
        decoder.ybr[y + 0][x + 1] = bc
        decoder.ybr[y + 0][x + 2] = cd
        decoder.ybr[y + 0][x + 3] = de
        decoder.ybr[y + 1][x + 0] = abc
        decoder.ybr[y + 1][x + 1] = bcd
        decoder.ybr[y + 1][x + 2] = cde
        decoder.ybr[y + 1][x + 3] = def
        decoder.ybr[y + 2][x + 0] = bc
        decoder.ybr[y + 2][x + 1] = cd
        decoder.ybr[y + 2][x + 2] = de
        decoder.ybr[y + 2][x + 3] = efg
        decoder.ybr[y + 3][x + 0] = bcd
        decoder.ybr[y + 3][x + 1] = cde
        decoder.ybr[y + 3][x + 2] = def
        decoder.ybr[y + 3][x + 3] = fgh

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
        decoder.ybr[y + 0][x + 0] = pa
        decoder.ybr[y + 0][x + 1] = pab
        decoder.ybr[y + 0][x + 2] = abc
        decoder.ybr[y + 0][x + 3] = bcd
        decoder.ybr[y + 1][x + 0] = qp
        decoder.ybr[y + 1][x + 1] = qpa
        decoder.ybr[y + 1][x + 2] = pa
        decoder.ybr[y + 1][x + 3] = pab
        decoder.ybr[y + 2][x + 0] = rq
        decoder.ybr[y + 2][x + 1] = rqp
        decoder.ybr[y + 2][x + 2] = qp
        decoder.ybr[y + 2][x + 3] = qpa
        decoder.ybr[y + 3][x + 0] = sr
        decoder.ybr[y + 3][x + 1] = srq
        decoder.ybr[y + 3][x + 2] = rq
        decoder.ybr[y + 3][x + 3] = rqp

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
        decoder.ybr[y + 2][x + 2] = cast(u8) s
        decoder.ybr[y + 2][x + 3] = cast(u8) s
        for i in 4 do
            decoder.ybr[y + 3][x + i] = cast(u8) s
    }
}

func vp8PredictLarge(decoder: *Vp8Decoder, y, x, size: s32, predictor: u8)
{
    switch predictor
    {
    case VP8_PRED_DC:
        var sum = size
        for i in size do
            sum += decoder.ybr[y - 1][x + i]
        for i in size do
            sum += decoder.ybr[y + i][x - 1]
        let value = cast(u8) (sum / (2 * size))
        for j in size do
            for i in size do
                decoder.ybr[y + j][x + i] = value

    case VP8_PRED_TM:
        let corner = cast(s32) decoder.ybr[y - 1][x - 1]
        for j in size do
            for i in size do
                decoder.ybr[y + j][x + i] = cast(u8) vp8Clip(cast(s32) decoder.ybr[y + j][x - 1] + decoder.ybr[y - 1][x + i] - corner, 0, 255)

    case VP8_PRED_VE:
        for j in size do
            for i in size do
                decoder.ybr[y + j][x + i] = decoder.ybr[y - 1][x + i]

    case VP8_PRED_HE:
        for j in size do
            for i in size do
                decoder.ybr[y + j][x + i] = decoder.ybr[y + j][x - 1]

    case VP8_PRED_DC_TOP:
        var sum = size / 2
        for i in size do
            sum += decoder.ybr[y + i][x - 1]
        let value = cast(u8) (sum / size)
        for j in size do
            for i in size do
                decoder.ybr[y + j][x + i] = value

    case VP8_PRED_DC_LEFT:
        var sum = size / 2
        for i in size do
            sum += decoder.ybr[y - 1][x + i]
        let value = cast(u8) (sum / size)
        for j in size do
            for i in size do
                decoder.ybr[y + j][x + i] = value

    case VP8_PRED_DC_NONE:
        for j in size do
            for i in size do
                decoder.ybr[y + j][x + i] = 0x80
    }
}

func vp8ParsePredY16(decoder: *Vp8Decoder, mbX: s32)
{
    var predictor: u8
    if !decoder.firstPart.readBit(156)
    {
        predictor = decoder.firstPart.readBit(163) ? VP8_PRED_VE : VP8_PRED_DC
    }
    elif !decoder.firstPart.readBit(128)
    {
        predictor = VP8_PRED_HE
    }
    else
    {
        predictor = VP8_PRED_TM
    }

    for i in 4
    {
        decoder.upMb[mbX].predictor[i] = predictor
        decoder.leftMb.predictor[i]    = predictor
    }

    decoder.predY16 = predictor
}

func vp8ParsePredC8(decoder: *Vp8Decoder)
{
    if !decoder.firstPart.readBit(142) do
        decoder.predC8 = VP8_PRED_DC
    elif !decoder.firstPart.readBit(114) do
        decoder.predC8 = VP8_PRED_VE
    elif !decoder.firstPart.readBit(183) do
        decoder.predC8 = VP8_PRED_HE
    else do
        decoder.predC8 = VP8_PRED_TM
}

func vp8ParsePredY4(decoder: *Vp8Decoder, mbX: s32)
{
    for j in 4
    {
        var predictor = decoder.leftMb.predictor[j]
        for i in 4
        {
            let probability = cast(u64) (decoder.upMb[mbX].predictor[i] * 10 + predictor) * 9
            if !decoder.firstPart.readBit(VP8_PRED_PROB[probability + 0]) do
                predictor = VP8_PRED_DC
            elif !decoder.firstPart.readBit(VP8_PRED_PROB[probability + 1]) do
                predictor = VP8_PRED_TM
            elif !decoder.firstPart.readBit(VP8_PRED_PROB[probability + 2]) do
                predictor = VP8_PRED_VE
            elif !decoder.firstPart.readBit(VP8_PRED_PROB[probability + 3])
            {
                if !decoder.firstPart.readBit(VP8_PRED_PROB[probability + 4]) do
                    predictor = VP8_PRED_HE
                elif !decoder.firstPart.readBit(VP8_PRED_PROB[probability + 5]) do
                    predictor = VP8_PRED_RD
                else do
                    predictor = VP8_PRED_VR
            }
            elif !decoder.firstPart.readBit(VP8_PRED_PROB[probability + 6]) do
                predictor = VP8_PRED_LD
            elif !decoder.firstPart.readBit(VP8_PRED_PROB[probability + 7]) do
                predictor = VP8_PRED_VL
            elif !decoder.firstPart.readBit(VP8_PRED_PROB[probability + 8]) do
                predictor = VP8_PRED_HD
            else do
                predictor = VP8_PRED_HU

            decoder.predY4[j][i]           = predictor
            decoder.upMb[mbX].predictor[i] = predictor
        }

        decoder.leftMb.predictor[j] = predictor
    }
}
