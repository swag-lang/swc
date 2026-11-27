#global namespace Pdf

using Core, Core.Errors, Core.Math, Pixel

private const CatalogObject = 1_u32
private const PagesObject   = 2_u32
private const InfoObject    = 3_u32

private struct ImageObject
{
    number:   u32
    firstUse: bool
}

private struct ImageSource
{
    number:  u32
    image:   const *Image
    encoded: const *EncodedImageStream
}

private struct ImageSources
{
    byChecksum:   HashTable!{u32, ImageSource}
    byImage:      HashTable!{u64, u32}
    encodedBytes: u64
}

private struct PageObjects
{
    page:    u32
    content: u32
    images:  Array!{ImageObject}
}

// One image reduced to what the writer stores: gray or RGB samples, plus coverage.
private struct EncodedImage
{
    samples: Array!{u8}
    alpha:   Array!{u8}
    bitsPerComponent: u8 = 8
    isGray:  bool
}

private struct Writer
{
    bytes:   Array!{u8}
    offsets: Array!{u64}
    flushed: u64
    zlib:    Compress.ZLib
}

private impl Writer
{
    mtd append(text: string)
    {
        .bytes.add(cast(const [..] u8, text))
    }

    mtd const position()->u64 => .flushed + .bytes.count

    mtd flush(file: *File.FileStream) fail
    {
        try file.writeAll(.bytes.toSlice())
        .flushed += .bytes.count
        .bytes.clear()
    }

    mtd beginObject(number: u32)
    {
        if number >= .offsets.count
        {
            .offsets.resize(cast(u64, number) + 1)
        }

        .offsets[number] = .position()
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

private func appendPdfNumber(result: *String, value: f32)
{
    let magnitude = Math.abs(value)
    if not (magnitude < 1e9)
    {
        var text = Format.toString("%{f4}", value)
        while text.endsWith("0")
        {
            text.removeBack(1)
        }

        if text.endsWith(".")
        {
            text.removeBack(1)
        }

        result.append(text.toString())
        return
    }

    // Scaling a 24-bit significand by 10,000 is exact in f64. Round ties to even.
    let scaled    = cast(f64, magnitude) * 10000.0
    var units     = cast(u64, scaled)
    let remainder = scaled - cast(f64, units)
    if remainder > 0.5 or (remainder == 0.5 and units & 1 != 0)
    {
        units += 1
    }

    var digits: [16] u8
    var start      = cast(u64, digits.count)
    var fractional = units % 10000
    if fractional
    {
        for 4
        {
            let digit = fractional % 10
            if digit or start < digits.count
            {
                start         -= 1
                digits[start] = '0'_u8 + cast(u8, digit)
            }

            fractional /= 10
        }

        start         -= 1
        digits[start] = '.'_u8
    }

    var whole = units / 10000
    while true
    {
        start         -= 1
        digits[start] = '0'_u8 + cast(u8, whole % 10)
        whole         /= 10
        if not whole
        {
            break
        }
    }

    if value < 0
    {
        start         -= 1
        digits[start] = '-'_u8
    }

    result.append(Swag.makeString(&digits[start], digits.count - start))
}

private func pdfNumber(value: f32)->String
{
    var result: #returntype
    appendPdfNumber(&result, value)
    return result
}

private func appendPdfPoint(result: *String, point: Vector2, suffix: string)
{
    appendPdfNumber(result, point.x)
    result[] += ' '
    appendPdfNumber(result, point.y)
    result[] += suffix
}

private func appendPdfMatrix(result: *String, transform: Transform2)
{
    appendPdfPoint(result, {transform.m11, -transform.m12}, " ")
    appendPdfPoint(result, {-transform.m21, transform.m22}, " ")
}

private func windows1252Byte(c: rune)->u8 fail
{
    if c <= 0x7F or (c >= 0xA0 and c <= 0xFF)
    {
        return cast(u8, c)
    }

    for value in 0x80_u32 to 0x9F where Text.windows1252Rune(cast(u8, value)) == c
    {
        return cast(u8, value)
    }

    fail UnsupportedFormatError{"PDF text output cannot encode this Unicode character"}
}

private func appendPdfString(result: *String, text: string) fail
{
    result[] += '('
    var first, offset: u64
    while offset < text.count
    {
        let byte = text[offset]
        if byte < 0x80 and
           byte != '(' and
           byte != ')' and
           byte != '\\' and
           byte != '\n' and
           byte != '\r' and
           byte != '\t'
        {
            offset += 1
            continue
        }

        result[] += text[first until offset]
        switch byte
        {
        case '(', ')', '\\':
            result[] += '\\'
            result[] += byte
            offset   += 1

        case '\n':
            result[] += "\\n"
            offset   += 1

        case '\r':
            result[] += "\\r"
            offset   += 1

        case '\t':
            result[] += "\\t"
            offset   += 1

        default:
            let {c, eat} = Utf8.decodeRune(text[offset until text.count])
            result[] += try windows1252Byte(c)
            offset   += eat
        }

        first = offset
    }

    result[] += text[first until text.count]
    result[] += ')'
}

private func appendColor(result: *String, color: Color, stroke: bool)
{
    appendPdfNumber(result, color.r / 255.0)
    result[] += ' '
    appendPdfNumber(result, color.g / 255.0)
    result[] += ' '
    appendPdfNumber(result, color.b / 255.0)
    result[] += stroke ? " RG\n" : " rg\n"
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
        if index
        {
            result[] += ' '
        }

        appendPdfNumber(result, length)
    }

    result.appendFormat("] % d\n", pdfNumber(item.strokeStyle.dashPhase))
}

private func encodedPoint(page: const *Page, item: const *Item, point: Vector2)->Vector2
{
    let transformed = item.transform.transformPoint(point)
    return Math.Vector2{transformed.x, page.height - transformed.y}
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
                appendPdfPoint(result, encoded, index == 0 ? " m\n" : " l\n")
            }

