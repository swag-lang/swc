#global if #command == Swag.CompilerCommand.Test

using Core, Pixel, Pdf

// Equal JPEGs with different color keys use distinct objects. Each key is independently reusable.
#test
{
    let jpeg = expect File.readAllBytes(guiTestDataPath("pdf-device-gray.jpg"))
    var objects: Array!{u8}
    const ImageDictionary = "/Type /XObject /Subtype /Image /Width 48 /Height 32 /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /DCTDecode /Decode [1 0] /Interpolate true"
    for limits, i in ["-10 95", "115 300", "115 300", "-10 95"]
    {
        let dictionary = Format.toString("% /Mask [%]", ImageDictionary, limits)
        addStreamObject(&objects, 5 + cast(u32, i), dictionary.toString(), jpeg.toSlice())
    }

    let content  = cast(const [..] u8, "q 48 0 0 32 0 0 cm /A Do Q q 48 0 0 32 48 0 cm /B Do Q q 48 0 0 32 0 32 cm /C Do Q q 48 0 0 32 48 32 cm /D Do Q")
    let source   = singlePagePdf("/XObject << /A 5 0 R /B 6 0 R /C 7 0 R /D 8 0 R >>", content, objects.toSlice())
    let document = expect Document.decode(source.toSlice())
    let saved    = expect document.encode()
    let reopened = expect Document.decode(saved.toSlice())
    let items    = reopened.pages[0].items
    Swag.require(items.count == 4)
    Swag.require(items[0].imageValue() != items[1].imageValue())
    Swag.require(items[0].imageValue() == items[3].imageValue())
    Swag.require(items[1].imageValue() == items[2].imageValue())

    for i in items.count
    {
        let image  = items[i].image
        let before = unwrap document.pages[0].items[i].imageValue()
        Swag.require(Slice.equals(image.encoded().bytes.toSlice(), jpeg.toSlice()))
        Swag.require(image.encoded().invertedSamples == 1 and image.encoded().interpolate)
        Swag.require(Slice.equals(image.value()!.pixels.toSlice(), before.pixels.toSlice()))
    }
}

// A JPEG carrying a color key retains a canonical Decode and cooks partial ranges into pixels.
#test
{
    const Width  = 32
    const Height = 16
    var samples: [Width * Height * 3] u8
    for x in Width * Height
    {
        samples[x * 3]     = 40 + cast(u8, x % Width) * 2
        samples[x * 3 + 1] = 90
        samples[x * 3 + 2] = 120 + cast(u8, x / Width) * 3
    }

    let image   = Image.create(Width, Height, .RGB8, samples)
    let encoded = expect image.encode(".jpg")
    let jpeg    = encoded.toArray()
    for decode, i in ["1 0 0 1 1 0", "1 0 0.25 0.75 1 0"]
    {
        var objects: Array!{u8}
        let dictionary = Format.toString("/Type /XObject /Subtype /Image /Width % /Height % /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Mask [40 80 0 255 120 160] /Decode [%]", Width, Height, decode)
        addStreamObject(&objects, 5, dictionary.toString(), jpeg.toSlice())
        let content   = cast(const [..] u8, "q 32 0 0 16 0 0 cm /Im Do Q")
        let bytes     = singlePagePdf("/XObject << /Im 5 0 R >>", content, objects.toSlice())
        let document  = expect Document.decode(bytes.toSlice())
        let reference = document.pages[0].items[0].image
        let saved     = expect document.encode()
        let reopened  = expect Document.decode(saved.toSlice())
        let result    = reopened.pages[0].items[0].image
        Swag.require(Slice.equals(reference.value()!.pixels.toSlice(), result.value()!.pixels.toSlice()))
        if i == 0
        {
            Swag.require(Slice.equals(jpeg.toSlice(), result.encoded().bytes.toSlice()))
            Swag.require(result.encoded().invertedSamples == 5)
        }
        else
        {
            Swag.require(not reference.encoded().bytes.count)
            Swag.require(not result.encoded().bytes.count or result.encoded().filter != .Dct)
        }
    }
}
