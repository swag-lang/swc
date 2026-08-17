using Core, Core.Errors, Core.Math, Pixel

private struct PageObjects
{
    page:    u32
    content: u32
    images:  Array'u32
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
        if @countof(dictionary)
        {
            .append(dictionary)
            .append(" ")
        }

        .append(Format.toString("/Length % >>\nstream\n", @countof(data)).toString())
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
            fail UnsupportedFormatError{"PDF Helvetica output cannot encode this Unicode character"}
    }

    return result
}

private func appendPdfString(result: *String, text: string) fail
{
    let encoded = try windows1252(text)
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
    }

    if item.hasFill and item.hasStroke do
        result[] += "B\n"
    elif item.hasFill do
        result[] += "f\n"
    else do
        result[] += "S\n"
}

private func pageContent(page: const *Page)->String fail
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
            result.appendFormat("BT\n/F0 % Tf\n% % % % % % Tm\n", pdfNumber(item.fontSize), pdfNumber(item.transform.m11), pdfNumber(-item.transform.m12), pdfNumber(-item.transform.m21), pdfNumber(item.transform.m22), pdfNumber(baseline.x), pdfNumber(page.height - baseline.y))
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

private func imageRgb(image: const *Image)->Array'u8
{
    var result: retval
    let count = cast(u64) image.width * cast(u64) image.height
    result.resize(count * 3)
    for y in cast(u64) image.height
    {
        let sourceY = cast(u64) image.height - y - 1
        for x in cast(u64) image.width
        {
            let src = (sourceY * cast(u64) image.width + x) * image.bytesPerPixel
            let dst = (y * cast(u64) image.width + x) * 3
            switch image.pixelFormat
            {
            case .RGB8, .RGBA8:
                result[dst + 0] = image.pixels[src + 0]
                result[dst + 1] = image.pixels[src + 1]
                result[dst + 2] = image.pixels[src + 2]

            case .BGR8, .BGRA8:
                result[dst + 0] = image.pixels[src + 2]
                result[dst + 1] = image.pixels[src + 1]
                result[dst + 2] = image.pixels[src + 0]
            }
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
    for field in fields where @countof(field.value)
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
    const FontObject    = 3'u32
    const InfoObject    = 4'u32
    var nextObject = 5'u32
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
            discard item
            objects.images.add(nextObject)
            nextObject += 1
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

    writer.beginObject(FontObject)
    writer.append("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>\n")
    writer.endObject()

    writer.beginObject(InfoObject)
    writer.append(try infoDictionary(&document.metadata))
    writer.endObject()

    for page, pageIndex in document.pages
    {
        let objects = &layout[pageIndex]
        writer.beginObject(objects.page)
        writer.append(Format.toString("<< /Type /Page /Parent % 0 R /MediaBox [0 0 % %] /Resources << /Font << /F0 % 0 R >>", PagesObject, pdfNumber(page.width), pdfNumber(page.height), FontObject).toString())
        if objects.images.count
        {
            writer.append(" /XObject <<")
            for imageObject, imageIndex in objects.images do
                writer.append(Format.toString(" /Im% % 0 R", imageIndex, imageObject).toString())
            writer.append(" >>")
        }

        writer.append(Format.toString(" >> /Contents % 0 R >>\n", objects.content).toString())
        writer.endObject()

        let content    = try pageContent(page)
        var zlib: Compress.ZLib
        let compressed = try zlib.compress(cast(const [..] u8) content)
        writer.streamObject(objects.content, compressed.toSlice(), "/Filter /FlateDecode")

        var imageIndex = 0'u64
        for item in page.items where item.kind == .Image
        {
            let rgb        = imageRgb(&item.image)
            var imageZlib: Compress.ZLib
            let encoded    = try imageZlib.compress(rgb.toSlice())
            let dictionary = Format.toString("/Type /XObject /Subtype /Image /Width % /Height % /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /FlateDecode", item.image.width, item.image.height)
            writer.streamObject(objects.images[imageIndex], encoded.toSlice(), dictionary.toString())
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
