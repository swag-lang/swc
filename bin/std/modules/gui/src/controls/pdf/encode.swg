#global namespace Pdf

using Core, Core.Errors, Core.Math, Pixel

private struct PageObjects
{
    page:    u32
    content: u32
    images:  Array'u32
    masks:   Array'u32     // Soft-mask object of each image, or zero when it is opaque.
}

// One image reduced to what the writer stores: gray or RGB samples, plus coverage.
private struct EncodedImage
{
    samples: Array'u8
    alpha:   Array'u8
    isGray:  bool
}

private struct Writer
{
    bytes:   Array'u8
    offsets: Array'u64
}

private impl Writer
{
    mtd append(text: string)
    {
        .bytes.add(cast(const [..] u8) text)
    }

    mtd beginObject(number: u32)
    {
        .offsets[number] = .bytes.count
        .append(Format.toString("% 0 obj\n", number).toString())
    }

    mtd endObject()
    {
        .append("endobj\n")
    }

    mtd streamObject(number: u32, data: const [..] u8, dictionary: string)
    {
        .beginObject(number)
        .append("<< ")
        if dictionary.count
        {
            .append(dictionary)
            .append(" ")
        }

        .append(Format.toString("/Length % >>\nstream\n", data.count).toString())
        .bytes.add(data)
        .append("\nendstream\n")
        .endObject()
    }
}

private func pdfNumber(value: f32)->String
{
    var result: retval
    if value == Math.trunc(value) and Math.abs(value) < 1e9
    {
        let magnitude = cast(s64) Math.abs(value)
        result.appendFormat("%", value < 0 ? -magnitude : magnitude)
        return result
    }

    result.appendFormat("%{f4}", value)
    while result.endsWith("0") do
        result.removeBack(1)
    if result.endsWith(".") do
        result.removeBack(1)
    return result
}

private func windows1252(text: string)->Array'u8 fail
{
    var result: retval
    Utf8.visitRunes(text)
    {
        if c <= 0x7F or (c >= 0xA0 and c <= 0xFF)
        {
            result.add(cast(u8) c)
            continue
        }

        var found = false
        for value in 0x80'u32 to 0x9F
        {
            if Text.windows1252Rune(cast(u8) value) == c
            {
                result.add(cast(u8) value)
                found = true
                break
            }
        }

        if !found do
            fail UnsupportedFormatError{"PDF text output cannot encode this Unicode character"}
    }

    return result
}

private func appendPdfString(result: *String, text: string) fail
{
    let encoded = #move try windows1252(text)
    result[] += '('
    for c in encoded
    {
        switch c
        {
        case '(', ')', '\\':
            result[] += '\\'
            result[] += c

        case '\n':
            result[] += "\\n"

        case '\r':
            result[] += "\\r"

        case '\t':
            result[] += "\\t"

        default:
            result[] += c
        }
    }

    result[] += ')'
}

private func appendColor(result: *String, color: Color, stroke: bool)
{
    result.appendFormat("% % % %\n", pdfNumber(color.r / 255.0), pdfNumber(color.g / 255.0), pdfNumber(color.b / 255.0), stroke ? "RG" : "rg")
}

private func appendStrokeStyle(result: *String, item: const *Item)
{
    var cap: u32
    switch item.strokeStyle.cap
    {
    case .Butt:   cap = 0
    case .Round:  cap = 1
    case .Square: cap = 2
    }

    var join: u32
    switch item.strokeStyle.join
    {
    case .Miter: join = 0
    case .Round: join = 1
    case .Bevel: join = 2
    }

    result.appendFormat("% J\n% j\n% M\n[", cap, join, pdfNumber(item.strokeStyle.miterLimit))
    for length, index in item.strokeStyle.dashPattern
    {
        if index do
            result[] += ' '
        result[] += pdfNumber(length)
    }

    result.appendFormat("] % d\n", pdfNumber(item.strokeStyle.dashPhase))
}

private func encodedPoint(page: const *Page, item: const *Item, point: Vector2)->Vector2
{
    let transformed = item.transform.transformPoint(point)
    return {transformed.x, page.height - transformed.y}
}

