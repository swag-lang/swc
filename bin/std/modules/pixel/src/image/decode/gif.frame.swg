// :LICENCE
// This code is based on "gifdec" (https://github.com/lecram/gifdec)
// The original code has been modified for Swag

#global namespace Gif

using Swag, Core, Core.Errors

impl Decoder
{
    mtd readImage() fail
    {
        // Image descriptor
        .fx = .readU16()
        .fy = .readU16()
        if .fx >= .width or .fy >= .height do
            fail InvalidFormatError{"invalid frame size"}

        .fw = .readU16()
        .fh = .readU16()
        .fw = Math.min(.fw, cast(u16) (.width - .fx))
        .fh = Math.min(.fh, cast(u16) (.height - .fy))

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

        .readImageData(interlace)
    }

    mtd renderFrame(buffer: [*] u8, pf: PixelFormat)
    {
        let palette = notnull .palette
        var i       = cast(u32) .fy * .width + .fx

        if pf.hasAlpha()
        {
            for #reverse [j] in 0 until .fh
            {
                for [k] in cast(u32) .fw
                {
                    let index = .frame[(.fy + j) * cast(u32) .width + (.fx + k)]
                    let color = cast([*] u8) &palette.colors[index * 3'u32]
                    let b     = buffer + (i + k) * 4
                    b[0] = color[0]
                    b[1] = color[1]
                    b[2] = color[2]
                    b[3] = index == .gce.tindex ? 0'u8 : 0xFF'u8
                }

                i += .width
            }
        }
        else
        {
            for #reverse [j] in 0 until .fh
            {
                for [k] in .fw
                {
                    let index = .frame[(.fy + j) * .width + (.fx + k)]
                    let color = cast([*] u8) &palette.colors[index * 3'u32]
                    let b     = buffer + (i + k) * 3
                    b[0] = color[0]
                    b[1] = color[1]
                    b[2] = color[2]
                }

                i += .width
            }
        }
    }

    mtd getFrame(decodePixels: bool)->s32 fail
    {
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

        if decodePixels do
            .readImage()
        return 1
    }
}
