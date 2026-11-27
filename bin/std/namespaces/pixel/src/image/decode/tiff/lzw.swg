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
        if next > .end
        {
            return false
        }

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
                if .source == .end
                {
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

// Copy a phrase longer than four bytes using two endpoint loads when possible.
#[Swag.Inline]
private func copyLongLzwWord(target: [*] u8, source: const [*] u8, length: u64)
{
    if length <= 8
    {
        let tail = length - 4
        cast(*u32, target)[] = cast(const *u32, source)[]
        cast(*u32, (target + tail))[] = cast(const *u32, (source + tail))[]
    }
    else if length <= 16
    {
        let tail = length - 8
        cast(*u64, target)[] = cast(const *u64, source)[]
        cast(*u64, (target + tail))[] = cast(const *u64, (source + tail))[]
    }
    else
    {
        Memory.copy(target, source, length)
    }
}

private enum LzwMode
{
    History
    LiteralPairs
    CachedWords
}

// TIFF LZW uses MSB-first codes and the early code-width transition used by
// Aldus TIFF writers. Each strip owns an independent dictionary.
private func(MODE: LzwMode) unpackLzwStrip(dst: [*] u8, expected: u64, src: const [*] u8, srcCount: u32, dictionary: *Array!{u64}) fail
{
    var reader = LzwBitReader{src, src + srcCount, 0, 0}

    // Each new dictionary word adds one byte to an earlier word.
    // Each code consumes at least nine bits, so the 32-bit strip size bounds decoded
    // offsets to 44 bits and leaves room for the 12-bit word length.
    const LengthBits = 12
    const LengthMask = (1_u64 << LengthBits) - 1

    // Cached words carry their length in the high bits. For a long word the
    // payload is an output offset followed by the first byte of the phrase.
    const ShortLengthShift = 64 - LengthBits
    const ShortLengthStep  = 1_u64 << ShortLengthShift
    const FirstByteMask    = 255_u64
    const LongOffsetMask   = (1_u64 << (ShortLengthShift - 8)) - 1
    const ShortWordBytes   = 4
    dictionary.reserve(LZW_FIRST_CODE + Math.min(expected, cast(u64, LZW_MAX_CODE + 1 - LZW_FIRST_CODE)))
    let words = dictionary.storage()
    #static if MODE == LzwMode.CachedWords
    {
        for literal in LZW_CLEAR_CODE
        {
            words[literal] = ShortLengthStep | literal
        }
    }

    var output:       u64
    var previousWord: u64
    var width = 9_u32
    var mask  = 511_u32

    // The first literal writes into the unused EOI slot, then starts the dictionary.
    // Until then a dictionary reference is necessarily greater than nextCode.
    var nextCode = LZW_EOI_CODE

    while true
    {
        #static if MODE != LzwMode.History
        {
            let pairWidth = width * 2
            if reader.available < pairWidth
            {
                discard reader.refillWord()
            }

            // A second four-byte store can start up to three bytes after the first.
            const MinPairOutput = MODE == LzwMode.LiteralPairs ? 2 : 7

            // Neither code may change the width or refer to an entry we are adding.
            if reader.available >= pairWidth and
               nextCode + 2 < mask and
               expected - output >= MinPairOutput
            {
                let codes  = cast(u32, (reader.bits >> (reader.available - pairWidth)))
                let first  = (codes >> width) & mask
                let second = codes & mask
                #static if MODE == LzwMode.LiteralPairs
                {
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
                else
                {
                    if first < nextCode and
                       second < nextCode and
                       (first & ~1_u32) != LZW_CLEAR_CODE and
                       (second & ~1_u32) != LZW_CLEAR_CODE
                    {
                        let left  = words[first]
                        let right = words[second]

                        // The three lengths must each be at most three, so both new words fit inline.
                        if (left | right | previousWord) < ShortWordBytes * ShortLengthStep
                        {
                            let firstLength    = left >> ShortLengthShift
                            let secondLength   = right >> ShortLengthShift
                            let previousLength = previousWord >> ShortLengthShift
                            cast(*u32, (dst + output))[] = cast(u32, left)
                            cast(*u32, (dst + output + firstLength))[] = cast(u32, right)
                            words[nextCode]     = (previousWord + ShortLengthStep) | ((left & FirstByteMask) << (previousLength * 8))
                            words[nextCode + 1] = (left + ShortLengthStep) | ((right & FirstByteMask) << (firstLength * 8))
                            previousWord        = right
                            output              += firstLength + secondLength
                            reader.available    -= pairWidth
                            nextCode            += 2
                            continue
                        }
                    }
                }
            }
        }

        let code = try reader.read(width, mask)
        if (code & ~1_u32) == LZW_CLEAR_CODE
        {
            if code == LZW_EOI_CODE
            {
                if output == expected
                {
                    return
                }

                break
            }

            width    = 9
            mask     = 511
            nextCode = LZW_EOI_CODE
            continue
        }

        var length: u64
        var phrase: u64
        #static if MODE == LzwMode.CachedWords
        {
            if code > nextCode
            {
                break
            }

            let repeat = code == nextCode
            phrase = repeat ? previousWord : words[code]
            let wordLength = phrase >> ShortLengthShift
            length = repeat ? wordLength + 1 : wordLength
            let remaining = expected - output
            if length > remaining
            {
                break
            }

            let target = dst + output
            if wordLength <= ShortWordBytes
            {
                if remaining >= 4
                {
                    // Later words replace any extra bytes within the strip.
                    cast(*u32, target)[] = cast(u32, phrase)
                }
                else
                {
                    switch wordLength
                    {
                    case 1:
                        target[0] = cast(u8, phrase)

                    case 2:
                        cast(*u16, target)[] = cast(u16, phrase)

                    case 3:
                        cast(*u16, target)[] = cast(u16, phrase)
                        target[2] = cast(u8, (phrase >> 16))
                    }
                }
            }
            else
            {
                let sourceOffset = repeat ? output - wordLength : (phrase >> 8) & LongOffsetMask
                let source       = dst + sourceOffset
                copyLongLzwWord(target, source, wordLength)
            }

            if repeat
            {
                let first = phrase & FirstByteMask
                target[wordLength] = cast(u8, first)
                if wordLength < ShortWordBytes
                {
                    phrase |= first << (wordLength * 8)
                }

                phrase += ShortLengthStep
            }
        }
        else
        {
            if output >= expected
            {
                break
            }

            let target = dst + output
            length = 1
            if code < LZW_CLEAR_CODE
            {
                target[0] = cast(u8, code)
            }
            else
            {
                if code > nextCode
                {
                    break
                }

                // A reference to the next entry uses the previous word and its first byte.
                let repeat     = code == nextCode
                let word       = repeat ? previousWord : words[code]
                let wordLength = word & LengthMask
                length = repeat ? wordLength + 1 : wordLength
                if length > expected - output
                {
                    break
                }

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
                        #static if MODE != LzwMode.LiteralPairs
                        {
                            copyLongLzwWord(target, source, wordLength)
                        }
                        else
                        {
                            Memory.copy(target, source, wordLength)
                        }
                    }
                }

                if repeat
                {
                    target[wordLength] = source[0]
                }
            }
        }

        // This entry ends at the first byte of this word. All future copies are disjoint.
        if nextCode <= LZW_MAX_CODE
        {
            #static if MODE == LzwMode.CachedWords
            {
                let previousLength = previousWord >> ShortLengthShift
                if previousLength < ShortWordBytes
                {
                    let first = phrase & FirstByteMask
                    words[nextCode] = (previousWord + ShortLengthStep) | (first << (previousLength * 8))
                }
                else
                {
                    let previousOffset = output - previousLength
                    let firstAndLength = previousWord & ((Swag.U64.Max << ShortLengthShift) | FirstByteMask)
                    words[nextCode] = ((previousOffset << 8) | firstAndLength) + ShortLengthStep
                }
            }
            else
            {
                words[nextCode] = previousWord + 1
            }

            nextCode += 1

            // TIFF changes width when the next code reaches the current all-ones value.
            if width < 12 and nextCode == mask
            {
                width += 1
                mask  = (mask << 1) | 1
            }
        }

        #static if MODE == LzwMode.CachedWords
        {
            previousWord = phrase
        }
        else
        {
            previousWord = (output << LengthBits) | length
        }

        output += length
    }

    fail InvalidFormatError{"invalid lzw stream"}
}

func unpackLzw(dst: [*] u8, expected: u64, src: const [*] u8, srcCount: u32, dictionary: *Array!{u64}) fail
{
    // Smaller strips need more short words to amortize the literal table.
    let cachedLimit = expected / 2 + (expected < 8 * 1024 ? expected / 8 : 0)

    // Significant expansion indicates that few input bytes used dictionary phrases.
    if expected >= 256 and srcCount > expected + expected / 8
    {
        try unpackLzwStrip!{LzwMode.LiteralPairs}(dst, expected, src, srcCount, dictionary)
    }
    else if expected >= 256 and srcCount >= cachedLimit
    {
        // Moderately compressible strips tend to use literals and short words.
        try unpackLzwStrip!{LzwMode.CachedWords}(dst, expected, src, srcCount, dictionary)
    }
    else
    {
        try unpackLzwStrip!{LzwMode.History}(dst, expected, src, srcCount, dictionary)
    }
}
