#global if #command == Swag.CompilerCommand.Test

using Core, Core.Math, Pixel, Pdf

// Builds a page holding a single image XObject, drawn over the unit square.
private func imageDocument(dictionary: string, samples: const [..] u8)->Document
{
    var extra: Array'u8
    addStreamObject(&extra, 5, dictionary, samples)

    let content = "q 10 0 0 10 0 0 cm /Im0 Do Q"
    return expect Document.decode(singlePagePdf("/XObject << /Im0 5 0 R >>", cast(const [..] u8) content, extra.toSlice()).toSlice())
}

// Every bit depth expands to the same eight-bit samples.
#test
{
    // Two rows of four one-bit samples; each row is padded to a byte.
    let oneBit: [2] u8 = [0b1010_0000, 0b0101_0000]
    let bilevel        = imageDocument("/Type /XObject /Subtype /Image /Width 4 /Height 2 /ColorSpace /DeviceGray /BitsPerComponent 1", oneBit)
    let bilevelImage   = onlyItem(bilevel.pages[0], .Image).imageValue()!
    Swag.assert(bilevelImage.width == 4 and bilevelImage.height == 2)
    Swag.assert(bilevelImage.pixelColor(0, 0).r == 255 and bilevelImage.pixelColor(1, 0).r == 0)
    Swag.assert(bilevelImage.pixelColor(0, 1).r == 0 and bilevelImage.pixelColor(1, 1).r == 255)

    // Four-bit samples: 0, 5, 10, and 15 sixteenths of full intensity.
    let fourBit: [2] u8 = [0x05, 0xAF]
    let quantized       = imageDocument("/Type /XObject /Subtype /Image /Width 4 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 4", fourBit)
    let quantizedImage  = onlyItem(quantized.pages[0], .Image).imageValue()!
    Swag.assert(quantizedImage.pixelColor(0, 0).r == 0)
    Swag.assert(quantizedImage.pixelColor(3, 0).r == 255)
    Swag.assert(quantizedImage.pixelColor(1, 0).r == 85)

    // Sixteen-bit samples are read most significant byte first and scaled down to eight bits.
    let sixteenBit: [6] u8 = [0x00, 0x00, 0x80, 0x00, 0xFF, 0xFF]
    let deep               = imageDocument("/Type /XObject /Subtype /Image /Width 3 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 16", sixteenBit)
    let deepImage          = onlyItem(deep.pages[0], .Image).imageValue()!
    Swag.assert(deepImage.pixelColor(0, 0).r == 0)
    Swag.assert(deepImage.pixelColor(1, 0).r == 128)
    Swag.assert(deepImage.pixelColor(2, 0).r == 255)
}

// A `/Decode` array remaps the samples before they become a color.
#test
{
    let samples: [2] u8 = [0, 255]
    let inverted        = imageDocument("/Type /XObject /Subtype /Image /Width 2 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /Decode [1 0]", samples)
    let image           = onlyItem(inverted.pages[0], .Image).imageValue()!
    Swag.assert(image.pixelColor(0, 0).r == 255)
    Swag.assert(image.pixelColor(1, 0).r == 0)
}

