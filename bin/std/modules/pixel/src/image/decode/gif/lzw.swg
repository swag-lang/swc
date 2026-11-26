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

private const LzwDictionaryLimit = 1 << 12

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
    mtd initTable(keySize: s32)
    {
        .table.bulk     = Math.max(1 << (keySize + 1), 0x100's32)
        .table.nentries = (1 << keySize) + 2
        .table.entries.resize(.table.bulk)
        for key in 1 << keySize do
            .table.entries[key] = Entry{1, 0, cast(u8, key)}
    }

    mtd addEntry(length: u16, prefix: u16, suffix: u8)->bool
    {
        if .table.nentries == .table.bulk
        {
            .table.bulk *= 2
            .table.entries.resize(cast(u64, .table.bulk))
        }

        .table.entries[.table.nentries] = {length, prefix, suffix}
        .table.nentries += 1
        return (.table.nentries & (.table.nentries - 1)) == 0
    }

    mtd readImageData() fail
    {
        let minKeySize = cast(s32, (try .readU8()))
        if minKeySize < 2 or minKeySize > 8 do
            fail InvalidFormatError{"invalid frame"}

        let start = .safeStream()
        var bits  = LzwBits{cursor: start, blockEnd: start}
        try .discardSubBlocks()

        let frameSize = cast(u32, .fw) * .fh
        .frame.resize(frameSize)
        let frame = .frame.storage()

        let clear       = 1 << minKeySize
        let stop        = clear + 1
        let initKeySize = minKeySize + 1
        .initTable(minKeySize)
        var keySize = initKeySize
        var key     = bits.readKey(keySize)
        if key != clear do
            fail InvalidFormatError{"GIF LZW stream does not start with a clear code"}

        var frameOffset = 0'u32
        var tableIsFull = false
        var length      = 0'u16
        var entry: Entry
        for
        {
            var growKey = false
            if key == clear
            {
                keySize         = initKeySize
                .table.nentries = stop + 1
                tableIsFull     = false
            }
            elif frameOffset < frameSize and not tableIsFull
            {
                // If the next code names this new entry, its suffix is the previous string's first index.
                growKey     = .addEntry(length + 1, key, entry.suffix)
                tableIsFull = .table.nentries == LzwDictionaryLimit
            }

            key = bits.readKey(keySize)
            if key == clear do
                continue
            if key == stop or key == LzwDictionaryLimit do
                break
            if key >= .table.nentries do
                fail InvalidFormatError{"GIF LZW code is outside its dictionary"}
            if frameOffset >= frameSize do
                fail InvalidFormatError{"GIF LZW data exceeds its frame"}

            let entries = .table.entries.storage()
            entry  = entries[key]
            length = entry.length
            if not length or length > frameSize - frameOffset do
                fail InvalidFormatError{"GIF LZW string exceeds its frame"}

            // Each dictionary entry links to a previously decoded, shorter string.
            var target = frame + frameOffset + length - 1
            for length - 1
            {
                target[0] = entry.suffix
                target    -= 1
                entry     = entries[entry.prefix]
            }

            target[0] = entry.suffix

            frameOffset += length
            if growKey and not tableIsFull and frameOffset < frameSize do
                keySize += 1
            if key < .table.nentries - 1 and not tableIsFull do
                entries[.table.nentries - 1].suffix = entry.suffix
        }

        if frameOffset != frameSize do
            fail InvalidFormatError{"GIF LZW frame has too few pixels"}
        if key != stop do
            fail InvalidFormatError{"GIF LZW stream needs an end code"}
    }
}