            if path.isClosed
            {
                result[] += "h\n"
            }

            continue
        }

        let start        = path.startPoint
        let encodedStart = encodedPoint(page, item, start)
        appendPdfPoint(result, encodedStart, " m\n")
        var current = start
        for element in path.elements
        {
            switch element.type
            {
            case .Line:
                let p = encodedPoint(page, item, element.position)
                appendPdfPoint(result, p, " l\n")

            case .Bezier1:
                let c1x = current.x + 2.0 / 3.0 * (element.p1.x - current.x)
                let c1y = current.y + 2.0 / 3.0 * (element.p1.y - current.y)
                let c2x = element.position.x + 2.0 / 3.0 * (element.p1.x - element.position.x)
                let c2y = element.position.y + 2.0 / 3.0 * (element.p1.y - element.position.y)
                let c1  = encodedPoint(page, item, Math.Vector2{c1x, c1y})
                let c2  = encodedPoint(page, item, Math.Vector2{c2x, c2y})
                let p   = encodedPoint(page, item, element.position)
                appendPdfPoint(result, c1, " ")
                appendPdfPoint(result, c2, " ")
                appendPdfPoint(result, p, " c\n")

            case .Bezier2:
                let c1 = encodedPoint(page, item, element.p1)
                let c2 = encodedPoint(page, item, element.p2)
                let p  = encodedPoint(page, item, element.position)
                appendPdfPoint(result, c1, " ")
                appendPdfPoint(result, c2, " ")
                appendPdfPoint(result, p, " c\n")

            default:
                break
            }

            current = element.position
        }

        if path.isClosed
        {
            result[] += "h\n"
        }
    }

    if item.hasFill
    {
        appendColor(result, item.fillColor, false)
    }

    if item.hasStroke
    {
        appendColor(result, item.strokeColor, true)
        appendPdfNumber(result, item.strokeWidth)
        result[] += " w\n"
        appendStrokeStyle(result, item)
    }

    if item.hasFill and item.hasStroke
    {
        result[] += "B\n"
    }
    else if item.hasFill
    {
        result[] += "f\n"
    }
    else
    {
        result[] += "S\n"
    }
}

