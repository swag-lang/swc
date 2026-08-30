#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// QOI is registered for loading and saving and is therefore offered by image consumers.
#test
{
    Swag.assert(Image.canLoad("sample.qoi"))
    Swag.assert(Image.canSave("sample.qoi"))
}

// Decode every QOI chunk family and map the file's top-down rows to Image storage.
#test
{
    const Bytes: [35] u8 = [
        'q', 'o', 'i', 'f',
        0, 0, 0, 3,
        0, 0, 0, 2,
        4, 0,
        0xFE, 10, 20, 30,
        0x76,
        0xA5, 0x79,
        0xFF, 1, 2, 3, 4,
        0xC1,
        0, 0, 0, 0, 0, 0, 0, 1]

    let image = expect Image.decode("chunks.qoi", Bytes, {})
    Swag.assert(image.width == 3 and image.height == 2)
    Swag.assert(image.pixelFormat == .RGBA8)

    let expected: [24] u8 = [1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
                             10, 20, 30, 255, 11, 19, 30, 255, 15, 24, 36, 255]
    Swag.assert(Memory.compare(image.pixels.buffer, expected.buffer, expected.count) == 0)
}

// Round-trip every existing packed channel order without changing logical colors.
#test
{
    for pixelFormat in [PixelFormat.RGB8, PixelFormat.BGR8, PixelFormat.RGBA8, PixelFormat.BGRA8]
    {
        var source = Image.create(19, 7, pixelFormat)
        for y in source.height
        {
            for x in source.width
            {
                let offset = cast(u64) y * source.rowStride + cast(u64) x * source.bytesPerPixel
                let pixel  = source.pixels.buffer! + offset
                if pixelFormat == .RGB8 or pixelFormat == .RGBA8
                {
                    pixel[0] = cast(u8) ((x * 13 + y * 3) & 0xFF)
                    pixel[1] = cast(u8) ((x * 5 + y * 17) & 0xFF)
                    pixel[2] = cast(u8) ((x * 7 + y * 11) & 0xFF)
                }
                else
                {
                    pixel[0] = cast(u8) ((x * 7 + y * 11) & 0xFF)
                    pixel[1] = cast(u8) ((x * 5 + y * 17) & 0xFF)
                    pixel[2] = cast(u8) ((x * 13 + y * 3) & 0xFF)
                }

                if source.bytesPerPixel == 4 do
                    pixel[3] = cast(u8) ((x * 9 + y * 19) & 0xFF)
            }
        }

        let encoded = expect source.encode("memory.qoi")
        let decoded = expect Image.decode("memory.qoi", nnBytes(encoded.toSlice()), {})
        Swag.assert(decoded.width == source.width and decoded.height == source.height)
        for y in source.height
        {
            for x in source.width do
                Swag.assert(decoded.pixelColor(x, y).argb == source.pixelColor(x, y).argb)
        }
    }
}

// Metadata probing validates the header without allocating the pixel buffer.
#test
{
    const Bytes: [23] u8 = ['q', 'o', 'i', 'f', 0, 0, 0, 1, 0, 0, 0, 1, 3, 1, 0xC0, 0, 0, 0, 0, 0, 0, 0, 1]
    var options: DecodeOptions
    options.decodePixels = false
    let image = expect Image.decode("metadata.qoi", Bytes, options)
    Swag.assert(image.width == 1 and image.height == 1)
    Swag.assert(image.pixelFormat == .RGB8)
    Swag.assert(!image.isValid())
}

// Malformed headers, truncated chunks, oversized runs, and missing end markers fail cleanly.
#test
{
    const Valid: [23] u8 = ['q', 'o', 'i', 'f', 0, 0, 0, 1, 0, 0, 0, 1, 3, 0, 0xC0, 0, 0, 0, 0, 0, 0, 0, 1]
    var bytes = Valid
    bytes[0] = 'x'
    var image: Image
    image = catch Image.decode("bad.qoi", bytes, {}) as signatureError
    Swag.assert(signatureError != null)

    bytes     = Valid
    bytes[12] = 2
    image     = catch Image.decode("bad.qoi", bytes, {}) as channelError
    Swag.assert(channelError != null)

    bytes     = Valid
    bytes[14] = 0xC1
    image     = catch Image.decode("bad.qoi", bytes, {}) as runError
    Swag.assert(runError != null)

    bytes     = Valid
    bytes[22] = 0
    image     = catch Image.decode("bad.qoi", bytes, {}) as markerError
    Swag.assert(markerError != null)
}
