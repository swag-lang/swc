#global namespace PackedPixel

using Core

const Expand5Low  = cast(Math.Simd.U8x16) [0'u8, 8, 16, 25, 33, 41, 49, 58, 66, 74, 82, 90, 99, 107, 115, 123]
const Expand5High = cast(Math.Simd.U8x16) [132'u8, 140, 148, 156, 165, 173, 181, 189, 197, 206, 214, 222, 230, 239, 247, 255]
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

func decodeBgr555Row(source: const [*] u8, destination: [*] u8, pixelCount: u64)
{
    var src   = source
    var dst   = destination
    var count = pixelCount
    while count >= 16
    {
        let lowPixels  = Math.Simd.load(cast(const [*] u16) src)
        let highPixels = Math.Simd.load(cast(const [*] u16) (src + 16))
        let b          = expand5(Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) (lowPixels & 31'u16),
                                                        cast #bit(Math.Simd.S16x8) (highPixels & 31'u16)))
        let g = expand5(Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) ((lowPixels >> 5) & 31'u16),
                                               cast #bit(Math.Simd.S16x8) ((highPixels >> 5) & 31'u16)))
        let r = expand5(Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) ((lowPixels >> 10) & 31'u16),
                                               cast #bit(Math.Simd.S16x8) ((highPixels >> 10) & 31'u16)))
        Math.Simd.store(dst, Math.Simd.shuffle(b, BgrB0) | Math.Simd.shuffle(g, BgrG0) | Math.Simd.shuffle(r, BgrR0))
        Math.Simd.store(dst + 16, Math.Simd.shuffle(b, BgrB1) | Math.Simd.shuffle(g, BgrG1) | Math.Simd.shuffle(r, BgrR1))
        Math.Simd.store(dst + 32, Math.Simd.shuffle(b, BgrB2) | Math.Simd.shuffle(g, BgrG2) | Math.Simd.shuffle(r, BgrR2))
        src   += 32
        dst   += 48
        count -= 16
    }

    while count
    {
        let pixel = cast(u32) src[as u16]
        dst[0] = cast(u8) (((pixel & 0x1F) * 255 + 15) / 31)
        dst[1] = cast(u8) ((((pixel >> 5) & 0x1F) * 255 + 15) / 31)
        dst[2] = cast(u8) ((((pixel >> 10) & 0x1F) * 255 + 15) / 31)
        src    += 2
        dst    += 3
        count  -= 1
    }
}

func decodeBgra5551Row(source: const [*] u8, destination: [*] u8, pixelCount: u64, alphaFromBit: bool)
{
    var src   = source
    var dst   = destination
    var count = pixelCount
    while count >= 16
    {
        let lowPixels  = Math.Simd.load(cast(const [*] u16) src)
        let highPixels = Math.Simd.load(cast(const [*] u16) (src + 16))
        let b          = expand5(Math.Simd.packUnsigned(cast #bit(Math.Simd.S16x8) (lowPixels & 31'u16),
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
        src   += 32
        dst   += 64
        count -= 16
    }

    while count
    {
        let pixel = cast(u32) src[as u16]
        dst[0] = cast(u8) (((pixel & 0x1F) * 255 + 15) / 31)
        dst[1] = cast(u8) ((((pixel >> 5) & 0x1F) * 255 + 15) / 31)
        dst[2] = cast(u8) ((((pixel >> 10) & 0x1F) * 255 + 15) / 31)
        dst[3] = alphaFromBit ? (pixel & 0x8000 ? 255'u8 : 0'u8) : 255'u8
        src    += 2
        dst    += 4
        count  -= 1
    }
}
