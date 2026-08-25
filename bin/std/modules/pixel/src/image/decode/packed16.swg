//! Format: Shared packed-pixel decoder support.
//! Supported: SIMD and scalar expansion of RGB565, BGR565, RGBA5551, and BGRA5551 rows used by image codecs.
//! Not supported: This file does not recognize or decode a container format by itself.
//! Role: This file owns shared SIMD and scalar expansion of packed 16-bit pixels.
//
#global namespace PackedPixel

using Core

const Expand5Low  = cast(Math.Simd.U8x16) [0'u8, 8, 16, 25, 33, 41, 49, 58, 66, 74, 82, 90, 99, 107, 115, 123]
const Expand5High = cast(Math.Simd.U8x16) [132'u8, 140, 148, 156, 165, 173, 181, 189, 197, 206, 214, 222, 230, 239, 247, 255]
const ReverseU16  = cast(Math.Simd.U8x16) [14'u8, 15, 12, 13, 10, 11, 8, 9, 6, 7, 4, 5, 2, 3, 0, 1]
const BgrB0       = cast(Math.Simd.U8x16) [0'u8, 0x80, 0x80, 1, 0x80, 0x80, 2, 0x80, 0x80, 3, 0x80, 0x80, 4, 0x80, 0x80, 5]
const BgrG0       = cast(Math.Simd.U8x16) [0x80'u8, 0, 0x80, 0x80, 1, 0x80, 0x80, 2, 0x80, 0x80, 3, 0x80, 0x80, 4, 0x80, 0x80]
const BgrR0       = cast(Math.Simd.U8x16) [0x80'u8, 0x80, 0, 0x80, 0x80, 1, 0x80, 0x80, 2, 0x80, 0x80, 3, 0x80, 0x80, 4, 0x80]
const BgrB1       = cast(Math.Simd.U8x16) [0x80'u8, 0x80, 6, 0x80, 0x80, 7, 0x80, 0x80, 8, 0x80, 0x80, 9, 0x80, 0x80, 10, 0x80]
const BgrG1       = cast(Math.Simd.U8x16) [5'u8, 0x80, 0x80, 6, 0x80, 0x80, 7, 0x80, 0x80, 8, 0x80, 0x80, 9, 0x80, 0x80, 10]
const BgrR1       = cast(Math.Simd.U8x16) [0x80'u8, 5, 0x80, 0x80, 6, 0x80, 0x80, 7, 0x80, 0x80, 8, 0x80, 0x80, 9, 0x80, 0x80]
const BgrB2       = cast(Math.Simd.U8x16) [0x80'u8, 11, 0x80, 0x80, 12, 0x80, 0x80, 13, 0x80, 0x80, 14, 0x80, 0x80, 15, 0x80, 0x80]
const BgrG2       = cast(Math.Simd.U8x16) [0x80'u8, 0x80, 11, 0x80, 0x80, 12, 0x80, 0x80, 13, 0x80, 0x80, 14, 0x80, 0x80, 15, 0x80]
const BgrR2       = cast(Math.Simd.U8x16) [10'u8, 0x80, 0x80, 11, 0x80, 0x80, 12, 0x80, 0x80, 13, 0x80, 0x80, 14, 0x80, 0x80, 15]

#[Swag.Inline]
func expand5(value: Math.Simd.U8x16)->Math.Simd.U8x16
{
    let high = value > Math.Simd.splat(15'u8)
    return Math.Simd.select(high, Math.Simd.shuffle(Expand5High, value), Math.Simd.shuffle(Expand5Low, value))
}

func(REVERSE: bool, GREEN6: bool) decodeBgr16RowImpl(source: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    var src   = REVERSE ? source + pixelCount * 2 : source
    var dst   = destination
    var count = pixelCount
    while count >= 16
    {
        var lowPixels, highPixels: Math.Simd.U16x8
        #static if REVERSE
        {
            src        -= 32
            lowPixels  = cast #bit(Math.Simd.U16x8) Math.Simd.shuffle(cast #bit(Math.Simd.U8x16) Math.Simd.load(cast(const [*] u16) (src + 16)), ReverseU16)
            highPixels = cast #bit(Math.Simd.U16x8) Math.Simd.shuffle(cast #bit(Math.Simd.U8x16) Math.Simd.load(cast(const [*] u16) src), ReverseU16)
        }
        else
        {
            lowPixels  = Math.Simd.load(cast(const [*] u16) src)
            highPixels = Math.Simd.load(cast(const [*] u16) (src + 16))
            src        += 32
        }

        let b = expand5(Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) (lowPixels & 31'u16),
                                               cast #bit(Math.Simd.S16x8) (highPixels & 31'u16)))
        var g: Math.Simd.U8x16
        #static if GREEN6
        {
            let lowGreen  = ((((lowPixels >> 5) & 63'u16) * 259'u16) + 33'u16) >> 6
            let highGreen = ((((highPixels >> 5) & 63'u16) * 259'u16) + 33'u16) >> 6
            g = Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) lowGreen, cast #bit(Math.Simd.S16x8) highGreen)
        }
        else
        {
            g = expand5(Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) ((lowPixels >> 5) & 31'u16),
                                               cast #bit(Math.Simd.S16x8) ((highPixels >> 5) & 31'u16)))
        }

        let redShift = GREEN6 ? 11 : 10
        let r        = expand5(Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) ((lowPixels >> redShift) & 31'u16),
                                                      cast #bit(Math.Simd.S16x8) ((highPixels >> redShift) & 31'u16)))
        Math.Simd.store(dst, Math.Simd.shuffle(b, BgrB0) | Math.Simd.shuffle(g, BgrG0) | Math.Simd.shuffle(r, BgrR0))
        Math.Simd.store(dst + 16, Math.Simd.shuffle(b, BgrB1) | Math.Simd.shuffle(g, BgrG1) | Math.Simd.shuffle(r, BgrR1))
        Math.Simd.store(dst + 32, Math.Simd.shuffle(b, BgrB2) | Math.Simd.shuffle(g, BgrG2) | Math.Simd.shuffle(r, BgrR2))
        dst   += 48
        count -= 16
    }

    while count
    {
        #static if REVERSE do
            src -= 2
        let pixel = cast(u32) src[as u16]
        dst[0] = cast(u8) (((pixel & 0x1F) * 255 + 15) / 31)
        #static if GREEN6 do
            dst[1] = cast(u8) (((((pixel >> 5) & 0x3F) * 259) + 33) >> 6)
        else do
            dst[1] = cast(u8) ((((pixel >> 5) & 0x1F) * 255 + 15) / 31)
        dst[2] = cast(u8) ((((pixel >> (GREEN6 ? 11 : 10)) & 0x1F) * 255 + 15) / 31)
        #static if !REVERSE do
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
    var result: retval
    result.mask        = mask
    result.sourceShift = sourceShift
    switch bits
    {
    case 1:
        result.scale = 255

    case 2:
        result.scale = 85

    case 3:
        result.scale       = 73
        result.resultShift = 1

    case 4:
        result.scale = 17

    case 5:
        result.scale       = 527
        result.bias        = 23
        result.resultShift = 6

    case 6:
        result.scale       = 259
        result.bias        = 33
        result.resultShift = 6

    case 7:
        result.scale       = 129
        result.resultShift = 6

    case 8:
        result.scale = 1
    }

    return result
}

#[Swag.Inline]
private func normalize16(lowPixels, highPixels: Math.Simd.U16x8, params: Normalize16)->Math.Simd.U8x16
{
    let lowValues  = (((lowPixels & params.mask) >> params.sourceShift) * params.scale + params.bias) >> params.resultShift
    let highValues = (((highPixels & params.mask) >> params.sourceShift) * params.scale + params.bias) >> params.resultShift
    return Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) lowValues, cast #bit(Math.Simd.S16x8) highValues)
}

func decodeBgrMasked16Row(source: const [*] u8, destination: [*] u8, pixelCount: u64, bMask: u16, bShift, bBits: u8, gMask: u16, gShift, gBits: u8, rMask: u16, rShift, rBits: u8)
{
    let bParams = makeNormalize16(bMask, bShift, bBits)
    let gParams = makeNormalize16(gMask, gShift, gBits)
    let rParams = makeNormalize16(rMask, rShift, rBits)
    var src     = source
    var dst     = destination
    var count   = pixelCount
    while count >= 16
    {
        let lowPixels  = Math.Simd.load(cast(const [*] u16) src)
        let highPixels = Math.Simd.load(cast(const [*] u16) (src + 16))
        let b          = normalize16(lowPixels, highPixels, bParams)
        let g          = normalize16(lowPixels, highPixels, gParams)
        let r          = normalize16(lowPixels, highPixels, rParams)
        Math.Simd.store(dst, Math.Simd.shuffle(b, BgrB0) | Math.Simd.shuffle(g, BgrG0) | Math.Simd.shuffle(r, BgrR0))
        Math.Simd.store(dst + 16, Math.Simd.shuffle(b, BgrB1) | Math.Simd.shuffle(g, BgrG1) | Math.Simd.shuffle(r, BgrR1))
        Math.Simd.store(dst + 32, Math.Simd.shuffle(b, BgrB2) | Math.Simd.shuffle(g, BgrG2) | Math.Simd.shuffle(r, BgrR2))
        src   += 32
        dst   += 48
        count -= 16
    }

    while count
    {
        let pixel = src[as u16]
        dst[0] = cast(u8) ((((pixel & bParams.mask) >> bParams.sourceShift) * bParams.scale + bParams.bias) >> bParams.resultShift)
        dst[1] = cast(u8) ((((pixel & gParams.mask) >> gParams.sourceShift) * gParams.scale + gParams.bias) >> gParams.resultShift)
        dst[2] = cast(u8) ((((pixel & rParams.mask) >> rParams.sourceShift) * rParams.scale + rParams.bias) >> rParams.resultShift)
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
    while count >= 16
    {
        var lowPixels, highPixels: Math.Simd.U16x8
        #static if REVERSE
        {
            src        -= 32
            lowPixels  = cast #bit(Math.Simd.U16x8) Math.Simd.shuffle(cast #bit(Math.Simd.U8x16) Math.Simd.load(cast(const [*] u16) (src + 16)), ReverseU16)
            highPixels = cast #bit(Math.Simd.U16x8) Math.Simd.shuffle(cast #bit(Math.Simd.U8x16) Math.Simd.load(cast(const [*] u16) src), ReverseU16)
        }
        else
        {
            lowPixels  = Math.Simd.load(cast(const [*] u16) src)
            highPixels = Math.Simd.load(cast(const [*] u16) (src + 16))
            src        += 32
        }

        let b = expand5(Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) (lowPixels & 31'u16),
                                               cast #bit(Math.Simd.S16x8) (highPixels & 31'u16)))
        let g = expand5(Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) ((lowPixels >> 5) & 31'u16),
                                               cast #bit(Math.Simd.S16x8) ((highPixels >> 5) & 31'u16)))
        let r = expand5(Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) ((lowPixels >> 10) & 31'u16),
                                               cast #bit(Math.Simd.S16x8) ((highPixels >> 10) & 31'u16)))
        let alphaBits = Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) (lowPixels >> 15),
                                               cast #bit(Math.Simd.S16x8) (highPixels >> 15))
        var a = Math.Simd.splat(255'u8)
        if alphaFromBit do
            a = alphaBits > Math.Simd.splat(0'u8)
        let bgLow  = Math.Simd.interleaveLow(b, g)
        let bgHigh = Math.Simd.interleaveHigh(b, g)
        let raLow  = Math.Simd.interleaveLow(r, a)
        let raHigh = Math.Simd.interleaveHigh(r, a)
        Math.Simd.store(dst, cast #bit(Math.Simd.U8x16) Math.Simd.interleaveLow(cast #bit(Math.Simd.U16x8) bgLow, cast #bit(Math.Simd.U16x8) raLow))
        Math.Simd.store(dst + 16, cast #bit(Math.Simd.U8x16) Math.Simd.interleaveHigh(cast #bit(Math.Simd.U16x8) bgLow, cast #bit(Math.Simd.U16x8) raLow))
        Math.Simd.store(dst + 32, cast #bit(Math.Simd.U8x16) Math.Simd.interleaveLow(cast #bit(Math.Simd.U16x8) bgHigh, cast #bit(Math.Simd.U16x8) raHigh))
        Math.Simd.store(dst + 48, cast #bit(Math.Simd.U8x16) Math.Simd.interleaveHigh(cast #bit(Math.Simd.U16x8) bgHigh, cast #bit(Math.Simd.U16x8) raHigh))
        dst   += 64
        count -= 16
    }

    while count
    {
        #static if REVERSE do
            src -= 2
        let pixel = cast(u32) src[as u16]
        dst[0] = cast(u8) (((pixel & 0x1F) * 255 + 15) / 31)
        dst[1] = cast(u8) ((((pixel >> 5) & 0x1F) * 255 + 15) / 31)
        dst[2] = cast(u8) ((((pixel >> 10) & 0x1F) * 255 + 15) / 31)
        dst[3] = alphaFromBit ? (pixel & 0x8000 ? 255'u8 : 0'u8) : 255'u8
        #static if !REVERSE do
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
