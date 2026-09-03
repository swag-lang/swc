#global internal

using Core, Core.Errors, Pixel

// IDML is an InDesign document package rather than a preview image. These bounds keep a damaged
// package from turning a simple document inspection into an unbounded decompression operation.
private const IdmlDocumentByteLimit = 128 * 1024 * 1024'u64
private const IdmlPageLimit         = 2_000'u64
private const IdmlSpreadLimit       = 1_000'u64
private const IdmlFrameLimit        = 100_000'u64
private const IdmlEmbeddedGraphicDataLimit = 24 * 1024 * 1024'u64
private const IdmlLinkedGraphicDataLimit   = 8 * 1024 * 1024'u64
private const IdmlLinkedGraphicsDataLimit  = 24 * 1024 * 1024'u64
private const IdmlGraphicSourcePixelLimit  = 16 * 1024 * 1024'u64
private const IdmlTextColumnLimit          = 16'u32

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
    self:       String
    story:      String
    previousFrame: String
    nextFrame:     String
    text:       String
    fill:       String
    stroke:     String
    strokeSize: f32
    oval:       bool
    line:       bool
    lineStartArrow: bool
    lineEndArrow:   bool
    imageFrame: bool
    imageHasBounds: bool
    cornerTopLeft:     f32
    cornerTopRight:    f32
    cornerBottomRight: f32
    cornerBottomLeft:  f32
    hasTextFrameLayout: bool
    textColumns:        u32 = 1
    textColumnGutter:   f32
    textColumnWidth:    f32
    textInsetTop:       f32
    textInsetRight:     f32
    textInsetBottom:    f32
    textInsetLeft:      f32
    clipPath:   String
    image:      String
    imageBounds: IdmlBounds
}

private struct IdmlTextStyle
{
    fontSize:      f32
    autoLeading:   f32
    spaceBefore:   f32
    spaceAfter:    f32
    leftIndent:    f32
    rightIndent:   f32
    firstLineIndent: f32
    fill:          String
    alignment:     String
    serif:         bool
    cjk:           bool
    bold:          bool
    italic:        bool
    bullet:        bool
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
    mtd const html(scale: f32)->String
    {
        var result: retval
        let factor   = Math.clamp(scale, 0.25, 3)
        let itemFont = 12 * factor
        let inset    = 2 * factor
        result += Format.toString("<style>html,body{margin:0;padding:0;background:#343438}.idml-page{position:relative;margin:%px auto;background:#fff;color:#101014;box-shadow:0 2px 12px #0008;overflow:hidden}.idml-item{position:absolute;box-sizing:border-box;overflow:hidden;font:%px/1.25 sans-serif;padding:%px}.idml-text-column{position:absolute;box-sizing:border-box;overflow:hidden}.idml-image{position:absolute;display:block}.idml-missing-image{display:block;width:100%%;height:100%%;background:#e5e5e5;color:#777;font:%px sans-serif;text-align:center;padding-top:%px}</style>", 24 * factor, itemFont, inset, 18 * factor, 8 * factor)
        result += Format.toString("<div class=\"idml-page\" style=\"width:%px;height:%px\">", .bounds.width * factor, .bounds.height * factor)
        for item in .items
        {
            result += Format.toString("<div class=\"idml-item\" style=\"left:%px;top:%px;width:%px;height:%px;background:%;border:%px solid %;%;%;%;%\">",
                                      item.bounds.left * factor,
                                      item.bounds.top * factor,
                                      item.bounds.width * factor,
                                      item.bounds.height * factor,
                                      item.line ? (item.stroke.isEmpty() ? "transparent" : item.stroke.toString()) : (item.fill.isEmpty() ? "transparent" : item.fill.toString()),
                                      item.line ? 0 : item.strokeSize * factor,
                                      item.stroke.isEmpty() ? "transparent" : item.stroke.toString(),
                                      item.oval ? "border-radius:50%" : idmlCornerCss(item, factor).toString(),
                                      item.clipPath,
                                      item.imageFrame ? "padding:0" : "",
                                      idmlTextFramePaddingCss(item, factor).toString())
            if item.image.count
            {
                let imageBounds = item.imageHasBounds ? &item.imageBounds : &item.bounds
                result += Format.toString("<img class=\"idml-image\" style=\"left:%px;top:%px;width:%px;height:%px\" src=\"%\">",
                                          (imageBounds.left - item.bounds.left) * factor,
                                          (imageBounds.top - item.bounds.top) * factor,
                                          imageBounds.width * factor,
                                          imageBounds.height * factor,
                                          item.image)
            }
            elif item.imageFrame do
                result += "<span class=\"idml-missing-image\">×</span>"
            // Text is escaped while the IDML story is converted to local paragraph markup. It is
            // deliberately not a document-supplied HTML fragment.
            idmlAppendTextColumns(&result, item, factor)
            result += "</div>"
        }

        result += "</div>"
        return result
    }
}

