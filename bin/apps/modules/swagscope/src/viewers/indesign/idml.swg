#global internal

using Core, Core.Errors

// IDML is an InDesign document package rather than a preview image. These bounds keep a damaged
// package from turning a simple document inspection into an unbounded decompression operation.
private const IdmlDocumentByteLimit = 128 * 1024 * 1024'u64
private const IdmlPageLimit         = 2_000'u64
private const IdmlSpreadLimit       = 1_000'u64
private const IdmlFrameLimit        = 100_000'u64

private struct IdmlBounds
{
    left, top:     f32
    width, height: f32
}

private struct IdmlTransform
{
    a, d: f32 = 1
    b, c: f32
    x, y: f32
}

private struct IdmlItem
{
    bounds:     IdmlBounds
    text:       String
    fill:       String
    stroke:     String
    strokeSize: f32
    oval:       bool
    line:       bool
    clipPath:   String
}

private struct IdmlTextStyle
{
    fontSize:  f32
    fill:      String
    alignment: String
    serif:     bool
}

struct IdmlPage
{
    name:            String
    master:          String
    bounds:          IdmlBounds
    items:           Array'IdmlItem
    textFrameCount:  u64
}

private struct IdmlMaster
{
    self:  String
    pages: Array'IdmlPage
}

impl IdmlPage
{
    // Builds one offline page scene from positioned IDML items. The HTML engine is used solely as
    // the local paint and text-layout backend; all package parsing and scene construction are Swag.
    mtd html()->String
    {
        var result: retval
        result += "<style>html,body{margin:0;padding:0;background:#343438}.idml-page{position:relative;margin:24px auto;background:#fff;color:#101014;box-shadow:0 2px 12px #0008;overflow:hidden}.idml-item{position:absolute;box-sizing:border-box;overflow:hidden;white-space:pre-wrap;font:12px/1.25 sans-serif;padding:2px}</style>"
        result += Format.toString("<div class=\"idml-page\" style=\"width:%px;height:%px\">", .bounds.width, .bounds.height)
        for item in .items
        {
            result += Format.toString("<div class=\"idml-item\" style=\"left:%px;top:%px;width:%px;height:%px;background:%;border:%px solid %;%;%\">",
                                      item.bounds.left,
                                      item.bounds.top,
                                      item.bounds.width,
                                      item.bounds.height,
                                      item.line ? (item.stroke.isEmpty() ? "transparent" : item.stroke.toString()) : (item.fill.isEmpty() ? "transparent" : item.fill.toString()),
                                      item.line ? 0 : item.strokeSize,
                                      item.stroke.isEmpty() ? "transparent" : item.stroke.toString(),
                                      item.oval ? "border-radius:50%" : "",
                                      item.clipPath)
            // Text is escaped while the IDML story is converted to local paragraph markup. It is
            // deliberately not a document-supplied HTML fragment.
            result += item.text
            result += "</div>"
        }

        result += "</div>"
        return result
    }
}

struct IdmlDocument
{
    fileName: String
    pages:    Array'IdmlPage
}

private func idmlFindEntry(archive: const *ZipArchive, path: string)->#null const *ZipEntry
{
    for entry in archive.entries where entry.path == path do
        return entry
    return null
}

private func idmlReadEntry(fileName: string, archive: const *ZipArchive, path: string)->String fail
{
    let entry = idmlFindEntry(archive, path)
    if !entry or entry!.isDirectory do
        fail InvalidFormatError{Errors.mkString(Format.toString("IDML package is missing '%'", path).toString())}
    let bytes = try loadZipEntry(fileName, entry!)
    if !Utf8.isValid(bytes.toSlice()) do
        fail InvalidFormatError{Errors.mkString(Format.toString("IDML entry '%' is not UTF-8 XML", path).toString())}
    return String.from(Swag.makeString(bytes.buffer!, bytes.count))
}

