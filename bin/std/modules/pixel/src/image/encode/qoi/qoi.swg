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
    result.addNative(cast(u8, (value >> 24)))
    result.addNative(cast(u8, (value >> 16)))
    result.addNative(cast(u8, (value >> 8)))
    result.addNative(cast(u8, value))
}

#[Swag.Inline]
private func(CHANNELS: u64, SWAP: bool) readPixel(source: const [*] u8)->u32
{
    var pixel: u32
    #static if CHANNELS == 4 do
        pixel = cast(const *u32, source)[]
    else do
        pixel = cast(u32, cast(const *u16, source)[]) | (cast(u32, source[2]) << 16) | 0xFF00_0000'u32

    #static if SWAP do
        pixel = (pixel & 0xFF00_FF00) | ((pixel & 255) << 16) | ((pixel >> 16) & 255)
    return pixel
}

#[Swag.Inline]
private func writePixelChunk(target: [*] u8, pixel, previous: u32, index: *[64] u32)->u64
{
    let indexPosition = hashWord(pixel)
    if index[][indexPosition] == pixel
    {
        target[0] = indexPosition
        return 1
    }

    index[][indexPosition] = pixel
    if (pixel ^ previous) < 0x0100_0000'u32
    {
        let dr = cast(s32, (pixel & 255)) - cast(s32, (previous & 255))
        let dg = cast(s32, ((pixel >> 8) & 255)) - cast(s32, ((previous >> 8) & 255))
        let db = cast(s32, ((pixel >> 16) & 255)) - cast(s32, ((previous >> 16) & 255))
        if dr >= -2 and dr <= 1 and dg >= -2 and dg <= 1 and db >= -2 and db <= 1
        {
            target[0] = cast(u8, (0x40 | ((dr + 2) << 4) | ((dg + 2) << 2) | (db + 2)))
            return 1
        }

        let drdg = dr - dg
        let dbdg = db - dg
        if dg >= -32 and dg <= 31 and drdg >= -8 and drdg <= 7 and dbdg >= -8 and dbdg <= 7
        {
            target[0] = cast(u8, (0x80 | (dg + 32)))
            target[1] = cast(u8, ((drdg + 8) << 4 | (dbdg + 8)))
            return 2
        }

        result.addNative(0xFE_u8)
        result.addNative(pixel.r)
        result.addNative(pixel.g)
        result.addNative(pixel.b)
        return
    }

    result.addNative(0xFF_u8)
    result.addNative(pixel.r)
    result.addNative(pixel.g)
    result.addNative(pixel.b)
    result.addNative(pixel.a)
}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"QOI - Quite OK Image", ".qoi"}

    mtd impl encode(result: *ConcatBuffer, image: Image, _: any?) fail
    {
        if not image.isValid()
        {
            fail InvalidFormatError{"invalid image"}
        }

        if image.pixelFormat != .RGB8 and
           image.pixelFormat != .BGR8 and
           image.pixelFormat != .RGBA8 and
           image.pixelFormat != .BGRA8
        {
            fail UnsupportedFormatError{"QOI encoding requires an 8-bit RGB or RGBA image"}
        }

        // Small files fit in one bucket even if every pixel needs a literal chunk.
        let pixelCount = cast(u64, image.width) * image.height
        let maxBytes   = HeaderSize + EndMarkerSize + image.byteCount + pixelCount
        result.setBucketSize(Math.min(maxBytes, 32'u64 * 1024))
        result.addBytes(Magic)
        writeU32BigEndian(result, cast(u32, image.width))
        writeU32BigEndian(result, cast(u32, image.height))
        result.addNative(image.pixelFormat.hasAlpha() ? 4_u8 : 3_u8)
        result.addNative(0_u8)

        switch image.pixelFormat
        {
        case .RGB8:  writeChunks'(3, false)(result, &image)
        case .BGR8:  writeChunks'(3, true)(result, &image)
        case .RGBA8: writeChunks'(4, false)(result, &image)
        case .BGRA8: writeChunks'(4, true)(result, &image)
        default:     unreachable
        }

        const EndMarker: [8] u8 = [0, 0, 0, 0, 0, 0, 0, 1]
        result.addBytes(EndMarker)
    }
}
