//! Format: Quite OK Image decoder.
//! Supported: QOI RGB and RGBA images in either declared color space.
//! Not supported: Concatenated images or bytes after the required end marker.
//! Role: This file owns QOI header validation and chunk reconstruction.
//
#global namespace Qoi

using Core, Core.Errors

const Magic: [4] u8 = ['q', 'o', 'i', 'f']
const HeaderSize    = 14'u64
const EndMarkerSize = 8'u64

struct Pixel
{
    r: u8
    g: u8
    b: u8
    a: u8
}

// Decodes QOI images into RGB8 or RGBA8 storage.
internal struct Decoder {}

#[Swag.Inline]
func readU32BigEndian(source: const [*] u8)->u32
{
    return (cast(u32) source[0] << 24) |
           (cast(u32) source[1] << 16) |
           (cast(u32) source[2] << 8) |
           cast(u32) source[3]
}

#[Swag.Inline]
func hash(pixel: Pixel)->u8
{
    return cast(u8) ((cast(u32) pixel.r * 3 + cast(u32) pixel.g * 5 + cast(u32) pixel.b * 7 + cast(u32) pixel.a * 11) & 63)
}

#[Swag.Inline]
func addWrapped(value: u8, delta: s32)->u8
{
    return cast(u8) ((cast(s32) value + delta) & 0xFF)
}

#[Swag.Inline]
func writePixel(image: *Image, sourceIndex: u64, pixel: Pixel)
{
    let sourceY = cast(s32) (sourceIndex / cast(u64) image.width)
    let sourceX = cast(s32) (sourceIndex % cast(u64) image.width)
    let targetY = image.height - sourceY - 1
    let target  = image.pixels.buffer! + cast(u64) targetY * image.rowStride + cast(u64) sourceX * image.bytesPerPixel
    target[0] = pixel.r
    target[1] = pixel.g
    target[2] = pixel.b
    if image.bytesPerPixel == 4 do
        target[3] = pixel.a
}

internal impl IImageDecoder for Decoder
{
    mtd impl format()->ImageFormat => {"QOI - Quite OK Image", ".qoi"}

    mtd impl decode(buffer: const [..] u8, options: DecodeOptions)->Image fail
    {
        if buffer.count < HeaderSize + EndMarkerSize do
            fail InvalidFormatError{"QOI data is shorter than its header and end marker"}

        let source = buffer.buffer
        for i in 4 where source[i] != Magic[i] do
            fail InvalidFormatError{"QOI signature is invalid"}

        let width      = readU32BigEndian(source + 4)
        let height     = readU32BigEndian(source + 8)
        let channels   = source[12]
        let colorSpace = source[13]
        if width == 0 or height == 0 do
            fail InvalidFormatError{"QOI dimensions must be positive"}
        if width > cast(u32) Swag.S32.Max or height > cast(u32) Swag.S32.Max do
            fail UnsupportedFormatError{"QOI dimensions exceed the image limits"}
        if channels != 3 and channels != 4 do
            fail InvalidFormatError{"QOI channel count must be 3 or 4"}
        if colorSpace > 1 do
            fail InvalidFormatError{"QOI color-space value must be 0 or 1"}
        if cast(u64) width * cast(u64) height > Swag.U64.Max / channels do
            fail UnsupportedFormatError{"QOI image is too large"}

        var result: retval
        result.init(cast(s32) width, cast(s32) height, channels == 4 ? .RGBA8 : .RGB8)
        if !options.decodePixels do
            return result

        result.allocPixels()
        var index: [64] Pixel
        var previous   = Pixel{0, 0, 0, 255}
        var input      = HeaderSize
        var output     = 0'u64
        let pixelCount = cast(u64) width * cast(u64) height
        let chunkLimit = buffer.count - EndMarkerSize

        while output < pixelCount
        {
            if input >= chunkLimit do
                fail InvalidFormatError{"QOI data ends before every pixel is decoded"}

            let tag = source[input]
            input += 1
            if tag == 0xFE
            {
                if input + 3 > chunkLimit do
                    fail InvalidFormatError{"QOI RGB chunk is truncated"}
                previous.r = source[input]
                previous.g = source[input + 1]
                previous.b = source[input + 2]
                input      += 3
            }
            elif tag == 0xFF
            {
                if input + 4 > chunkLimit do
                    fail InvalidFormatError{"QOI RGBA chunk is truncated"}
                previous.r = source[input]
                previous.g = source[input + 1]
                previous.b = source[input + 2]
                previous.a = source[input + 3]
                input      += 4
            }
            else
            {
                switch tag & 0xC0
                {
                case 0x00:
                    previous = index[tag & 63]

                case 0x40:
                    previous.r = addWrapped(previous.r, cast(s32) ((tag >> 4) & 3) - 2)
                    previous.g = addWrapped(previous.g, cast(s32) ((tag >> 2) & 3) - 2)
                    previous.b = addWrapped(previous.b, cast(s32) (tag & 3) - 2)

                case 0x80:
                    if input >= chunkLimit do
                        fail InvalidFormatError{"QOI luma chunk is truncated"}
                    let next = source[input]
                    input += 1
                    let greenDelta = cast(s32) (tag & 63) - 32
                    previous.r = addWrapped(previous.r, greenDelta + cast(s32) ((next >> 4) & 15) - 8)
                    previous.g = addWrapped(previous.g, greenDelta)
                    previous.b = addWrapped(previous.b, greenDelta + cast(s32) (next & 15) - 8)

                case 0xC0:
                    let run = cast(u64) (tag & 63) + 1
                    if run > pixelCount - output do
                        fail InvalidFormatError{"QOI run exceeds the image dimensions"}
                    for run
                    {
                        writePixel(&result, output, previous)
                        output += 1
                    }

                    continue
                }
            }

            index[hash(previous)] = previous
            writePixel(&result, output, previous)
            output += 1
        }

        let expectedEnd: [8] u8 = [0, 0, 0, 0, 0, 0, 0, 1]
        if input + EndMarkerSize != buffer.count do
            fail InvalidFormatError{"QOI data has bytes after the image payload"}
        for i in EndMarkerSize where source[input + i] != expectedEnd[i] do
            fail InvalidFormatError{"QOI end marker is invalid"}
        return result
    }
}
