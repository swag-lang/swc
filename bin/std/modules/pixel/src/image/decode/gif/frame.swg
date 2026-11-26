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

    mtd readImage(decodePixels = true) fail
    {
        .descriptorOffset    = cast(u64, (.stream - .streamStart))
        .descriptorRemaining = .streamLen

        // Image descriptor
        .fx = try .readU16()
        .fy = try .readU16()
        if .fx >= .width or .fy >= .height do
            fail InvalidFormatError{"invalid frame size"}

        .fw = try .readU16()
        .fh = try .readU16()
        if not .fw or not .fh or .fw > .width - .fx or .fh > .height - .fy do
            fail InvalidFormatError{"GIF frame rectangle lies outside its canvas"}

        let fisrz = try .readU8()
        .interlaced = (fisrz & 0x40) != 0

        // Ignore Sort Flag
        // Local Color Table?
        if fisrz & 0x80
        {
            /* Read LCT */
            .lct.size = 1 << ((fisrz & 0x07) + 1)
            try .read(.lct.colors, 3'u64 * .lct.size)
            .palette = &.lct
        }
        else
        {
            .palette = &.gct
        }

        if not .palette.size do
            fail InvalidFormatError{"GIF frame has no color table"}
        if decodePixels
        {
            try .readImageData()
        }
        else
        {
            let codeSize = try .readU8()
            if codeSize < 2 or codeSize > 8 do
                fail InvalidFormatError{"GIF LZW code size is invalid"}
            try .discardSubBlocks()
        }
    }

    mtd getFrame(decodePixels: bool)->s32 fail
    {
        .gce = {}
        var sep = try .readU8()
        while sep != ','
        {
            if sep == ';' do
                return 0
            if sep != '!' do
                fail InvalidFormatError{"invalid format"}
            try .readExt()
            sep = try .readU8()
        }

        try .readImage(decodePixels)
        return 1
    }
}
