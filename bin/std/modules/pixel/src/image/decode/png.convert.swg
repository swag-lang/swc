/*
    :LICENCE
    This code is based on the libspng library by Randy (https://libspng.org/)
    The original code has been modified for Swag
    See LICENCE.md for the corresponding licence.
*/

#global namespace Png

using Core, Core.Errors

impl Decoder
{
    mtd convert(result: *Image)
    {
        defer Memory.free(.safeDstPixels(), .dstPixelsSize)

        // Paletted, no transparency
        if .inChannels == 1 and .seenPLTE and !.seenTRSN
        {
            var src = .safeDstPixels()
            var dst = cast([*] u8) (notnull result.pixels.buffer)
            for result.width * result.height
            {
                let pal   = src[0]
                let color = .palette[pal]
                dst[0] = cast() ((color >> 16) & 0xFF)
                dst[1] = cast() ((color >> 8) & 0xFF)
                dst[2] = cast() (color & 0xFF)
                src    += 1
                dst    += result.bpp8
            }
        }

        // Paletted, transparency
        elif .inChannels == 1 and .seenPLTE and .seenTRSN
        {
            var src = .safeDstPixels()
            var dst = cast([*] u8) (notnull result.pixels.buffer)
            for result.width * result.height
            {
                let pal   = src[0]
                let color = .palette[pal]
                dst[0] = cast() ((color >> 16) & 0xFF)
                dst[1] = cast() ((color >> 8) & 0xFF)
                dst[2] = cast() (color & 0xFF)
                dst[3] = pal < @countof(.safeTRNSData()) ? .safeTRNSData()[pal] : 255
                src    += 1
                dst    += result.bpp8
            }
        }

        // Grayscale without alpha channel, no transparency
        elif .inChannels == 1 and !.seenTRSN
        {
            var src = .safeDstPixels()
            var dst = cast([*] u8) (notnull result.pixels.buffer)
            for result.width * result.height
            {
                dst[0] = src[0]
                dst[1] = src[0]
                dst[2] = src[0]
                src    += 1
                dst    += result.bpp8
            }
        }

        // Grayscale without alpha channel, but transparency
        elif .inChannels == 1 and .seenTRSN
        {
            var key   = .safeTRNSData()[1]
            let scale = .header.bitDepth == 1 ? 255'u8 : .header.bitDepth == 2 ? 85'u8 : 17'u8
            key *= scale
            var src = .safeDstPixels()
            var dst = cast([*] u8) (notnull result.pixels.buffer)
            for result.width * result.height
            {
                dst[0] = src[0]
                dst[1] = src[0]
                dst[2] = src[0]
                dst[3] = src[0] == key ? 0 : 255
                src    += 1
                dst    += result.bpp8
            }
        }

        // Grayscale with alpha channel
        elif .inChannels == 2
        {
            var src = .safeDstPixels()
            var dst = cast([*] u8) (notnull result.pixels.buffer)
            for result.width * result.height
            {
                dst[0] = src[0]
                dst[1] = src[0]
                dst[2] = src[0]
                dst[3] = src[1]
                src    += 2
                dst    += result.bpp8
            }
        }

        // Color without alpha but transparency
        elif .inChannels == 3 and .seenTRSN
        {
            let key  = cast(const [*] u8) @dataof(.safeTRNSData())
            let key0 = key[1]
            let key1 = key[3]
            let key2 = key[5]
            var src  = .safeDstPixels()
            var dst  = cast([*] u8) (notnull result.pixels.buffer)
            for result.width * result.height
            {
                dst[0] = src[0]
                dst[1] = src[1]
                dst[2] = src[2]
                if src[0] == key0 and src[1] == key1 and src[2] == key2 do
                    dst[3] = 0
                else do
                    dst[3] = 255
                src        += 3
                dst        += result.bpp8
            }
        }
    }
}
