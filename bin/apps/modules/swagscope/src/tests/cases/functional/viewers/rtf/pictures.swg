#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

// Embedded JPEG pictures keep their reading position and declared size rather than a placeholder.
#test
{
    let document = expect Rtf.Document.load(scopeTestDataPath("viewer.pictures.rtf"))
    Swag.require(document.images == 1 and document.omittedObjects == 0)
    Swag.require(Utf8.contains(document.html, "data:image/jpeg;base64,"))
    Swag.require(Utf8.contains(document.html, "width=\"320\" height=\"240\""))
    Swag.require(Utf8.indexOf(document.html, "Every document") < Utf8.indexOf(document.html, "<img"))
    Swag.require(Utf8.indexOf(document.html, "<img") < Utf8.indexOf(document.html, "The picture stays"))
    Swag.require(not Utf8.contains(document.html, Rtf.texts().ui_ImageOmitted))
}

// A modern shape picture and its compatibility fallback are displayed once.
#test
{
    let document = expect Rtf.Document.load(scopeTestDataPath("viewer.alternate-picture.rtf"))
    Swag.require(document.images == 1 and document.omittedObjects == 0)
    let at = Utf8.indexOf(document.html, "data:image/png;base64,")
    Swag.require(at != Swag.U64.Max)
    Swag.require(Utf8.indexOf(document.html.toString()[at + 1 to], "data:image/png;base64,") == Swag.U64.Max)
    Swag.require(Utf8.contains(document.html, "A modern picture and its fallback"))
}

// Binary PNG payloads may contain RTF braces and backslashes without changing group structure.
#test
{
    let png = expect File.readAllBytes(scopeTestDataPath("viewer.png"))
    var bytes: Array'u8
    bytes.add(Format.toString("{\\rtf1\\ansi {\\pict\\pngblip\\picwgoal2400\\pichgoal2400\\bin% ", png.count))
    bytes.add(png.toSlice())
    bytes.add("}\\par After the binary picture.\\par}")
    let path = writeTempFile("binary-picture.rtf", bytes.toSlice())
    defer discard catch File.delete(path)
    let document = expect Rtf.Document.load(path)
    Swag.require(document.images == 1 and document.omittedObjects == 0)
    Swag.require(Utf8.contains(document.html, "data:image/png;base64,"))
    Swag.require(Utf8.contains(document.html, "After the binary picture."))
}

// Nested picture metadata is ignored; only the declared picture payload becomes image bytes.
#test
{
    let png = expect File.readAllBytes(scopeTestDataPath("viewer.png"))
    var payload: String = "\\pngblip{\\*\\picprop{\\sp{\\sn hex}{\\sv ABCDEF}}} "
    for byte in png do
        payload += Format.toString("%{X02}", byte)
    payload += "}"
    let picture = expect Rtf.Picture.parse(payload.toSlice(), 0, 2)
    Swag.require(picture.end == payload.count - 1 and picture.encodedBytes == png.count)
    let encoded = Base64.encode(png.toSlice())
    Swag.require(Utf8.contains(picture.html, encoded.toString()))
}

// Unsupported or malformed image data is named while later prose remains readable.
#test
{
    for picture in ["\\wmetafile8 01020304", "\\pngblip zz", "\\pngblip 123", "\\jpegblip 01020304"]
    {
        let source = Format.toString("{\\rtf1\\ansi {\\pict %}\\par Still readable.\\par}", picture)
        let path   = writeTempFile("unsupported-picture.rtf", cast(const [..] u8, source.toString()))
        defer discard catch File.delete(path)
        let document = expect Rtf.Document.load(path)
        Swag.require(document.images == 0 and document.omittedObjects == 1)
        Swag.require(Utf8.contains(document.html, Rtf.texts().ui_ImageOmitted))
        Swag.require(Utf8.contains(document.html, "Still readable."))
    }
}

// A picture beyond the byte budget is omitted without consuming the following paragraph.
#test
{
    var payload: Array'u8
    payload.resize(2 * 1024 * 1024 + 1)
    var bytes: Array'u8
    bytes.add(Format.toString("{\\rtf1\\ansi {\\pict\\pngblip\\bin% ", payload.count))
    bytes.add(payload.toSlice())
    bytes.add("}\\par After the large picture.\\par}")
    let path = writeTempFile("large-picture.rtf", bytes.toSlice())
    defer discard catch File.delete(path)
    let document = expect Rtf.Document.load(path)
    Swag.require(document.images == 0 and document.omittedObjects == 1)
    Swag.require(Utf8.contains(document.html, "After the large picture."))
}

// Truncated picture groups and binary payloads remain damaged RTF rather than successful images.
#test
{
    for source in ["{\\rtf1 {\\pict\\pngblip 1234", "{\\rtf1 {\\pict\\pngblip\\bin100 x}}", "{\\rtf1 {\\pict\\pngblip\\bin-1 x}}"]
    {
        let path = writeTempFile("damaged-picture.rtf", cast(const [..] u8, source))
        defer discard catch File.delete(path)
        var error: Swag.Error
        discard catch Rtf.Document.load(path) as error
        Swag.require(error.value() is Errors.InvalidFormatError)
    }
}

// An object preview and an unknown ignorable destination cannot publish their embedded pictures.
#test
{
    let source = "{\\rtf1 {\\object {\\pict\\pngblip 010203}}{\\*\\unknown {\\pict\\pngblip 010203}} Visible.\\par}"
    let path   = writeTempFile("ignored-picture.rtf", cast(const [..] u8, source))
    defer discard catch File.delete(path)
    let document = expect Rtf.Document.load(path)
    Swag.require(document.images == 0 and document.omittedObjects == 1)
    Swag.require(Utf8.contains(document.html, Rtf.texts().ui_ObjectOmitted))
    Swag.require(not Utf8.contains(document.html, Rtf.texts().ui_ImageOmitted))
    Swag.require(Utf8.contains(document.html, "Visible."))
}
