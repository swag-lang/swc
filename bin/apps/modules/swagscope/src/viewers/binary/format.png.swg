#global internal
#global namespace Viewers.Binary

using Core

// The eight bytes every PNG file begins with.
const PngSignature: [8] u8 = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

// Bytes a chunk adds around its data: the length and the type before it, the CRC after it.
private const PngChunkFrame = 12'u64

// Returns whether the file is a PNG image.
func isPngImage(image: *BinaryImage)->bool => image.matches(0, PngSignature)

// Adds the signature and the chunk chain of a PNG image, each chunk with the fields of its data.
//
// Every chunk is a group of its own, at the top of the report, because a PNG is nothing but its
// chunks: a reader looks for IHDR the way they look for the header of an executable.
func reportPngImage(image: *BinaryImage, report: *Report)
{
    image.bigEndian = true

    let texts = texts()
    report.beginGroup(texts.fld_Signature, "PNG", "", offset: 0, length: 8, open: true)
    report.field(0, 8, texts.fld_Signature, "89 50 4E 47 0D 0A 1A 0A", "PNG")
    report.endGroup()

    var scan   = 8'u64
    var count  = 0'u64
    var ended  = false
    var width  = 0'u32
    var height = 0'u32
    var colour = 0'u8
    while scan + PngChunkFrame <= image.bytes.count and count < ListLimit
    {
        let size = cast(u64, image.u32At(scan))
        let kind = image.fixedTextAt(scan + 4, 4)
        let data = scan + 8
        if size > image.bytes.count - data - 4 do
            break

        report.beginGroup(kind, StrConv.toDisplaySize(size), pngChunkMeaning(kind), offset: scan, length: size + PngChunkFrame)
        switch kind.toString()
        {
        case "IHDR" where size >= 13:
            width  = image.u32At(data)
            height = image.u32At(data + 4)
            colour = image.u8At(data + 9)
            reportPngHeader(image, report, data)

        case "pHYs" where size >= 9:
            let unit = image.u8At(data + 8)
            report.numField(data, 4, "Pixels per unit, X", cast(u64, image.u32At(data)))
            report.numField(data + 4, 4, "Pixels per unit, Y", cast(u64, image.u32At(data + 4)))
            report.numField(data + 8, 1, "Unit specifier", cast(u64, unit), unit == 1 ? "metre" : "")

        case "gAMA" where size >= 4:
            let gamma = image.u32At(data)
            report.numField(data, 4, "Image gamma", cast(u64, gamma), Format.toString("%{f5}", cast(f64, gamma) / 100_000))

        case "tEXt", "iTXt", "zTXt":
            report.field(data, Math.min(size, 79'u64), "Keyword", image.cstringAt(data, Math.min(size, 79'u64)))
        }

        report.hexField(data + size, 4, "CRC", cast(u64, image.u32At(data + size)))
        report.endGroup()

        count += 1
        scan  = data + size + 4
        if kind == "IEND"
        {
            ended = true
            break
        }
    }

    if not ended do
        report.note(texts.png_Malformed)

    report.formatName = "PNG"
    if width do
        report.summary = Format.toString("PNG · % × % · %", width, height, pngColourName(colour))
    else do
        report.summary = String.from("PNG")
}

// Adds the seven fields of the image header, in the order the specification lists them.
private func reportPngHeader(image: *BinaryImage, report: *Report, at: u64)
{
    let colour    = image.u8At(at + 9)
    let interlace = image.u8At(at + 12)
    report.numField(at, 4, "Width", cast(u64, image.u32At(at)))
    report.numField(at + 4, 4, "Height", cast(u64, image.u32At(at + 4)))
    report.numField(at + 8, 1, "Bit depth", cast(u64, image.u8At(at + 8)))
    report.numField(at + 9, 1, "Colour type", cast(u64, colour), pngColourName(colour))
    report.numField(at + 10, 1, "Compression method", cast(u64, image.u8At(at + 10)))
    report.numField(at + 11, 1, "Filter method", cast(u64, image.u8At(at + 11)))
    report.numField(at + 12, 1, "Interlace method", cast(u64, interlace), interlace == 1 ? "Adam7" : "none")
}

// Returns how the colour type of the image header lays out a pixel.
private func pngColourName(colour: u8)->string
{
    switch colour
    {
    case 0: return "greyscale"
    case 2: return "RGB"
    case 3: return "indexed"
    case 4: return "greyscale + alpha"
    case 6: return "RGBA"
    }

    return "?"
}

// Returns, in the active language, what a chunk of type `kind` holds; an empty text for a type the
// reader does not know.
private func pngChunkMeaning(kind: string)->string
{
    let texts = texts()
    switch kind
    {
    case "IHDR":                 return texts.png_Header
    case "PLTE":                 return texts.png_Palette
    case "IDAT":                 return texts.png_Data
    case "IEND":                 return texts.png_End
    case "pHYs":                 return texts.png_Density
    case "gAMA":                 return texts.png_Gamma
    case "tRNS":                 return texts.png_Transparency
    case "tIME":                 return texts.png_Time
    case "sRGB", "iCCP", "cHRM": return texts.png_ColourSpace
    case "tEXt", "iTXt", "zTXt": return texts.fld_Text
    }

    return ""
}
