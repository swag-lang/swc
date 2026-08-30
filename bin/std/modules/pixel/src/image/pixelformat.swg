#global public

using Swag

// Describes the channel set, sample representation, byte order, and storage class of a picture.
//
// Every format but one packs its channels into consecutive bytes of one row. `Yuv420` does not:
// it is what a video codec reconstructs, and it stores luma at full resolution beside two chroma
// planes at half resolution on both axes, so one chroma sample serves a two-by-two block. Ask
// [[Pixel.PixelFormat.isPacked]] before treating a format as bytes per pixel; [[Pixel.Image]]
// holds packed formats only, and a planar picture is described by [[Pixel.Yuv420View]].
enum PixelFormat: u8
{
    // These five values retain their historical serialized identifiers.
    BGR8   = 0       // Blue, green, then red; 24 bits per pixel.
    BGRA8  = 1       // Blue, green, red, then alpha; 32 bits per pixel.
    RGB8   = 2       // Red, green, then blue; 24 bits per pixel.
    RGBA8  = 3       // Red, green, blue, then alpha; 32 bits per pixel.
    Yuv420 = 4       // Planar 4:2:0 luma and chroma; twelve bits per pixel on average.
    Gray8            // One unsigned normalized luminance channel; 8 bits per pixel.
    GrayAlpha8       // Unsigned normalized luminance then alpha; 16 bits per pixel.
    Gray16           // One native-endian unsigned normalized 16-bit luminance channel.
    GrayAlpha16      // Native-endian unsigned normalized 16-bit luminance then alpha.
    GrayF16          // One native-endian IEEE 754 binary16 luminance channel.
    GrayAlphaF16     // Native-endian IEEE 754 binary16 luminance then alpha.
    GrayF32          // One native-endian IEEE 754 binary32 luminance channel.
    GrayAlphaF32     // Native-endian IEEE 754 binary32 luminance then alpha.
    RGB16            // Red, green, then blue as native-endian unsigned normalized 16-bit samples.
    RGBA16           // Red, green, blue, then alpha as native-endian unsigned normalized 16-bit samples.
    RGBF16           // Red, green, then blue as native-endian IEEE 754 binary16 samples.
    RGBAF16          // Red, green, blue, then alpha as native-endian IEEE 754 binary16 samples.
    RGBF32           // Red, green, then blue as native-endian IEEE 754 binary32 samples.
    RGBAF32          // Red, green, blue, then alpha as native-endian IEEE 754 binary32 samples.
}

// States how RGB samples relate to alpha in formats that store alpha.
enum AlphaMode: u8
{
    Straight          // RGB retains the unassociated source color independently of alpha.
    Premultiplied     // RGB is multiplied by alpha and is zero when alpha is zero.
}

impl PixelFormat
{
    // Reports whether one pixel occupies a whole number of consecutive bytes.
    //
    // Everything that walks a picture by [[Pixel.Image.bytesPerPixel]] and
    // [[Pixel.Image.rowStride]] needs this to hold. A planar format is carried by a texture and
    // by [[Pixel.Yuv420View]], never by an image.
    #[ConstExpr]
    func isPacked(me)->bool
    {
        switch #complete me
        {
        case .Gray8:        return true
        case .GrayAlpha8:   return true
        case .Gray16:       return true
        case .GrayAlpha16:  return true
        case .GrayF16:      return true
        case .GrayAlphaF16: return true
        case .GrayF32:      return true
        case .GrayAlphaF32: return true
        case .BGR8:         return true
        case .BGRA8:        return true
        case .RGB8:         return true
        case .RGBA8:        return true
        case .RGB16:        return true
        case .RGBA16:       return true
        case .RGBF16:       return true
        case .RGBAF16:      return true
        case .RGBF32:       return true
        case .RGBAF32:      return true
        case .Yuv420:       return false
        }

        return false
    }

    // Returns the number of bits one pixel occupies on average.
    //
    // A planar format answers its average, which is not the size of anything addressable: twelve
    // bits is what 4:2:0 costs per pixel over a whole picture.
    #[ConstExpr]
    func bitsPerPixel(me)->u8
    {
        switch #complete me
        {
        case .Gray8:        return 8
        case .GrayAlpha8:   return 16
        case .Gray16:       return 16
        case .GrayAlpha16:  return 32
        case .GrayF16:      return 16
        case .GrayAlphaF16: return 32
        case .GrayF32:      return 32
        case .GrayAlphaF32: return 64
        case .BGR8:         return 24
        case .BGRA8:        return 32
        case .RGB8:         return 24
        case .RGBA8:        return 32
        case .RGB16:        return 48
        case .RGBA16:       return 64
        case .RGBF16:       return 48
        case .RGBAF16:      return 64
        case .RGBF32:       return 96
        case .RGBAF32:      return 128
        case .Yuv420:       return 12
        }

        return 0
    }

    // Returns the number of stored color channels.
    #[ConstExpr]
    func channels(me)->u8
    {
        switch #complete me
        {
        case .Gray8:        return 1
        case .GrayAlpha8:   return 2
        case .Gray16:       return 1
        case .GrayAlpha16:  return 2
        case .GrayF16:      return 1
        case .GrayAlphaF16: return 2
        case .GrayF32:      return 1
        case .GrayAlphaF32: return 2
        case .BGR8:         return 3
        case .BGRA8:        return 4
        case .RGB8:         return 3
        case .RGBA8:        return 4
        case .RGB16:        return 3
        case .RGBA16:       return 4
        case .RGBF16:       return 3
        case .RGBAF16:      return 4
        case .RGBF32:       return 3
        case .RGBAF32:      return 4
        case .Yuv420:       return 3
        }

        return 0
    }

