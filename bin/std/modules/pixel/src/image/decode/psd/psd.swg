//! Format: Adobe Photoshop document decoder.
//! Supported: Flattened PSD version 1 composite images in RGB or grayscale, at 8 or 16 bits,
//!            with raw or PackBits channel data and an optional alpha channel.
//! Not supported: PSB, indexed/CMYK/Lab color, layer extraction, spot channels, or ZIP composites.
//! Role: This file imports the flattened composite that image viewers conventionally display.
//
#global namespace Psd

using Core, Core.Errors

const HeaderSize = 26'u64

internal struct Decoder {}

#[Swag.Inline]
func readU16(source: const [*] u8)->u16
{
    return (cast(u16) source[0] << 8) | source[1]
}

#[Swag.Inline]
func readU32(source: const [*] u8)->u32
{
    return (cast(u32) source[0] << 24) |
           (cast(u32) source[1] << 16) |
           (cast(u32) source[2] << 8) |
           cast(u32) source[3]
}

func skipSection(buffer: const [..] u8, offset: *u64) fail
{
    if offset[] + 4 > buffer.count do
        fail InvalidFormatError{"PSD section length is truncated"}
    let size = cast(u64) readU32(buffer.buffer + offset[])
    offset[] += 4
    if size > buffer.count - offset[] do
        fail InvalidFormatError{"PSD section exceeds the file"}
    offset[] += size
}

func decodePackBits(destination: [*] u8, expected: u64, source: const [..] u8) fail
{
    var input  = 0'u64
    var output = 0'u64
    while input < source.count and output < expected
    {
        let control = cast #bit (s8) source[input]
        input += 1
        if control >= 0
        {
            let count = cast(u64) control + 1
            if count > source.count - input or count > expected - output do
                fail InvalidFormatError{"PSD PackBits literal exceeds its row"}
            Memory.copy(destination + output, source.buffer + input, count)
            input  += count
            output += count
        }
        elif control != -128
        {
            let count = cast(u64) (1 - cast(s32) control)
            if input >= source.count or count > expected - output do
                fail InvalidFormatError{"PSD PackBits run exceeds its row"}
            Memory.set(destination + output, source[input], count)
            input  += 1
            output += count
        }
    }

    if output != expected or input != source.count do
        fail InvalidFormatError{"PSD PackBits row has an invalid decoded length"}
}

func storeChannel(image: *Image, channel: u16, sourceY: s32, source: const [..] u8, depth: u16)
{
    let alphaChannel = image.pixelFormat.isGrayscale() ? 1'u16 : 3'u16
    if channel >= image.pixelFormat.channels() or channel > alphaChannel do
        return

    let targetY = image.height - sourceY - 1
    var target  = image.pixels.buffer! + cast(u64) targetY * image.rowStride
    if depth == 8
    {
        for x in image.width
        {
            target[channel] = source[x]
            target          += image.bytesPerPixel
        }
    }
    else
    {
        for x in image.width
        {
            let sourceOffset = cast(u64) x * 2
            let sample       = (cast(u16) source[sourceOffset] << 8) | cast(u16) source[sourceOffset + 1]
            (target + cast(u64) channel * 2)[as u16] = sample
            target += image.bytesPerPixel
        }
    }
}

internal impl IImageDecoder for Decoder
{
    mtd impl format()->ImageFormat => {"PSD - Adobe Photoshop Document", ".psd"}

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        if buffer.count < HeaderSize do
            fail InvalidFormatError{"PSD header is truncated"}
        let source = buffer.buffer
        if source[0] != '8' or source[1] != 'B' or source[2] != 'P' or source[3] != 'S' do
            fail InvalidFormatError{"PSD signature is invalid"}
        if readU16(source + 4) != 1 do
            fail UnsupportedFormatError{"only PSD version 1 files are supported"}
        for i in 6 where source[6 + i] do
            fail InvalidFormatError{"PSD reserved header bytes must be zero"}

        let channels  = readU16(source + 12)
        let height    = readU32(source + 14)
        let width     = readU32(source + 18)
        let depth     = readU16(source + 22)
        let colorMode = readU16(source + 24)
        if width == 0 or height == 0 or width > cast(u32) Swag.S32.Max or height > cast(u32) Swag.S32.Max do
            fail UnsupportedFormatError{"PSD dimensions exceed the image limits"}
        if depth != 8 and depth != 16 do
            fail UnsupportedFormatError{"PSD composite depth must be 8 or 16 bits"}

        var format: PixelFormat
        switch colorMode
        {
        case 1:
            if channels < 1 do
                fail InvalidFormatError{"grayscale PSD data has no channel"}
            if depth == 8 do
                format = channels >= 2 ? .GrayAlpha8 : .Gray8
            else do
                format = channels >= 2 ? .GrayAlpha16 : .Gray16

        case 3:
            if channels < 3 do
                fail InvalidFormatError{"RGB PSD data has fewer than three channels"}
            if depth == 8 do
                format = channels >= 4 ? .RGBA8 : .RGB8
            else do
                format = channels >= 4 ? .RGBA16 : .RGB16

        default:
            fail UnsupportedFormatError{"PSD color mode is not RGB or grayscale"}
        }

        var result: retval
        result.init(cast(s32) width, cast(s32) height, format)
        if !options.decodePixels do
            return result

        var offset = HeaderSize
        try skipSection(buffer, &offset)     // Color-mode data.
        try skipSection(buffer, &offset)     // Image resources.
        try skipSection(buffer, &offset)     // Layer and mask information.
        if offset + 2 > buffer.count do
            fail InvalidFormatError{"PSD composite compression is missing"}
        let compression = readU16(source + offset)
        offset += 2
        if compression > 1 do
            fail UnsupportedFormatError{"PSD composite compression must be raw or PackBits"}

        let rowBytes = cast(u64) width * (depth / 8)
        if rowBytes > Swag.U32.Max or cast(u64) channels * height > Swag.U64.Max / rowBytes do
            fail UnsupportedFormatError{"PSD composite is too large"}
        result.allocPixels()
        result.clear()

        var rowLengths: Array'u16
        if compression == 1
        {
            let rowCount = cast(u64) channels * height
            if rowCount > (buffer.count - offset) / 2 do
                fail InvalidFormatError{"PSD PackBits row table is truncated"}
            rowLengths.resize(rowCount)
            for i in rowCount
            {
                rowLengths[i] = readU16(source + offset)
                offset        += 2
            }
        }

        var row: Array'u8
        row.resize(rowBytes)
        for channel in channels
        {
            for y in cast(s32) height
            {
                if compression == 0
                {
                    if rowBytes > buffer.count - offset do
                        fail InvalidFormatError{"PSD raw composite is truncated"}
                    Memory.copy(row.buffer, source + offset, rowBytes)
                    offset += rowBytes
                }
                else
                {
                    let encodedSize = cast(u64) rowLengths[cast(u64) channel * height + cast(u64) y]
                    if encodedSize > buffer.count - offset do
                        fail InvalidFormatError{"PSD PackBits row is truncated"}
                    try decodePackBits(row.buffer!, rowBytes, Swag.makeSlice(source + offset, encodedSize))
                    offset += encodedSize
                }

                storeChannel(&result, channel, y, row.toSlice(), depth)
            }
        }

        return result
    }
}
