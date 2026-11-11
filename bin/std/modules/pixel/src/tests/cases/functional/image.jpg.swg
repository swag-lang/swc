#global if #command == Swag.CompilerCommand.Test

using Swag, Core

func assertNearByte(value, expected: u8, tolerance: u8)
{
    let diff = Math.abs(cast(s32, value) - cast(s32, expected))
    Swag.require(diff <= tolerance)
}

func assertJpgPixelNear(img: Image, b, g, r: u8, tolerance: u8)
{
    Swag.require(img.isValid())
    Swag.require(img.pixels.buffer != null)
    assertNearByte(img.pixels.buffer[0], b, tolerance)
    assertNearByte(img.pixels.buffer[1], g, tolerance)
    assertNearByte(img.pixels.buffer[2], r, tolerance)
}

func assertLoadedJpg(fileName: string, width, height: s32, b, g, r: u8)
{
    let img = expect Image.load(getTestDataPath(fileName))
    Swag.require(img.isValid())
    Swag.require(img.width == width)
    Swag.require(img.height == height)
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(img.bitsPerPixel == 24)
    Swag.require(img.bytesPerPixel == 3)
    Swag.require(img.pixels.count == cast(u64, width) * height * 3)
    assertJpgPixelNear(img, b, g, r, 8'u8)
}

func assertJpgHasMarker(bytes: const [..] u8, marker: u8)
{
    for i in bytes.count - 1
    {
        if bytes[i] == 0xFF and bytes[i + 1] == marker do
            return
    }

    Swag.require(false)
}

func addAdobeRgbMarker(encoded: const [..] u8)->Array'u8
{
    Swag.require(encoded.count >= 2)
    Swag.require(encoded[0] == 0xFF and encoded[1] == 0xD8)

    const app14: [16] u8 = [
        0xFF, 0xEE, 0, 14,
        'A', 'd', 'o', 'b', 'e',
        0, 100,
        0, 0,
        0, 0,
        0]

    var result: ConcatBuffer
    result.addBytes(encoded[until 2])
    result.addBytes(app14)
    result.addBytes(encoded[2 to])
    return result.toArray()
}

func fillSolidImage(img: *Image, b, g, r, a: u8)
{
    var pix = img.pixels.storage()
    for img.width * img.height
    {
        switch img.pixelFormat
        {
        case .BGR8:
            pix[0] = b
            pix[1] = g
            pix[2] = r

        case .RGB8:
            pix[0] = r
            pix[1] = g
            pix[2] = b

        case .BGRA8:
            pix[0] = b
            pix[1] = g
            pix[2] = r
            pix[3] = a

        case .RGBA8:
            pix[0] = r
            pix[1] = g
            pix[2] = b
            pix[3] = a
        }

        pix += img.bytesPerPixel
    }
}

func assertEncodedJpgRoundtrip(src: Image, expectedB, expectedG, expectedR: u8, tolerance: u8, quality: u8 = 100'u8)
{
    var opt: Jpg.EncodeOptions
    opt.quality = quality

    let cb    = expect src.encode("memory.jpg", opt)
    let bytes = nnBytes(cb.toSlice())
    Swag.require(bytes.count > 20)
    Swag.require(bytes[0] == 0xFF and bytes[1] == 0xD8)
    Swag.require(bytes[bytes.count - 2] == 0xFF and bytes[bytes.count - 1] == 0xD9)
    assertJpgHasMarker(bytes, 0xDB'u8)
    assertJpgHasMarker(bytes, 0xC0'u8)
    assertJpgHasMarker(bytes, 0xC4'u8)
    assertJpgHasMarker(bytes, 0xDA'u8)

    let img = expect Image.decode("encoded.jpg", bytes, {})
    Swag.require(img.width == src.width)
    Swag.require(img.height == src.height)
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(img.pixels.count == cast(u64, src.width) * src.height * 3)
    assertJpgPixelNear(img, expectedB, expectedG, expectedR, tolerance)
}

// Decoder and encoder registries accept both JPEG extensions.
#test
{
    Swag.require(Image.canLoad("photo.jpg"))
    Swag.require(Image.canLoad("photo.jpeg"))
    Swag.require(not Image.canLoad("photo.jxl"))
    Swag.require(Image.canSave("photo.jpg"))
    Swag.require(Image.canSave("photo.jpeg"))
}

// Load real baseline JPEG fixtures with different sampling layouts.
#test
{
    assertLoadedJpg("h1v1.jpg", 660, 441, 201'u8, 205'u8, 194'u8)
    assertLoadedJpg("h2v1.jpg", 660, 441, 112'u8, 122'u8, 109'u8)
    assertLoadedJpg("h2v2.jpg", 1024, 768, 30'u8, 26'u8, 25'u8)
}

// Load grayscale-like, progressive, and larger JPEG fixtures.
#test
{
    assertLoadedJpg("gray.jpg", 660, 441, 202'u8, 202'u8, 202'u8)
    let gray = expect Image.load(getTestDataPath("gray.jpg"))
    for pixel in cast(u64, gray.width) * gray.height
    {
        let offset = pixel * 3
        Swag.require(gray.pixels.storage()[offset] == gray.pixels.storage()[offset + 1])
        Swag.require(gray.pixels.storage()[offset] == gray.pixels.storage()[offset + 2])
    }

    assertLoadedJpg("progh1v1.jpg", 660, 441, 202'u8, 206'u8, 195'u8)
    assertLoadedJpg("testA.jpg", 1200, 704, 30'u8, 30'u8, 30'u8)
}

// A four-component frame is the ink layout a print-ready photograph is written in.
//
// The fixture is a red, green and blue band saved as CMYK, so a correct decode returns exactly
// the colours it was made from: the Adobe marker says the inks are stored complemented, and the
// three bands are what proves the complement and the ink-to-screen conversion agree.
#test
{
    let img = expect Image.load(getTestDataPath("cmyk.jpg"))
    Swag.require(img.width == 48 and img.height == 32)
    Swag.require(img.pixelFormat == .BGR8)

    let row = cast(u64, (img.height - 1 - 16)) * cast(u64, img.width) * 3
    let red = img.pixels.storage() + row + 8 * 3
    assertNearByte(red[0], 0'u8, 8'u8)
    assertNearByte(red[1], 0'u8, 8'u8)
    assertNearByte(red[2], 255'u8, 8'u8)

    let green = img.pixels.storage() + row + 24 * 3
    assertNearByte(green[0], 0'u8, 8'u8)
    assertNearByte(green[1], 255'u8, 8'u8)
    assertNearByte(green[2], 0'u8, 8'u8)

    let blue = img.pixels.storage() + row + 40 * 3
    assertNearByte(blue[0], 255'u8, 8'u8)
    assertNearByte(blue[1], 0'u8, 8'u8)
    assertNearByte(blue[2], 0'u8, 8'u8)
}

// Decode from preloaded bytes and verify .jpeg extension routing.
#test
{
    let bytes = expect File.readAllBytes(getTestDataPath("h1v1.jpg"))
    let img   = expect Image.decode("fixture.jpeg", bytes.toSlice(), {})
    Swag.require(img.width == 660)
    Swag.require(img.height == 441)
    Swag.require(img.pixelFormat == .BGR8)
    assertJpgPixelNear(img, 202'u8, 200'u8, 192'u8, 8'u8)
}

// Metadata-only decode must populate dimensions without allocating pixels.
#test
{
    let bytes = expect File.readAllBytes(getTestDataPath("h2v2.jpg"))
    var opts: DecodeOptions
    opts.decodePixels = false

    let img = expect Image.decode("meta.jpg", bytes.toSlice(), opts)
    Swag.require(img.width == 1024)
    Swag.require(img.height == 768)
    Swag.require(img.pixelFormat == .BGR8)
    Swag.require(not img.isValid())
}

// JPEG metadata collection is independent of pixel decoding, including header-only probes.
#test
{
    var source = Image.create(8, 8, .RGB8)
    source.fill(Color.fromRgb(32, 64, 96))
    var record: ImageMetadata
    record.signature = 1
    record.tag       = "Source"
    record.value     = "camera"
    source.metadata.add(record)
    let encoded = expect source.encode("metadata.jpg")
    for pixels in [true, false]
    {
        for metadata in [true, false]
        {
            let decoded = expect Image.decode("metadata.jpg", encoded.toSlice(), {decodePixels: pixels, decodeMetadata: metadata})
            Swag.require(decoded.isValid() == pixels)
            Swag.require(decoded.width == 8 and decoded.height == 8)
            var found = false
            for item in decoded.metadata where item.isTag("Source")
            {
                Swag.require(cast(string, item.toSlice()) == "camera")
                found = true
            }

            Swag.require(found == metadata)
            if not metadata do
                Swag.require(decoded.metadata.isEmpty())
        }
    }
}

#test
{
    var image = Image.create(1, 1, .BGR8)
    var record: ImageMetadata
    record.signature = 0
    record.tag.resize(65_533)
    image.metadata.add(record)

    var encoded:      ConcatBuffer
    var errorOutcome: Swag.Error
    catch { encoded = try image.encode("oversized-metadata.jpg") } as errorOutcome
    Swag.require(errorOutcome.value() != null)

    record.signature = 16
    record.tag       = "Vendor"
    record.value     = "metadata"
    image.metadata.clear()
    image.metadata.add(record)
    errorOutcome = {}
    catch { encoded = try image.encode("invalid-metadata-signature.jpg") } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// Invalid and truncated buffers should fail without producing an image.
#test
{
    let bad:         [8] u8 = [0, 1, 2, 3, 4, 5, 6, 7]
    var img:         Image
    var err8Outcome: Swag.Error
    catch { img = try Image.decode("bad.jpg", Swag.makeSlice(&bad[0], bad.count), {}) } as err8Outcome
    let err8 = err8Outcome.value()
    Swag.require(err8 != null)

    let bytes = expect File.readAllBytes(getTestDataPath("h1v1.jpg"))
    var err10Outcome: Swag.Error
    catch { img = try Image.decode("truncated.jpg", Swag.makeSlice(bytes.buffer, 32), {}) } as err10Outcome
    let err10 = err10Outcome.value()
    Swag.require(err10 != null)
}

#test
{
    var bytes     = expect File.readAllBytes(getTestDataPath("h1v1.jpg"))
    var sofOffset = Swag.U64.Max

    // EXIF thumbnails can contain their own SOF marker before the main image.
    for i in bytes.count - 11
    {
        if bytes[i] == 0xFF and bytes[i + 1] == 0xC0 do
            sofOffset = i
    }

    Swag.require(sofOffset != Swag.U64.Max)
    bytes[sofOffset + 11] = 0     // The first component's horizontal sampling factor.

    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try Image.decode("zero-sampling.jpg", bytes.toSlice()) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

#test
{
    var bytes     = expect File.readAllBytes(getTestDataPath("h1v1.jpg"))
    var dhtOffset = Swag.U64.Max

    // EXIF thumbnails can define their own Huffman tables before the main image.
    for i in bytes.count - 5
    {
        if bytes[i] == 0xFF and bytes[i + 1] == 0xC4 do
            dhtOffset = i
    }

    Swag.require(dhtOffset != Swag.U64.Max)
    bytes[dhtOffset + 4] = 0x20     // Huffman table class 2 is reserved.

    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try Image.decode("invalid-huffman-class.jpg", bytes.toSlice()) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

#test
{
    var bytes     = expect File.readAllBytes(getTestDataPath("h1v1.jpg"))
    var sosOffset = Swag.U64.Max

    // EXIF thumbnails can contain their own scan markers before the main image.
    for i in bytes.count - 7
    {
        if bytes[i] == 0xFF and bytes[i + 1] == 0xDA do
            sosOffset = i
    }

    Swag.require(sosOffset != Swag.U64.Max)
    bytes[sosOffset + 6] = 0x40     // DC Huffman table id 4 is outside the supported range.

    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try Image.decode("invalid-sos-table.jpg", bytes.toSlice()) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

#test
{
    var bytes     = expect File.readAllBytes(getTestDataPath("h1v1.jpg"))
    var sosOffset = Swag.U64.Max

    // EXIF thumbnails can contain their own scan markers before the main image.
    for i in bytes.count - 7
    {
        if bytes[i] == 0xFF and bytes[i + 1] == 0xDA do
            sosOffset = i
    }

    Swag.require(sosOffset != Swag.U64.Max)
    bytes[sosOffset + 6] = 0x04     // AC Huffman table id 4 is outside the supported range.

    var image:        Image
    var errorOutcome: Swag.Error
    catch { image = try Image.decode("invalid-sos-table.jpg", bytes.toSlice()) } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

#test
{
    let wideImage = Image.create(65_536, 1, .BGR8)
    var encoded:      ConcatBuffer
    var errorOutcome: Swag.Error
    catch { encoded = try wideImage.encode("too-wide.jpg") } as errorOutcome
    Swag.require(errorOutcome.value() != null)

    let tallImage = Image.create(1, 65_536, .BGR8)
    errorOutcome = {}
    catch { encoded = try tallImage.encode("too-tall.jpg") } as errorOutcome
    Swag.require(errorOutcome.value() != null)
}

// Encode BGR8 and round-trip through the JPEG decoder.
#test
{
    var src = Image.create(8, 8, .BGR8)
    fillSolidImage(&src, 40'u8, 90'u8, 210'u8, 255'u8)
    assertEncodedJpgRoundtrip(src, 40'u8, 90'u8, 210'u8, 6'u8)
}

// Encode BGRA8; alpha is ignored by JPEG, while B/G/R survive the round-trip.
#test
{
    var src = Image.create(8, 8, .BGRA8)
    fillSolidImage(&src, 15'u8, 170'u8, 80'u8, 33'u8)
    assertEncodedJpgRoundtrip(src, 15'u8, 170'u8, 80'u8, 6'u8)
}

// Encode RGB8 by converting from RGB memory order to JPEG RGB components.
#test
{
    var src = Image.create(8, 8, .RGB8)
    fillSolidImage(&src, 25'u8, 60'u8, 230'u8, 255'u8)
    assertEncodedJpgRoundtrip(src, 25'u8, 60'u8, 230'u8, 6'u8)
}

// Encode RGBA8 by converting from RGBA memory order and dropping alpha.
#test
{
    var src = Image.create(8, 8, .RGBA8)
    fillSolidImage(&src, 190'u8, 40'u8, 70'u8, 11'u8)
    assertEncodedJpgRoundtrip(src, 190'u8, 40'u8, 70'u8, 6'u8)
}

// Encode dimensions that require MCU padding; the decoded image keeps original dimensions.
#test
{
    var src = Image.create(5, 7, .BGR8)
    fillSolidImage(&src, 120'u8, 30'u8, 200'u8, 255'u8)
    assertEncodedJpgRoundtrip(src, 120'u8, 30'u8, 200'u8, 8'u8, 95'u8)
}

// Adobe APP14 transform 0 marks three equally sampled components as direct RGB.
#test
{
    var src = Image.create(8, 8, .RGB8)
    fillSolidImage(&src, 0, 0, 255, 255)

    var options: Jpg.EncodeOptions
    options.quality = 100
    let encoded  = expect src.encode("memory.jpg", options)
    let adobeRgb = addAdobeRgbMarker(nnBytes(encoded.toSlice()))
    let decoded  = expect Image.decode("adobe-rgb.jpg", nnBytes(adobeRgb.toSlice()), {})
    Swag.require(decoded.width == 8 and decoded.height == 8)

    // The source encoder's Y, Cb and Cr component samples become direct R, G and B.
    assertJpgPixelNear(decoded, 255, 85, 76, 4)
}
