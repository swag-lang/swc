#global if #command == Swag.CompilerCommand.Test

using Core, Pdf

// The LZW example of the PDF specification, which exercises the clear code, the
// output-before-definition case, and the end-of-data code in nine bytes.
#test
{
    let encoded: [9] u8  = [0x80, 0x0B, 0x60, 0x50, 0x22, 0x0C, 0x0C, 0x85, 0x01]
    let decoded          = expect decodeLzw(encoded)
    let awaited: [10] u8 = [45, 45, 45, 45, 45, 65, 45, 45, 45, 66]
    Swag.assert(decoded.count == 10)
    for value, index in decoded do
        Swag.assert(value == awaited[index])
}

// A stream that ends inside a code is padding rather than a failure, and an undefined code is
// rejected instead of expanding random dictionary memory.
#test
{
    // Nine bits of clear code, then seven bits that cannot complete a code.
    let truncated: [2] u8 = [0x80, 0x0B]
    let padded            = expect decodeLzw(truncated)
    Swag.assert(padded.isEmpty())

    // A clear code followed by code 259, which no entry defines yet.
    let unknownCode: [3] u8 = [0x80, 0x40, 0xC0]
    discard catch decodeLzw(unknownCode) as undefinedError
    Swag.assert(undefinedError != null)
}

#test
{
    let ascii85 = expect decodeAscii85("z!!~>")
    Swag.assert(ascii85.count == 5)
    for value in ascii85 do
        Swag.assert(value == 0)

    // A full group, and a short group whose missing digits are filled with the highest one.
    let group = expect decodeAscii85("!!!!\"~>")
    Swag.assert(group.count == 4)
    Swag.assert(group[0] == 0 and group[1] == 0 and group[2] == 0 and group[3] == 1)

    let partial = expect decodeAscii85("88/~>")
    Swag.assert(partial.count == 2)
    Swag.assert(cast(string) partial.toSlice() == "Hi")

    discard catch decodeAscii85("!~") as terminatorError
    Swag.assert(terminatorError != null)
    discard catch decodeAscii85("!~>") as incompleteError
    Swag.assert(incompleteError != null)
}

#test
{
    let encoded: [7] u8 = [2, 'A', 'B', 'C', 254, 'Z', 128]
    let runLength       = expect decodeRunLength(encoded)
    Swag.assert(runLength.count == 6)
    Swag.assert(cast(string) runLength.toSlice() == "ABCZZZ")

    let truncated: [3] u8 = [4, 'A', 'B']
    discard catch decodeRunLength(truncated) as truncatedError
    Swag.assert(truncatedError != null)
}

#test
{
    let hex = expect decodeAsciiHex("48 65 6C 6c 6F>ignored")
    Swag.assert(cast(string) hex.toSlice() == "Hello")

    // An odd trailing digit is completed with a zero.
    let odd = expect decodeAsciiHex("4>")
    Swag.assert(odd.count == 1 and odd[0] == 0x40)

    discard catch decodeAsciiHex("4Z>") as hexError
    Swag.assert(hexError != null)
}

// An image stream carried by LZW reaches the sample decoder expanded.
#test
{
    let encoded: [9] u8 = [0x80, 0x0B, 0x60, 0x50, 0x22, 0x0C, 0x0C, 0x85, 0x01]
    var extra:   Array'u8
    addStreamObject(&extra, 5, "/Type /XObject /Subtype /Image /Width 5 /Height 2 /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /LZWDecode", encoded)

    let content  = "q 5 0 0 2 0 0 cm /Im0 Do Q"
    let document = expect Document.decode(singlePagePdf("/XObject << /Im0 5 0 R >>", cast(const [..] u8) content, extra.toSlice()).toSlice())
    let image    = onlyItem(document.pages[0], .Image).imageValue()!
    Swag.assert(image.width == 5 and image.height == 2)

    // The decoded samples are 45 45 45 45 45 / 65 45 45 45 66.
    Swag.assert(image.pixelColor(0, 0).r == 45)
    Swag.assert(image.pixelColor(4, 0).r == 45)
    Swag.assert(image.pixelColor(0, 1).r == 65)
    Swag.assert(image.pixelColor(4, 1).r == 66)
}

// A Flate stream with a PNG predictor is reconstructed row by row.
#test
{
    // Three rows of four gray samples, each row filtered with the `Up` predictor so every row
    // after the first stores its difference with the one above.
    let filtered: [15] u8 = [
        0, 10, 20, 30, 40,
        2, 1, 1, 1, 1,
        2, 1, 1, 1, 1]

    var zlib: Compress.ZLib
    let packed = expect zlib.compress(filtered)

    var extra: Array'u8
    addStreamObject(&extra, 5, "/Type /XObject /Subtype /Image /Width 4 /Height 3 /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode /DecodeParms << /Predictor 15 /Colors 1 /Columns 4 >>", packed.toSlice())

    let content  = "q 4 0 0 3 0 0 cm /Im0 Do Q"
    let document = expect Document.decode(singlePagePdf("/XObject << /Im0 5 0 R >>", cast(const [..] u8) content, extra.toSlice()).toSlice())
    let image    = onlyItem(document.pages[0], .Image).imageValue()!
    Swag.assert(image.width == 4 and image.height == 3)

    Swag.assert(image.pixelColor(0, 0).r == 10)
    Swag.assert(image.pixelColor(3, 0).r == 40)
    Swag.assert(image.pixelColor(0, 2).r == 12)
    Swag.assert(image.pixelColor(3, 2).r == 42)
}

// The facsimile filter is checked against the exact samples its encoder started from.
//
// The fixture is one Group 4 page written by a reference encoder next to the bitmap it encoded,
// so a single wrong entry in either run table changes a row and is caught here rather than as a
// smudge on a scanned document.
#test
{
    let encoded  = expect File.readAllBytes(corpusPdfPath("pdf.ccitt-g4.bin"))
    let expected = expect File.readAllBytes(corpusPdfPath("pdf.ccitt-g4.samples.bin"))

    var params: CcittParameters
    params.k       = -1
    params.columns = 64
    params.rows    = 48

    let decoded = expect decodeCcittFax(encoded.toSlice(), params)
    Swag.assert(decoded.count == expected.count)
    for value, index in decoded do
        Swag.assert(value == expected[index])

    // `BlackIs1` names the sample value black takes, so the same stream decodes to the complement.
    params.blackIs1 = true
    let inverted = expect decodeCcittFax(encoded.toSlice(), params)
    Swag.assert(inverted.count == expected.count)
    for value, index in inverted do
        Swag.assert(value == ~expected[index])
}

// A stream that ends early still describes an image of the height its dictionary declares, and a
// declared width of zero is a damaged dictionary rather than an empty image.
#test
{
    let encoded = expect File.readAllBytes(corpusPdfPath("pdf.ccitt-g4.bin"))

    var params: CcittParameters
    params.k       = -1
    params.columns = 64
    params.rows    = 60

    let decoded = expect decodeCcittFax(encoded.toSlice(), params)
    Swag.assert(decoded.count == 60 * 8)
    for index in 48 * 8 until decoded.count do
        Swag.assert(decoded[index] == 0xFF)

    params.columns = 0
    discard catch decodeCcittFax(encoded.toSlice(), params) as widthError
    Swag.assert(widthError != null)
}