// Returns the index each standard face occupies in the shared font resource dictionary.
private func documentFonts(document: const *Document)->Array!{StandardFont}
{
    var result: #returntype
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

            if not found
            {
                result.add(item.standardFont)
            }
        }
    }

    return result
}

private func fontSlot(fonts: const [..] StandardFont, font: StandardFont)->u64
{
    for candidate, index in fonts where candidate == font
    {
        return index
    }

    return 0
}

private func pageContent(page: const *Page, fonts: const [..] StandardFont)->String fail
{
    var result: #returntype
    var imageIndex = 0_u32
    for item in page.items
    {
        switch item.kind
        {
        case .Text:
            appendColor(&result, item.fillColor, false)
            let baseline = item.transform.transformPoint(Math.Vector2{0, item.fontSize})
            result.appendFormat("BT\n/F% ", fontSlot(fonts, item.standardFont))
            appendPdfNumber(&result, item.fontSize)
            result += " Tf\n"
            appendPdfMatrix(&result, item.transform)
            appendPdfPoint(&result, {baseline.x, page.height - baseline.y}, " Tm\n")
            if item.invisibleText
            {
                result += "3 Tr\n"
            }

            try appendPdfString(&result, item.text.toString())
            result += item.invisibleText ? " Tj\n0 Tr\nET\n" : " Tj\nET\n"

        case .Path:
            appendPath(&result, page, item)

        case .Image:
            let tr = item.transform
            result += "q\n"
            appendPdfMatrix(&result, tr)
            appendPdfPoint(&result, {tr.tx + tr.m21, page.height - tr.ty - tr.m22}, " cm\n")
            result.appendFormat("/Im% Do\nQ\n", imageIndex)
            imageIndex += 1
        }
    }

    return result
}

// Writes gray or RGB samples in PDF row order and keeps any non-opaque coverage.
private func encodeImagePixels(image: const *Image)->EncodedImage
{
    var result: #returntype
    let width       = cast(u64, image.width)
    let height      = cast(u64, image.height)
    let sourceStep  = cast(u64, image.bytesPerPixel)
    let source      = image.pixels.storage()
    let nativeGray  = image.pixelFormat == .Gray8 or image.pixelFormat == .GrayAlpha8
    let grayChannel = nativeGray ? 0_u64 : 1_u64
    let swapRedBlue = image.pixelFormat == .BGR8 or image.pixelFormat == .BGRA8
    let hasAlpha    = image.pixelFormat == .BGRA8 or image.pixelFormat == .RGBA8 or image.pixelFormat == .GrayAlpha8

    result.isGray = true
    var bilevel     = true
    var transparent = false
    var pixel       = source
    for width * height
    {
        let gray = pixel[grayChannel]
        if not nativeGray and (pixel[0] != gray or pixel[2] != gray)
        {
            result.isGray = false
        }

        if gray != 0 and gray != 255
        {
            bilevel = false
        }

        if hasAlpha and pixel[sourceStep - 1] != 255
        {
            transparent = true
        }

        if not result.isGray and (not hasAlpha or transparent)
        {
            break
        }

        pixel += sourceStep
    }

    let packBits   = result.isGray and bilevel
    let components = result.isGray ? 1_u64 : 3_u64
    let rowBytes   = packBits ? (width + 7) / 8 : width * components
    result.bitsPerComponent = packBits ? 1 : 8
    result.samples.resize(rowBytes * height)
    if transparent
    {
        result.alpha.resize(width * height)
    }

    for y in height
    {
        let row = source + (height - y - 1) * width * sourceStep
        let out = result.samples.storage() + y * rowBytes
        if packBits
        {
            for x in width
            {
                let bit = row[x * sourceStep + grayChannel] >> 7
                out[x >> 3] |= bit << (7 - cast(u8, x & 7))
            }
        }
        else if result.isGray
        {
            if sourceStep == 1
            {
                Memory.copy(out, row, rowBytes)
            }
            else
            {
                for x in width
                {
                    out[x] = row[x * sourceStep + grayChannel]
                }
            }
        }
        else if image.pixelFormat == .RGB8
        {
            Memory.copy(out, row, rowBytes)
        }
        else
        {
            for x in width
            {
                let src = row + x * sourceStep
                let dst = out + x * 3
                dst[0] = src[swapRedBlue ? 2 : 0]
                dst[1] = src[1]
                dst[2] = src[swapRedBlue ? 0 : 2]
            }
        }

        if transparent
        {
            let coverage = result.alpha.storage() + y * width
            for x in width
            {
                coverage[x] = row[x * sourceStep + sourceStep - 1]
            }
        }
    }

    return result
}

