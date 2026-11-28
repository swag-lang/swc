#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// QOI is registered for loading and saving and is therefore offered by image consumers.
#test
{
    Swag.require(Image.canLoad("sample.qoi"))
    Swag.require(Image.canSave("sample.qoi"))
}

// QOI refuses a buffer that no longer matches the image geometry.
#test
{
    var image = Image.create(1, 1, .RGBA8)
    image.pixels.resize(1)

    var errorOutcome: Swag.Error
    catch { discard try image.encodeToBytes("truncated.qoi") } as errorOutcome
    Swag.require(errorOutcome.value() != null)
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
    Swag.require(image.width == 3 and image.height == 2)
    Swag.require(image.pixelFormat == .RGBA8)

    let expected: [24] u8 = [1, 2, 3, 4, 1, 2, 3, 4, 1, 2, 3, 4,
                             10, 20, 30, 255, 11, 19, 30, 255, 15, 24, 36, 255]
    Swag.require(Memory.compare(image.pixels.storage(), expected.buffer, expected.count) == 0)
}

// Four consecutive RGBA chunks keep the most recent color in a colliding index slot.
#test
{
    const Bytes: [43] u8 = [
        'q', 'o', 'i', 'f', 0, 0, 0, 5, 0, 0, 0, 1, 4, 0,
        0xFF, 1, 2, 3, 4, 0xFF, 5, 6, 7, 8,
        0xFF, 9, 10, 11, 12, 0xFF, 65, 2, 3, 4,
        14, 0, 0, 0, 0, 0, 0, 0, 1]
    const Expected: [20] u8 = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 65, 2, 3, 4, 65, 2, 3, 4]
    let image = expect Image.decode("rgba-batch-index.qoi", Bytes)
    Swag.require(Memory.compare(image.pixels.storage(), Expected.buffer, Expected.count) == 0)
}

// Four RGB chunks update colliding indices and write exactly twelve bytes.
#test
{
    const Bytes: [43] u8 = [
        'q', 'o', 'i', 'f', 0, 0, 0, 6, 0, 0, 0, 1, 3, 0,
        0xFE, 1, 2, 3, 0xFE, 5, 6, 7, 0xFE, 9, 10, 11, 0xFE, 65, 2, 3,
        23, 0xFE, 39, 53, 82, 0, 0, 0, 0, 0, 0, 0, 1]
    const Expected: [18] u8 = [1, 2, 3, 5, 6, 7, 9, 10, 11, 65, 2, 3, 65, 2, 3, 39, 53, 82]
    let image = expect Image.decode("rgb-batch-index.qoi", Bytes)
    Swag.require(image.pixelFormat == .RGB8 and image.byteCount == Expected.count)
    Swag.require(Memory.compare(image.pixels.storage(), Expected.buffer, Expected.count) == 0)
}

// A run updates the QOI index table for a following INDEX chunk of the same pixel.
#test
{
    const Bytes:    [24] u8 = ['q', 'o', 'i', 'f', 0, 0, 0, 2, 0, 0, 0, 1, 4, 0, 0xC0, 53, 0, 0, 0, 0, 0, 0, 0, 1]
    const Expected: [8] u8  = [0, 0, 0, 255, 0, 0, 0, 255]
    let image = expect Image.decode("run-index.qoi", Bytes, {})
    Swag.require(Memory.compare(image.pixels.storage(), Expected.buffer, Expected.count) == 0)
}

// Runs span bottom-up row boundaries in both RGB and RGBA output.
#test
{
    // Thirteen pixels of the first color span two complete rows and part of the third.
    var bytes: [32] u8 = [
        'q', 'o', 'i', 'f', 0, 0, 0, 5, 0, 0, 0, 3, 3, 0,
        0xFE, 10, 20, 30, 0xCB, 0xFE, 40, 50, 60, 0xC0,
        0, 0, 0, 0, 0, 0, 0, 1]
    for channels in [3_u8, 4_u8]
    {
        bytes[12] = channels
        let image = expect Image.decode("row-spanning.qoi", bytes)
        for y in 3
        {
            for x in 5
            {
                Swag.require(image.pixelColor(x, y) == (y * 5 + x < 13 ? Color.fromRgb(10, 20, 30) : Color.fromRgb(40, 50, 60)))
            }
        }
    }
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
                let offset = cast(u64, y) * source.rowStride + cast(u64, x) * source.bytesPerPixel
                let pixel  = source.pixels.storage() + offset
                if pixelFormat == .RGB8 or pixelFormat == .RGBA8
                {
                    pixel[0] = cast(u8, ((x * 13 + y * 3) & 0xFF))
                    pixel[1] = cast(u8, ((x * 5 + y * 17) & 0xFF))
                    pixel[2] = cast(u8, ((x * 7 + y * 11) & 0xFF))
                }
                else
                {
                    pixel[0] = cast(u8, ((x * 7 + y * 11) & 0xFF))
                    pixel[1] = cast(u8, ((x * 5 + y * 17) & 0xFF))
                    pixel[2] = cast(u8, ((x * 13 + y * 3) & 0xFF))
                }

                if source.bytesPerPixel == 4
                {
                    pixel[3] = cast(u8, ((x * 9 + y * 19) & 0xFF))
                }
            }
        }

        let encoded = expect source.encode("memory.qoi")
        let decoded = expect Image.decode("memory.qoi", nnBytes(encoded.toSlice()), {})
        Swag.require(decoded.width == source.width and decoded.height == source.height)
        for y in source.height
        {
            for x in source.width
            {
                Swag.require(decoded.pixelColor(x, y).argb == source.pixelColor(x, y).argb)
            }
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
    Swag.require(image.width == 1 and image.height == 1)
    Swag.require(image.pixelFormat == .RGB8)
    Swag.require(not image.isValid())
}