private func appendPath(result: *String, page: const *Page, item: const *Item)
{
    for path in item.path.toSlice()
    {
        var needsFlatten = false
        for element in path.elements where element.type == .Arc or element.type == .Curve
        {
            needsFlatten = true
            break
        }

        if needsFlatten
        {
            var copy = path[]
            copy.flatten(.High)
            let polygon = copy.flattenedPolygon()
            for point, index in polygon.points
            {
                let encoded = encodedPoint(page, item, point)
                result.appendFormat("% % %\n", pdfNumber(encoded.x), pdfNumber(encoded.y), index == 0 ? "m" : "l")
            }

            if path.isClosed do
                result[] += "h\n"
            continue
        }

        let start        = path.startPoint
        let encodedStart = encodedPoint(page, item, start)
        result.appendFormat("% % m\n", pdfNumber(encodedStart.x), pdfNumber(encodedStart.y))
        var current = start
        for element in path.elements
        {
            switch element.type
            {
            case .Line:
                let p = encodedPoint(page, item, element.position)
                result.appendFormat("% % l\n", pdfNumber(p.x), pdfNumber(p.y))

            case .Bezier1:
                let c1x = current.x + 2.0 / 3.0 * (element.p1.x - current.x)
                let c1y = current.y + 2.0 / 3.0 * (element.p1.y - current.y)
                let c2x = element.position.x + 2.0 / 3.0 * (element.p1.x - element.position.x)
                let c2y = element.position.y + 2.0 / 3.0 * (element.p1.y - element.position.y)
                let c1  = encodedPoint(page, item, {c1x, c1y})
                let c2  = encodedPoint(page, item, {c2x, c2y})
                let p   = encodedPoint(page, item, element.position)
                result.appendFormat("% % % % % % c\n", pdfNumber(c1.x), pdfNumber(c1.y), pdfNumber(c2.x), pdfNumber(c2.y), pdfNumber(p.x), pdfNumber(p.y))

            case .Bezier2:
                let c1 = encodedPoint(page, item, element.p1)
                let c2 = encodedPoint(page, item, element.p2)
                let p  = encodedPoint(page, item, element.position)
                result.appendFormat("% % % % % % c\n", pdfNumber(c1.x), pdfNumber(c1.y), pdfNumber(c2.x), pdfNumber(c2.y), pdfNumber(p.x), pdfNumber(p.y))

            default:
                break
            }

            current = element.position
        }

        if path.isClosed do
            result[] += "h\n"
    }

    if item.hasFill do
        appendColor(result, item.fillColor, false)
    if item.hasStroke
    {
        appendColor(result, item.strokeColor, true)
        result.appendFormat("% w\n", pdfNumber(item.strokeWidth))
        appendStrokeStyle(result, item)
    }

    if item.hasFill and item.hasStroke do
        result[] += "B\n"
    elif item.hasFill do
        result[] += "f\n"
    else do
        result[] += "S\n"
}

// Returns the index each standard face occupies in the shared font resource dictionary.
private func documentFonts(document: const *Document)->Array'StandardFont
{
    var result: retval
    for page in document.pages
    {
        for item in page.items where item.kind == .Text
        {
            var found = false
            for font in result where font == item.standardFont
            {
                found = true
                break
            }

            if !found do
                result.add(item.standardFont)
        }
    }

    return result
}

private func fontSlot(fonts: const [..] StandardFont, font: StandardFont)->u64
{
    for candidate, index in fonts where candidate == font do
        return index
    return 0
}

private func pageContent(page: const *Page, fonts: const [..] StandardFont)->String fail
{
    var result: retval
    var imageIndex = 0'u32
    for item in page.items
    {
        switch item.kind
        {
        case .Text:
            appendColor(&result, item.fillColor, false)
            let baseline = item.transform.transformPoint({0, item.fontSize})
            result.appendFormat("BT\n/F% % Tf\n% % % % % % Tm\n", fontSlot(fonts, item.standardFont), pdfNumber(item.fontSize), pdfNumber(item.transform.m11), pdfNumber(-item.transform.m12), pdfNumber(-item.transform.m21), pdfNumber(item.transform.m22), pdfNumber(baseline.x), pdfNumber(page.height - baseline.y))
            try appendPdfString(&result, item.text.toString())
            result += " Tj\nET\n"

        case .Path:
            appendPath(&result, page, item)

        case .Image:
            let tr = item.transform
            result.appendFormat("q\n% % % % % % cm\n/Im% Do\nQ\n", pdfNumber(tr.m11), pdfNumber(-tr.m12), pdfNumber(-tr.m21), pdfNumber(tr.m22), pdfNumber(tr.tx + tr.m21), pdfNumber(page.height - tr.ty - tr.m22), imageIndex)
            imageIndex += 1
        }
    }

    return result
}