private func idmlAttribute(tag: string, name: string)->string
{
    var marker: String
    marker += name
    marker += "=\""
    let start = Utf8.indexOf(tag, marker.toString())
    if start == Swag.U64.Max do
        return ""
    let valueStart = start + marker.count
    let valueEnd   = Utf8.indexOf(tag, '"'rune, valueStart)
    if valueEnd == Swag.U64.Max do
        return ""
    return tag[valueStart until valueEnd]
}

private func idmlNumber(text: string)->{ value: f32, valid: bool }
{
    let trimmed = Latin1.trim(text)
    if !trimmed.count do
        return {}
    let parsed = catch StrConv.parseF32(trimmed) as parseError
    if parseError != null or parsed.eat != trimmed.count or parsed.ovf do
        return {}
    return {parsed.value, true}
}

private func idmlNumbers(text: string, result: *Array'f32)->bool
{
    result.clear()
    for part in Tokenize.split(text, ' 'rune)
    {
        let number = idmlNumber(part)
        if !number.valid do
            return false
        result.add(number.value)
    }

    return !result.isEmpty()
}

private func idmlBoundsFromGeometric(value: string, result: *IdmlBounds)->bool
{
    var numbers: Array'f32
    if !idmlNumbers(value, &numbers) or numbers.count != 4 do
        return false
    result.top    = numbers[0]
    result.left   = numbers[1]
    result.height = numbers[2] - numbers[0]
    result.width  = numbers[3] - numbers[1]
    return result.width > 0 and result.height > 0
}

private func idmlTransform(tag: string)->IdmlTransform
{
    var result: retval
    let transform = idmlAttribute(tag, "ItemTransform")
    if !transform.count do
        return result
    var numbers: Array'f32
    if !idmlNumbers(transform, &numbers) or numbers.count != 6 do
        return result
    result.a = numbers[0]
    result.b = numbers[1]
    result.c = numbers[2]
    result.d = numbers[3]
    result.x = numbers[4]
    result.y = numbers[5]
    return result
}

private func idmlComposeTransform(parent, child: const *IdmlTransform)->IdmlTransform
{
    var result: retval
    result.a = parent.a * child.a + parent.c * child.b
    result.b = parent.b * child.a + parent.d * child.b
    result.c = parent.a * child.c + parent.c * child.d
    result.d = parent.b * child.c + parent.d * child.d
    result.x = parent.a * child.x + parent.c * child.y + parent.x
    result.y = parent.b * child.x + parent.d * child.y + parent.y
    return result
}

private func idmlBoundsFromPath(item: string, transform: const *IdmlTransform, result: *IdmlBounds, allowLine = false)->bool
{
    var left = Swag.F32.Max
    var top  = Swag.F32.Max
    var right = -Swag.F32.Max
    var bottom = -Swag.F32.Max
    var cursor = 0'u64
    var points: u64
    while true
    {
        let pointStart = Utf8.indexOf(item, "<PathPointType", cursor)
        if pointStart == Swag.U64.Max do
            break
        let pointEnd = Utf8.indexOf(item, '>'rune, pointStart)
        if pointEnd == Swag.U64.Max do
            return false
        let tag    = item[pointStart until pointEnd + 1]
        let anchor = idmlAttribute(tag, "Anchor")
        var values: Array'f32
        if !idmlNumbers(anchor, &values) or values.count != 2 do
            return false
        let x = transform.a * values[0] + transform.c * values[1] + transform.x
        let y = transform.b * values[0] + transform.d * values[1] + transform.y
        left   = Math.min(left, x)
        right  = Math.max(right, x)
        top    = Math.min(top, y)
        bottom = Math.max(bottom, y)
        points += 1
        cursor = pointEnd + 1
    }

    if points < 2 or (!allowLine and (right <= left or bottom <= top)) do
        return false
    result.left   = left
    result.top    = top
    result.width  = allowLine ? Math.max(right - left, 1) : right - left
    result.height = allowLine ? Math.max(bottom - top, 1) : bottom - top
    return true
}

private func idmlPolygonClipPath(item: string, transform: const *IdmlTransform)->String
{
    var bounds: IdmlBounds
    if !idmlBoundsFromPath(item, transform, &bounds) do
        return {}

    var result: retval
    result += "clip-path:polygon("
    var cursor = 0'u64
    var points: u64
    while true
    {
        let pointStart = Utf8.indexOf(item, "<PathPointType", cursor)
        if pointStart == Swag.U64.Max do
            break
        let pointEnd = Utf8.indexOf(item, '>'rune, pointStart)
        if pointEnd == Swag.U64.Max do
            return {}
        var values: Array'f32
        if !idmlNumbers(idmlAttribute(item[pointStart until pointEnd + 1], "Anchor"), &values) or values.count != 2 do
            return {}
        if points do
            result += ","
        let x = transform.a * values[0] + transform.c * values[1] + transform.x
        let y = transform.b * values[0] + transform.d * values[1] + transform.y
        result += Format.toString("%", 100 * (x - bounds.left) / bounds.width)
        result += "% "
        result += Format.toString("%", 100 * (y - bounds.top) / bounds.height)
        result += "%"
        points += 1
        cursor = pointEnd + 1
    }

    if points < 3 do
        return {}
    result += ");"
    return result
}

private func idmlEntity(text: string)->rune
{
    if text == "amp" do return '&'
    if text == "lt" do return '<'
    if text == "gt" do return '>'
    if text == "quot" do return '"'
    if text == "apos" do return '\''
    if text.count > 2 and text[0] == '#' and (text[1] == 'x' or text[1] == 'X')
    {
        var value: u32
        for digit in text[2 to ]
        {
            let nibble = (digit >= '0' and digit <= '9') ? cast(u32) (digit - '0') :
                         (digit >= 'a' and digit <= 'f') ? cast(u32) (digit - 'a' + 10) :
                         (digit >= 'A' and digit <= 'F') ? cast(u32) (digit - 'A' + 10) : Swag.U32.Max
            if nibble == Swag.U32.Max or value > (Swag.U32.Max - nibble) / 16 do
                return 0xFFFD
            value = value * 16 + nibble
        }
        if value <= 0x10FFFF do
            return cast(rune) value
    }
    elif text.count > 1 and text[0] == '#'
    {
        let parsed = catch StrConv.parseU32(text[1 to ]) as parseError
        if parseError == null and !parsed.ovf and parsed.eat == text.count - 1 do
            return cast(rune) parsed.value
    }

    return 0xFFFD
}

private func idmlDecodeEntities(text: string)->String
{
    var result: retval
    var cursor = 0'u64
    while cursor < text.count
    {
        let entityStart = Utf8.indexOf(text, '&'rune, cursor)
        if entityStart == Swag.U64.Max
        {
            result += text[cursor to ]
            break
        }

        result += text[cursor until entityStart]
        let entityEnd = Utf8.indexOf(text, ';'rune, entityStart + 1)
        if entityEnd == Swag.U64.Max
        {
            result += text[entityStart to ]
            break
        }

        result += idmlEntity(text[entityStart + 1 until entityEnd])
        cursor = entityEnd + 1
    }

    return result
}

private func idmlStoryText(source: string)->String
{
    var result: retval
    var cursor = 0'u64
    while cursor < source.count
    {
        let contentStart = Utf8.indexOf(source, "<Content", cursor)
        let breakStart   = Utf8.indexOf(source, "<Br", cursor)
        let paragraphEnd = Utf8.indexOf(source, "</ParagraphStyleRange>", cursor)
        let next = Math.min(contentStart, Math.min(breakStart, paragraphEnd))
        if next == Swag.U64.Max do
            break

        if next == contentStart
        {
            let openEnd  = Utf8.indexOf(source, '>'rune, contentStart)
            let close    = openEnd == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(source, "</Content>", openEnd + 1)
            if close == Swag.U64.Max do
                break
            result += idmlDecodeEntities(source[openEnd + 1 until close])
            cursor = close + 10
            continue
        }

        if next == breakStart
        {
            result += '\n'
            let end = Utf8.indexOf(source, '>'rune, breakStart)
            cursor = end == Swag.U64.Max ? source.count : end + 1
            continue
        }

        if !result.isEmpty() and result.back() != '\n' do
            result += '\n'
        cursor = paragraphEnd + ("</ParagraphStyleRange>").count
    }

    return result
}

private func idmlTextAlignment(value: string)->string
{
    if value == "CenterAlign" do return "center"
    if value == "RightAlign" do return "right"
    if value == "JustifyAll" or value == "JustifyLeft" or value == "JustifyRight" or value == "JustifyCenter" do return "justify"
    return "left"
}

private func idmlTextStyleCss(style: const *IdmlTextStyle)->String
{
    var result: retval
    if style.fontSize > 0 do
        result += Format.toString("font-size:%px;", style.fontSize)
    if !style.fill.isEmpty() do
        result += Format.toString("color:%;", style.fill)
    if !style.alignment.isEmpty() do
        result += Format.toString("text-align:%;", style.alignment)
    result += style.serif ? "font-family:serif;" : "font-family:sans-serif;"
    return result
}

private func idmlCharacterStyleCss(tag: string, colors: const *HashTable'(String, String))->String
{
    var result: retval
    let fontSize = idmlNumber(idmlAttribute(tag, "PointSize")).value
    if fontSize > 0 do
        result += Format.toString("font-size:%px;", fontSize)
    let color = idmlColor(colors, idmlAttribute(tag, "FillColor"))
    if color.count do
        result += Format.toString("color:%;", color)
    if idmlAttribute(tag, "Capitalization") == "AllCaps" do
        result += "text-transform:uppercase;"
    return result
}

private func idmlCharacterRangeHtml(source: string, colors: const *HashTable'(String, String))->String
{
    var result: retval
    var cursor = 0'u64
    while cursor < source.count
    {
        let rangeStart = Utf8.indexOf(source, "<CharacterStyleRange", cursor)
        if rangeStart == Swag.U64.Max do
            break
        let openEnd = Utf8.indexOf(source, '>'rune, rangeStart)
        let close   = openEnd == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(source, "</CharacterStyleRange>", openEnd + 1)
        if close == Swag.U64.Max do
            break
        result += "<span style=\""
        result += idmlCharacterStyleCss(source[rangeStart until openEnd + 1], colors)
        result += "\">"
        result += idmlEscapeHtml(idmlStoryText(source[openEnd + 1 until close]).toString())
        result += "</span>"
        cursor = close + ("</CharacterStyleRange>").count
    }

    return result.isEmpty() ? idmlEscapeHtml(idmlStoryText(source).toString()) : result
}

private func idmlStoryHtml(source: string, styles: const *HashTable'(String, IdmlTextStyle), colors: const *HashTable'(String, String))->String
{
    var result: retval
    var cursor = 0'u64
    while cursor < source.count
    {
        let rangeStart = Utf8.indexOf(source, "<ParagraphStyleRange", cursor)
        if rangeStart == Swag.U64.Max do
            break
        let openEnd = Utf8.indexOf(source, '>'rune, rangeStart)
        let close   = openEnd == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(source, "</ParagraphStyleRange>", openEnd + 1)
        if close == Swag.U64.Max do
            break
        let tag      = source[rangeStart until openEnd + 1]
        let styleKey = idmlAttribute(tag, "AppliedParagraphStyle")
        let style    = styles.tryFind(styleKey)
        result += "<div style=\"margin:0;"
        if style do
            result += idmlTextStyleCss(&style!.value)
        result += "\">"
        result += idmlCharacterRangeHtml(source[openEnd + 1 until close], colors)
        result += "</div>"
        cursor = close + ("</ParagraphStyleRange>").count
    }

    return result.isEmpty() ? idmlEscapeHtml(idmlStoryText(source).toString()) : result
}

private func idmlEscapeHtml(text: string)->String
{
    var result: retval
    var cursor = 0'u64
    while cursor < text.count
    {
        // IDML uses U+2028/U+2029 as hard text separators. The HTML text painter works on UTF-8
        // bytes here, so recognize their three-byte encoding before escaping ordinary content.
        if cursor + 2 < text.count and text[cursor] == 0xE2 and text[cursor + 1] == 0x80 and (text[cursor + 2] == 0xA8 or text[cursor + 2] == 0xA9)
        {
            result += "<br>"
            cursor += 3
            continue
        }

        let value = text[cursor]
        switch value
        {
        case '&':  result += "&amp;"
        case '<':  result += "&lt;"
        case '>':  result += "&gt;"
        case '"':  result += "&quot;"
        default:   result += value
        }
        cursor += 1
    }

    return result
}

private func idmlCssColor(space, value: string)->String
{
    var values: Array'f32
    if !idmlNumbers(value, &values) do
        return {}
    if space == "RGB" and values.count == 3 do
        return Format.toString("rgb(%, %, %)", cast(u32) Math.round(Math.clamp(values[0], 0, 255)), cast(u32) Math.round(Math.clamp(values[1], 0, 255)), cast(u32) Math.round(Math.clamp(values[2], 0, 255)))
    if space == "CMYK" and values.count == 4
    {
        let cyan    = Math.clamp(values[0] / 100, 0, 1)
        let magenta = Math.clamp(values[1] / 100, 0, 1)
        let yellow  = Math.clamp(values[2] / 100, 0, 1)
        let black   = Math.clamp(values[3] / 100, 0, 1)
        return Format.toString("rgb(%, %, %)", cast(u32) Math.round(255 * (1 - cyan) * (1 - black)), cast(u32) Math.round(255 * (1 - magenta) * (1 - black)), cast(u32) Math.round(255 * (1 - yellow) * (1 - black)))
    }

    return {}
}

private func idmlLoadColors(fileName: string, archive: const *ZipArchive)->HashTable'(String, String)
{
    var result: retval
    let entry = idmlFindEntry(archive, "Resources/Graphic.xml")
    if !entry do
        return result
    let source = catch idmlReadEntry(fileName, archive, entry!.path.toString()) as readError
    if readError != null do
        return result

    var cursor = 0'u64
    while true
    {
        let start = Utf8.indexOf(source.toString(), "<Color ", cursor)
        if start == Swag.U64.Max do
            break
        let end = Utf8.indexOf(source.toString(), '>'rune, start)
        if end == Swag.U64.Max do
            break
        let tag   = source.toString()[start until end + 1]
        let self  = idmlAttribute(tag, "Self")
        let color = idmlCssColor(idmlAttribute(tag, "Space"), idmlAttribute(tag, "ColorValue"))
        if self.count and color.count and !result.tryFind(self) do
            result.add(self, color)
        cursor = end + 1
    }

    if !result.tryFind("Color/Paper") do
        result.add("Color/Paper", "rgb(255, 255, 255)")
    if !result.tryFind("Color/Black") do
        result.add("Color/Black", "rgb(0, 0, 0)")
    return result
}

private func idmlColor(colors: const *HashTable'(String, String), name: string)->string
{
    if name == "Swatch/None" or !name.count do
        return ""
    let found = colors.tryFind(name)
    return found ? found!.value.toString() : ""
}

private func idmlLoadTextStyles(fileName: string, archive: const *ZipArchive, colors: const *HashTable'(String, String))->HashTable'(String, IdmlTextStyle)
{
    var result: retval
    let entry = idmlFindEntry(archive, "Resources/Styles.xml")
    if !entry do
        return result
    let source = catch idmlReadEntry(fileName, archive, entry!.path.toString()) as readError
    if readError != null do
        return result

    var cursor = 0'u64
    while true
    {
        let start = Utf8.indexOf(source.toString(), "<ParagraphStyle ", cursor)
        if start == Swag.U64.Max do
            break
        let openEnd = Utf8.indexOf(source.toString(), '>'rune, start)
        if openEnd == Swag.U64.Max do
            break
        let tag  = source.toString()[start until openEnd + 1]
        let self = idmlAttribute(tag, "Self")
        let close = Utf8.indexOf(source.toString(), "</ParagraphStyle>", openEnd + 1)
        let bodyEnd = close == Swag.U64.Max ? openEnd + 1 : close
        if self.count and !result.tryFind(self)
        {
            var style: IdmlTextStyle
            style.fontSize  = idmlNumber(idmlAttribute(tag, "PointSize")).value
            style.fill      = idmlColor(colors, idmlAttribute(tag, "FillColor"))
            style.alignment = idmlTextAlignment(idmlAttribute(tag, "Justification"))
            let fontStart   = Utf8.indexOf(source.toString(), "<AppliedFont", openEnd + 1)
            if fontStart != Swag.U64.Max and fontStart < bodyEnd
            {
                let fontOpenEnd = Utf8.indexOf(source.toString(), '>'rune, fontStart)
                let fontClose   = fontOpenEnd == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(source.toString(), "</AppliedFont>", fontOpenEnd + 1)
                if fontClose != Swag.U64.Max and fontClose < bodyEnd do
                    style.serif = Utf8.contains(source.toString()[fontOpenEnd + 1 until fontClose], "Minion")
            }
            result.add(self, #move style)
        }
        cursor = close == Swag.U64.Max ? openEnd + 1 : close + ("</ParagraphStyle>").count
    }

    return result
}

private func idmlAppendPages(source: string, pages: *Array'IdmlPage)
{
    var cursor = 0'u64
    while pages.count < IdmlPageLimit
    {
        let start = Utf8.indexOf(source, "<Page ", cursor)
        if start == Swag.U64.Max do
            break
        let end = Utf8.indexOf(source, '>'rune, start)
        if end == Swag.U64.Max do
            break
        let tag = source[start until end + 1]
        var bounds: IdmlBounds
        if idmlBoundsFromGeometric(idmlAttribute(tag, "GeometricBounds"), &bounds)
        {
            let transform = idmlTransform(tag)
            bounds.left += transform.x
            bounds.top  += transform.y
            var page: IdmlPage
            page.name   = idmlAttribute(tag, "Name")
            page.master = idmlAttribute(tag, "AppliedMaster")
            page.bounds = bounds
            pages.add(#move page)
        }

        cursor = end + 1
    }
}

private func idmlPageIndex(pages: const *Array'IdmlPage, bounds: const *IdmlBounds)->u64
{
    let centerX = bounds.left + bounds.width * 0.5
    let centerY = bounds.top + bounds.height * 0.5
    for page, index in pages
    {
        let inside = centerX >= page.bounds.left and centerX <= page.bounds.left + page.bounds.width and centerY >= page.bounds.top and centerY <= page.bounds.top + page.bounds.height
        if inside do
            return index
    }

    return Swag.U64.Max
}

private func idmlAppendItems(source: string, stories: const *HashTable'(String, String), colors: const *HashTable'(String, String), pages: *Array'IdmlPage)
{
    var cursor = 0'u64
    var groupCursor: u64
    var groupTransforms: Array'IdmlTransform
    var itemCount: u64
    while itemCount < IdmlFrameLimit
    {
        let textStart  = Utf8.indexOf(source, "<TextFrame ", cursor)
        let rectStart  = Utf8.indexOf(source, "<Rectangle ", cursor)
        let ovalStart  = Utf8.indexOf(source, "<Oval ", cursor)
        let polygonStart = Utf8.indexOf(source, "<Polygon ", cursor)
        let lineStart    = Utf8.indexOf(source, "<GraphicLine ", cursor)
        let shapeStart   = Math.min(Math.min(rectStart, ovalStart), Math.min(polygonStart, lineStart))
        let start      = Math.min(textStart, shapeStart)
        if start == Swag.U64.Max do
            break

        // Group items carry a transform inherited by each child. Consume their open and close
        // tags in document order before locating the next drawable item.
        while groupCursor < start
        {
            let open  = Utf8.indexOf(source, "<Group ", groupCursor)
            let close = Utf8.indexOf(source, "</Group>", groupCursor)
            if open == Swag.U64.Max and close == Swag.U64.Max do
                break
            if open < close and open < start
            {
                let end = Utf8.indexOf(source, '>'rune, open)
                if end == Swag.U64.Max or end >= start do
                    break
                groupTransforms.add(idmlTransform(source[open until end + 1]))
                groupCursor = end + 1
                continue
            }
            if close < start
            {
                if groupTransforms.count do
                    discard groupTransforms.popBack()
                groupCursor = close + ("</Group>").count
                continue
            }
            break
        }

        let textItem = start == textStart
        let oval     = start == ovalStart
        let polygon  = start == polygonStart
        let line     = start == lineStart
        let closing  = textItem ? "</TextFrame>" : oval ? "</Oval>" : polygon ? "</Polygon>" : line ? "</GraphicLine>" : "</Rectangle>"
        let openEnd  = Utf8.indexOf(source, '>'rune, start)
        let close    = openEnd == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(source, closing, openEnd + 1)
        if close == Swag.U64.Max do
            break
        let tag     = source[start until openEnd + 1]
        let content = source[start until close + closing.count]
        var transform = idmlTransform(tag)
        var inherited: IdmlTransform
        for groupTransform in groupTransforms do
            inherited = idmlComposeTransform(&inherited, groupTransform)
        transform = idmlComposeTransform(&inherited, &transform)
        var bounds: IdmlBounds
        if idmlBoundsFromPath(content, &transform, &bounds, line)
        {
            let pageIndex = idmlPageIndex(pages, &bounds)
            if pageIndex != Swag.U64.Max
            {
                // Item transforms are expressed in the spread coordinate system. The local page
                // scene begins at its own top-left corner, so remove the selected page origin
                // before handing the rectangle to the renderer.
                bounds.left -= pages[pageIndex].bounds.left
                bounds.top  -= pages[pageIndex].bounds.top
                var item: IdmlItem
                item.bounds     = bounds
                item.fill       = idmlColor(colors, idmlAttribute(tag, "FillColor"))
                item.stroke     = idmlColor(colors, idmlAttribute(tag, "StrokeColor"))
                item.strokeSize = idmlNumber(idmlAttribute(tag, "StrokeWeight")).value
                item.oval       = oval
                item.line       = line
                if polygon do
                    item.clipPath = idmlPolygonClipPath(content, &transform)
                if textItem
                {
                    let story = stories.tryFind(idmlAttribute(tag, "ParentStory"))
                    if story do
                        item.text = story!.value
                    pages[pageIndex].textFrameCount += 1
                }

                pages[pageIndex].items.add(#move item)
            }
        }

        itemCount += 1
        cursor = close + closing.count
    }
}

private func idmlAppendMasterItems(masters: const *Array'IdmlMaster, pages: *Array'IdmlPage)
{
    for &page, pageIndex in pages
    {
        if page.master.isEmpty() do
            continue
        for master in masters where master.self == page.master
        {
            if master.pages.isEmpty() do
                break
            let index = Math.min(pageIndex, master.pages.count - 1)
            for item in master.pages[index].items
            {
                page.items.add(item)
                if !item.text.isEmpty() do
                    page.textFrameCount += 1
            }
            break
        }
    }
}

private func idmlLoadMasters(fileName: string, archive: const *ZipArchive, designMap: string, stories: const *HashTable'(String, String), colors: const *HashTable'(String, String))->Array'IdmlMaster
{
    var result: retval
    var cursor = 0'u64
    while cursor < designMap.count
    {
        let start = Utf8.indexOf(designMap, "<idPkg:MasterSpread ", cursor)
        if start == Swag.U64.Max do
            break
        let end = Utf8.indexOf(designMap, '>'rune, start)
        if end == Swag.U64.Max do
            break
        let path   = idmlAttribute(designMap[start until end + 1], "src")
        let source = catch idmlReadEntry(fileName, archive, path) as readError
        if readError == null
        {
            let masterStart = Utf8.indexOf(source.toString(), "<MasterSpread ")
            let masterEnd   = masterStart == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(source.toString(), '>'rune, masterStart)
            if masterEnd != Swag.U64.Max
            {
                let self = idmlAttribute(source.toString()[masterStart until masterEnd + 1], "Self")
                if self.count
                {
                    var master: IdmlMaster
                    master.self = self
                    idmlAppendPages(source.toString(), &master.pages)
                    idmlAppendItems(source.toString(), stories, colors, &master.pages)
                    result.add(#move master)
                }
            }
        }
        cursor = end + 1
    }

    return result
}

// Reads an IDML package into positioned pages, text frames, and vector frame backgrounds. Linked
// external assets deliberately remain offline; a missing link never causes the viewer to fetch it.
func loadIdmlDocument(fileName: string)->IdmlDocument fail
{
    let archive = try loadZipArchive(fileName)
    if archive.uncompressedSize > IdmlDocumentByteLimit do
        fail UnsupportedFormatError{"IDML package expands beyond the document reader limit"}
    let mimetype = try idmlReadEntry(fileName, &archive, "mimetype")
    if Latin1.trim(mimetype.toString()) != "application/vnd.adobe.indesign-idml-package" do
        fail InvalidFormatError{"the ZIP package is not an InDesign Markup document"}

    let designMap = try idmlReadEntry(fileName, &archive, "designmap.xml")
    let colors     = idmlLoadColors(fileName, &archive)
    let textStyles = idmlLoadTextStyles(fileName, &archive, &colors)
    var stories: HashTable'(String, String)
    for entry in archive.entries where Utf8.startsWith(entry.path.toString(), "Stories/") and Utf8.endsWith(entry.path.toString(), ".xml")
    {
        let source = catch idmlReadEntry(fileName, &archive, entry.path.toString()) as readError
        if readError != null do
            continue
        let storyStart = Utf8.indexOf(source.toString(), "<Story ")
        let storyEnd   = storyStart == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(source.toString(), '>'rune, storyStart)
        if storyEnd == Swag.U64.Max do
            continue
        let self = idmlAttribute(source.toString()[storyStart until storyEnd + 1], "Self")
        if self.count and !stories.tryFind(self) do
            stories.add(self, idmlStoryHtml(source.toString(), &textStyles, &colors))
    }

    let masters = idmlLoadMasters(fileName, &archive, designMap.toString(), &stories, &colors)
    var result: retval
    result.fileName = fileName
    var cursor      = 0'u64
    var spreadCount: u64
    while spreadCount < IdmlSpreadLimit
    {
        let start = Utf8.indexOf(designMap.toString(), "<idPkg:Spread ", cursor)
        if start == Swag.U64.Max do
            break
        let end = Utf8.indexOf(designMap.toString(), '>'rune, start)
        if end == Swag.U64.Max do
            break
        let spreadPath = idmlAttribute(designMap.toString()[start until end + 1], "src")
        let spread     = try idmlReadEntry(fileName, &archive, spreadPath)
        var spreadPages: Array'IdmlPage
        idmlAppendPages(spread.toString(), &spreadPages)
        if !spreadPages.isEmpty()
        {
            idmlAppendMasterItems(&masters, &spreadPages)
            idmlAppendItems(spread.toString(), &stories, &colors, &spreadPages)
            for page in spreadPages do
                result.pages.add(page[])
        }
        cursor = end + 1
        spreadCount += 1
    }

    if result.pages.isEmpty() do
        fail InvalidFormatError{"IDML document contains no readable pages"}
    return result
}
