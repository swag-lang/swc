//! Format: Shared packed-pixel decoder support.
//! Supported: SIMD and scalar expansion of RGB565, BGR565, RGBA5551, and BGRA5551 rows used by image codecs.
//! Not supported: This file does not recognize or decode a container format by itself.
//! Role: This file owns shared SIMD and scalar expansion of packed 16-bit pixels.
//
#global namespace PackedPixel

using Core, Core.Math

const Expand5Low  = cast(Simd.U8x16, [0'u8, 8, 16, 25, 33, 41, 49, 58, 66, 74, 82, 90, 99, 107, 115, 123])
const Expand5High = cast(Simd.U8x16, [132'u8, 140, 148, 156, 165, 173, 181, 189, 197, 206, 214, 222, 230, 239, 247, 255])
const ReverseU16  = cast(Simd.U8x16, [14'u8, 15, 12, 13, 10, 11, 8, 9, 6, 7, 4, 5, 2, 3, 0, 1])

// Three output blocks interleave sixteen blue, green, and red channel values.
const BgrB0 = cast(Simd.U8x16, [0'u8, 0x80, 0x80, 1, 0x80, 0x80, 2, 0x80, 0x80, 3, 0x80, 0x80, 4, 0x80, 0x80, 5])
const BgrG0 = cast(Simd.U8x16, [0x80'u8, 0, 0x80, 0x80, 1, 0x80, 0x80, 2, 0x80, 0x80, 3, 0x80, 0x80, 4, 0x80, 0x80])
const BgrR0 = cast(Simd.U8x16, [0x80'u8, 0x80, 0, 0x80, 0x80, 1, 0x80, 0x80, 2, 0x80, 0x80, 3, 0x80, 0x80, 4, 0x80])

const BgrB1 = cast(Simd.U8x16, [0x80'u8, 0x80, 6, 0x80, 0x80, 7, 0x80, 0x80, 8, 0x80, 0x80, 9, 0x80, 0x80, 10, 0x80])
const BgrG1 = cast(Simd.U8x16, [5'u8, 0x80, 0x80, 6, 0x80, 0x80, 7, 0x80, 0x80, 8, 0x80, 0x80, 9, 0x80, 0x80, 10])
const BgrR1 = cast(Simd.U8x16, [0x80'u8, 5, 0x80, 0x80, 6, 0x80, 0x80, 7, 0x80, 0x80, 8, 0x80, 0x80, 9, 0x80, 0x80])

const BgrB2 = cast(Simd.U8x16, [0x80'u8, 11, 0x80, 0x80, 12, 0x80, 0x80, 13, 0x80, 0x80, 14, 0x80, 0x80, 15, 0x80, 0x80])
const BgrG2 = cast(Simd.U8x16, [0x80'u8, 0x80, 11, 0x80, 0x80, 12, 0x80, 0x80, 13, 0x80, 0x80, 14, 0x80, 0x80, 15, 0x80])
const BgrR2 = cast(Simd.U8x16, [10'u8, 0x80, 0x80, 11, 0x80, 0x80, 12, 0x80, 0x80, 13, 0x80, 0x80, 14, 0x80, 0x80, 15])

#[Swag.Inline]
func expand5(value: Simd.U8x16)->Simd.U8x16
{
    let high = value > Simd.splat(15'u8)
    return Simd.select(high, Simd.shuffle(Expand5High, value), Simd.shuffle(Expand5Low, value))
}

func(REVERSE: bool, GREEN6: bool) decodeBgr16RowImpl(source: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    var src   = REVERSE ? source + pixelCount * 2 : source
    var dst   = destination
    var count = pixelCount

    // Expand complete SIMD blocks before handling the remaining pixels.
    while count >= 16
    {
        var lowPixels, highPixels: Simd.U16x8
        #static if REVERSE
        {
            src -= 32

            // Reverse word order within each block, and exchange the blocks.
            let highBytes = cast #bit(Simd.U8x16, Simd.load(cast(const [*] u16, (src + 16))))
            lowPixels = cast #bit(Simd.U16x8, Simd.shuffle(highBytes, ReverseU16))
            let lowBytes = cast #bit(Simd.U8x16, Simd.load(cast(const [*] u16, src)))
            highPixels = cast #bit(Simd.U16x8, Simd.shuffle(lowBytes, ReverseU16))
        }
        else
        {
            lowPixels  = Simd.load(cast(const [*] u16, src))
            highPixels = Simd.load(cast(const [*] u16, (src + 16)))
            src        += 32
        }

        let b = expand5(Simd.packUnsigned(cast #bit(Simd.S16x8, (lowPixels & 31'u16)),
                                          cast #bit(Simd.S16x8, (highPixels & 31'u16))))
        var g: Simd.U8x16
        #static if GREEN6
        {
            let lowGreen  = ((((lowPixels >> 5) & 63'u16) * 259'u16) + 33'u16) >> 6
            let highGreen = ((((highPixels >> 5) & 63'u16) * 259'u16) + 33'u16) >> 6
            g = Simd.packUnsigned(cast #bit(Simd.S16x8, lowGreen), cast #bit(Simd.S16x8, highGreen))
        }
        else
        {
            g = expand5(Simd.packUnsigned(cast #bit(Simd.S16x8, ((lowPixels >> 5) & 31'u16)),
                                          cast #bit(Simd.S16x8, ((highPixels >> 5) & 31'u16))))
        }

        let redShift = GREEN6 ? 11 : 10
        let r        = expand5(Simd.packUnsigned(cast #bit(Simd.S16x8, ((lowPixels >> redShift) & 31'u16)),
                                                 cast #bit(Simd.S16x8, ((highPixels >> redShift) & 31'u16))))
        Simd.store(dst, Simd.shuffle(b, BgrB0) | Simd.shuffle(g, BgrG0) | Simd.shuffle(r, BgrR0))
        Simd.store(dst + 16, Simd.shuffle(b, BgrB1) | Simd.shuffle(g, BgrG1) | Simd.shuffle(r, BgrR1))
        Simd.store(dst + 32, Simd.shuffle(b, BgrB2) | Simd.shuffle(g, BgrG2) | Simd.shuffle(r, BgrR2))
        dst   += 48
        count -= 16
    }

    while count
    {
        #static if REVERSE do
            src -= 2
        let pixel = cast(u32, cast(const *u16, src)[])
        dst[0] = cast(u8, (((pixel & 0x1F) * 255 + 15) / 31))
        #static if GREEN6 do
            dst[1] = cast(u8, (((((pixel >> 5) & 0x3F) * 259) + 33) >> 6))
        else do
            dst[1] = cast(u8, ((((pixel >> 5) & 0x1F) * 255 + 15) / 31))
        dst[2] = cast(u8, ((((pixel >> (GREEN6 ? 11 : 10)) & 0x1F) * 255 + 15) / 31))
        #static if not REVERSE do
            src += 2
        dst   += 3
        count -= 1
    }
}

func decodeBgr555Row(source: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    decodeBgr16RowImpl'(false, false)(source, destination, pixelCount)
}

func decodeBgr555RowReversed(source: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    decodeBgr16RowImpl'(true, false)(source, destination, pixelCount)
}

func decodeBgr565Row(source: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    decodeBgr16RowImpl'(false, true)(source, destination, pixelCount)
}

private struct Normalize16
{
    mask:        u16
    sourceShift: u8
    scale:       u16
    bias:        u16
    resultShift: u8
}

private func makeNormalize16(mask: u16, sourceShift, bits: u8)->Normalize16
{
    with var result: retval
    {
        .mask        = mask
        .sourceShift = sourceShift
        switch bits
        {
        case 1:
            .scale = 255

        case 2:
            .scale = 85

        case 3:
            .scale       = 73
            .resultShift = 1

        case 4:
            .scale = 17

        case 5:
            .scale       = 527
            .bias        = 23
            .resultShift = 6

        case 6:
            .scale       = 259
            .bias        = 33
            .resultShift = 6

        case 7:
            .scale       = 129
            .resultShift = 6

        case 8:
            .scale = 1
        }
    }

    return result
}

#[Swag.Inline]
private func normalize16(lowPixels, highPixels: Simd.U16x8, params: Normalize16)->Simd.U8x16
{
    let lowValues  = (((lowPixels & params.mask) >> params.sourceShift) * params.scale + params.bias) >> params.resultShift
    let highValues = (((highPixels & params.mask) >> params.sourceShift) * params.scale + params.bias) >> params.resultShift
    return Simd.packUnsigned(cast #bit(Simd.S16x8, lowValues), cast #bit(Simd.S16x8, highValues))
}

#[Swag.Inline]
private func normalize16(pixel: u16, params: Normalize16)->u8
{
    let channel = (pixel & params.mask) >> params.sourceShift
    let scaled  = channel * params.scale + params.bias
    return cast(u8, (scaled >> params.resultShift))
}

func decodeBgrMasked16Row(source: const [*] u8,
                          destination: [*] u8,
                          pixelCount: u64,
                          bMask: u16,
                          bShift,
                          bBits: u8,
                          gMask: u16,
                          gShift,
                          gBits: u8,
                          rMask: u16,
                          rShift,
                          rBits: u8)
{
    let bParams = makeNormalize16(bMask, bShift, bBits)
    let gParams = makeNormalize16(gMask, gShift, gBits)
    let rParams = makeNormalize16(rMask, rShift, rBits)
    var src     = source
    var dst     = destination
    var count   = pixelCount

    // Expand complete SIMD blocks before handling the remaining pixels.
    while count >= 16
    {
        let lowPixels  = Simd.load(cast(const [*] u16, src))
        let highPixels = Simd.load(cast(const [*] u16, (src + 16)))
        let b          = normalize16(lowPixels, highPixels, bParams)
        let g          = normalize16(lowPixels, highPixels, gParams)
        let r          = normalize16(lowPixels, highPixels, rParams)
        Simd.store(dst, Simd.shuffle(b, BgrB0) | Simd.shuffle(g, BgrG0) | Simd.shuffle(r, BgrR0))
        Simd.store(dst + 16, Simd.shuffle(b, BgrB1) | Simd.shuffle(g, BgrG1) | Simd.shuffle(r, BgrR1))
        Simd.store(dst + 32, Simd.shuffle(b, BgrB2) | Simd.shuffle(g, BgrG2) | Simd.shuffle(r, BgrR2))
        src   += 32
        dst   += 48
        count -= 16
    }

    while count
    {
        let pixel = cast(const *u16, src)[]
        dst[0] = normalize16(pixel, bParams)
        dst[1] = normalize16(pixel, gParams)
        dst[2] = normalize16(pixel, rParams)
        src    += 2
        dst    += 3
        count  -= 1
    }
}

func(REVERSE: bool) decodeBgra5551RowImpl(source: const [*] u8, destination: [*] u8, pixelCount: u64, alphaFromBit: bool)
{
    var src   = REVERSE ? source + pixelCount * 2 : source
    var dst   = destination
    var count = pixelCount

    // Expand complete SIMD blocks before handling the remaining pixels.
    while count >= 16
    {
        var lowPixels, highPixels: Simd.U16x8
        #static if REVERSE
        {
            src -= 32

            // Reverse word order within each block, and exchange the blocks.
            let highBytes = cast #bit(Simd.U8x16, Simd.load(cast(const [*] u16, (src + 16))))
            lowPixels = cast #bit(Simd.U16x8, Simd.shuffle(highBytes, ReverseU16))
            let lowBytes = cast #bit(Simd.U8x16, Simd.load(cast(const [*] u16, src)))
            highPixels = cast #bit(Simd.U16x8, Simd.shuffle(lowBytes, ReverseU16))
        }
        else
        {
            lowPixels  = Simd.load(cast(const [*] u16, src))
            highPixels = Simd.load(cast(const [*] u16, (src + 16)))
            src        += 32
        }

        let b = expand5(Simd.packUnsigned(cast #bit(Simd.S16x8, (lowPixels & 31'u16)),
                                          cast #bit(Simd.S16x8, (highPixels & 31'u16))))
        let g = expand5(Simd.packUnsigned(cast #bit(Simd.S16x8, ((lowPixels >> 5) & 31'u16)),
                                          cast #bit(Simd.S16x8, ((highPixels >> 5) & 31'u16))))
        let r = expand5(Simd.packUnsigned(cast #bit(Simd.S16x8, ((lowPixels >> 10) & 31'u16)),
                                          cast #bit(Simd.S16x8, ((highPixels >> 10) & 31'u16))))
        let alphaBits = Simd.packUnsigned(cast #bit(Simd.S16x8, (lowPixels >> 15)),
                                          cast #bit(Simd.S16x8, (highPixels >> 15)))
        var a = Simd.splat(255'u8)
        if alphaFromBit do
            a = alphaBits > Simd.splat(0'u8)

        // Pair blue/green and red/alpha before interleaving complete pixels.
        let bgLow  = cast #bit(Simd.U16x8, Simd.interleaveLow(b, g))
        let bgHigh = cast #bit(Simd.U16x8, Simd.interleaveHigh(b, g))
        let raLow  = cast #bit(Simd.U16x8, Simd.interleaveLow(r, a))
        let raHigh = cast #bit(Simd.U16x8, Simd.interleaveHigh(r, a))
        Simd.store(dst, cast #bit(Simd.U8x16, Simd.interleaveLow(bgLow, raLow)))
        Simd.store(dst + 16, cast #bit(Simd.U8x16, Simd.interleaveHigh(bgLow, raLow)))
        Simd.store(dst + 32, cast #bit(Simd.U8x16, Simd.interleaveLow(bgHigh, raHigh)))
        Simd.store(dst + 48, cast #bit(Simd.U8x16, Simd.interleaveHigh(bgHigh, raHigh)))
        dst   += 64
        count -= 16
    }

    while count
    {
        #static if REVERSE do
            src -= 2
        let pixel = cast(u32, cast(const *u16, src)[])
        dst[0] = cast(u8, (((pixel & 0x1F) * 255 + 15) / 31))
        dst[1] = cast(u8, ((((pixel >> 5) & 0x1F) * 255 + 15) / 31))
        dst[2] = cast(u8, ((((pixel >> 10) & 0x1F) * 255 + 15) / 31))
        dst[3] = alphaFromBit ? (pixel & 0x8000 ? 255'u8 : 0'u8) : 255'u8
        #static if not REVERSE do
            src += 2
        dst   += 4
        count -= 1
    }
}

func decodeBgra5551Row(source: const [*] u8, destination: [*] u8, pixelCount: u64, alphaFromBit: bool)
{
    decodeBgra5551RowImpl'(false)(source, destination, pixelCount, alphaFromBit)
}

func decodeBgra5551RowReversed(source: const [*] u8, destination: [*] u8, pixelCount: u64, alphaFromBit: bool)
{
    decodeBgra5551RowImpl'(true)(source, destination, pixelCount, alphaFromBit)
}
