#global if #command == Swag.CompilerCommand.Test

using Core, Pixel, Pdf

private func dctDecodeDocument(width, height: s32, space, decode: string, jpeg: const [..] u8, mask: const [..] u8 = [], maskDecode = "")->Document
{
    var objects: Array!{u8}
    var definition = Format.toString("/Type /XObject /Subtype /Image /Width % /Height % /ColorSpace /Device% /BitsPerComponent 8 /Filter /DCTDecode %", width, height, space, decode)
    if mask.count
    {
        definition += " /SMask 6 0 R"
        let maskDefinition = Format.toString("/Type /XObject /Subtype /Image /Width % /Height % /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /DCTDecode %", width, height, maskDecode)
        addStreamObject(&objects, 6, maskDefinition.toString(), mask)
    }

    addStreamObject(&objects, 5, definition.toString(), jpeg)
    return expect Document.decode(singlePagePdf("/XObject << /Im0 5 0 R >>", cast(const [..] u8, "q 10 0 0 10 0 0 cm /Im0 Do Q"), objects.toSlice()).toSlice())
}

// A grayscale JPEG keeps one byte per sample when the PDF remaps its brightness.
#test
{
    let bytes          = expect File.readAllBytes(guiTestDataPath("pdf-device-gray.jpg"))
    let source         = expect Image.decode(".jpg", bytes.toSlice(), {keepJpegGrayscale: true})
    let inverted       = dctDecodeDocument(source.width, source.height, "Gray", "/Decode [1 0]", bytes.toSlice())
    let ranged         = dctDecodeDocument(source.width, source.height, "Gray", "/Decode [0.125 0.875]", bytes.toSlice())
    let identity       = dctDecodeDocument(source.width, source.height, "Gray", "/Decode [0 1]", bytes.toSlice())
    let inversePixels  = unwrap onlyItem(inverted.pages[0], .Image).imageValue()
    let rangePixels    = unwrap onlyItem(ranged.pages[0], .Image).imageValue()
    let identityPixels = unwrap onlyItem(identity.pages[0], .Image).imageValue()
    Swag.require(inversePixels.pixelFormat == .Gray8 and rangePixels.pixelFormat == .Gray8)
    Swag.require(Slice.equals(source.pixels.toSlice(), identityPixels.pixels.toSlice()))
    for sample, i in source.pixels
    {
        Swag.require(inversePixels.pixels[i] == 255 - sample)
        Swag.require(rangePixels.pixels[i] == (259 + 6 * cast(u32, sample)) / 8)
    }
}

// DeviceRGB ranges apply in PDF channel order after the JPEG color transform.
#test
{
    const Width  = 19
    const Height = 3
    var samples: [Width * Height * 3] u8
    for i in Width * Height
    {
        samples[i * 3]     = cast(u8, 10 + i * 4)
        samples[i * 3 + 1] = cast(u8, 180 - i * 2)
        samples[i * 3 + 2] = cast(u8, 25 + i * 3)
    }

    let source        = Image.create(Width, Height, .RGB8, samples)
    let encoded       = expect source.encode(".jpg")
    let jpeg          = encoded.toArray()
    let plain         = expect Image.decode(".jpg", jpeg.toSlice())
    let inverted      = dctDecodeDocument(Width, Height, "RGB", "/Decode [1 0 1 0 1 0]", jpeg.toSlice())
    let ranged        = dctDecodeDocument(Width, Height, "RGB", "/Decode [1 0 0.25 0.75 0.125 0.625]", jpeg.toSlice())
    let inversePixels = unwrap onlyItem(inverted.pages[0], .Image).imageValue()
    let rangePixels   = unwrap onlyItem(ranged.pages[0], .Image).imageValue()
    for y in Height
    {
        for x in Width
        {
            let color = plain.pixelColor(x, y)
            Swag.require(inversePixels.pixelColor(x, y) == Color.fromRgb(255 - color.r, 255 - color.g, 255 - color.b))
            let green = cast(u8, (257 + 2 * cast(u32, color.g)) / 4)
            let blue  = cast(u8, (259 + 4 * cast(u32, color.b)) / 8)
            Swag.require(rangePixels.pixelColor(x, y) == Color.fromRgb(255 - color.r, green, blue))
        }
    }
}

// Color and alpha each apply their own /Decode before a JPEG soft mask is composed.
#test
{
    let bytes  = expect File.readAllBytes(guiTestDataPath("pdf-device-gray.jpg"))
    let source = expect Image.decode(".jpg", bytes.toSlice(), {keepJpegGrayscale: true})
    let masked = dctDecodeDocument(source.width, source.height, "Gray", "/Decode [0.125 0.875]", bytes.toSlice(), bytes.toSlice(), "/Decode [1 0]")
    let image  = unwrap onlyItem(masked.pages[0], .Image).imageValue()
    Swag.require(image.pixelFormat == .RGBA8 and image.width == source.width and image.height == source.height)
    for y in source.height
    {
        for x in source.width
        {
            let sample = source.pixelColor(x, y).r
            let value  = cast(u8, (259 + 6 * cast(u32, sample)) / 8)
            Swag.require(image.pixelColor(x, y) == Color.fromArgb(255 - sample, value, value, value))
        }
    }
}
