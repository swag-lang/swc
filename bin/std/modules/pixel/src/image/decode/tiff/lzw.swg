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
        let next = .source + 4
        if next > .end do
            return false
        let word = Math.byteSwap(cast(const [*] u32, .source)[0])
        .bits      = (.bits << 32) | word
        .available += 32
        .source    = next
        return true
    }

    #[Swag.Inline]
    mtd read(width, mask: u32)->u32 fail
    {
        if .available < width and not .refillWord()
        {
            while .available < width
            {
                if .source == .end do
                    fail InvalidFormatError{"invalid source buffer"}
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
private func(LITERAL_PAIRS: bool) unpackLzwStrip(dst: [*] u8, expected: u64, src: const [*] u8, srcCount: u32, dictionary: *Array'u64) fail
{
    var reader = LzwBitReader{src, src + srcCount, 0, 0}

    // Each new dictionary word adds one byte to an earlier word.
    // Each code consumes at least nine bits, so the 32-bit strip size bounds decoded
    // offsets to 44 bits and leaves room for the 12-bit word length.
    const LengthBits = 12
    const LengthMask = (1'u64 << LengthBits) - 1
    dictionary.reserve(LZW_FIRST_CODE + Math.min(expected, cast(u64, LZW_MAX_CODE + 1 - LZW_FIRST_CODE)))
    let words = dictionary.storage()

    var output:       u64
    var previousWord: u64
    var width = 9'u32
    var mask  = 511'u32

    // The first literal writes into the unused EOI slot, then starts the dictionary.
    // Until then a dictionary reference is necessarily greater than nextCode.
    var nextCode = LZW_EOI_CODE

    while true
    {
        #static if LITERAL_PAIRS
        {
            let pairWidth = width * 2
            if reader.available < pairWidth do
                discard reader.refillWord()

            // Both literals must use this code width and fit in the output.
            if reader.available >= pairWidth and nextCode + 2 < mask and expected - output >= 2
            {
                let codes  = cast(u32, (reader.bits >> (reader.available - pairWidth)))
                let first  = (codes >> width) & mask
                let second = codes & mask
                if (first | second) < LZW_CLEAR_CODE
                {
                    let firstWord = output << LengthBits
                    cast(*u16, (dst + output))[] = cast(u16, (first | (second << 8)))
                    words[nextCode]     = previousWord + 1
                    words[nextCode + 1] = firstWord | 2
                    previousWord        = ((output + 1) << LengthBits) | 1
                    output              += 2
                    reader.available    -= pairWidth
                    nextCode            += 2
                    continue
                }
            }
        }

        let code = try reader.read(width, mask)
        if code == LZW_EOI_CODE do
            break
        if code == LZW_CLEAR_CODE
        {
            width    = 9
            mask     = 511
            nextCode = LZW_EOI_CODE
            continue
        }

        if output >= expected do
            fail InvalidFormatError{"invalid lzw stream"}

        let target = dst + output
        var length = 1'u64
        if code < LZW_CLEAR_CODE
        {
            target[0] = cast(u8, code)
        }
        else
        {
            if code > nextCode do
                fail InvalidFormatError{"invalid lzw stream"}

            // A reference to the next entry uses the previous word and its first byte.
            let repeat     = code == nextCode
            let word       = repeat ? previousWord : words[code]
            let wordLength = word & LengthMask
            length = repeat ? wordLength + 1 : wordLength
            if length > expected - output do
                fail InvalidFormatError{"invalid lzw stream"}

            let sourceOffset = word >> LengthBits
            let source       = dst + sourceOffset
            if wordLength <= 4 and sourceOffset + 4 <= output and expected - output >= 4
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

            if repeat do
                target[wordLength] = source[0]
        }

        // This entry ends at the first byte of this word. All future copies are disjoint.
        if nextCode <= LZW_MAX_CODE
        {
            words[nextCode] = previousWord + 1
            nextCode        += 1

            // TIFF changes width when the next code reaches the current all-ones value.
            if width < 12 and nextCode == mask
            {
                width += 1
                mask  = (mask << 1) | 1
            }
        }

        previousWord = (output << LengthBits) | length
        output       += length
    }

    if output != expected do
        fail InvalidFormatError{"invalid lzw stream"}
}

func unpackLzw(dst: [*] u8, expected: u64, src: const [*] u8, srcCount: u32, dictionary: *Array'u64) fail
{
    // Significant expansion indicates that few input bytes used dictionary phrases.
    if expected >= 256 and srcCount > expected + expected / 8 do
        try unpackLzwStrip'true(dst, expected, src, srcCount, dictionary)
    else do
        try unpackLzwStrip'false(dst, expected, src, srcCount, dictionary)
}
