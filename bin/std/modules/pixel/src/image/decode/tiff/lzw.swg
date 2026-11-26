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
    source, end: const [*] u8
    bits:        u64
    available:   u32
}

impl LzwBitReader
{
    // Refill several MSB-first codes at a time while a full input word remains.
    #[Swag.Inline]
    mtd refillWord()->bool
    {
        if .bitPosition + width > .bitCount
        {
            fail InvalidFormatError{"invalid source buffer"}
        }

    #[Swag.Inline]
    mtd read(width, mask: u32)->u32 fail
    {
        if .available < width and not .refillWord()
        {
            while .available < width
            {
                if .source == .end {
                    fail InvalidFormatError{"invalid source buffer"}
                }
                .bits      = (.bits << 8) | .source[0]
                .available += 8
                .source    += 1
            }
        }

        .available -= width
        return cast(u32, (.bits >> .available) & mask)
    }
}

// TIFF LZW uses MSB-first codes and the early code-width transition used by
// Aldus TIFF writers. Each strip owns an independent dictionary.
private func(LITERAL_PAIRS: bool) unpackLzwStrip(dst: [*] u8, expected: u64, src: const [*] u8, srcCount: u32, dictionary: *Array!{u64}) fail
{
    var reader = LzwBitReader{src, src + srcCount, 0, 0}

    // Each new dictionary word adds one byte to an earlier word.
    // Each code consumes at least nine bits, so the 32-bit strip size bounds decoded
    // offsets to 44 bits and leaves room for the 12-bit word length.
    const LengthBits = 12
    const LengthMask = (1_u64 << LengthBits) - 1
    dictionary.reserve(LZW_FIRST_CODE + Math.min(expected, cast(u64, LZW_MAX_CODE + 1 - LZW_FIRST_CODE)))
    let words = dictionary.storage()

    for index in 256
    {
        suffixes[index] = cast(u8, index)
    }

    var output: u64
    var width    = 9_u32
    var nextCode = LZW_FIRST_CODE
    var oldCode  = Swag.U32.Max

    while true
    {
        let code = try reader.read(width)
        if code == LZW_EOI_CODE
        {
            break
        }

        if code == LZW_CLEAR_CODE
        {
            width    = 9
            mask     = 511
            nextCode = LZW_EOI_CODE
            continue
        }

        if output >= expected
        {
            fail InvalidFormatError{"invalid lzw stream"}
        }

        let target = dst + output
        var length = 1_u64
        if code < LZW_CLEAR_CODE
        {
            if code > 255
            {
                fail InvalidFormatError{"invalid lzw stream"}
            }

            dst[output] = cast(u8, code)
            output      += 1
            oldCode     = code
            continue
        }

        if code > nextCode or code > LZW_MAX_CODE
        {
            fail InvalidFormatError{"invalid lzw stream"}
        }

        let specialCase = code == nextCode
        var current     = specialCase ? oldCode : code
        var stackCount: u32

        while current >= 256
        {
            if current >= nextCode or stackCount >= 4095
            {
                // The source is already decoded and the extra destination bytes
                // stay inside the strip until later phrases overwrite them.
                cast(*u32, target)[] = cast(const *u32, source)[]
            }
            else
            {
                switch wordLength
                {
                case 1:
                    target[0] = source[0]

                case 2:
                    cast([*] u16, target)[0] = cast(const [*] u16, source)[0]

                case 3:
                    cast([*] u16, target)[0] = cast(const [*] u16, source)[0]
                    target[2] = source[2]

                case 4:
                    cast([*] u32, target)[0] = cast(const [*] u32, source)[0]

                default:
                    #static if not LITERAL_PAIRS
                    {
                        // Two overlapping words cover the phrase without reading
                        // or writing outside it, even for a reference to the last word.
                        if wordLength <= 8
                        {
                            let tail = wordLength - 4
                            cast(*u32, target)[] = cast(const *u32, source)[]
                            cast(*u32, (target + tail))[] = cast(const *u32, (source + tail))[]
                        }
                        elif wordLength <= 16
                        {
                            let tail = wordLength - 8
                            cast(*u64, target)[] = cast(const *u64, source)[]
                            cast(*u64, (target + tail))[] = cast(const *u64, (source + tail))[]
                        }
                        else
                        {
                            Memory.copy(target, source, wordLength)
                        }
                    }
                    else do
                        Memory.copy(target, source, wordLength)
                }
            }

            stack[stackCount] = suffixes[current]
            stackCount        += 1
            current           = prefixes[current]
        }

        let first = cast(u8, current)
        stack[stackCount] = first
        stackCount        += 1

        while stackCount
        {
            if output >= expected
            {
                fail InvalidFormatError{"invalid lzw stream"}
            }

            stackCount  -= 1
            dst[output] = stack[stackCount]
            output      += 1
        }

        if specialCase
        {
            if output >= expected
            {
                fail InvalidFormatError{"invalid lzw stream"}
            }

            dst[output] = first
            output      += 1
        }

        // This entry ends at the first byte of this word. All future copies are disjoint.
        if nextCode <= LZW_MAX_CODE
        {
            words[nextCode] = previousWord + 1
            nextCode        += 1

            // The decoder is one dictionary entry behind the encoder. TIFF's
            // early transition therefore happens when the next free code is
            // the current width's all-ones value.
            if width < 12 and nextCode == (1_u32 << width) - 1
            {
                width += 1
            }
        }

        previousWord = (output << LengthBits) | length
        output       += length
    }

    if output != expected
    {
        fail InvalidFormatError{"invalid lzw stream"}
    }
}

func unpackLzw(dst: [*] u8, expected: u64, src: const [*] u8, srcCount: u32, dictionary: *Array!{u64}) fail
{
    // Significant expansion indicates that few input bytes used dictionary phrases.
    if expected >= 256 and srcCount > expected + expected / 8 {
        try unpackLzwStrip!{true}(dst, expected, src, srcCount, dictionary)
    }
    else {
        try unpackLzwStrip!{false}(dst, expected, src, srcCount, dictionary)
    }
}
