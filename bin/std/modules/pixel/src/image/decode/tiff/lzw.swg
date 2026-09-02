//! Format: Tagged Image File Format (TIFF) decoder component.
//! Supported: 8-bit chunky grayscale, palette, RGB, and RGBA strips using no compression, PackBits, or LZW with predictors.
//! Not supported: Planar samples, tiled images, JPEG/Deflate compression, and sample depths other than 8-bit.
//! Role: This file owns TIFF LZW dictionary decoding.
//
#global namespace Tiff

using Core, Core.Errors

const LZW_CLEAR_CODE = 256
const LZW_EOI_CODE   = 257
const LZW_FIRST_CODE = 258
const LZW_MAX_CODE   = 4095

struct LzwBitReader
{
    data:        const [*] u8
    bitCount:    u64
    bitPosition: u64
}

impl LzwBitReader
{
    mtd read(width: u32)->u32 fail
    {
        if .bitPosition + width > .bitCount do
            fail InvalidFormatError{"invalid source buffer"}

        var result: u32
        for width
        {
            let byteIndex = .bitPosition >> 3
            let bitIndex  = 7 - (.bitPosition & 7)
            result       = (result << 1) | ((cast(u32) .data[byteIndex] >> bitIndex) & 1)
            .bitPosition += 1
        }

        return result
    }
}

// TIFF LZW uses MSB-first codes and the early code-width transition used by
// Aldus TIFF writers. Each strip owns an independent dictionary.
func unpackLzw(dst: [*] u8, expected: u64, src: const [*] u8, srcCount: u64) fail
{
    var reader: LzwBitReader = undefined
    reader.data        = src
    reader.bitCount    = srcCount * 8
    reader.bitPosition = 0

    var prefixes: [4096] u16
    var suffixes: [4096] u8 = undefined
    var stack:    [4096] u8 = undefined

    for index in 256 do
        suffixes[index] = cast(u8) index

    var output: u64
    var width    = 9'u32
    var nextCode = LZW_FIRST_CODE
    var oldCode  = Swag.U32.Max

    while output < expected
    {
        let code = reader.read(width)
        if code == LZW_CLEAR_CODE
        {
            width    = 9
            nextCode = LZW_FIRST_CODE
            oldCode  = Swag.U32.Max
            continue
        }

        if code == LZW_EOI_CODE do
            break

        if oldCode == Swag.U32.Max
        {
            if code > 255 do
                fail InvalidFormatError{"invalid lzw stream"}

            dst[output] = cast(u8) code
            output      += 1
            oldCode     = code
            continue
        }

        if code > nextCode or code > LZW_MAX_CODE do
            fail InvalidFormatError{"invalid lzw stream"}

        let specialCase = code == nextCode
        var current     = specialCase ? oldCode : code
        var stackCount: u32

        while current >= 256
        {
            if current >= nextCode or stackCount >= 4095 do
                fail InvalidFormatError{"invalid lzw stream"}

            stack[stackCount] = suffixes[current]
            stackCount        += 1
            current           = prefixes[current]
        }

        let first = cast(u8) current
        stack[stackCount] = first
        stackCount        += 1

        while stackCount
        {
            if output >= expected do
                fail InvalidFormatError{"invalid lzw stream"}

            stackCount  -= 1
            dst[output] = stack[stackCount]
            output      += 1
        }

        if specialCase
        {
            if output >= expected do
                fail InvalidFormatError{"invalid lzw stream"}
            dst[output] = first
            output      += 1
        }

        if nextCode <= LZW_MAX_CODE
        {
            prefixes[nextCode] = cast(u16) oldCode
            suffixes[nextCode] = first
            nextCode           += 1

            // The decoder is one dictionary entry behind the encoder. TIFF's
            // early transition therefore happens when the next free code is
            // the current width's all-ones value.
            if width < 12 and nextCode == (1'u32 << width) - 1 do
                width += 1
        }

        oldCode = code
    }

    if output != expected do
        fail InvalidFormatError{"invalid lzw stream"}
}