// Samples adjacent pixels at several positions. Smooth channels become a narrow residual
// distribution, which gives Deflate more matches and cheaper literals.
private func preferSubPredictor(samples: const [..] u8, rowBytes, components: u64)->bool
{
    if samples.count < 256 * 1024 or rowBytes < components * 16
    {
        return false
    }

    func distance(value: s32)->s32
    {
        let magnitude = Math.abs(value)
        return Math.min(magnitude, 256 - magnitude)
    }

    let rows = samples.count / rowBytes
    var sourceTotal, residualTotal: s32
    for y in 8
    {
        let row = samples.buffer + (y * rows / 8) * rowBytes
        for x in 8
        {
            let pixel    = row + (1 + x * (rowBytes / components - 1) / 8) * components
            let previous = pixel - components
            for c in components
            {
                let value = cast(s32, pixel[c])
                sourceTotal   += distance(value)
                residualTotal += distance(value - cast(s32, previous[c]))
            }
        }
    }

    return sourceTotal and residualTotal * 4 < sourceTotal
}

private func compressImageSamples(zlib: *Compress.ZLib, samples: const [..] u8, width, components: u64, bits = 8_u8)->{bytes: Array!{u8}, predicted: bool} fail
{
    var result:    #returntype
    let rowBytes = width * components
    var residuals: Array!{u8}
    var input    = samples
    if bits == 8 and preferSubPredictor(samples, rowBytes, components)
    {
        residuals.resize(samples.count + samples.count / rowBytes)
        Swag.require(Pixel.Png.filterSubPredictorRows(samples, residuals.toSlice(), rowBytes, components))
        result.predicted = true
        input = residuals.toSlice()
    }

    // The predictor lowers entropy enough that a short greedy match search still saves space.
    const PredictorLevel = cast(Compress.Deflate.CompressionLevel, 2)
    result.bytes = #move try zlib.compress(input, result.predicted ? PredictorLevel : .Default)
    return result
}

private func infoDictionary(metadata: const *Metadata)->String fail
{
    var result: #returntype = "<<"
    let fields: [6] { name: string, value: string } = [
        {name: "Title",    value: metadata.title.toString()},
        {name: "Author",   value: metadata.author.toString()},
        {name: "Subject",  value: metadata.subject.toString()},
        {name: "Keywords", value: metadata.keywords.toString()},
        {name: "Creator",  value: metadata.creator.toString()},
        {name: "Producer", value: metadata.producer.toString()}]
    for field in fields where field.value.count
    {
        result.appendFormat(" /% ", field.name)
        try appendPdfString(&result, field.value)
    }

    result += " >>\n"
    return result
}

// One document keeps its source pages alive until every image reference has been written.
private func sameImageSource(first, second: const *Image)->bool
{
    return first.pixelFormat == second.pixelFormat and
           first.alphaMode == second.alphaMode and
           first.width == second.width and
           first.height == second.height and
           first.pixels.count == second.pixels.count and
           not Memory.compare(first.pixels.storage(), second.pixels.storage(), first.pixels.count)
}

