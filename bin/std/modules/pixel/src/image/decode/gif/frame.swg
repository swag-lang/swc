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
    mtd readImage(decodePixels = true) fail
    {
        .descriptorOffset    = cast(u64) (.stream - .streamStart)
        .descriptorRemaining = .streamLen

        // Image descriptor
        .fx = .readU16()
        .fy = .readU16()
        if .fx >= .width or .fy >= .height do
            fail InvalidFormatError{"invalid frame size"}

        .fw = .readU16()
        .fh = .readU16()
        if !.fw or !.fh or .fw > .width - .fx or .fh > .height - .fy do
            fail InvalidFormatError{"GIF frame rectangle lies outside its canvas"}

        let fisrz     = .readU8()
        let interlace = fisrz & 0x40

        // Ignore Sort Flag
        // Local Color Table?
        if fisrz & 0x80
        {
            /* Read LCT */
            .lct.size = 1 << ((fisrz & 0x07) + 1)
            .read(.lct.colors, 3'u64 * .lct.size)
            .palette = &.lct
        }
        else do
            .palette = &.gct

        if !.palette!.size do
            fail InvalidFormatError{"GIF frame has no color table"}
        if decodePixels do
            .readImageData(interlace)
        else
        {
            let codeSize = .readU8()
            if codeSize < 2 or codeSize > 8 do
                fail InvalidFormatError{"GIF LZW code size is invalid"}
            .discardSubBlocks()
        }
    }

    mtd getFrame(decodePixels: bool)->s32 fail
    {
        .gce = {}
        var sep = .readU8()
        while sep != ','
        {
            if sep == ';' do
                return 0
            if sep != '!' do
                fail InvalidFormatError{"invalid format"}
            .readExt()
            sep = .readU8()
        }

        .readImage(decodePixels)
        return 1
    }
}