// Header-only probes must reject dimensions that cannot fit an Image row before initialization.
#test
{
    const Bytes: [23] u8 = ['q', 'o', 'i', 'f', 0x2F, 0x6A, 0xE3, 0x00, 0, 0, 0, 1, 3, 0, 0xC0, 0, 0, 0, 0, 0, 0, 0, 1]
    var options: DecodeOptions
    options.maxPixels       = 0
    options.maxDecodedBytes = 0
    options.decodePixels    = false

    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try Image.decode("wide-row.qoi", Bytes, options) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// Malformed headers, truncated chunks, oversized runs, and missing end markers fail cleanly.
#test
{
    const Valid: [23] u8 = ['q', 'o', 'i', 'f', 0, 0, 0, 1, 0, 0, 0, 1, 3, 0, 0xC0, 0, 0, 0, 0, 0, 0, 0, 1]
    var bytes = Valid
    bytes[0] = 'x'
    var image: Image
    var signatureErrorOutcome: Swag.Error
    catch { image = try Image.decode("bad.qoi", bytes, {}) } as signatureErrorOutcome
    let signatureError = signatureErrorOutcome.value()
    Swag.require(signatureError != null)

    bytes     = Valid
    bytes[12] = 2
    var channelErrorOutcome: Swag.Error
    catch { image = try Image.decode("bad.qoi", bytes, {}) } as channelErrorOutcome
    let channelError = channelErrorOutcome.value()
    Swag.require(channelError != null)

    bytes     = Valid
    bytes[14] = 0xC1
    var runErrorOutcome: Swag.Error
    catch { image = try Image.decode("bad.qoi", bytes, {}) } as runErrorOutcome
    let runError = runErrorOutcome.value()
    Swag.require(runError != null)

    bytes     = Valid
    bytes[22] = 0
    var markerErrorOutcome: Swag.Error
    catch { image = try Image.decode("bad.qoi", bytes, {}) } as markerErrorOutcome
    let markerError = markerErrorOutcome.value()
    Swag.require(markerError != null)
}

// Uniform images emit complete 62-pixel packets across row boundaries and a final remainder.
#test
{
    for format in [PixelFormat.RGB8, .BGR8, .RGBA8, .BGRA8]
    {
        var source = Image.create(37, 7, format)
        for solid in [Color.fromRgb(0, 0, 0), Color.fromArgb(format.hasAlpha() ? 123_u8 : 255_u8, 19, 53, 241)]
        {
            source.fill(solid)
            let encoded = expect source.encodeToBytes("uniform.qoi")
            let prefix  = solid.argb == 0xFF000000 ? 0_u64 : (format.hasAlpha() ? 5_u64 : 4_u64)
            Swag.require(encoded.count == 14 + prefix + 5 + 8)
            for run in 4
            {
                Swag.require(encoded[14 + prefix + run] == 0xFD)
            }

            Swag.require(encoded[14 + prefix + 4] == (prefix ? 0xC9_u8 : 0xCA_u8))
            let decoded = expect Image.decode("uniform.qoi", encoded.toSlice())
            for y in source.height
            {
                for x in source.width
                {
                    Swag.require(decoded.pixelColor(x, y).argb == solid.argb)
                }
            }
        }

        // A different interior pixel must use the ordinary chunk writer.
        source.pixels.storage()[source.rowStride + source.bytesPerPixel] = 43
        let encoded = expect source.encodeToBytes("mixed.qoi")
        let decoded = expect Image.decode("mixed.qoi", encoded.toSlice())
        for y in source.height
        {
            for x in source.width
            {
                Swag.require(decoded.pixelColor(x, y).argb == source.pixelColor(x, y).argb)
            }
        }
    }
}