private func sameFaxParameters(first, second: const *EncodedFaxParameters)->bool
{
    return first.k == second.k and
           first.rows == second.rows and
           first.damagedRows == second.damagedRows and
           first.blackIs1 == second.blackIs1 and
           first.byteAlign == second.byteAlign and
           first.endOfLine == second.endOfLine and
           first.endOfBlock == second.endOfBlock
}

private func sameEncodedImage(first, second: const *EncodedImageStream, image, prior: const *Image)->bool
{
    return first.filter == second.filter and
           first.channels == second.channels and
           first.bits == second.bits and
           first.predictor == second.predictor and
           first.interpolate == second.interpolate and
           image.width == prior.width and
           image.height == prior.height and
           (first.filter != .Ccitt or sameFaxParameters(&first.fax, &second.fax)) and
           Slice.equals(first.bytes.toSlice(), second.bytes.toSlice())
}

private func allocateImageObject(item: const *Item, nextObject: *u32, sources: *ImageSources?)->ImageObject
{
    if not sources
    {
        let result = ImageObject{nextObject[], true}
        nextObject[] += 1
        return result
    }

    let image    = unwrap item.imageValue()
    let identity = cast(u64, cast(const *void, image))
    if let known = sources.byImage.tryFind(identity)
    {
        return {number: known.value, firstUse: false}
    }

    let encoded = item.image.encoded()
    let key     = Hash.Crc32.compute(encoded.bytes.count ? encoded.bytes.toSlice() : image.pixels.toSlice())

    // Compare contents and metadata too, since separate image owners may hold the same data.
    if let source = sources.byChecksum.tryFind(key)
    {
        let prior = &source.value
        let same  = (encoded.bytes.count or prior.encoded.bytes.count) ?
                    sameEncodedImage(encoded, prior.encoded, image, prior.image) : sameImageSource(image, prior.image)
        if same
        {
            sources.byImage.add(identity, prior.number)
            return {number: prior.number, firstUse: false}
        }
    }
    else
    {
        sources.byChecksum.add(key, ImageSource{nextObject[], image, encoded})
    }

    let result = ImageObject{nextObject[], true}
    sources.encodedBytes += encoded.bytes.count
    sources.byImage.add(identity, result.number)
    nextObject[] += 1
    return result
}

private func allocatePageObjects(page: const *Page, nextObject: *u32, sources: *ImageSources? = null)->PageObjects fail
{
    if page.width <= 0 or
       page.height <= 0 or
       not Math.isFinite(page.width) or
       not Math.isFinite(page.height)
    {
        fail BadParameterError{}
    }

    var objects: #returntype
    objects.page    = nextObject[]
    nextObject[]    += 1
    objects.content = nextObject[]
    nextObject[]    += 1
    for item in page.items where item.kind == .Image
    {
        objects.images.add(allocateImageObject(item, nextObject, sources))
    }

    return objects
}

private impl Writer
{
    mtd writeHeader()
    {
        .append("%PDF-1.7\n")
        .bytes.add([0x25_u8, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A])
        .beginObject(CatalogObject)
        .append("<< /Type /Catalog /Pages 2 0 R >>\n")
        .endObject()
    }

    mtd writeTrailer(nextObject: u32)
    {
        let xref = .position()
        .append(Format.toString("xref\n0 %\n", nextObject).toString())
        .append("0000000000 65535 f \n")

        // Classic in-use entries occupy 20 bytes, including the final line feed.
        var entry: [20] u8
        const InUse = " 00000 n \n"
        Memory.copy(&entry[10], InUse.buffer, InUse.count)
        for number in 1_u32 until nextObject
        {
            var offset = .offsets[number]
            if offset >= 10_000_000_000_u64
            {
                .append(Format.toString("%{D010} 00000 n \n", offset).toString())
                continue
            }

            for digit in 10
            {
                entry[9 - digit] = '0'_u8 + cast(u8, offset % 10)
                offset /= 10
            }

            .bytes.add(cast(const [..] u8, entry))
        }

        .append(Format.toString("trailer\n<< /Size % /Root % 0 R /Info % 0 R >>\nstartxref\n%\n%%EOF\n", nextObject, CatalogObject, InfoObject, xref).toString())
    }

