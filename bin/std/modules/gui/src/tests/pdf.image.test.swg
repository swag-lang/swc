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
    @assert(bilevelImage.width == 4 and bilevelImage.height == 2)
    @assert(bilevelImage.pixelColor(0, 0).r == 255 and bilevelImage.pixelColor(1, 0).r == 0)
    @assert(bilevelImage.pixelColor(0, 1).r == 0 and bilevelImage.pixelColor(1, 1).r == 255)

    // Four-bit samples: 0, 5, 10, and 15 sixteenths of full intensity.
    let fourBit: [2] u8 = [0x05, 0xAF]
    let quantized       = imageDocument("/Type /XObject /Subtype /Image /Width 4 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 4", fourBit)
    let quantizedImage  = onlyItem(quantized.pages[0], .Image).imageValue()!
    @assert(quantizedImage.pixelColor(0, 0).r == 0)
    @assert(quantizedImage.pixelColor(3, 0).r == 255)
    @assert(quantizedImage.pixelColor(1, 0).r == 85)

    // Sixteen-bit samples are read most significant byte first and scaled down to eight bits.
    let sixteenBit: [6] u8 = [0x00, 0x00, 0x80, 0x00, 0xFF, 0xFF]
    let deep               = imageDocument("/Type /XObject /Subtype /Image /Width 3 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 16", sixteenBit)
    let deepImage          = onlyItem(deep.pages[0], .Image).imageValue()!
    @assert(deepImage.pixelColor(0, 0).r == 0)
    @assert(deepImage.pixelColor(1, 0).r == 128)
    @assert(deepImage.pixelColor(2, 0).r == 255)
}

// A `/Decode` array remaps the samples before they become a color.
#test
{
    let samples: [2] u8 = [0, 255]
    let inverted        = imageDocument("/Type /XObject /Subtype /Image /Width 2 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /Decode [1 0]", samples)
    let image           = onlyItem(inverted.pages[0], .Image).imageValue()!
    @assert(image.pixelColor(0, 0).r == 255)
    @assert(image.pixelColor(1, 0).r == 0)
}

// An indexed image reads its colors from the palette its color space carries.
#test
{
    let samples: [4] u8 = [0, 1, 2, 1]
    let palette         = "/ColorSpace [/Indexed /DeviceRGB 2 <FF0000 00FF00 0000FF>]"
    let document        = imageDocument(Format.toString("/Type /XObject /Subtype /Image /Width 4 /Height 1 % /BitsPerComponent 8", palette).toString(), samples)
    let image           = onlyItem(document.pages[0], .Image).imageValue()!
    @assert(image.pixelColor(0, 0).r == 255 and image.pixelColor(0, 0).g == 0)
    @assert(image.pixelColor(1, 0).g == 255 and image.pixelColor(1, 0).r == 0)
    @assert(image.pixelColor(2, 0).b == 255)
    @assert(image.pixelColor(3, 0).g == 255)
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
    @assert(image.pixelColor(0, 0).r == 10 and image.pixelColor(0, 0).g == 20 and image.pixelColor(0, 0).b == 30)
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
    @assert(image.pixelFormat == .RGBA8)

    let painted = image.pixelColor(0, 0)
    @assert(painted.a == 255 and painted.r == 255 and painted.g == 0)
    @assert(image.pixelColor(1, 0).a == 0)
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
    @assert(image.pixelFormat == .RGBA8)
    @assert(image.pixelColor(0, 0).a == 0 and image.pixelColor(1, 0).a == 0)
    @assert(image.pixelColor(2, 0).a == 255 and image.pixelColor(3, 0).a == 255)
    @assert(image.pixelColor(3, 0).r == 40)
}

// A color key mask turns the sample ranges it names transparent.
#test
{
    let samples: [3] u8 = [10, 200, 30]
    let document        = imageDocument("/Type /XObject /Subtype /Image /Width 3 /Height 1 /ColorSpace /DeviceGray /BitsPerComponent 8 /Mask [150 255]", samples)
    let image           = onlyItem(document.pages[0], .Image).imageValue()!
    @assert(image.pixelFormat == .RGBA8)
    @assert(image.pixelColor(0, 0).a == 255)
    @assert(image.pixelColor(1, 0).a == 0)
    @assert(image.pixelColor(2, 0).a == 255)
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
    @assert(image.width == 2 and image.height == 1)
    @assert(image.pixelColor(0, 0).r == 255 and image.pixelColor(0, 0).b == 0)
    @assert(image.pixelColor(1, 0).b == 255 and image.pixelColor(1, 0).r == 0)

    // The unit square of the image is mapped by the current transform.
    let transform = item.itemTransform()
    @assert(transform.m11 == 20 and transform.m22 == 10)
}

// An unsupported codec is reported instead of producing a wrong picture.
#test
{
    var extra: Array'u8
    addStreamObject(&extra, 5, "/Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceGray /BitsPerComponent 1 /Filter /JBIG2Decode", [0'u8, 0])

    let content = "q 10 0 0 10 0 0 cm /Im0 Do Q"
    let bytes   = singlePagePdf("/XObject << /Im0 5 0 R >>", cast(const [..] u8) content, extra.toSlice())
    discard catch Document.decode(bytes.toSlice()) as codecError
    @assert(codecError != null)
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
    @assert(Utf8.indexOf(text, "/DeviceGray") != Swag.U64.Max)
    @assert(Utf8.indexOf(text, "/SMask") == Swag.U64.Max)

    let decoded = expect Document.decode(bytes.toSlice())
    let image   = onlyItem(decoded.pages[0], .Image).imageValue()!
    @assert(image.width == 2 and image.height == 2)
    @assert(image.pixelColor(0, 1).r == 10 and image.pixelColor(0, 1).g == 10)
    @assert(image.pixelColor(1, 0).r == 200 and image.pixelColor(1, 1).r == 40)
}

#test
{
    let rgba: [16] u8 = [255, 0, 0, 255, 0, 255, 0, 128, 0, 0, 255, 0, 255, 255, 0, 255]
    var document      = Document.create()
    var page          = Page.create(200, 100)
    page.addImage(Image.create(2, 2, .RGBA8, rgba), 10, 10, 40, 40)
    document.addPage(#move page)

    let bytes = expect document.encode()
    @assert(Utf8.indexOf(cast(string) bytes.toSlice(), "/SMask") != Swag.U64.Max)

    let decoded = expect Document.decode(bytes.toSlice())
    let image   = onlyItem(decoded.pages[0], .Image).imageValue()!
    @assert(image.pixelFormat == .RGBA8)

    // Every pixel keeps its own coverage through the writer and the reader.
    @assert(image.pixelColor(0, 0).a == 0 and image.pixelColor(1, 0).a == 255)
    @assert(image.pixelColor(0, 1).a == 255 and image.pixelColor(1, 1).a == 128)

    // A partly transparent picture also reaches the rasterizer.
    let rendered = expect decoded.pages[0].render({scale: 1})
    @assert(rendered.isValid() and rendered.width == 200)
}
