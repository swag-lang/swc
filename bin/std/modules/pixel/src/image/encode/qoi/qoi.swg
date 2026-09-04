//! Format: Quite OK Image encoder.
//! Supported: QOI output from RGB8, BGR8, RGBA8, and BGRA8 images.
//! Not supported: Alternate channel depths or embedded metadata.
//! Role: This file owns QOI chunk selection and serialization.
//
#global namespace Qoi

using Core, Core.Errors

// Encodes 8-bit packed images as QOI.
internal struct Encoder {}

#[Swag.Inline]
func writeU32BigEndian(result: *ConcatBuffer, value: u32)
{
    result.addNative(cast(u8) (value >> 24))
    result.addNative(cast(u8) (value >> 16))
    result.addNative(cast(u8) (value >> 8))
    result.addNative(cast(u8) value)
}

#[Swag.Inline]
func readPixel(image: Image, source: const [*] u8)->Pixel
{
    switch image.pixelFormat
    {
    case .RGB8:  return {source[0], source[1], source[2], 255}
    case .RGBA8: return {source[0], source[1], source[2], source[3]}
    case .BGR8:  return {source[2], source[1], source[0], 255}
    case .BGRA8: return {source[2], source[1], source[0], source[3]}
    }

    return {}
}

#[Swag.Inline]
func pixelsEqual(left, right: Pixel)->bool
{
    return left.r == right.r and left.g == right.g and left.b == right.b and left.a == right.a
}

func writePixelChunk(result: *ConcatBuffer, pixel, previous: Pixel, index: *[64] Pixel)
{
    let indexPosition = hash(pixel)
    if pixelsEqual(index[][indexPosition], pixel)
    {
        result.addNative(indexPosition)
        return
    }

    index[][indexPosition] = pixel
    if pixel.a == previous.a
    {
        let dr = cast(s32) pixel.r - previous.r
        let dg = cast(s32) pixel.g - previous.g
        let db = cast(s32) pixel.b - previous.b
        if dr >= -2 and dr <= 1 and dg >= -2 and dg <= 1 and db >= -2 and db <= 1
        {
            result.addNative(cast(u8) (0x40 | ((dr + 2) << 4) | ((dg + 2) << 2) | (db + 2)))
            return
        }

        let drdg = dr - dg
        let dbdg = db - dg
        if dg >= -32 and dg <= 31 and drdg >= -8 and drdg <= 7 and dbdg >= -8 and dbdg <= 7
        {
            result.addNative(cast(u8) (0x80 | (dg + 32)))
            result.addNative(cast(u8) ((drdg + 8) << 4 | (dbdg + 8)))
            return
        }

        result.addNative(0xFE'u8)
        result.addNative(pixel.r)
        result.addNative(pixel.g)
        result.addNative(pixel.b)
        return
    }

    result.addNative(0xFF'u8)
    result.addNative(pixel.r)
    result.addNative(pixel.g)
    result.addNative(pixel.b)
    result.addNative(pixel.a)
}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"QOI - Quite OK Image", ".qoi"}

    mtd impl encode(result: *ConcatBuffer, image: Image, options: any?) fail
    {
        discard options
        if image.width <= 0 or image.height <= 0 or !image.pixels.buffer do
            fail InvalidFormatError{"invalid image"}
        if image.pixelFormat != .RGB8 and image.pixelFormat != .BGR8 and image.pixelFormat != .RGBA8 and image.pixelFormat != .BGRA8 do
            fail UnsupportedFormatError{"QOI encoding requires an 8-bit RGB or RGBA image"}

        result.addBytes(Magic)
        writeU32BigEndian(result, cast(u32) image.width)
        writeU32BigEndian(result, cast(u32) image.height)
        result.addNative(image.pixelFormat.hasAlpha() ? 4'u8 : 3'u8)
        result.addNative(0'u8)

        var index: [64] Pixel
        var previous   = Pixel{0, 0, 0, 255}
        var run:   u8
        let pixelCount = cast(u64) image.width * cast(u64) image.height
        for sourceIndex in pixelCount
        {
            let sourceY  = cast(s32) (sourceIndex / cast(u64) image.width)
            let sourceX  = cast(s32) (sourceIndex % cast(u64) image.width)
            let storageY = image.height - sourceY - 1
            let source   = image.pixels.buffer! + cast(u64) storageY * image.rowStride + cast(u64) sourceX * image.bytesPerPixel
            let pixel    = readPixel(image, source)
            if pixelsEqual(pixel, previous)
            {
                run += 1
                if run == 62 or sourceIndex + 1 == pixelCount
                {
                    result.addNative(cast(u8) (0xC0 | (run - 1)))
                    run = 0
                }

                continue
            }

            if run
            {
                result.addNative(cast(u8) (0xC0 | (run - 1)))
                run = 0
            }

            writePixelChunk(result, pixel, previous, &index)
            previous = pixel
        }

        const EndMarker: [8] u8 = [0, 0, 0, 0, 0, 0, 0, 1]
        result.addBytes(EndMarker)
    }
}