    mtd writePage(page: const *Page, objects: const *PageObjects, fonts: const [..] StandardFont, fontObjects: const [..] u32, nextObject: *u32) fail
    {
        .beginObject(objects.page)
        .append(Format.toString("<< /Type /Page /Parent % 0 R /MediaBox [0 0 % %] /Resources <<", PagesObject, pdfNumber(page.width), pdfNumber(page.height)).toString())
        if fontObjects.count
        {
            .append(" /Font <<")
            for fontObject, fontIndex in fontObjects
            {
                .append(Format.toString(" /F% % 0 R", fontIndex, fontObject).toString())
            }

            .append(" >>")
        }

        if objects.images.count
        {
            .append(" /XObject <<")
            for imageObject, imageIndex in objects.images
            {
                .append(Format.toString(" /Im% % 0 R", imageIndex, imageObject.number).toString())
            }

            .append(" >>")
        }

        .append(Format.toString(" >> /Contents % 0 R >>\n", objects.content).toString())
        .endObject()

        let content    = #move try pageContent(page, fonts)
        let compressed = #move try .zlib.compress(cast(const [..] u8, content))
        .streamObject(objects.content, compressed.toSlice(), "/Filter /FlateDecode")

        var imageIndex = 0_u64
        for item in page.items where item.kind == .Image
        {
            let imageObject = objects.images[imageIndex]
            imageIndex += 1
            if not imageObject.firstUse
            {
                continue
            }

            let image  = unwrap item.imageValue()
            let source = item.image.encoded()
            if source.bytes.count
            {
                let space      = source.channels == 1 ? "Gray" : (source.channels == 4 ? "CMYK" : "RGB")
                let filter     = source.filter == .Dct ? "DCTDecode" : (source.filter == .Ccitt ? "CCITTFaxDecode" : "FlateDecode")
                var dictionary = Format.toString("/Type /XObject /Subtype /Image /Width % /Height % /ColorSpace /Device% /BitsPerComponent % /Filter /%", image.width, image.height, space, source.bits, filter)
                if source.filter == .Ccitt
                {
                    let fax = &source.fax
                    dictionary.appendFormat(" /DecodeParms << /K % /Columns %", fax.k, image.width)
                    if fax.rows >= 0
                    {
                        dictionary.appendFormat(" /Rows %", fax.rows)
                    }

                    if fax.blackIs1
                    {
                        dictionary += " /BlackIs1 true"
                    }

                    if fax.byteAlign
                    {
                        dictionary += " /EncodedByteAlign true"
                    }

                    if fax.endOfLine
                    {
                        dictionary += " /EndOfLine true"
                    }

                    if not fax.endOfBlock
                    {
                        dictionary += " /EndOfBlock false"
                    }

                    if fax.damagedRows
                    {
                        dictionary.appendFormat(" /DamagedRowsBeforeError %", fax.damagedRows)
                    }

                    dictionary += " >>"
                }
                else if source.predictor > 1
                {
                    dictionary.appendFormat(" /DecodeParms << /Predictor % /Colors % /Columns % /BitsPerComponent % >>", source.predictor, source.channels, image.width, source.bits)
                }

                if source.interpolate
                {
                    dictionary += " /Interpolate true"
                }

                .streamObject(imageObject.number, source.bytes.toSlice(), dictionary.toString())
                continue
            }

            let encoded    = encodeImagePixels(image)
            let width      = cast(u64, image.width)
            let components = encoded.isGray ? 1_u64 : 3_u64
            let samples    = #move try compressImageSamples(&.zlib, encoded.samples.toSlice(), width, components, encoded.bitsPerComponent)
            var maskObject: u32
            if encoded.alpha.count
            {
                maskObject   = nextObject[]
                nextObject[] += 1
            }

            var dictionary = Format.toString("/Type /XObject /Subtype /Image /Width % /Height % /ColorSpace /Device% /BitsPerComponent % /Filter /FlateDecode", image.width, image.height, encoded.isGray ? "Gray" : "RGB", encoded.bitsPerComponent)
            if maskObject
            {
                dictionary.appendFormat(" /SMask % 0 R", maskObject)
            }

            if samples.predicted
            {
                dictionary.appendFormat(" /DecodeParms << /Predictor 15 /Colors % /Columns % >>", components, width)
            }

            .streamObject(imageObject.number, samples.bytes.toSlice(), dictionary.toString())

            if maskObject
            {
                let maskData = #move try compressImageSamples(&.zlib, encoded.alpha.toSlice(), width, 1)
                var maskDict = Format.toString("/Type /XObject /Subtype /Image /Width % /Height % /ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /FlateDecode", image.width, image.height)
                if maskData.predicted
                {
                    maskDict.appendFormat(" /DecodeParms << /Predictor 15 /Colors 1 /Columns % >>", width)
                }

                .streamObject(maskObject, maskData.bytes.toSlice(), maskDict.toString())
            }
        }
    }
}