// Reduces one image to the narrowest representation that keeps every pixel.
//
// A picture whose channels are equal everywhere is written as one gray component instead of
// three, and a picture that is not fully opaque contributes a soft mask.
private func encodeImagePixels(image: const *Image)->EncodedImage
{
    var result: retval
    let width       = cast(u64) image.width
    let height      = cast(u64) image.height
    let swapRedBlue = image.pixelFormat == .BGR8 or image.pixelFormat == .BGRA8
    let hasAlpha    = image.pixelFormat == .BGRA8 or image.pixelFormat == .RGBA8

    result.isGray = true
    var transparent = false
    for y in height
    {
        let sourceY = height - y - 1
        for x in width
        {
            let src = (sourceY * width + x) * image.bytesPerPixel
            let r   = image.pixels[src + (swapRedBlue ? 2 : 0)]
            let b   = image.pixels[src + (swapRedBlue ? 0 : 2)]
            if r != image.pixels[src + 1] or r != b do
                result.isGray = false
            if hasAlpha and image.pixels[src + 3] != 0xFF do
                transparent = true
        }
    }

    let components = result.isGray ? 1'u64 : 3'u64
    result.samples.resize(width * height * components)
    if transparent do
        result.alpha.resize(width * height)

    for y in height
    {
        let sourceY = height - y - 1
        for x in width
        {
            let src = (sourceY * width + x) * image.bytesPerPixel
            let dst = (y * width + x) * components
            if result.isGray do
                result.samples[dst] = image.pixels[src + 1]
            else
            {
                result.samples[dst + 0] = image.pixels[src + (swapRedBlue ? 2 : 0)]
                result.samples[dst + 1] = image.pixels[src + 1]
                result.samples[dst + 2] = image.pixels[src + (swapRedBlue ? 0 : 2)]
            }

            if transparent do
                result.alpha[y * width + x] = image.pixels[src + 3]
        }
    }

    return result
}

private func infoDictionary(metadata: const *Metadata)->String fail
{
    var result: retval = "<<"
    let fields: [6] { name: string, value: string } = [
        {"Title",    metadata.title.toString()},
        {"Author",   metadata.author.toString()},
        {"Subject",  metadata.subject.toString()},
        {"Keywords", metadata.keywords.toString()},
        {"Creator",  metadata.creator.toString()},
        {"Producer", metadata.producer.toString()}]
    for field in fields where field.value.count
    {
        result.appendFormat(" /% ", field.name)
        try appendPdfString(&result, field.value)
    }

    result += " >>\n"
    return result
}