// The default eight-bit device-space fast paths match their scalar definitions for every tail.
#test
{
    var graySource:   [80] u8
    var grayActual:   [240] u8
    var grayExpected: [240] u8
    for index in graySource.count do
        graySource[index] = cast(u8) ((cast(u64) index * 37 + 11) & 0xFF)

    for idx in 65
    {
        for index in grayActual.count
        {
            grayActual[index]   = 0xA5
            grayExpected[index] = 0xA5
        }

        expandGray8(grayActual.buffer, graySource.buffer, idx)
        for i in idx
        {
            grayExpected[i * 3 + 0] = graySource[i]
            grayExpected[i * 3 + 1] = graySource[i]
            grayExpected[i * 3 + 2] = graySource[i]
        }

        Swag.assert(Memory.compare(grayActual.buffer, grayExpected.buffer, #sizeof(grayActual)) == 0)
    }

    var cmykSource:   [80] u8
    var cmykActual:   [64] u8
    var cmykExpected: [64] u8
    for index in cmykSource.count do
        cmykSource[index] = cast(u8) ((cast(u64) index * 53 + 19) & 0xFF)

    for length in 21
    {
        for index in cmykActual.count
        {
            cmykActual[index]   = 0x5A
            cmykExpected[index] = 0x5A
        }

        expandCmyk8(cmykActual.buffer, cmykSource.buffer, length)
        for i in length
        {
            let src = i * 4
            cmykToRgb(cast(f32) cmykSource[src + 0] / 255.0, cast(f32) cmykSource[src + 1] / 255.0, cast(f32) cmykSource[src + 2] / 255.0, cast(f32) cmykSource[src + 3] / 255.0, cmykExpected[i * 3 until i * 3 + 3])
        }

        Swag.assert(Memory.compare(cmykActual.buffer, cmykExpected.buffer, #sizeof(cmykActual)) == 0)
    }
}

// Saturating C+K is exactly the scalar floating-point definition for every eight-bit pair.
#test
{
    var source: [16] u8
    var actual: [12] u8
    var scalar: [3] u8
    for component in 256
    {
        for black in 256
        {
            for pixel in 4
            {
                source[pixel * 4 + 0] = cast(u8) component
                source[pixel * 4 + 1] = cast(u8) component
                source[pixel * 4 + 2] = cast(u8) component
                source[pixel * 4 + 3] = cast(u8) black
            }

            expandCmyk8(actual.buffer, source.buffer, 4)
            cmykToRgb(cast(f32) component / 255.0, cast(f32) component / 255.0, cast(f32) component / 255.0, cast(f32) black / 255.0, scalar)
            for index in actual.count do
                Swag.assert(actual[index] == scalar[index % 3])
        }
    }
}

// DeviceCMYK uses four-pixel blocks and preserves the final partial block.
#test
{
    let samples: [20] u8 = [
        0, 0, 0, 0,
        0, 0, 0, 255,
        0, 255, 255, 0,
        255, 0, 255, 0,
        255, 255, 0, 0]
    let document = imageDocument("/Type /XObject /Subtype /Image /Width 5 /Height 1 /ColorSpace /DeviceCMYK /BitsPerComponent 8", samples)
    let image    = onlyItem(document.pages[0], .Image).imageValue()!
    Swag.assert(image.pixelColor(0, 0) == Color.fromRgb(255, 255, 255))
    Swag.assert(image.pixelColor(1, 0) == Color.fromRgb(0, 0, 0))
    Swag.assert(image.pixelColor(2, 0) == Color.fromRgb(255, 0, 0))
    Swag.assert(image.pixelColor(3, 0) == Color.fromRgb(0, 255, 0))
    Swag.assert(image.pixelColor(4, 0) == Color.fromRgb(0, 0, 255))
}

// An indexed image reads its colors from the palette its color space carries.
#test
{
    let samples: [4] u8 = [0, 1, 2, 1]
    let palette         = "/ColorSpace [/Indexed /DeviceRGB 2 <FF0000 00FF00 0000FF>]"
    let document        = imageDocument(Format.toString("/Type /XObject /Subtype /Image /Width 4 /Height 1 % /BitsPerComponent 8", palette).toString(), samples)
    let image           = onlyItem(document.pages[0], .Image).imageValue()!
    Swag.assert(image.pixelColor(0, 0).r == 255 and image.pixelColor(0, 0).g == 0)
    Swag.assert(image.pixelColor(1, 0).g == 255 and image.pixelColor(1, 0).r == 0)
    Swag.assert(image.pixelColor(2, 0).b == 255)
    Swag.assert(image.pixelColor(3, 0).g == 255)
}

// An ICCBased space is reduced to the family its component count names.
#test
{
    var extra: Array'u8
    addStreamObject(&extra, 6, "/N 3", cast(const [..] u8) "profile bytes ignored")
    addStreamObject(&extra, 5, "/Type /XObject /Subtype /Image /Width 1 /Height 1 /ColorSpace [/ICCBased 6 0 R] /BitsPerComponent 8", [10'u8, 20, 30])

    let content  = "q 10 0 0 10 0 0 cm /Im0 Do Q"
    let document = expect Document.decode(singlePagePdf("/XObject << /Im0 5 0 R >>", cast(const [..] u8) content, extra.toSlice()).toSlice())
    let image    = onlyItem(document.pages[0], .Image).imageValue()!
    Swag.assert(image.pixelColor(0, 0).r == 10 and image.pixelColor(0, 0).g == 20 and image.pixelColor(0, 0).b == 30)
}

// A stencil mask paints the fill color where its samples are zero, and nothing elsewhere.
#test
{
    let samples: [1] u8 = [0b0100_0000]
    var extra:   Array'u8
    addStreamObject(&extra, 5, "/Type /XObject /Subtype /Image /Width 2 /Height 1 /ImageMask true", samples)

    let content  = "q 1 0 0 rg 10 0 0 10 0 0 cm /Im0 Do Q"
    let document = expect Document.decode(singlePagePdf("/XObject << /Im0 5 0 R >>", cast(const [..] u8) content, extra.toSlice()).toSlice())
    let image    = onlyItem(document.pages[0], .Image).imageValue()!
    Swag.assert(image.pixelFormat == .RGBA8)

    let painted = image.pixelColor(0, 0)
    Swag.assert(painted.a == 255 and painted.r == 255 and painted.g == 0)
    Swag.assert(image.pixelColor(1, 0).a == 0)
}

// A soft mask becomes the alpha channel, resampled to the size of the image it covers.
#test
{
    var extra: Array'u8
    addStreamObject(&extra, 6, "/Type /XObject /Subtype /Image /Width 2 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8", [0'u8, 255])
    addStreamObject(&extra, 5, "/Type /XObject /Subtype /Image /Width 4 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /SMask 6 0 R", [10'u8, 20, 30, 40])

    let content  = "q 10 0 0 10 0 0 cm /Im0 Do Q"
    let document = expect Document.decode(singlePagePdf("/XObject << /Im0 5 0 R >>", cast(const [..] u8) content, extra.toSlice()).toSlice())
    let image    = onlyItem(document.pages[0], .Image).imageValue()!
    Swag.assert(image.pixelFormat == .RGBA8)
    Swag.assert(image.pixelColor(0, 0).a == 0 and image.pixelColor(1, 0).a == 0)
    Swag.assert(image.pixelColor(2, 0).a == 255 and image.pixelColor(3, 0).a == 255)
    Swag.assert(image.pixelColor(3, 0).r == 40)
}

// A color key mask turns the sample ranges it names transparent.
#test
{
    let samples: [3] u8 = [10, 200, 30]
    let document        = imageDocument("/Type /XObject /Subtype /Image /Width 3 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /Mask [150 255]", samples)
    let image           = onlyItem(document.pages[0], .Image).imageValue()!
    Swag.assert(image.pixelFormat == .RGBA8)
    Swag.assert(image.pixelColor(0, 0).a == 255)
    Swag.assert(image.pixelColor(1, 0).a == 0)
    Swag.assert(image.pixelColor(2, 0).a == 255)
}

// An inline image carries its dictionary in the content stream, with abbreviated keys.
#test
{
    var content: Array'u8
    content.add(cast(const [..] u8) "q 20 0 0 10 0 0 cm BI /W 2 /H 1 /CS /RGB /BPC 8 ID ")
    content.add([255'u8, 0, 0, 0, 0, 255])
    content.add(cast(const [..] u8) " EI Q")

    let document = expect Document.decode(singlePagePdf("", content.toSlice(), "").toSlice())
    let item     = onlyItem(document.pages[0], .Image)
    let image    = item.imageValue()!
    Swag.assert(image.width == 2 and image.height == 1)
    Swag.assert(image.pixelColor(0, 0).r == 255 and image.pixelColor(0, 0).b == 0)
    Swag.assert(image.pixelColor(1, 0).b == 255 and image.pixelColor(1, 0).r == 0)

    // The unit square of the image is mapped by the current transform.
    let transform = item.itemTransform()
    Swag.assert(transform.m11 == 20 and transform.m22 == 10)
}

// A scanned stencil and a print-ready photograph reach the page from one file.
//
// The fixture carries a Group 4 facsimile image and a four-component JPEG, which are the two
// image encodings an office document most often hides behind: before they decoded, either one
// cost the whole page it appeared on.
#test
{
    var reader = expect Reader.open(corpusPdfPath("synthetic-ccitt-cmyk.pdf"))
    Swag.assert(reader.pageCount() == 1)
    var page = expect reader.loadPage(0)

    var fax:   #null const *Image
    var photo: #null const *Image
    for item in page.items where item.kind == .Image
    {
        let image = item.imageValue()!
        if image.width == 64 do
            fax = image
        elif image.width == 48 do
            photo = image
    }

    Swag.assert(fax != null and photo != null)
    Swag.assert(fax!.width == 64 and fax!.height == 48)
    Swag.assert(fax!.pixelColor(0, 0).r == 255)
    Swag.assert(fax!.pixelColor(20, 10).r == 0)

    // The three bands are the colours the fixture was made from, so the ink complement and the
    // ink-to-screen conversion are both checked here rather than only inside the decoder.
    Swag.assert(photo!.width == 48 and photo!.height == 32)
    let red = photo!.pixelColor(8, 16)
    Swag.assert(red.r > 200 and red.g < 60 and red.b < 60)
    let green = photo!.pixelColor(24, 16)
    Swag.assert(green.g > 200 and green.r < 60 and green.b < 60)
    let blue = photo!.pixelColor(40, 16)
    Swag.assert(blue.b > 200 and blue.r < 60 and blue.g < 60)

    let rendered = expect page.render({scale: 1})
    Swag.assert(rendered.isValid())
}

// An unsupported codec is reported instead of producing a wrong picture.
#test
{
    var extra: Array'u8
    addStreamObject(&extra, 5, "/Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceGray /BitsPerComponent 1 /Filter /JBIG2Decode", [0'u8, 0])

    let content = "q 10 0 0 10 0 0 cm /Im0 Do Q"
    let bytes   = singlePagePdf("/XObject << /Im0 5 0 R >>", cast(const [..] u8) content, extra.toSlice())
    discard catch Document.decode(bytes.toSlice()) as codecError
    Swag.assert(codecError != null)
}

// The writer stores a gray picture with one component and keeps transparency as a soft mask.
#test
{
    let gray: [12] u8 = [10, 10, 10, 40, 40, 40, 90, 90, 90, 200, 200, 200]
    var document      = Document.create()
    var page          = Page.create(200, 100)
    page.addImage(Image.create(2, 2, .RGB8, gray), 10, 10, 40, 40)
    document.addPage(#move page)

    let bytes = expect document.encode()
    let text  = cast(string) bytes.toSlice()
    Swag.assert(Utf8.indexOf(text, "/DeviceGray") != Swag.U64.Max)
    Swag.assert(Utf8.indexOf(text, "/SMask") == Swag.U64.Max)

    let decoded = expect Document.decode(bytes.toSlice())
    let image   = onlyItem(decoded.pages[0], .Image).imageValue()!
    Swag.assert(image.width == 2 and image.height == 2)
    Swag.assert(image.pixelColor(0, 1).r == 10 and image.pixelColor(0, 1).g == 10)
    Swag.assert(image.pixelColor(1, 0).r == 200 and image.pixelColor(1, 1).r == 40)
}

#test
{
    let rgba: [16] u8 = [255, 0, 0, 255, 0, 255, 0, 128, 0, 0, 255, 0, 255, 255, 0, 255]
    var document      = Document.create()
    var page          = Page.create(200, 100)
    page.addImage(Image.create(2, 2, .RGBA8, rgba), 10, 10, 40, 40)
    document.addPage(#move page)

    let bytes = expect document.encode()
    Swag.assert(Utf8.indexOf(cast(string) bytes.toSlice(), "/SMask") != Swag.U64.Max)

    var decoded = expect Document.decode(bytes.toSlice())
    let image   = onlyItem(decoded.pages[0], .Image).imageValue()!
    Swag.assert(image.pixelFormat == .RGBA8)

    // Every pixel keeps its own coverage through the writer and the reader.
    Swag.assert(image.pixelColor(0, 0).a == 0 and image.pixelColor(1, 0).a == 255)
    Swag.assert(image.pixelColor(0, 1).a == 255 and image.pixelColor(1, 1).a == 128)

    // A partly transparent picture also reaches the rasterizer.
    let rendered = expect decoded.editPage(0).render({scale: 1})
    Swag.assert(rendered.isValid() and rendered.width == 200)
}
