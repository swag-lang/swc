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

        cast(*u32, target)[] = (pixel << 8) | 0xFE
        return 4
    }

    target[0] = 0xFF
    cast(*u32, target + 1)[] = pixel
    return 5
}

private func(CHANNELS: u64, SWAP: bool) writeChunks(result: *ConcatBuffer, image: const *Image)
{
    const BatchSize = 4096

    // A pending run plus an RGBA chunk can extend past the flush point by six bytes.
    var batch: [BatchSize + 6] u8
    let bytes    = batch.buffer
    let width    = cast(u64, image.width)
    let height   = cast(u64, image.height)
    let pixels   = image.pixels.storage()
    var previous = 0xFF00_0000'u32
    var index: [64] u32
    var run:   u8
    var used:  u64
    for y in height
    {
        var source = pixels + (height - y - 1) * image.rowStride
        for width
        {
            if used >= BatchSize
            {
                result.addBytes(Swag.makeSlice(bytes, used))
                used = 0
            }

            let pixel = readPixel'(CHANNELS, SWAP)(source)
            source += CHANNELS
            if pixel == previous
            {
                run += 1
                if run == 62
                {
                    bytes[used] = 0xC0 | (run - 1)
                    used        += 1
                    run         = 0
                }

                continue
            }

            if run
            {
                bytes[used] = 0xC0 | (run - 1)
                used        += 1
                run         = 0
            }

            used     += writePixelChunk(bytes + used, pixel, previous, &index)
            previous = pixel
        }
    }

    if run
    {
        bytes[used] = 0xC0 | (run - 1)
        used        += 1
    }

    if used do
        result.addBytes(Swag.makeSlice(bytes, used))
}

internal impl IImageEncoder for Encoder
{
    mtd impl format()->ImageFormat => {"QOI - Quite OK Image", ".qoi"}

    mtd impl encode(result: *ConcatBuffer, image: Image, _: any?) fail
    {
        if not image.isValid() do
            fail InvalidFormatError{"invalid image"}
        if image.pixelFormat != .RGB8 and
           image.pixelFormat != .BGR8 and
           image.pixelFormat != .RGBA8 and
           image.pixelFormat != .BGRA8 do
            fail UnsupportedFormatError{"QOI encoding requires an 8-bit RGB or RGBA image"}

        result.addBytes(Magic)
        writeU32BigEndian(result, cast(u32, image.width))
        writeU32BigEndian(result, cast(u32, image.height))
        result.addNative(image.pixelFormat.hasAlpha() ? 4'u8 : 3'u8)
        result.addNative(0'u8)

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
