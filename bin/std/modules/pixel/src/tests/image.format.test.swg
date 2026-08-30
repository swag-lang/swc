#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// ImageFormat.matches compares the extension only, case-insensitively, and a format
// declaring several spellings claims every one of them.
#test
{
    let png = ImageFormat{"PNG", ".png"}
    Swag.assert(png.matches("capture.png"))
    Swag.assert(png.matches("C:/a folder/CAPTURE.PNG"))
    Swag.assert(!png.matches("capture.jpg"))
    Swag.assert(!png.matches("png"))
    Swag.assert(!png.matches("capture"))
    Swag.assert(!png.matches(""))

    let jpeg = ImageFormat{"JPEG", ".jpg;.jpeg"}
    Swag.assert(jpeg.matches("photo.jpg"))
    Swag.assert(jpeg.matches("photo.jpeg"))
    Swag.assert(!jpeg.matches("photo.jpe"))
}

// Every registered encoder and decoder declares a usable format, and the declared
// extensions are exactly what canSave/canLoad accept: the registry has one source of
// truth, so a format list built for a file dialog cannot offer an unwritable filter.
#test
{
    let encodable = Image.encodableFormats()
    Swag.assert(encodable.count >= 8)
    for &format in encodable
    {
        Swag.assert(format.name.count != 0)
        for ext in Tokenize.split(format.extensions, ';'rune)
        {
            Swag.assert(Utf8.startsWith(ext, "."))
            Swag.assert(Image.canSave(Format.toString("image%", ext)))
        }
    }

    let decodable = Image.decodableFormats()
    Swag.assert(decodable.count >= 8)
    for &format in decodable
    {
        Swag.assert(format.name.count != 0)
        for ext in Tokenize.split(format.extensions, ';'rune)
        {
            Swag.assert(Utf8.startsWith(ext, "."))
            Swag.assert(Image.canLoad(Format.toString("image%", ext)))
        }
    }
}

// An extension no registered codec claims is rejected by both halves of the registry,
// and the matching encode/decode entry points fail rather than picking an arbitrary codec.
#test
{
    Swag.assert(!Image.canSave("capture.unknown"))
    Swag.assert(!Image.canLoad("capture.unknown"))
    Swag.assert(!Image.canSave("capture"))

    var img = Image.create(2, 2, .RGBA8)
    img.clear()
    discard catch img.encode("capture.unknown") as errEncode
    Swag.assert(errEncode != null)

    discard catch Image.decode("capture.unknown", img.pixels.toSlice()) as errDecode
    Swag.assert(errDecode != null)
}