// Streams generated pages through the same object encoder. Only the current page, its encoded
// bytes, and the cross-reference and page-tree indexes need to be retained.
internal func writeGeneratedDocument(file: *File.FileStream, count: u64, source: func||(u64)->Page fail) fail
{
    if not count or count > cast(u64, Swag.U32.Max - 4) / 4
    {
        fail BadParameterError{}
    }

    var writer: Writer
    writer.writeHeader()
    writer.beginObject(InfoObject)
    writer.append("<< >>\n")
    writer.endObject()

    var nextObject = 4_u32
    var pages:         Array!{u32}
    let noFonts:       Array!{StandardFont}
    let noFontObjects: Array!{u32}
    for i in count
    {
        let page    = #move try source(i)
        let objects = #move try allocatePageObjects(&page, &nextObject)
        try writer.writePage(&page, &objects, noFonts.toSlice(), noFontObjects.toSlice(), &nextObject)
        try writer.flush(file)
        pages.add(objects.page)
    }

    writer.beginObject(PagesObject)
    writer.append(Format.toString("<< /Type /Pages /Count % /Kids [", count).toString())
    for number in pages
    {
        writer.append(Format.toString(" % 0 R", number).toString())
    }

    writer.append(" ] >>\n")
    writer.endObject()
    writer.writeTrailer(nextObject)
    try writer.flush(file)
}

func encodeDocument(document: const *Document)->Array!{u8} fail
{
    if not document.pages.count
    {
        fail BadParameterError{}
    }

    var nextObject = 4_u32

    let fonts = documentFonts(document)
    var fontObjects: Array!{u32}
    for fonts
    {
        fontObjects.add(nextObject)
        nextObject += 1
    }

    var layout:       Array!{PageObjects}
    var imageSources: ImageSources
    for page in document.pages
    {
        let objects = #move try allocatePageObjects(page, &nextObject, &imageSources)
        layout.add(#move objects)
    }

    var writer: Writer

    // Reserve the preserved streams plus room for their dictionaries and the page tree.
    if imageSources.encodedBytes >= 65536
    {
        let overhead = Math.min(65536_u64, cast(u64, nextObject) * 512)
        writer.bytes.reserve(imageSources.encodedBytes + overhead)
    }

    writer.offsets.resize(nextObject)
    writer.writeHeader()

    writer.beginObject(PagesObject)
    writer.append(Format.toString("<< /Type /Pages /Count % /Kids [", document.pages.count).toString())
    for objects in layout
    {
        writer.append(Format.toString(" % 0 R", objects.page).toString())
    }

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
        try writer.writePage(page, objects, fonts.toSlice(), fontObjects.toSlice(), &nextObject)
    }

    writer.writeTrailer(nextObject)
    return #move writer.bytes
}
