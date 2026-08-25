//! Format: Graphics Interchange Format (GIF87a/GIF89a) decoder component.
//! Supported: Global/local palettes, transparency, interlacing, disposal, timing, loops, and sequential animation frames.
//! Not supported: Unknown extension labels and malformed or truncated sub-block streams.
//! Role: This file owns GIF LZW dictionary decoding.
//
// @LICENCE: LicenseRef-Public-Domain
// @ORIGIN: gifdec, https://github.com/lecram/gifdec
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRD_PARTY_NOTICES.md#gifdec

#global namespace Gif

using Swag, Core, Core.Errors

impl Decoder
{
    mtd initTable(keySize: s32)
    {
        .table.bulk     = Math.max(1 << (keySize + 1), 0x100's32)
        .table.nentries = (1 << keySize) + 2
        .table.entries.resize(.table.bulk)
        for key in 1 << keySize do
            .table.entries[key] = {1, 0xFFF, cast(u8) key}
    }

    mtd getKey(keySize: s32, subLen, shift, byte: *u8)->u16 fail
    {
        var key       = 0'u32
        var frag_size = 0
        for var bits_read = 0; bits_read < keySize; bits_read += frag_size
        {
            let rpad = (shift[] + bits_read) % 8
            if rpad == 0
            {
                // Update byte.
                if subLen[] == 0
                {
                    subLen[] = .readU8()     // Must be nonzero!
                    if subLen[] == 0 do
                        return 0x1000
                }

                byte[]   = .readU8()
                subLen[] -= 1
            }

            frag_size = Math.min(cast(s32) (keySize - bits_read), cast(s32) (8 - rpad))
            key       |= (cast(u32) byte[] >> rpad) << bits_read
        }

        // Clear extra bits to the left
        key     &= (1'u32 << keySize) - 1
        shift[] = cast(u8) ((shift[] + keySize) % 8)
        return cast(u16) key
    }

    mtd addEntry(length: u16, prefix: u16, suffix: u8)->s32
    {
        if .table.nentries == .table.bulk
        {
            .table.bulk *= 2
            .table.entries.resize(cast(u64) .table.bulk)
        }

        .table.entries[.table.nentries] = {length, prefix, suffix}
        .table.nentries                 += 1
        if (.table.nentries & (.table.nentries - 1)) == 0 do
            return 1
        return 0
    }

    func interlacedLineIndex(h0, y0: s32)->s32
    {
        let h = h0
        var y = y0
        var p = (h - 1) / 8 + 1
        if y < p do
            return y * 8
        y -= p
        p = (h - 5) / 8 + 1
        if y < p do
            return y * 8 + 4
        y -= p
        p = (h - 3) / 4 + 1
        if y < p do
            return y * 4 + 2
        y -= p

        // pass 4
        return y * 2 + 1
    }

    mtd readImageData(interlace: u8) fail
    {
        var byte    = .readU8()
        var keySize = cast(s32) byte
        if keySize < 2 or keySize > 8 do
            fail InvalidFormatError{"invalid frame"}

        let start       = cast(u64) (.stream - .streamStart)
        let remainStart = .streamLen
        .discardSubBlocks()
        let end       = cast(u64) (.stream - .streamStart)
        let remainEnd = .streamLen
        .stream    = .streamStart + start
        .streamLen = remainStart

        let clear = 1 << keySize
        let stop  = clear + 1
        .initTable(keySize)
        keySize += 1
        let initKeySize   = keySize
        var subLen, shift = 0'u8
        var key           = .getKey(keySize, &subLen, &shift, &byte)     // clear code
        var frmOff        = 0
        var ret           = 0
        let frmSize       = cast(u32) .fw * .fh
        var tableIsFull   = 0
        var strLen        = 0'u16

        var entry: Entry
        while frmOff < frmSize
        {
            if key == clear
            {
                keySize         = initKeySize
                .table.nentries = (1 << (keySize - 1)) + 2
                tableIsFull     = 0
            }
            elif !tableIsFull
            {
                ret = .addEntry(cast(u16) (strLen + 1), key, entry.suffix)
                if .table.nentries == 0x1000
                {
                    ret         = 0
                    tableIsFull = 1
                }
            }

            key = .getKey(keySize, &subLen, &shift, &byte)
            if key == clear do
                continue
            if key == stop or key == 0x1000 do
                break
            if ret == 1 do
                keySize += 1
            entry  = .table.entries.buffer![key]
            strLen = entry.length
            for i in strLen
            {
                let p = frmOff + entry.length - 1
                let x = p % .fw
                var y = p / .fw
                if interlace do
                    y = interlacedLineIndex(cast(s32) .fh, y)
                .frame[(.fy + y) * .width + .fx + x] = entry.suffix
                if entry.prefix == 0xFFF do
                    break
                entry = .table.entries.buffer![entry.prefix]
            }

            frmOff += strLen
            if key < .table.nentries - 1 and !tableIsFull do
                .table.entries[.table.nentries - 1].suffix = entry.suffix
        }

        if key == stop do
            subLen = .readU8()     // Must be zero!
        .stream    = .streamStart + end
        .streamLen = remainEnd
    }
}
