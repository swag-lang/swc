// :LICENCE
// This code is based on "gifdec" (https://github.com/lecram/gifdec)
// The original code has been modified for Swag

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
            let size = .readU8()
            if !size do
                break
            .seek(cast() size)
        }
    }

    mtd readPlainTextExt() fail
    {
        // Discard plain text metadata.
        .seek(13)

        // Discard plain text sub-blocks.
        .discardSubBlocks()
    }

    mtd readGraphicControlExt() fail
    {
        // Discard block size (always 0x04)
        .seek(1)
        let rdit = .readU8()
        .gce.disposal     = (rdit >> 2) & 3
        .gce.input        = rdit & 2
        .gce.transparency = rdit & 1
        .gce.delay        = .readU16()
        .gce.tindex       = .readU8()

        // Skip block terminator
        .seek(1)
    }

    mtd readCommentExt() fail
    {
        .discardSubBlocks()
    }

    mtd readApplicationExt() fail
    {
        var app_id:        [8] u8
        var app_auth_code: [3] u8

        // Discard block size (always 0x0B)
        .seek(1)

        // Application Identifier
        .read(app_id, 8)

        // Application Authentication Code
        .read(app_auth_code, 3)

        if !Memory.compare(app_id, @dataof("NETSCAPE"), @countof(app_id))
        {
            // Discard block size (0x03) and constant byte (0x01).
            .seek(2)
            .loopCount = .readU16()

            // Skip block terminator.
            .seek(1)
        }
        else
        {
            .discardSubBlocks()
        }
    }

    mtd readExt() fail
    {
        let label = .readU8()
        switch label
        {
        case 0x01: .readPlainTextExt()
        case 0xF9: .readGraphicControlExt()
        case 0xFE: .readCommentExt()
        case 0xFF: .readApplicationExt()
        default:   fail UnsupportedFormatError{Errors.mkString(Format.toString("unknown extension: %", label))}
        }
    }
}