    // Returns the bit depth of each channel.
    #[ConstExpr]
    func bitDepth(me)->u8
    {
        switch #complete me
        {
        case .Gray8:        return 8
        case .GrayAlpha8:   return 8
        case .Gray16:       return 16
        case .GrayAlpha16:  return 16
        case .GrayF16:      return 16
        case .GrayAlphaF16: return 16
        case .GrayF32:      return 32
        case .GrayAlphaF32: return 32
        case .BGR8:         return 8
        case .BGRA8:        return 8
        case .RGB8:         return 8
        case .RGBA8:        return 8
        case .RGB16:        return 16
        case .RGBA16:       return 16
        case .RGBF16:       return 16
        case .RGBAF16:      return 16
        case .RGBF32:       return 32
        case .RGBAF32:      return 32
        case .Yuv420:       return 8
        }

        return 0
    }

    // Reports whether the format stores an alpha channel.
    #[ConstExpr]
    func hasAlpha(me)->bool
    {
        switch #complete me
        {
        case .Gray8:        return false
        case .GrayAlpha8:   return true
        case .Gray16:       return false
        case .GrayAlpha16:  return true
        case .GrayF16:      return false
        case .GrayAlphaF16: return true
        case .GrayF32:      return false
        case .GrayAlphaF32: return true
        case .BGR8:         return false
        case .BGRA8:        return true
        case .RGB8:         return false
        case .RGBA8:        return true
        case .RGB16:        return false
        case .RGBA16:       return true
        case .RGBF16:       return false
        case .RGBAF16:      return true
        case .RGBF32:       return false
        case .RGBAF32:      return true
        case .Yuv420:       return false
        }

        return false
    }

    // Reports whether channels use an IEEE floating-point representation.
    #[ConstExpr]
    func isFloat(me)->bool
    {
        return me == .GrayF16 or me == .GrayAlphaF16 or me == .GrayF32 or me == .GrayAlphaF32 or me == .RGBF16 or me == .RGBAF16 or me == .RGBF32 or me == .RGBAF32
    }

    // Reports whether channels use one unsigned normalized integer representation.
    #[ConstExpr]
    func isNormalizedInteger(me)->bool => me.isPacked() and !me.isFloat()

    // Reports whether the format stores one luminance channel instead of separate RGB channels.
    #[ConstExpr]
    func isGrayscale(me)->bool => me == .Gray8 or me == .GrayAlpha8 or me == .Gray16 or me == .GrayAlpha16 or me == .GrayF16 or me == .GrayAlphaF16 or me == .GrayF32 or me == .GrayAlphaF32
}

// Converts an IEEE 754 binary16 bit pattern to binary32, preserving signed zero,
// infinities, and NaN payload bits that fit in binary32.
internal func halfToFloat(value: u16)->f32
{
    let sign     = cast(u32) (value & 0x8000) << 16
    let exponent = cast(u32) (value >> 10) & 0x1F
    var mantissa = cast(u32) value & 0x3FF
    var bits: u32
    if exponent == 0
    {
        if mantissa == 0 do
            return cast #bit (f32) sign

        var unbiased = -14
        while (mantissa & 0x400) == 0
        {
            mantissa <<= 1
            unbiased -= 1
        }

        mantissa &= 0x3FF
        bits     = sign | (cast(u32) (unbiased + 127) << 23) | (mantissa << 13)
    }
    elif exponent == 0x1F do
        bits = sign | 0x7F800000 | (mantissa << 13)
    else do
        bits = sign | ((exponent + 112) << 23) | (mantissa << 13)
    return cast #bit (f32) bits
}

// Converts binary32 to IEEE 754 binary16 with round-to-nearest, ties-to-even.
// NaNs are canonicalized while their sign is preserved.
internal func floatToHalf(value: f32)->u16
{
    let bits     = cast #bit (u32) value
    let sign     = cast(u16) ((bits >> 16) & 0x8000)
    let exponent = cast(s32) ((bits >> 23) & 0xFF)
    let mantissa = bits & 0x7FFFFF
    if exponent == 0xFF do
        return sign | (mantissa == 0 ? 0x7C00'u16 : 0x7E00'u16)

    let unbiased = exponent - 127
    if unbiased > 15 do
        return sign | 0x7C00
    if unbiased < -24 do
        return sign

    if unbiased < -14
    {
        let significand = mantissa | 0x800000
        let shift       = cast(u32) (-unbiased - 1)
        var rounded     = significand >> shift
        let remainder   = significand & ((1'u32 << shift) - 1)
        let halfway     = 1'u32 << (shift - 1)
        if remainder > halfway or (remainder == halfway and (rounded & 1)) do
            rounded += 1
        return sign | cast(u16) rounded
    }

    var halfExponent = cast(u32) (unbiased + 15)
    var halfMantissa = mantissa >> 13
    let remainder    = mantissa & 0x1FFF
    if remainder > 0x1000 or (remainder == 0x1000 and (halfMantissa & 1))
    {
        halfMantissa += 1
        if halfMantissa == 0x400
        {
            halfMantissa = 0
            halfExponent += 1
            if halfExponent >= 0x1F do
                return sign | 0x7C00
        }
    }

    return sign | cast(u16) ((halfExponent << 10) | halfMantissa)
}
