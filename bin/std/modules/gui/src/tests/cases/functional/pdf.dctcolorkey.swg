#global if #command == Swag.CompilerCommand.Test

using Core, Pixel, Pdf

private func dctColorKeyPdf(width, height: s32, colorName, mask, decode: string, jpeg: const [..] u8, softMask: const [..] u8 = [])->Document
{
    var objects: Array!{u8}
    var dictionary = Format.toString("/Type /XObject /Subtype /Image /Width % /Height % /ColorSpace /Device% /BitsPerComponent 8 /Filter /DCTDecode /Mask [%] %", width, height, colorName, mask, decode)
    if softMask.count
    {
        dictionary += " /SMask 6 0 R"
        let maskDictionary = Format.toString("/Type /XObject /Subtype /Image /Width % /Height % /ColorSpace /DeviceGray /BitsPerComponent 8", width, height)
        addStreamObject(&objects, 6, maskDictionary.toString(), softMask)
    }

    addStreamObject(&objects, 5, dictionary.toString(), jpeg)
    let content = cast(const [..] u8, "q 10 0 0 10 0 0 cm /Im0 Do Q")
    return expect Document.decode(singlePagePdf("/XObject << /Im0 5 0 R >>", content, objects.toSlice()).toSlice())
}

// A grayscale JPEG key compares the original sample even when /Decode inverts it.
#test
{
    let jpeg   = expect File.readAllBytes(guiTestDataPath("pdf-device-gray.jpg"))
    let source = expect Image.decode(".jpg", jpeg.toSlice(), {keepJpegGrayscale: true})
    let key    = source.pixelColor(7, 7).r
    let mask   = Format.toString("% %", key, key)
    let keyed  = dctColorKeyPdf(source.width, source.height, "Gray", mask.toString(), "/Decode [1 0]", jpeg.toSlice())
    let image  = unwrap onlyItem(keyed.pages[0], .Image).imageValue()
    Swag.require(image.pixelFormat == .RGBA8)
    var transparent = 0_u64
    for y in source.height
    {
        for x in source.width
        {
            let sample  = source.pixelColor(x, y).r
            let inverse = 255 - sample
            let alpha   = sample == key ? 0_u8 : 255_u8
            Swag.require(image.pixelColor(x, y) == Color.fromArgb(alpha, inverse, inverse, inverse))
            if alpha == 0
            {
                transparent += 1
            }
        }
    }

    Swag.require(transparent > 0 and transparent < source.byteCount)
}

// A DeviceRGB key uses all three channels in PDF order before applying the color ranges.
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

    let source  = Image.create(Width, Height, .RGB8, samples)
    let encoded = expect source.encode(".jpg")
    let jpeg    = encoded.toArray()
    let decoded = expect Image.decode(".jpg", jpeg.toSlice())
    let key     = decoded.pixelColor(10, 0)
    let mask    = Format.toString("% % % % % %", key.r, key.r, key.g, key.g, key.b, key.b)
    let keyed   = dctColorKeyPdf(Width, Height, "RGB", mask.toString(), "/Decode [1 0 0.25 0.75 0.125 0.625]", jpeg.toSlice())
    let image   = unwrap onlyItem(keyed.pages[0], .Image).imageValue()
    Swag.require(image.pixelFormat == .RGBA8 and image.pixelColor(10, 0).a == 0)
    var opaque = 0_u64
    for y in Height
    {
        for x in Width
        {
            let sample = decoded.pixelColor(x, y)
            let alpha  = sample == key ? 0_u8 : 255_u8
            let green  = cast(u8, (257 + 2 * cast(u32, sample.g)) / 4)
            let blue   = cast(u8, (259 + 4 * cast(u32, sample.b)) / 8)
            Swag.require(image.pixelColor(x, y) == Color.fromArgb(alpha, 255 - sample.r, green, blue))
            if alpha == 255
            {
                opaque += 1
            }
        }
    }

    Swag.require(opaque > 0)

    // /SMask takes precedence over a key that would make every sample transparent.
    var coverage: [Width * Height] u8
    for &sample in coverage
    {
        sample[] = 137
    }

    let masked      = dctColorKeyPdf(Width, Height, "RGB", "0 255 0 255 0 255", "", jpeg.toSlice(), coverage)
    let maskedImage = unwrap onlyItem(masked.pages[0], .Image).imageValue()
    Swag.require(maskedImage.pixelColor(10, 0) == Color.fromArgb(137, key.r, key.g, key.b))
}
