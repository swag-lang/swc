//! Format: Graphics Interchange Format (GIF87a/GIF89a) decoder component.
//! Supported: Global/local palettes, transparency, interlacing, disposal, timing, loops, and sequential animation frames.
//! Not supported: Unknown extension labels and malformed or truncated sub-block streams.
//! Role: This file owns bounded byte reads and GIF extension parsing.
//
// @LICENCE: LicenseRef-Public-Domain
// @ORIGIN: gifdec, https://github.com/lecram/gifdec
// @MODIFIED: Ported and modified for Swag.
// @NOTICE: /bin/THIRDPARTY.md#gifdec

#global namespace Gif

using Swag, Core, Core.Errors

impl Decoder
{
    mtd seek(len: u64) fail
    {
        if len > .streamLen do
            fail InvalidFormatError{"read error"}
        .stream    += len
        .streamLen -= len
    }

    mtd read(dest: *u8, len: u64) fail
    {
        if len > .streamLen do
            fail InvalidFormatError{"read error"}
        Memory.copy(dest, .safeStream(), len)
        .stream    += len
        .streamLen -= len
    }

    #[Swag.Inline]
    mtd readU8()->u8 fail
    {
        if .streamLen < 1 do
            fail InvalidFormatError{"read error"}
        let res = .safeStream()[0]
        .stream    += 1
        .streamLen -= 1
        return res
    }

    mtd readU16()->u16 fail
    {
        if .streamLen < 2 do
            fail InvalidFormatError{"read error"}
        let stream = .safeStream()
        let res    = cast(u16) (stream[0] + (cast(u16) stream[1] << 8))
        .stream    += 2
        .streamLen -= 2
        return res
    }

    mtd discardSubBlocks() fail
    {
        for
        {
            let size = try .readU8()
            if not size do
                break
            try .seek(cast() size)
        }
    }

    mtd readPlainTextExt() fail
    {
        // Discard plain text metadata.
        try .seek(13)

        // Discard plain text sub-blocks.
        try .discardSubBlocks()
    }

    mtd readGraphicControlExt() fail
    {
        // Discard block size (always 0x04)
        try .seek(1)
        let rdit = try .readU8()
        .gce.disposal     = (rdit >> 2) & 3
        .gce.input        = rdit & 2
        .gce.transparency = rdit & 1
        .gce.delay        = try .readU16()
        .gce.tindex       = try .readU8()

        // Skip block terminator
        try .seek(1)
    }

    mtd readCommentExt() fail
    {
        try .discardSubBlocks()
    }

    mtd readApplicationExt() fail
    {
        var app_id:        [8] u8
        var app_auth_code: [3] u8

        // Discard block size (always 0x0B)
        try .seek(1)

        // Application Identifier
        try .read(app_id, 8)

        // Application Authentication Code
        try .read(app_auth_code, 3)

        if not Memory.compare(app_id, ("NETSCAPE").buffer, app_id.count)
        {
            // Discard block size (0x03) and constant byte (0x01).
            try .seek(2)
            .loopCount        = try .readU16()
            .hasLoopExtension = true

            // Skip block terminator.
            try .seek(1)
        }
        else
        {
            try .discardSubBlocks()
        }
    }

    mtd readExt() fail
    {
        let label = try .readU8()
        switch label
        {
        case 0x01: try .readPlainTextExt()
        case 0xF9: try .readGraphicControlExt()
        case 0xFE: try .readCommentExt()
        case 0xFF: try .readApplicationExt()
        default:   fail UnsupportedFormatError{Errors.mkString(Format.toString("unknown extension: %", label))}
        }
    }
}