func encodeDocument(document: const *Document)->Array'u8 fail
{
    if !document.pages.count do
        fail BadParameterError{}

    const CatalogObject = 1'u32
    const PagesObject   = 2'u32
    const InfoObject    = 3'u32
    var nextObject = 4'u32

    let fonts = documentFonts(document)
    var fontObjects: Array'u32
    for font in fonts
    {
        discard font
        fontObjects.add(nextObject)
        nextObject += 1
    }

    var layout: Array'PageObjects
    for page in document.pages
    {
        if page.width <= 0 or page.height <= 0 or !Math.isFinite(page.width) or !Math.isFinite(page.height) do
            fail BadParameterError{}
        var objects: PageObjects
        objects.page    = nextObject
        nextObject      += 1
        objects.content = nextObject
        nextObject      += 1
        for item in page.items where item.kind == .Image
        {
            objects.images.add(nextObject)
            nextObject += 1
            if item.image.pixelFormat == .BGRA8 or item.image.pixelFormat == .RGBA8
            {
                objects.masks.add(nextObject)
                nextObject += 1
            }
            else do
                objects.masks.add(0)
        }

        layout.add(#move objects)
    }

    var writer: Writer
    writer.offsets.resize(nextObject)
    writer.append("%PDF-1.7\n")
    writer.bytes.add([0x25'u8, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A])

    writer.beginObject(CatalogObject)
    writer.append("<< /Type /Catalog /Pages 2 0 R >>\n")
    writer.endObject()

    writer.beginObject(PagesObject)
    writer.append(Format.toString("<< /Type /Pages /Count % /Kids [", document.pages.count).toString())
    for objects in layout do
        writer.append(Format.toString(" % 0 R", objects.page).toString())
    writer.append(" ] >>\n")
    writer.endObject()

    writer.beginObject(InfoObject)
    writer.append(try infoDictionary(&document.metadata))
    writer.endObject()

    for font, index in fonts
    {
        writer.beginObject(fontObjects[index])
        writer.append(Format.toString("<< /Type /Font /Subtype /Type1 /BaseFont /% /Encoding /WinAnsiEncoding >>\n", font.baseFontName()).toString())
        writer.endObject()
    }

    for page, pageIndex in document.pages
    {
        let objects = &layout[pageIndex]
        writer.beginObject(objects.page)
        writer.append(Format.toString("<< /Type /Page /Parent % 0 R /MediaBox [0 0 % %] /Resources <<", PagesObject, pdfNumber(page.width), pdfNumber(page.height)).toString())
        if fontObjects.count
        {
            writer.append(" /Font <<")
            for fontObject, fontIndex in fontObjects do
                writer.append(Format.toString(" /F% % 0 R", fontIndex, fontObject).toString())
            writer.append(" >>")
        }

        if objects.images.count
        {
            writer.append(" /XObject <<")
            for imageObject, imageIndex in objects.images do
                writer.append(Format.toString(" /Im% % 0 R", imageIndex, imageObject).toString())
            writer.append(" >>")
        }

        writer.append(Format.toString(" >> /Contents % 0 R >>\n", objects.content).toString())
        writer.endObject()

        let content    = #move try pageContent(page, fonts.toSlice())
        var zlib: Compress.ZLib
        let compressed = #move try zlib.compress(cast(const [..] u8) content)
        writer.streamObject(objects.content, compressed.toSlice(), "/Filter /FlateDecode")

        var imageIndex = 0'u64
        for item in page.items where item.kind == .Image
        {
            let encoded    = encodeImagePixels(&item.image)
            var samplesZlib: Compress.ZLib
            let samples    = #move try samplesZlib.compress(encoded.samples.toSlice())
            let maskObject = objects.masks[imageIndex]
            var dictionary = Format.toString("/Type /XObject /Subtype /Image /Width % /Height % /ColorSpace /Device% /BitsPerComponent 8 /Filter /FlateDecode", item.image.width, item.image.height, encoded.isGray ? "Gray" : "RGB")
            if maskObject and encoded.alpha.count do
                dictionary.appendFormat(" /SMask % 0 R", maskObject)
            writer.streamObject(objects.images[imageIndex], samples.toSlice(), dictionary.toString())

            if maskObject
            {
                // An opaque channel still needs an object when one was reserved, so the
                // cross-reference table keeps one entry per reserved number.
                var alpha = encoded.alpha
                if !alpha.count
                {
                    alpha.resize(cast(u64) item.image.width * cast(u64) item.image.height)
                    for i in alpha.count do
                        alpha[i] = 0xFF
                }

                var maskZlib: Compress.ZLib
                let maskData = #move try maskZlib.compress(alpha.toSlice())
                let maskDict = Format.toString("/Type /XObject /Subtype /Image /Width % /Height % /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode", item.image.width, item.image.height)
                writer.streamObject(maskObject, maskData.toSlice(), maskDict.toString())
            }

            imageIndex += 1
        }
    }

    let xref = writer.bytes.count
    writer.append(Format.toString("xref\n0 %\n", nextObject).toString())
    writer.append("0000000000 65535 f \n")
    for number in 1'u32 until nextObject do
        writer.append(Format.toString("%{D010} 00000 n \n", writer.offsets[number]).toString())
    writer.append(Format.toString("trailer\n<< /Size % /Root % 0 R /Info % 0 R >>\nstartxref\n%\n%%EOF\n", nextObject, CatalogObject, InfoObject, xref).toString())
    return #move writer.bytes
}
