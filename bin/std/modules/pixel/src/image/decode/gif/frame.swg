//! Format: Graphics Interchange Format (GIF87a/GIF89a) decoder component.
//! Supported: Global/local palettes, transparency, interlacing, disposal, timing, loops, and sequential animation frames.
//! Not supported: Unknown extension labels and malformed or truncated sub-block streams.
//! Role: This file reads image descriptors, palettes, and bounded frame payloads.
//
// @LICENCE: LicenseRef-Public-Domain
// @ORIGIN: gifdec, https://github.com/lecram/gifdec
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#gifdec

#global namespace Gif

using Swag, Core, Core.Errors

impl Decoder
{
    func interlacedLineIndex(height, encodedRow: s32)->s32
    {
        var row      = encodedRow
        var passRows = (height - 1) / 8 + 1
        if row < passRows do
            return row * 8
        row -= passRows

        passRows = height > 4 ? (height - 5) / 8 + 1 : 0
        if row < passRows do
            return row * 8 + 4
        row -= passRows

        passRows = height > 2 ? (height - 3) / 4 + 1 : 0
        if row < passRows do
            return row * 4 + 2
        row -= passRows

        return row * 2 + 1
    }

    mtd readImage()->IndexedFrame fail
    {
        var result: #returntype
        result.x = try .readU16()
        result.y = try .readU16()
        if result.x >= .width or result.y >= .height do
            fail InvalidFormatError{"invalid frame size"}

        result.width  = try .readU16()
        result.height = try .readU16()
        if not result.width or
           not result.height or
           result.width > .width - result.x or
           result.height > .height - result.y do
            fail InvalidFormatError{"GIF frame rectangle lies outside its canvas"}

        let flags = try .readU8()
        result.interlaced = (flags & 0x40) != 0
        result.palette    = .gct
        if flags & 0x80
        {
            result.palette = {size: 1 << ((flags & 0x07) + 1), colors: .stream}
            try .seek(3'u64 * result.palette.size)
        }

        if not result.palette.size do
            fail InvalidFormatError{"GIF frame has no color table"}

        result.minKeySize = try .readU8()
        if result.minKeySize < 2 or result.minKeySize > 8 do
            fail InvalidFormatError{"GIF LZW code size is invalid"}

        result.data = .stream
        let remaining = .streamLen
        try .discardSubBlocks()

        // Longer dictionary strings favor copying already decoded prefixes.
        result.copyLzwPrefixes = remaining - .streamLen <= cast(u64, result.width) * result.height * 3 / 16

        result.control = .gce
        return result
    }

    mtd getFrame(indexed: *IndexedFrame)->bool fail
    {
        .gce = {}
        var sep = try .readU8()
        while sep != ','
        {
            if sep == ';' do
                return false
            if sep != '!' do
                fail InvalidFormatError{"invalid format"}
            try .readExt()
            sep = try .readU8()
        }

        indexed[] = try .readImage()
        return true
    }
}
