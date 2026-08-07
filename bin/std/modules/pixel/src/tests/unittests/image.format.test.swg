#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// ImageFormat.matches compares the extension only, case-insensitively, and a format
// declaring several spellings claims every one of them.
#test
{
    let png = ImageFormat{"PNG", ".png"}
    @assert(png.matches("capture.png"))
    @assert(png.matches("C:/a folder/CAPTURE.PNG"))
    @assert(!png.matches("capture.jpg"))
    @assert(!png.matches("png"))
    @assert(!png.matches("capture"))
    @assert(!png.matches(""))

    let jpeg = ImageFormat{"JPEG", ".jpg;.jpeg"}
    @assert(jpeg.matches("photo.jpg"))
    @assert(jpeg.matches("photo.jpeg"))
    @assert(!jpeg.matches("photo.jpe"))
}

// Every registered encoder and decoder declares a usable format, and the declared
// extensions are exactly what canSave/canLoad accept: the registry has one source of
// truth, so a format list built for a file dialog cannot offer an unwritable filter.
#test
{
    let encodable = Image.encodableFormats()
    @assert(encodable.count >= 8)
    for &format in encodable
    {
        @assert(@countof(format.name) != 0)
        for ext in Tokenize.split(format.extensions, ';'rune)
        {
            @assert(Utf8.startsWith(ext, "."))
            @assert(Image.canSave(Format.toString("image%", ext)))
        }
    }

    let decodable = Image.decodableFormats()
    @assert(decodable.count >= 8)
    for &format in decodable
    {
        @assert(@countof(format.name) != 0)
        for ext in Tokenize.split(format.extensions, ';'rune)
        {
            @assert(Utf8.startsWith(ext, "."))
            @assert(Image.canLoad(Format.toString("image%", ext)))
        }
    }
}

// An extension no registered codec claims is rejected by both halves of the registry,
// and the matching encode/decode entry points fail rather than picking an arbitrary codec.
#test
{
    @assert(!Image.canSave("capture.unknown"))
    @assert(!Image.canLoad("capture.unknown"))
    @assert(!Image.canSave("capture"))

    var img = Image.create(2, 2, .RGBA8)
    img.clear()
    discard catch img.encode("capture.unknown") as errEncode
    @assert(errEncode != null)

    discard catch Image.decode("capture.unknown", img.pixels.toSlice()) as errDecode
    @assert(errDecode != null)
}
