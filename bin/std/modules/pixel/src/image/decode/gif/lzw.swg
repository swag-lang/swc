//! Format: Graphics Interchange Format (GIF87a/GIF89a) decoder component.
//! Supported: Global/local palettes, transparency, interlacing, disposal, timing, loops, and sequential animation frames.
//! Not supported: Unknown extension labels and malformed or truncated sub-block streams.
//! Role: This file owns GIF LZW dictionary decoding.
//
// @LICENCE: LicenseRef-Public-Domain
// @ORIGIN: gifdec, https://github.com/lecram/gifdec
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#gifdec

#global namespace Gif

using Swag, Core, Core.Errors

private
{
    const LzwDictionaryLimit  = 1 << 12
    const LzwPrefixMask       = LzwDictionaryLimit - 1
    const LzwSuffixMask       = 0xFF'u32
    const LzwPrefixShift      = 8
    const LzwLengthShift      = 20
    const LzwCopyPrefixLength = 8     // Eight bytes amortize the copy over dependent dictionary reads.
}

private struct LzwBits
{
    cursor:    const [*] u8
    blockEnd:  const [*] u8
    bits:      u64
    available: s32
}

impl LzwBits
{
    #[Swag.Inline]
    mtd readKey(width: s32)->u16
    {
        while .available < width
        {
            if .cursor == .blockEnd
            {
                let length = .cursor[0]
                if not length do
                    return LzwDictionaryLimit
                .cursor   += 1
                .blockEnd = .cursor + length
            }

            // The sub-block scan already validated the byte ranges and terminator.
            if .blockEnd - .cursor >= 4
            {
                .bits      |= cast(u64, cast(const [*] u32, .cursor)[0]) << .available
                .cursor    += 4
                .available += 32
            }
            else
            {
                .bits      |= cast(u64, .cursor[0]) << .available
                .cursor    += 1
                .available += 8
            }
        }

        let key = cast(u16, (.bits & ((1'u64 << width) - 1)))
        .bits      >>= width
        .available -= width
        return key
    }
}

impl Decoder
{
    mtd(COPY_PREFIX: bool, FAST_LITERAL: bool) readImageData(indexed: const *IndexedFrame) fail
    {
        let minKeySize = cast(s32, indexed.minKeySize)
        let start      = cast(const [*] u8, unwrap indexed.data)
        var bits       = LzwBits{cursor: start, blockEnd: start}

        let frameSize = cast(u32, indexed.width) * indexed.height
        .frame.grow(frameSize)
        .frame.count = frameSize
        let frame = .frame.storage()

        let clear       = 1 << minKeySize
        let stop        = clear + 1
        let initKeySize = minKeySize + 1
        var keySize     = initKeySize
        var key         = bits.readKey(keySize)
        if key != clear do
            fail InvalidFormatError{"GIF LZW stream does not start with a clear code"}

        // An entry stores an 8-bit suffix, a 12-bit prefix and a 12-bit length minus one.
        var entries: [LzwDictionaryLimit] u32
        const OffsetCount = COPY_PREFIX ? LzwDictionaryLimit : 1
        var prefixOffsets: [OffsetCount] u32
        #static if not FAST_LITERAL
        {
            for literal in clear do
                entries[literal] = cast(u32, literal)
        }

        var frameOffset = 0'u32
        var nextCode    = stop + 1
        var length      = 0'u32
        var first       = 0'u32
        for
        {
            var addedEntry = false
            if key == clear
            {
                keySize  = initKeySize
                nextCode = stop + 1
            }
            elif frameOffset < frameSize and nextCode < LzwDictionaryLimit
            {
                // If the next code names this new entry, its suffix is the previous string's first index.
                entries[nextCode] = (length << LzwLengthShift) | (cast(u32, key) << LzwPrefixShift) | first
                if COPY_PREFIX and length >= LzwCopyPrefixLength do
                    prefixOffsets[nextCode] = frameOffset - length
                nextCode   += 1
                addedEntry = true
            }

            key = bits.readKey(keySize)
            if FAST_LITERAL and key < clear
            {
                if frameOffset >= frameSize do
                    fail InvalidFormatError{"GIF LZW data exceeds its frame"}
                length = 1
                first  = cast(u32, key)
                frame[frameOffset] = cast(u8, key)
            }
            else
            {
                if key == clear do
                    continue
                if key == stop or key == LzwDictionaryLimit do
                    break
                if key >= nextCode do
                    fail InvalidFormatError{"GIF LZW code is outside its dictionary"}
                if frameOffset >= frameSize do
                    fail InvalidFormatError{"GIF LZW data exceeds its frame"}

                var entry = entries[key]
                length = (entry >> LzwLengthShift) + 1
                if length > frameSize - frameOffset do
                    fail InvalidFormatError{"GIF LZW string exceeds its frame"}

                if COPY_PREFIX and length > LzwCopyPrefixLength
                {
                    // The prefix was written before this string, with no overlap.
                    let prefix = frame + prefixOffsets[key]
                    let target = frame + frameOffset
                    Memory.copy(target, prefix, length - 1)
                    first = prefix[0]
                    target[length - 1] = cast(u8, (entry & LzwSuffixMask))
                }
                else
                {
                    #static if FAST_LITERAL
                    {
                        // Finish the string by writing the literal prefix and the next suffix together.
                        var target = frame + frameOffset + length - 1
                        var prefix = (entry >> LzwPrefixShift) & LzwPrefixMask
                        while prefix >= clear
                        {
                            target[0] = cast(u8, (entry & LzwSuffixMask))
                            target    -= 1
                            entry     = entries[prefix]
                            prefix    = (entry >> LzwPrefixShift) & LzwPrefixMask
                        }

                        let pair = prefix | ((entry & LzwSuffixMask) << 8)
                        cast([*] u16, target - 1)[0] = cast(u16, pair)
                        first = prefix
                    }
                    else
                    {
                        var target = frame + frameOffset + length - 1
                        for length - 1
                        {
                            target[0] = cast(u8, (entry & LzwSuffixMask))
                            target    -= 1
                            entry     = entries[(entry >> LzwPrefixShift) & LzwPrefixMask]
                        }

                        first     = entry & LzwSuffixMask
                        target[0] = cast(u8, first)
                    }
                }
            }

            frameOffset += length
            if addedEntry and nextCode < LzwDictionaryLimit
            {
                if (nextCode & (nextCode - 1)) == 0 and frameOffset < frameSize do
                    keySize += 1
                if key < nextCode - 1 do
                    entries[nextCode - 1] = (entries[nextCode - 1] & ~LzwSuffixMask) | first
            }
        }

        if frameOffset != frameSize do
            fail InvalidFormatError{"GIF LZW frame has too few pixels"}
        if key != stop do
            fail InvalidFormatError{"GIF LZW stream needs an end code"}
    }

    mtd decodeIndices(indexed: const *IndexedFrame) fail
    {
        switch indexed.lzwMode
        {
        case .Chained:       try .readImageData'(false, false)(indexed)
        case .CopyPrefixes:  try .readImageData'(true, false)(indexed)
        case .DenseLiterals: try .readImageData'(false, true)(indexed)
        }
    }
}