// InDesign may give each corner a different treatment. Rounded corners are directly representable
// by the local painter, so retain the four radii rather than flattening a visibly rounded frame.
private func idmlCornerCss(item: const *IdmlItem, factor: f32)->String
{
    if item.cornerTopLeft <= 0 and item.cornerTopRight <= 0 and item.cornerBottomRight <= 0 and item.cornerBottomLeft <= 0 do
        return {}
    return Format.toString("border-radius:%px %px %px %px", item.cornerTopLeft * factor, item.cornerTopRight * factor, item.cornerBottomRight * factor, item.cornerBottomLeft * factor)
}

private func idmlTextFramePaddingCss(item: const *IdmlItem, factor: f32)->String
{
    if !item.hasTextFrameLayout do
        return {}
    if item.textColumns > 1 do
        return "padding:0"
    return Format.toString("padding:%px %px %px %px", item.textInsetTop * factor, item.textInsetRight * factor, item.textInsetBottom * factor, item.textInsetLeft * factor)
}

// The HTML painter does not make arbitrary text into columns. Preserve the IDML geometry with
// sibling clipping rectangles and allocate complete paragraph blocks to each one, so a malformed
// story never leaves unmatched markup in the page scene.
private func idmlAppendTextColumns(html: *String, item: const *IdmlItem, factor: f32)
{
    if !item.text.count do
        return
    if !item.hasTextFrameLayout or item.textColumns <= 1
    {
        html[] += item.text
        return
    }

    let columns = Math.clamp(item.textColumns, 1'u32, IdmlTextColumnLimit)
    let left    = item.textInsetLeft * factor
    let top     = item.textInsetTop * factor
    let width   = Math.max(item.bounds.width * factor - left - item.textInsetRight * factor, 1)
    let height  = Math.max(item.bounds.height * factor - top - item.textInsetBottom * factor, 1)
    var gap     = Math.max(item.textColumnGutter * factor, 0)
    if !gap and item.textColumnWidth > 0 and columns > 1 do
        gap = Math.max((width - item.textColumnWidth * factor * columns) / (columns - 1), 0)
    let columnWidth = item.textColumnWidth > 0 ? item.textColumnWidth * factor : Math.max((width - gap * (columns - 1)) / columns, 1)
    var cursor = 0'u64
    for column in columns
    {
        if cursor >= item.text.count do
            break
        let remainingColumns = columns - column
        let target            = (item.text.count - cursor) / remainingColumns
        var end               = cursor
        while end < item.text.count
        {
            let next = idmlStoryBlockEnd(item.text.toString(), end)
            if end != cursor and next - cursor > target do
                break
            end = next
            if end - cursor >= target do
                break
        }
        if end == cursor do
            end = idmlStoryBlockEnd(item.text.toString(), cursor)
        html[] += Format.toString("<div class=\"idml-text-column\" style=\"left:%px;top:%px;width:%px;height:%px\">", left + column * (columnWidth + gap), top, columnWidth, height)
        html[] += item.text[cursor until end]
        html[] += "</div>"
        cursor = end
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

// A per-corner declaration overrides the legacy all-corners value. Do not round a corner whose
// explicit option is not RoundedCorner: bevelled and inverse corners need path rendering instead.
private func idmlRoundedCornerRadius(tag, corner: string)->f32
{
    let cornerOption = idmlAttribute(tag, Format.toString("%CornerOption", corner).toString())
    if cornerOption.count
    {
        if cornerOption != "RoundedCorner" do
            return 0
        let radius = idmlNumber(idmlAttribute(tag, Format.toString("%CornerRadius", corner).toString()))
        return radius.valid ? Math.max(radius.value, 0) : 0
    }

    if idmlAttribute(tag, "CornerOption") != "RoundedCorner" do
        return 0
    let radius = idmlNumber(idmlAttribute(tag, "CornerRadius"))
    return radius.valid ? Math.max(radius.value, 0) : 0
}

private func idmlFirstOpenTag(source, name: string)->String
{
    var marker: String
    marker += '<'rune
    marker += name
    let start = Utf8.indexOf(source, marker.toString())
    if start == Swag.U64.Max do
        return {}
    let end = Utf8.indexOf(source, '>'rune, start)
    return end == Swag.U64.Max ? {} : String.from(source[start until end + 1])
}

private func idmlElementContents(source, name: string)->String
{
    let opening = idmlFirstOpenTag(source, name)
    if !opening.count do
        return {}
    let start = Utf8.indexOf(source, opening.toString())
    let body  = start + opening.count
    var close: String
    close += "</"
    close += name
    close += '>'rune
    let end = Utf8.indexOf(source, close.toString(), body)
    return end == Swag.U64.Max ? {} : String.from(source[body until end])
}

private func idmlTextFrameInsets(preference: string, item: *IdmlItem)
{
    let insetTag = idmlFirstOpenTag(preference, "InsetSpacing")
    let contents = idmlElementContents(preference, "InsetSpacing")
    if !insetTag.count or !contents.count do
        return
    if idmlAttribute(insetTag.toString(), "type") == "unit"
    {
        let inset = idmlNumber(contents.toString())
        if inset.valid
        {
            item.textInsetTop    = Math.max(inset.value, 0)
            item.textInsetRight  = item.textInsetTop
            item.textInsetBottom = item.textInsetTop
            item.textInsetLeft   = item.textInsetTop
        }
        return
    }

    var values: Array'f32
    var cursor = 0'u64
    while cursor < contents.count and values.count < 4
    {
        let start = Utf8.indexOf(contents.toString(), "<ListItem", cursor)
        let open  = start == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(contents.toString(), '>'rune, start)
        let end   = open == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(contents.toString(), "</ListItem>", open + 1)
        if end == Swag.U64.Max do
            break
        let value = idmlNumber(contents[open + 1 until end])
        if value.valid do
            values.add(Math.max(value.value, 0))
        cursor = end + ("</ListItem>").count
    }
    if values.count == 4
    {
        // IDML stores frame insets clockwise from the top: top, left, bottom, right.
        item.textInsetTop    = values[0]
        item.textInsetLeft   = values[1]
        item.textInsetBottom = values[2]
        item.textInsetRight  = values[3]
    }
}

private func idmlTextFrameLayout(content: string, item: *IdmlItem)
{
    let preference = idmlFirstOpenTag(content, "TextFramePreference")
    if !preference.count do
        return
    item.hasTextFrameLayout = true
    let columns = idmlNumber(idmlAttribute(preference.toString(), "TextColumnCount"))
    if columns.valid and columns.value >= 1 do
        item.textColumns = Math.clamp(cast(u32) columns.value, 1'u32, IdmlTextColumnLimit)
    let gutter = idmlNumber(idmlAttribute(preference.toString(), "TextColumnGutter"))
    if gutter.valid do
        item.textColumnGutter = Math.max(gutter.value, 0)
    let width = idmlNumber(idmlAttribute(preference.toString(), "TextColumnFixedWidth"))
    if width.valid do
        item.textColumnWidth = Math.max(width.value, 0)
    idmlTextFrameInsets(content, item)
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

// An image's transform is independent from its enclosing frame. Keep the axis-aligned cases as a
// local image rectangle so a crop or proportional fit does not become a stretched frame fill.
// Rotated, sheared, and reflected images remain on the conservative frame fallback until the scene
// renderer can preserve their orientation.
private func idmlBoundsFromGraphic(item: string, parent: const *IdmlTransform, result: *IdmlBounds)->bool
{
    let imageStart   = Utf8.indexOf(item, "<Image ")
    let imageOpenEnd = imageStart == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(item, '>'rune, imageStart)
    let imageEnd     = imageOpenEnd == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(item, "</Image>", imageOpenEnd + 1)
    let boundsStart  = imageOpenEnd == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(item, "<GraphicBounds ", imageOpenEnd + 1)
    let boundsEnd    = boundsStart == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(item, '>'rune, boundsStart)
    if imageEnd == Swag.U64.Max or boundsEnd == Swag.U64.Max or boundsStart > imageEnd do
        return false

    let boundsTag = item[boundsStart until boundsEnd + 1]
    let left      = idmlNumber(idmlAttribute(boundsTag, "Left"))
    let top       = idmlNumber(idmlAttribute(boundsTag, "Top"))
    let right     = idmlNumber(idmlAttribute(boundsTag, "Right"))
    let bottom    = idmlNumber(idmlAttribute(boundsTag, "Bottom"))
    if !left.valid or !top.valid or !right.valid or !bottom.valid or right.value <= left.value or bottom.value <= top.value do
        return false

    let imageTag       = item[imageStart until imageOpenEnd + 1]
    let childTransform = idmlTransform(imageTag)
    let imageTransform = idmlComposeTransform(parent, &childTransform)
    if Math.abs(imageTransform.b) > 0.0001 or Math.abs(imageTransform.c) > 0.0001 or imageTransform.a <= 0 or imageTransform.d <= 0 do
        return false
    result.left   = imageTransform.a * left.value + imageTransform.x
    result.top    = imageTransform.d * top.value + imageTransform.y
    result.width  = imageTransform.a * (right.value - left.value)
    result.height = imageTransform.d * (bottom.value - top.value)
    return result.width > 0 and result.height > 0
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

// A graphic line is an oriented stroke, not its axis-aligned bounding rectangle. Build its
// painted silhouette in the local page space so the HTML painter retains both direction and
// triangular InDesign arrowheads without relying on an external SVG implementation.
private func idmlLineClipPath(item: string, transform: const *IdmlTransform, pageLeft, pageTop: f32, bounds: const *IdmlBounds, strokeSize: f32, startArrow, endArrow: bool)->String
{
    var firstX, firstY, secondX, secondY: f32
    var pointCount = 0'u64
    var cursor     = 0'u64
    while pointCount < 3
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
        let x = transform.a * values[0] + transform.c * values[1] + transform.x - pageLeft
        let y = transform.b * values[0] + transform.d * values[1] + transform.y - pageTop
        if !pointCount
        {
            firstX = x
            firstY = y
        }
        else
        {
            secondX = x
            secondY = y
        }
        pointCount += 1
        cursor = pointEnd + 1
    }
    if pointCount != 2 or bounds.width <= 0 or bounds.height <= 0 do
        return {}

    let dx     = secondX - firstX
    let dy     = secondY - firstY
    let length = Math.sqrt(dx * dx + dy * dy)
    if length < 0.01 do
        return {}

    let halfStroke  = Math.max(strokeSize, 0.75) * 0.5
    let normalX     = -dy * halfStroke / length
    let normalY     = dx * halfStroke / length
    let startInset  = startArrow ? Math.min(length * 0.45, Math.max(6, halfStroke * 8)) : 0
    let endInset    = endArrow ? Math.min(length * 0.45, Math.max(6, halfStroke * 8)) : 0
    let startBaseX  = firstX + dx * startInset / length
    let startBaseY  = firstY + dy * startInset / length
    let endBaseX    = secondX - dx * endInset / length
    let endBaseY    = secondY - dy * endInset / length

    var result: retval
    result += "clip-path:polygon("
    if startArrow
    {
        result += Format.toString("%{f3}%% %{f3}%%,", 100 * (firstX - bounds.left) / bounds.width, 100 * (firstY - bounds.top) / bounds.height)
        result += Format.toString("%{f3}%% %{f3}%%,", 100 * (startBaseX + normalX - bounds.left) / bounds.width, 100 * (startBaseY + normalY - bounds.top) / bounds.height)
    }
    else
    {
        result += Format.toString("%{f3}%% %{f3}%%,", 100 * (firstX + normalX - bounds.left) / bounds.width, 100 * (firstY + normalY - bounds.top) / bounds.height)
    }
    result += Format.toString("%{f3}%% %{f3}%%,", 100 * (endBaseX + normalX - bounds.left) / bounds.width, 100 * (endBaseY + normalY - bounds.top) / bounds.height)
    if endArrow do
        result += Format.toString("%{f3}%% %{f3}%%,", 100 * (secondX - bounds.left) / bounds.width, 100 * (secondY - bounds.top) / bounds.height)
    else do
        result += Format.toString("%{f3}%% %{f3}%%,", 100 * (secondX + normalX - bounds.left) / bounds.width, 100 * (secondY + normalY - bounds.top) / bounds.height)
    result += Format.toString("%{f3}%% %{f3}%%,", 100 * (endBaseX - normalX - bounds.left) / bounds.width, 100 * (endBaseY - normalY - bounds.top) / bounds.height)
    if startArrow do
        result += Format.toString("%{f3}%% %{f3}%%", 100 * (startBaseX - normalX - bounds.left) / bounds.width, 100 * (startBaseY - normalY - bounds.top) / bounds.height)
    else do
        result += Format.toString("%{f3}%% %{f3}%%", 100 * (firstX - normalX - bounds.left) / bounds.width, 100 * (firstY - normalY - bounds.top) / bounds.height)
    result += ");"
    return result
}

// Returns an image data URI only for pixels embedded in the IDML package.
internal func idmlEmbeddedGraphicDataUri(item: string)->String
{
    let imageStart = Utf8.indexOf(item, "<Image ")
    if imageStart == Swag.U64.Max do
        return {}
    let imageOpenEnd = Utf8.indexOf(item, '>'rune, imageStart)
    let imageEnd     = imageOpenEnd == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(item, "</Image>", imageOpenEnd + 1)
    if imageEnd == Swag.U64.Max do
        return {}

    let type = idmlAttribute(item[imageStart until imageOpenEnd + 1], "ImageTypeName")
    let mime = Utf8.contains(type, "JPEG") ? "image/jpeg" : Utf8.contains(type, "PNG") ? "image/png" : ""
    if !mime.count do
        return {}

    let contentsStart   = Utf8.indexOf(item, "<Contents", imageOpenEnd + 1)
    let contentsOpenEnd = contentsStart == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(item, '>'rune, contentsStart)
    let contentsEnd     = contentsOpenEnd == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(item, "</Contents>", contentsOpenEnd + 1)
    if contentsEnd == Swag.U64.Max or contentsEnd > imageEnd do
        return {}

    var payload: String
    var cursor = contentsOpenEnd + 1
    while cursor < contentsEnd
    {
        let start = Utf8.indexOf(item, "<![CDATA[", cursor)
        if start == Swag.U64.Max or start >= contentsEnd do
            break
        let contentStart = start + ("<![CDATA[").count
        let end = Utf8.indexOf(item, "]]>", contentStart)
        if end == Swag.U64.Max or end > contentsEnd do
            return {}
        if payload.count + end - contentStart > IdmlEmbeddedGraphicDataLimit do
            return {}
        payload += item[contentStart until end]
        cursor = end + ("]]>").count
    }
    if payload.isEmpty() do
        return {}

    // Metadata packets also use Contents CDATA. Retain only actual image payloads so a malformed
    // embedded item can still fall through to its ordinary local link.
    let bytes = catch Base64.decode(payload.toString()) as decodeError
    if decodeError != null or bytes.isEmpty() do
        return {}
    return Format.toString("data:%;base64,%", mime, payload)
}

private func idmlGraphicMimeType(path: string)->string
{
    switch Path.lowercaseExtension(path).toString()
    {
    case ".gif":        return "image/gif"
    case ".jpg", ".jpeg": return "image/jpeg"
    case ".png":        return "image/png"
    case ".tif", ".tiff": return "image/tiff"
    case ".webp":       return "image/webp"
    default:              return ""
    }
}

private func idmlHexNibble(value: u8)->u8
{
    if value >= '0' and value <= '9' do return value - '0'
    if value >= 'a' and value <= 'f' do return value - 'a' + 10
    if value >= 'A' and value <= 'F' do return value - 'A' + 10
    return Swag.U8.Max
}

// File links are local resources chosen by the document author. Decode only file: URLs and
// reject malformed escapes so the viewer never turns a linked graphic into a network request.
private func idmlFileUriPath(uri: string)->String
{
    if !Utf8.startsWith(uri, "file:", .Latin1NoCase) do
        return {}

    var source = uri[5 to ]
    if Utf8.startsWith(source, "//")
    {
        source = source[2 to ]
        if Utf8.startsWith(source, "localhost/", .Latin1NoCase) do
            source = source[9 to ]
        elif !Utf8.startsWith(source, "/") do
            return {}
    }
    if source.count > 2 and source[0] == '/' and source[2] == ':' do
        source = source[1 to ]

    var result: retval
    var cursor = 0'u64
    while cursor < source.count
    {
        if source[cursor] != '%'
        {
            result += source[cursor]
            cursor += 1
            continue
        }
        if cursor + 2 >= source.count do
            return {}
        let high = idmlHexNibble(source[cursor + 1])
        let low  = idmlHexNibble(source[cursor + 2])
        if high == Swag.U8.Max or low == Swag.U8.Max do
            return {}
        result += high * 16 + low
        cursor += 3
    }

    return result
}

private func idmlLocalGraphicSource(path: string, loaded: *u64)->String
{
    let mime = idmlGraphicMimeType(path)
    if !mime.count do
        return {}
    let info = catch File.info(path) as infoError
    if infoError != null or info.size > IdmlLinkedGraphicDataLimit or info.size > IdmlLinkedGraphicsDataLimit - loaded[] do
        return {}
    var options: DecodeOptions
    options.decodePixels   = false
    options.decodeMetadata = false
    let probe = catch Image.load(path, options) as probeError
    if probeError != null or probe.width <= 0 or probe.height <= 0 or cast(u64) probe.width * cast(u64) probe.height > IdmlGraphicSourcePixelLimit do
        return {}

    loaded[] += info.size
    return String.from(path)
}

// Resolves a linked image without fetching. A direct file URI wins; a same-folder basename is a
// portable fallback for a document moved together with its links after InDesign saved host paths.
private func idmlLinkedGraphicSource(documentFileName, item: string, loaded: *u64)->String
{
    let embedded = idmlEmbeddedGraphicDataUri(item)
    if embedded.count do
        return embedded

    let imageStart = Utf8.indexOf(item, "<Image ")
    let imageEnd   = imageStart == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(item, "</Image>", imageStart)
    let linkStart  = imageStart == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(item, "<Link ", imageStart)
    let linkEnd    = linkStart == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(item, '>'rune, linkStart)
    if imageEnd == Swag.U64.Max or linkEnd == Swag.U64.Max or linkStart > imageEnd do
        return {}

    let linkedPath = idmlFileUriPath(idmlAttribute(item[linkStart until linkEnd + 1], "LinkResourceURI"))
    if linkedPath.isEmpty() do
        return {}
    let direct = idmlLocalGraphicSource(linkedPath.toString(), loaded)
    if direct.count do
        return direct

    let folder = Path.directoryName(documentFileName)
    let name   = Path.fileName(linkedPath.toString())
    return folder != null and name != null ? idmlLocalGraphicSource(Path.combine(folder!, name!).toString(), loaded) : String{}
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

private func idmlFontStyleBold(value: string)->bool
{
    return Utf8.contains(value, "Bold") or Utf8.contains(value, "bold") or value == "W6" or value == "W7" or value == "W8" or value == "W9"
}

private func idmlFontStyleItalic(value: string)->bool
{
    return Utf8.contains(value, "Italic") or Utf8.contains(value, "italic") or Utf8.contains(value, "Oblique") or Utf8.contains(value, "oblique")
}

private func idmlContainsCjk(text: string)->bool
{
    var cursor = 0'u64
    while cursor < text.count
    {
        let {c, eat} = Utf8.decodeRune(text[cursor to ])
        if c >= 0x2E80 and c <= 0x9FFF or
           c >= 0xAC00 and c <= 0xD7A3 or
           c >= 0xF900 and c <= 0xFAFF or
           c >= 0xFE30 and c <= 0xFE4F or
           c >= 0xFF00 and c <= 0xFFEF or
           c >= 0x20000 and c <= 0x3FFFD do
            return true
        cursor += eat
    }

    return false
}

private func idmlTextStyleCss(style: const *IdmlTextStyle)->String
{
    var result: retval
    if style.fontSize > 0 do
        result += Format.toString("font-size:%em;", style.fontSize / 12)
    if style.autoLeading > 0 do
        result += Format.toString("line-height:%;", style.autoLeading / 100)
    let scale = style.fontSize > 0 ? style.fontSize : 12
    if style.spaceBefore != 0 do
        result += Format.toString("margin-top:%em;", style.spaceBefore / scale)
    if style.spaceAfter != 0 do
        result += Format.toString("margin-bottom:%em;", style.spaceAfter / scale)
    if style.leftIndent != 0 do
        result += Format.toString("padding-left:%em;", style.leftIndent / scale)
    if style.rightIndent != 0 do
        result += Format.toString("padding-right:%em;", style.rightIndent / scale)
    if style.firstLineIndent != 0 do
        result += Format.toString("text-indent:%em;", style.firstLineIndent / scale)
    if !style.fill.isEmpty() do
        result += Format.toString("color:%;", style.fill)
    if !style.alignment.isEmpty() do
        result += Format.toString("text-align:%;", style.alignment)
    if style.bold do
        result += "font-weight:bold;"
    if style.italic do
        result += "font-style:italic;"
    result += style.cjk ? "font-family:cjk;" : style.serif ? "font-family:serif;" : "font-family:sans-serif;"
    return result
}

private func idmlCharacterStyleCss(tag: string, colors: const *HashTable'(String, String))->String
{
    var result: retval
    let fontSize = idmlNumber(idmlAttribute(tag, "PointSize")).value
    if fontSize > 0 do
        result += Format.toString("font-size:%em;", fontSize / 12)
    let color = idmlColor(colors, idmlAttribute(tag, "FillColor"), idmlAttribute(tag, "FillTint"))
    if color.count do
        result += Format.toString("color:%;", color)
    let fontStyle = idmlAttribute(tag, "FontStyle")
    if idmlFontStyleBold(fontStyle) do
        result += "font-weight:bold;"
    if idmlFontStyleItalic(fontStyle) do
        result += "font-style:italic;"
    if idmlAttribute(tag, "Capitalization") == "AllCaps" do
        result += "text-transform:uppercase;"
    if idmlAttribute(tag, "Underline") == "true" do
        result += "text-decoration:underline;"
    if idmlAttribute(tag, "StrikeThru") == "true" do
        result += "text-decoration:line-through;"
    let tracking = idmlNumber(idmlAttribute(tag, "Tracking")).value
    if tracking != 0 do
        result += Format.toString("letter-spacing:%em;", tracking / 1_000)
    if idmlAttribute(tag, "Position") == "Superscript" do
        result += "vertical-align:super;"
    if idmlAttribute(tag, "Position") == "Subscript" do
        result += "vertical-align:sub;"
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
        let content  = source[openEnd + 1 until close]
        let styleKey = idmlAttribute(tag, "AppliedParagraphStyle")
        let style    = styles.tryFind(styleKey)
        result += "<div style=\"margin:0;"
        if style do
            result += idmlTextStyleCss(&style!.value)
        if idmlContainsCjk(content) do
            result += "font-family:cjk;"
        result += "\">"
        if style and style!.value.bullet do
            result += "&#x2022;&nbsp;"
        result += idmlCharacterRangeHtml(content, colors)
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

private func idmlTintedColor(color, tint: string)->String
{
    let percentage = idmlNumber(tint)
    if !percentage.valid or percentage.value >= 100 do
        return String.from(color)

    let open  = Utf8.indexOf(color, '('rune)
    let close = Utf8.indexOf(color, ')'rune, open == Swag.U64.Max ? 0 : open + 1)
    if open == Swag.U64.Max or close == Swag.U64.Max do
        return String.from(color)
    var channels: Array'f32
    for channel in Tokenize.split(color[open + 1 until close], ','rune)
    {
        let value = idmlNumber(Latin1.trim(channel))
        if !value.valid do
            return String.from(color)
        channels.add(value.value)
    }
    if channels.count != 3 do
        return String.from(color)

    let factor = Math.clamp(percentage.value / 100, 0, 1)
    return Format.toString("rgb(%, %, %)",
                           cast(u32) Math.round(255 + (channels[0] - 255) * factor),
                           cast(u32) Math.round(255 + (channels[1] - 255) * factor),
                           cast(u32) Math.round(255 + (channels[2] - 255) * factor))
}

private func idmlColor(colors: const *HashTable'(String, String), name: string, tint = "")->String
{
    if name == "Swatch/None" or !name.count do
        return ""
    let found = colors.tryFind(name)
    return found ? idmlTintedColor(found!.value.toString(), tint) : ""
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
            style.fontSize        = idmlNumber(idmlAttribute(tag, "PointSize")).value
            style.autoLeading     = idmlNumber(idmlAttribute(tag, "AutoLeading")).value
            style.spaceBefore     = idmlNumber(idmlAttribute(tag, "SpaceBefore")).value
            style.spaceAfter      = idmlNumber(idmlAttribute(tag, "SpaceAfter")).value
            style.leftIndent      = idmlNumber(idmlAttribute(tag, "LeftIndent")).value
            style.rightIndent     = idmlNumber(idmlAttribute(tag, "RightIndent")).value
            style.firstLineIndent = idmlNumber(idmlAttribute(tag, "FirstLineIndent")).value
            style.fill            = idmlColor(colors, idmlAttribute(tag, "FillColor"), idmlAttribute(tag, "FillTint"))
            style.alignment       = idmlTextAlignment(idmlAttribute(tag, "Justification"))
            style.cjk             = idmlAttribute(tag, "AppliedLanguage") == "$ID/Japanese"
            style.bold            = idmlFontStyleBold(idmlAttribute(tag, "FontStyle"))
            style.italic          = idmlFontStyleItalic(idmlAttribute(tag, "FontStyle"))
            style.bullet          = idmlAttribute(tag, "BulletsAndNumberingListType") == "BulletList"
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

private func idmlAppendItems(fileName, source: string, stories: const *HashTable'(String, String), colors: const *HashTable'(String, String), linkedGraphicBytes: *u64, pages: *Array'IdmlPage)
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
                item.self       = idmlAttribute(tag, "Self")
                item.fill       = idmlColor(colors, idmlAttribute(tag, "FillColor"), idmlAttribute(tag, "FillTint"))
                item.stroke     = idmlColor(colors, idmlAttribute(tag, "StrokeColor"), idmlAttribute(tag, "StrokeTint"))
                item.strokeSize = idmlNumber(idmlAttribute(tag, "StrokeWeight")).value
                item.oval       = oval
                item.line       = line
                item.imageFrame = Utf8.indexOf(content, "<Image ") != Swag.U64.Max
                item.cornerTopLeft     = idmlRoundedCornerRadius(tag, "TopLeft")
                item.cornerTopRight    = idmlRoundedCornerRadius(tag, "TopRight")
                item.cornerBottomRight = idmlRoundedCornerRadius(tag, "BottomRight")
                item.cornerBottomLeft  = idmlRoundedCornerRadius(tag, "BottomLeft")
                if line
                {
                    item.lineStartArrow = idmlAttribute(tag, "LeftLineEnd") == "TriangleArrowHead"
                    item.lineEndArrow   = idmlAttribute(tag, "RightLineEnd") == "TriangleArrowHead"
                    let padding         = Math.max(item.strokeSize * 2, 4)
                    item.bounds.left   -= padding
                    item.bounds.top    -= padding
                    item.bounds.width  += 2 * padding
                    item.bounds.height += 2 * padding
                    item.clipPath = idmlLineClipPath(content, &transform, pages[pageIndex].bounds.left, pages[pageIndex].bounds.top, &item.bounds, item.strokeSize, item.lineStartArrow, item.lineEndArrow)
                }
                elif polygon do
                    item.clipPath = idmlPolygonClipPath(content, &transform)
                if item.imageFrame
                {
                    item.image = idmlLinkedGraphicSource(fileName, content, linkedGraphicBytes)
                    var imageBounds: IdmlBounds
                    if idmlBoundsFromGraphic(content, &transform, &imageBounds)
                    {
                        imageBounds.left -= pages[pageIndex].bounds.left
                        imageBounds.top  -= pages[pageIndex].bounds.top
                        item.imageBounds    = imageBounds
                        item.imageHasBounds = true
                    }
                }
                if textItem
                {
                    item.story         = idmlAttribute(tag, "ParentStory")
                    item.previousFrame = idmlAttribute(tag, "PreviousTextFrame")
                    item.nextFrame     = idmlAttribute(tag, "NextTextFrame")
                    idmlTextFrameLayout(content, &item)
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
                if !item.story.isEmpty() do
                    page.textFrameCount += 1
            }
            break
        }
    }
}

// A story is one text flow, potentially crossing several positioned text frames and pages. The
// package stores its text once; duplicating it in every frame is both visually wrong and expensive
// for long editorial copy. Preserve paragraph markup and partition it across the linked frames.
private func idmlFindTextFrame(pages: *Array'IdmlPage, self: string)->#null *IdmlItem
{
    for &page in pages
    {
        for &item in page.items where item.self == self do
            return item
    }

    return null
}

private func idmlStoryBlockEnd(source: string, start: u64)->u64
{
    let close = Utf8.indexOf(source, "</div>", start)
    return close == Swag.U64.Max ? source.count : close + ("</div>").count
}

// The local HTML renderer owns line breaking, but a text frame's area is a reliable first-order
// capacity signal. Weight paragraph blocks by that area so an editorial chain with unequal columns
// does not place the same amount of prose into a caption-sized frame and a body-sized frame.
private func idmlTextFrameCapacity(frame: const *IdmlItem)->f32
{
    let width  = frame.bounds.width - frame.textInsetLeft - frame.textInsetRight
    let height = frame.bounds.height - frame.textInsetTop - frame.textInsetBottom
    return Math.max(width, 1) * Math.max(height, 1)
}

private func idmlFlowStory(source: string, frames: const *Array'*IdmlItem)
{
    if !frames.count or !source.count do
        return

    var blockCount: u64
    var cursor = 0'u64
    while cursor < source.count
    {
        cursor = idmlStoryBlockEnd(source, cursor)
        blockCount += 1
    }

    var totalCapacity: f32
    for frame in frames do
        totalCapacity += idmlTextFrameCapacity(frame!)

    cursor             = 0
    var allocatedBlocks: u64
    var remainingBlocks = blockCount
    var consumedCapacity: f32
    for frame, index in frames
    {
        let remainingFrames = frames.count - index
        consumedCapacity += idmlTextFrameCapacity(frame!)
        let target          = cast(u64) Math.round(cast(f32) blockCount * consumedCapacity / totalCapacity)
        let minimum         = remainingBlocks >= remainingFrames ? 1 : 0
        let maximum         = remainingBlocks - (remainingBlocks >= remainingFrames ? remainingFrames - 1 : 0)
        let desired         = target > allocatedBlocks ? target - allocatedBlocks : 0
        let take            = Math.clamp(desired, minimum, maximum)
        var text: String
        for take
        {
            let end = idmlStoryBlockEnd(source, cursor)
            text += source[cursor until end]
            cursor = end
        }
        allocatedBlocks += take
        remainingBlocks -= take
        frame!.text = #move text
    }
}

private func idmlFlowTextStories(pages: *Array'IdmlPage, stories: const *HashTable'(String, String))
{
    for &page in pages
    {
        for &item in page.items where !item.story.isEmpty() do
            item.text.clear()
    }

    for &page in pages
    {
        for &item in page.items
        {
            if item.story.isEmpty() or item.previousFrame != "n" do
                continue
            let story = stories.tryFind(item.story)
            if !story do
                continue

            var frames: Array'*IdmlItem
            var frame: #null *IdmlItem = item
            while frame and frames.count < IdmlFrameLimit
            {
                var repeated: bool
                for existing in frames where existing == frame
                {
                    repeated = true
                    break
                }
                if repeated do
                    break
                frames.add(frame!)
                if frame!.nextFrame.isEmpty() or frame!.nextFrame == "n" do
                    break
                frame = idmlFindTextFrame(pages, frame!.nextFrame.toString())
            }

            idmlFlowStory(story!.value.toString(), &frames)
        }
    }
}

private func idmlLoadMasters(fileName: string, archive: const *ZipArchive, designMap: string, stories: const *HashTable'(String, String), colors: const *HashTable'(String, String), linkedGraphicBytes: *u64)->Array'IdmlMaster
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
                    idmlAppendItems(fileName, source.toString(), stories, colors, linkedGraphicBytes, &master.pages)
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

    var linkedGraphicBytes: u64
    let masters = idmlLoadMasters(fileName, &archive, designMap.toString(), &stories, &colors, &linkedGraphicBytes)
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
            idmlAppendItems(fileName, spread.toString(), &stories, &colors, &linkedGraphicBytes, &spreadPages)
            for page in spreadPages do
                result.pages.add(page[])
        }
        cursor = end + 1
        spreadCount += 1
    }

    if result.pages.isEmpty() do
        fail InvalidFormatError{"IDML document contains no readable pages"}
    idmlFlowTextStories(&result.pages, &stories)
    return result
}
