#global internal
#global namespace Viewers.InDesign.Idml

using Core, Core.Errors, Pixel

private
{
    // IDML is an InDesign document package rather than a preview image. These bounds keep a damaged
    // package from turning a simple document inspection into an unbounded decompression operation.
    const DocumentByteLimit        = 128 * 1024 * 1024'u64
    const PageLimit                = 2_000'u64
    const SpreadLimit              = 1_000'u64
    const FrameLimit               = 100_000'u64
    const EmbeddedGraphicDataLimit = 24 * 1024 * 1024'u64
    const LinkedGraphicDataLimit   = 8 * 1024 * 1024'u64
    const LinkedGraphicsDataLimit  = 24 * 1024 * 1024'u64
    const GraphicSourcePixelLimit  = 16 * 1024 * 1024'u64
    const TextColumnLimit          = 16'u32
}

// What remains of the page and frame bounds while one package is read.
//
// Both bounds are document-wide: every spread and master spends from the same budget, and so does
// each master item copied onto a page, so a package of many small spreads cannot multiply them.
struct LoadLimits
{
    pages:  u64 = PageLimit
    frames: u64 = FrameLimit
}

// A rectangle in page points.
private struct Bounds
{
    left, top:     f32
    width, height: f32
}

private impl Bounds
{
    // Whether the point `x, y` lies inside the box, edges included.
    mtd const contains(x, y: f32)->bool => x >= .left and x <= .left + .width and y >= .top and y <= .top + .height
}

// An affine transform as IDML writes it: `a b c d` for the linear part, `x y` for the translation.
private struct Transform
{
    a, d: f32 = 1
    b, c: f32
    x, y: f32
}

// One page item resolved to page coordinates: a frame, a shape, a line, or an image, with the
// story text it shows and the layout of that text.
private struct Item
{
    bounds:             Bounds
    self:               String
    story:              String
    previousFrame:      String
    nextFrame:          String
    text:               String
    fill:               String
    stroke:             String
    strokeSize:         f32
    oval:               bool
    line:               bool
    lineStartArrow:     bool
    lineEndArrow:       bool
    imageFrame:         bool
    imageHasBounds:     bool
    cornerTopLeft:      f32
    cornerTopRight:     f32
    cornerBottomRight:  f32
    cornerBottomLeft:   f32
    hasTextFrameLayout: bool
    textColumns:        u32 = 1
    textColumnGutter:   f32
    textColumnWidth:    f32
    textInsetTop:       f32
    textInsetRight:     f32
    textInsetBottom:    f32
    textInsetLeft:      f32
    clipPath:           String
    image:              String
    imageBounds:        Bounds
}

// The paragraph and character properties a story needs to be rendered as HTML.
private struct TextStyle
{
    fontSize:        f32
    autoLeading:     f32
    spaceBefore:     f32
    spaceAfter:      f32
    leftIndent:      f32
    rightIndent:     f32
    firstLineIndent: f32
    fill:            String
    alignment:       String
    serif:           bool
    cjk:             bool
    bold:            bool
    italic:          bool
    bullet:          bool
}

// One page of an IDML document, with the positioned items of its scene.
struct Page
{
    name:           String
    master:         String
    bounds:         Bounds
    items:          Array'Item
    textFrameCount: u64
}

// A master spread: pages whose items every page based on it also shows.
private struct Master
{
    self:  String
    pages: Array'Page
}

impl Page
{
    // Returns the number of image frames whose picture could not be resolved.
    mtd const missingImageCount()->u64
    {
        var result: retval
        for item in .items where item.imageFrame and item.image.isEmpty() do
            result += 1
        return result
    }

    // The style sheet of a page. Its `%` take, in pixels: the page margin, the item font size and
    // padding, and the font size and top padding of a missing image.
    const PageStyle = """<style>
                         html, body { margin: 0; padding: 0; background: #343438 }
                         .idml-page { position: relative; margin: %px auto; background: #fff; color: #101014; box-shadow: 0 2px 12px #0008; overflow: hidden }
                         .idml-item { position: absolute; box-sizing: border-box; overflow: hidden; font: %px/1.25 sans-serif; padding: %px }
                         .idml-text-column { position: absolute; box-sizing: border-box; overflow: hidden }
                         .idml-image { position: absolute; display: block }
                         .idml-missing-image { display: block; width: 100%%; height: 100%%; background: #e5e5e5; color: #777; font: %px sans-serif; text-align: center; padding-top: %px }
                         </style>"""

    // Builds one offline page scene from positioned IDML items, at `scale` clamped to 0.25..3.
    //
    // The HTML engine is used solely as the local paint and text-layout backend; all package
    // parsing and scene construction are Swag.
    mtd const html(scale: f32)->String
    {
        var result: retval
        let factor   = Math.clamp(scale, 0.25, 3)
        let itemFont = 12 * factor
        let inset    = 2 * factor
        result += Format.toString(PageStyle, 24 * factor, itemFont, inset, 18 * factor, 8 * factor)
        result += Format.toString("<div class=\"idml-page\" style=\"width:%px;height:%px\">", .bounds.width * factor, .bounds.height * factor)
        for item in .items
        {
            result += Format.toString("<div class=\"idml-item\" style=\"left:%px;top:%px;width:%px;height:%px;background:%;border:%px solid %;%;%;%;%\">",
                                      item.bounds.left * factor,
                                      item.bounds.top * factor,
                                      item.bounds.width * factor,
                                      item.bounds.height * factor,
                                      item.line ? (item.stroke.isEmpty() ? "transparent" : item.stroke) : (item.fill.isEmpty() ? "transparent" : item.fill),
                                      item.line ? 0 : item.strokeSize * factor,
                                      item.stroke.isEmpty() ? "transparent" : item.stroke,
                                      item.oval ? "border-radius:50%" : cornerCss(item, factor),
                                      item.clipPath,
                                      item.imageFrame ? "padding:0" : "",
                                      textFramePaddingCss(item, factor))
            if not item.image.isEmpty()
            {
                let imageBounds = item.imageHasBounds ? &item.imageBounds : &item.bounds
                result += Format.toString("<img class=\"idml-image\" style=\"left:%px;top:%px;width:%px;height:%px\" src=\"%\">",
                                          (imageBounds.left - item.bounds.left) * factor,
                                          (imageBounds.top - item.bounds.top) * factor,
                                          imageBounds.width * factor,
                                          imageBounds.height * factor,
                                          escapeHtmlAttribute(item.image))
            }
            elif item.imageFrame
            {
                result += "<span class=\"idml-missing-image\">×</span>"
            }

            // Text is escaped while the IDML story is converted to local paragraph markup. It is
            // deliberately not a document-supplied HTML fragment.
            appendTextColumns(&result, item, factor)
            result += "</div>"
        }

        result += "</div>"
        return result
    }
}

// Returns the CSS radii of a frame's rounded corners, or an empty string when every corner is square.
//
// InDesign may give each corner a different treatment. Rounded corners are directly representable
// by the local painter, so the four radii are retained rather than flattened.
private func cornerCss(item: const *Item, factor: f32)->String
{
    if item.cornerTopLeft <= 0 and item.cornerTopRight <= 0 and item.cornerBottomRight <= 0 and item.cornerBottomLeft <= 0 do
        return {}
    return Format.toString("border-radius:%px %px %px %px", item.cornerTopLeft * factor, item.cornerTopRight * factor, item.cornerBottomRight * factor, item.cornerBottomLeft * factor)
}

private func textFramePaddingCss(item: const *Item, factor: f32)->String
{
    if not item.hasTextFrameLayout do
        return {}
    if item.textColumns > 1 do
        return "padding:0"
    return Format.toString("padding:%px %px %px %px", item.textInsetTop * factor, item.textInsetRight * factor, item.textInsetBottom * factor, item.textInsetLeft * factor)
}

// Appends the story text of a frame to `html`, laid out in the frame's columns.
//
// The HTML painter does not flow arbitrary text into columns. The IDML geometry is preserved with
// sibling clipping rectangles, each receiving complete paragraph blocks, so a malformed story never
// leaves unmatched markup in the page scene.
private func appendTextColumns(html: *String, item: const *Item, factor: f32)
{
    if item.text.isEmpty() do
        return
    if not item.hasTextFrameLayout or item.textColumns <= 1
    {
        html[] += item.text
        return
    }

    let columns = Math.clamp(item.textColumns, 1'u32, TextColumnLimit)
    let left    = item.textInsetLeft * factor
    let top     = item.textInsetTop * factor
    let width   = Math.max(item.bounds.width * factor - left - item.textInsetRight * factor, 1)
    let height  = Math.max(item.bounds.height * factor - top - item.textInsetBottom * factor, 1)
    var gap     = Math.max(item.textColumnGutter * factor, 0)
    if not gap and item.textColumnWidth > 0 and columns > 1 do
        gap = Math.max((width - item.textColumnWidth * factor * columns) / (columns - 1), 0)
    let columnWidth = item.textColumnWidth > 0 ? item.textColumnWidth * factor : Math.max((width - gap * (columns - 1)) / columns, 1)
    var cursor      = 0'u64
    for column in columns
    {
        if cursor >= item.text.count do
            break
        let remainingColumns = columns - column
        let target = (item.text.count - cursor) / remainingColumns
        var end    = cursor
        while end < item.text.count
        {
            let next = storyBlockEnd(item.text, end)
            if end != cursor and next - cursor > target do
                break
            end = next
            if end - cursor >= target do
                break
        }

        if end == cursor do
            end = storyBlockEnd(item.text, cursor)
        html[] += Format.toString("<div class=\"idml-text-column\" style=\"left:%px;top:%px;width:%px;height:%px\">", left + column * (columnWidth + gap), top, columnWidth, height)
        html[] += item.text[cursor until end]
        html[] += "</div>"
        cursor = end
    }
}

// An IDML package, read as the pages it lays out.
struct Document
{
    fileName: String
    pages:    Array'Page
}

// Returns the text of the package entry stored at `path`, failing when it is missing or not UTF-8.
private func readEntry(fileName: string, archive: const *Archive.Zip, path: string)->String fail
{
    let entry = archive.tryFindEntry(path)
    if not entry or entry.isDirectory do
        fail InvalidFormatError{Errors.mkString(Format.toString(texts().err_MissingPart, path))}
    let bytes = try Archive.Zip.loadEntry(fileName, entry)
    if not Utf8.isValid(bytes.toSlice()) do
        fail InvalidFormatError{Errors.mkString(Format.toString(texts().err_PartNotXml, path))}
    return cast(string, bytes.toSlice())
}

private func attribute(tag: string, name: string)->string
{
    var marker: String
    marker += name
    marker += "=\""
    let start = Utf8.indexOf(tag, marker)
    if start == Swag.U64.Max do
        return ""
    let valueStart = start + marker.count
    let valueEnd   = Utf8.indexOf(tag, '"'rune, valueStart)
    if valueEnd == Swag.U64.Max do
        return ""
    return tag[valueStart until valueEnd]
}

private func parseNumber(text: string)->{ value: f32, valid: bool }
{
    let trimmed = Latin1.trim(text)
    if not trimmed.count do
        return {}
    let parsed = catch StrConv.parseF32(trimmed) as parseError
    if parseError != null or parsed.eat != trimmed.count or parsed.ovf do
        return {}
    return {parsed.value, true}
}

// Returns the radius of one rounded frame corner, or zero when that corner is not rounded.
//
// A per-corner declaration overrides the legacy all-corners value. A corner whose explicit option
// is not RoundedCorner stays square: bevelled and inverse corners need path rendering instead.
private func roundedCornerRadius(tag, corner: string)->f32
{
    let cornerOption = attribute(tag, Format.toString("%CornerOption", corner))
    if cornerOption.count
    {
        if cornerOption != "RoundedCorner" do
            return 0
        let radius = parseNumber(attribute(tag, Format.toString("%CornerRadius", corner)))
        return radius.valid ? Math.max(radius.value, 0) : 0
    }

    if attribute(tag, "CornerOption") != "RoundedCorner" do
        return 0
    let radius = parseNumber(attribute(tag, "CornerRadius"))
    return radius.valid ? Math.max(radius.value, 0) : 0
}

private func firstOpenTag(source, name: string)->String
{
    var marker: String
    marker += '<'rune
    marker += name
    let start = Utf8.indexOf(source, marker)
    if start == Swag.U64.Max do
        return {}
    let end = Utf8.indexOf(source, '>'rune, start)
    return end == Swag.U64.Max ? {} : source[start until end + 1]
}

private func elementContents(source, name: string)->String
{
    let opening = firstOpenTag(source, name)
    if opening.isEmpty() do
        return {}
    let start = Utf8.indexOf(source, opening)
    let body  = start + opening.count
    var close: String
    close += "</"
    close += name
    close += '>'rune
    let end = Utf8.indexOf(source, close, body)
    return end == Swag.U64.Max ? {} : source[body until end]
}

// Reads a text frame's inset spacing from its preference markup into `item`. IDML stores either one
// `unit` value for all sides or a list of four; any other form leaves the insets unchanged.
private func textFrameInsets(preference: string, item: *Item)
{
    let insetTag = firstOpenTag(preference, "InsetSpacing")
    let contents = elementContents(preference, "InsetSpacing")
    if insetTag.isEmpty() or contents.isEmpty() do
        return
    if attribute(insetTag, "type") == "unit"
    {
        let inset = parseNumber(contents)
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
        let start = Utf8.indexOf(contents, "<ListItem", cursor)
        let open  = start == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(contents, '>'rune, start)
        let end   = open == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(contents, "</ListItem>", open + 1)
        if end == Swag.U64.Max do
            break
        let value = parseNumber(contents[open + 1 until end])
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

// Reads a text frame's column count, gutter, fixed column width and insets from its
// `TextFramePreference`.
private func textFrameLayout(content: string, item: *Item)
{
    let preference = firstOpenTag(content, "TextFramePreference")
    if preference.isEmpty() do
        return
    item.hasTextFrameLayout = true
    let columns = parseNumber(attribute(preference, "TextColumnCount"))
    if columns.valid and columns.value >= 1 do
        item.textColumns = Math.clamp(cast(u32, columns.value), 1'u32, TextColumnLimit)
    let gutter = parseNumber(attribute(preference, "TextColumnGutter"))
    if gutter.valid do
        item.textColumnGutter = Math.max(gutter.value, 0)
    let width = parseNumber(attribute(preference, "TextColumnFixedWidth"))
    if width.valid do
        item.textColumnWidth = Math.max(width.value, 0)
    textFrameInsets(content, item)
}

// The numbers of a space-separated list; empty when any part is not a number.
private func parseNumbers(text: string)->Array'f32
{
    var result: retval
    for part in Tokenize.split(text, ' 'rune)
    {
        let number = parseNumber(part)
        if not number.valid do
            return {}
        result.add(number.value)
    }

    return result
}

private func boundsFromGeometric(value: string, result: *Bounds)->bool
{
    let numbers = parseNumbers(value)
    if numbers.count != 4 do
        return false
    result.top    = numbers[0]
    result.left   = numbers[1]
    result.height = numbers[2] - numbers[0]
    result.width  = numbers[3] - numbers[1]
    return result.width > 0 and result.height > 0
}

// Reads the `ItemTransform` matrix of `tag`; a missing or malformed one gives the identity.
private func parseTransform(tag: string)->Transform
{
    var result: retval
    let transform = attribute(tag, "ItemTransform")
    if not transform.count do
        return result
    let numbers = parseNumbers(transform)
    if numbers.count != 6 do
        return result
    result.a = numbers[0]
    result.b = numbers[1]
    result.c = numbers[2]
    result.d = numbers[3]
    result.x = numbers[4]
    result.y = numbers[5]
    return result
}

private func composeTransform(parent, child: const *Transform)->Transform
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

// The anchors of the path points of `item`, placed by `transform`; empty when one is malformed.
private func pathAnchors(item: string, transform: const *Transform)->Array'Math.Vector2
{
    var result: retval
    var cursor = 0'u64
    for
    {
        let pointStart = Utf8.indexOf(item, "<PathPointType", cursor)
        if pointStart == Swag.U64.Max do
            return result
        let pointEnd = Utf8.indexOf(item, '>'rune, pointStart)
        if pointEnd == Swag.U64.Max do
            return {}
        let values = parseNumbers(attribute(item[pointStart until pointEnd + 1], "Anchor"))
        if values.count != 2 do
            return {}
        result.add({transform.a * values[0] + transform.c * values[1] + transform.x,
                    transform.b * values[0] + transform.d * values[1] + transform.y})
        cursor = pointEnd + 1
    }
}

// Computes the bounding box of an item's path anchors after `transform`. Returns false for a
// degenerate box unless `allowLine` is set, which gives a line at least one unit thick.
private func boundsFromPath(item: string, transform: const *Transform, result: *Bounds, allowLine = false)->bool
{
    let anchors = pathAnchors(item, transform)
    if anchors.count < 2 do
        return false

    var left   = Swag.F32.Max
    var top    = Swag.F32.Max
    var right  = -Swag.F32.Max
    var bottom = -Swag.F32.Max
    for anchor in anchors
    {
        left   = Math.min(left, anchor.x)
        right  = Math.max(right, anchor.x)
        top    = Math.min(top, anchor.y)
        bottom = Math.max(bottom, anchor.y)
    }

    if not allowLine and (right <= left or bottom <= top) do
        return false
    result.left   = left
    result.top    = top
    result.width  = allowLine ? Math.max(right - left, 1) : right - left
    result.height = allowLine ? Math.max(bottom - top, 1) : bottom - top
    return true
}

// Reports whether the image of a frame has axis-aligned placed bounds, and stores them in `result`.
//
// An image's transform is independent from its enclosing frame. The axis-aligned cases are kept as
// a local image rectangle so a crop or proportional fit does not become a stretched frame fill.
// Rotated, sheared, and reflected images remain on the conservative frame fallback until the scene
// renderer can preserve their orientation.
private func boundsFromGraphic(item: string, parent: const *Transform, result: *Bounds)->bool
{
    let imageStart   = Utf8.indexOf(item, "<Image ")
    let imageOpenEnd = imageStart == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(item, '>'rune, imageStart)
    let imageEnd     = imageOpenEnd == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(item, "</Image>", imageOpenEnd + 1)
    let boundsStart  = imageOpenEnd == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(item, "<GraphicBounds ", imageOpenEnd + 1)
    let boundsEnd    = boundsStart == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(item, '>'rune, boundsStart)
    if imageEnd == Swag.U64.Max or boundsEnd == Swag.U64.Max or boundsStart > imageEnd do
        return false

    let boundsTag = item[boundsStart until boundsEnd + 1]
    let left      = parseNumber(attribute(boundsTag, "Left"))
    let top       = parseNumber(attribute(boundsTag, "Top"))
    let right     = parseNumber(attribute(boundsTag, "Right"))
    let bottom    = parseNumber(attribute(boundsTag, "Bottom"))
    if not left.valid or not top.valid or not right.valid or not bottom.valid or right.value <= left.value or bottom.value <= top.value do
        return false

    let imageTag       = item[imageStart until imageOpenEnd + 1]
    let childTransform = parseTransform(imageTag)
    let imageTransform = composeTransform(parent, &childTransform)
    if Math.abs(imageTransform.b) > 0.0001 or Math.abs(imageTransform.c) > 0.0001 or imageTransform.a <= 0 or imageTransform.d <= 0 do
        return false
    result.left   = imageTransform.a * left.value + imageTransform.x
    result.top    = imageTransform.d * top.value + imageTransform.y
    result.width  = imageTransform.a * (right.value - left.value)
    result.height = imageTransform.d * (bottom.value - top.value)
    return result.width > 0 and result.height > 0
}

// Builds a CSS `clip-path` polygon from the item's anchors, in percentages of its bounding box.
// Returns an empty string for fewer than three anchors or an empty box.
private func polygonClipPath(item: string, transform: const *Transform)->String
{
    var bounds: Bounds
    if not boundsFromPath(item, transform, &bounds) do
        return {}
    let anchors = pathAnchors(item, transform)
    if anchors.count < 3 do
        return {}

    var result: retval
    result += "clip-path:polygon("
    for anchor, index in anchors
    {
        if index do
            result += ","
        result += Format.toString("%", 100 * (anchor.x - bounds.left) / bounds.width)
        result += "% "
        result += Format.toString("%", 100 * (anchor.y - bounds.top) / bounds.height)
        result += "%"
    }

    result += ");"
    return result
}

// Returns the CSS clip path that paints a graphic line and its arrowheads inside `bounds`.
//
// A graphic line is an oriented stroke, not its axis-aligned bounding rectangle. Its painted
// silhouette is built in the local page space so the HTML painter retains both direction and
// triangular InDesign arrowheads without relying on an external SVG implementation.
private func lineClipPath(item: string, transform: const *Transform, pageLeft, pageTop: f32, bounds: const *Bounds, strokeSize: f32, startArrow, endArrow: bool)->String
{
    let anchors = pathAnchors(item, transform)
    if anchors.count != 2 or bounds.width <= 0 or bounds.height <= 0 do
        return {}

    let firstX  = anchors[0].x - pageLeft
    let firstY  = anchors[0].y - pageTop
    let secondX = anchors[1].x - pageLeft
    let secondY = anchors[1].y - pageTop
    let dx      = secondX - firstX
    let dy      = secondY - firstY
    let length  = Math.sqrt(dx * dx + dy * dy)
    if length < 0.01 do
        return {}

    let halfStroke = Math.max(strokeSize, 0.75) * 0.5
    let normalX    = -dy * halfStroke / length
    let normalY    = dx * halfStroke / length
    let startInset = startArrow ? Math.min(length * 0.45, Math.max(6, halfStroke * 8)) : 0
    let endInset   = endArrow ? Math.min(length * 0.45, Math.max(6, halfStroke * 8)) : 0
    let startBaseX = firstX + dx * startInset / length
    let startBaseY = firstY + dy * startInset / length
    let endBaseX   = secondX - dx * endInset / length
    let endBaseY   = secondY - dy * endInset / length

    // The silhouette, around from the start: one side of the stroke out to the end, back along
    // the other. An arrowhead puts its tip on the end point and its base corners on the sides.
    var outline: Array'Math.Vector2
    if startArrow
    {
        outline.add({firstX, firstY})
        outline.add({startBaseX + normalX, startBaseY + normalY})
    }
    else
    {
        outline.add({firstX + normalX, firstY + normalY})
    }

    outline.add({endBaseX + normalX, endBaseY + normalY})
    if endArrow do
        outline.add({secondX, secondY})
    else do
        outline.add({secondX + normalX, secondY + normalY})
    outline.add({endBaseX - normalX, endBaseY - normalY})
    if startArrow do
        outline.add({startBaseX - normalX, startBaseY - normalY})
    else do
        outline.add({firstX - normalX, firstY - normalY})

    var result: retval
    result += "clip-path:polygon("
    for vertex, index in outline
    {
        if index do
            result += ","
        result += Format.toString("%{f3}%% %{f3}%%", 100 * (vertex.x - bounds.left) / bounds.width, 100 * (vertex.y - bounds.top) / bounds.height)
    }

    result += ");"
    return result
}

// Returns an image data URI only for pixels embedded in the IDML package.
func embeddedGraphicDataUri(item: string)->String
{
    let imageStart = Utf8.indexOf(item, "<Image ")
    if imageStart == Swag.U64.Max do
        return {}
    let imageOpenEnd = Utf8.indexOf(item, '>'rune, imageStart)
    let imageEnd     = imageOpenEnd == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(item, "</Image>", imageOpenEnd + 1)
    if imageEnd == Swag.U64.Max do
        return {}

    let type = attribute(item[imageStart until imageOpenEnd + 1], "ImageTypeName")
    let mime = Utf8.contains(type, "JPEG") ? "image/jpeg" : Utf8.contains(type, "PNG") ? "image/png" : ""
    if not mime.count do
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
        if payload.count + end - contentStart > EmbeddedGraphicDataLimit do
            return {}
        payload += item[contentStart until end]
        cursor  = end + ("]]>").count
    }

    if payload.isEmpty() do
        return {}

    // Metadata packets also use Contents CDATA. Retain only actual image payloads so a malformed
    // embedded item can still fall through to its ordinary local link.
    let bytes = catch Base64.decode(payload) as decodeError
    if decodeError != null or bytes.isEmpty() do
        return {}
    return Format.toString("data:%;base64,%", mime, payload)
}

private func graphicMimeType(path: string)->string
{
    switch Path.lowercaseExtension(path).toString()
    {
    case ".gif":          return "image/gif"
    case ".jpg", ".jpeg": return "image/jpeg"
    case ".png":          return "image/png"
    case ".tif", ".tiff": return "image/tiff"
    case ".webp":         return "image/webp"
    default:              return ""
    }
}

private func hexNibble(value: u8)->u8
{
    if value >= '0' and value <= '9' do
        return value - '0'
    if value >= 'a' and value <= 'f' do
        return value - 'a' + 10
    if value >= 'A' and value <= 'F' do
        return value - 'A' + 10
    return Swag.U8.Max
}

// Returns the local path a `file:` URI names, or an empty string for any other or unsafe URI.
//
// File links are local resources chosen by the document author. Only `file:` URLs are decoded and
// malformed escapes are rejected, so the viewer never turns a linked graphic into a network request.
func fileUriPath(uri: string)->String
{
    if not Utf8.startsWith(uri, "file:", .Latin1NoCase) do
        return {}

    var source = uri[5 to]
    if Utf8.startsWith(source, "//")
    {
        source = source[2 to]
        if Utf8.startsWith(source, "localhost/", .Latin1NoCase) do
            source = source[9 to]
        elif not Utf8.startsWith(source, "/") do
            return {}
    }

    if source.count > 2 and source[0] == '/' and source[2] == ':' do
        source = source[1 to]

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
        let high = hexNibble(source[cursor + 1])
        let low  = hexNibble(source[cursor + 2])
        if high == Swag.U8.Max or low == Swag.U8.Max do
            return {}
        result += high * 16 + low
        cursor += 3
    }

    // Validate the decoded spelling: escaped separators must not introduce a network path.
    if not Path.isValidPathName(result) do
        return {}
    if result.count >= 2 and Path.isDirectorySeparator(result[0]) and Path.isDirectorySeparator(result[1]) do
        return {}
    return result
}

// Returns `path` when it names a local image within the linked-graphics budget, charging its size to `loaded`.
private func localGraphicSource(path: string, loaded: *u64)->String
{
    let mime = graphicMimeType(path)
    if not mime.count do
        return {}
    let info = catch File.info(path) as infoError
    if infoError != null or info.size > LinkedGraphicDataLimit or info.size > LinkedGraphicsDataLimit - loaded[] do
        return {}
    var options: DecodeOptions
    options.decodePixels   = false
    options.decodeMetadata = false
    let probe = catch Image.load(path, options) as probeError
    if probeError != null or probe.width <= 0 or probe.height <= 0 or cast(u64, probe.width) * cast(u64, probe.height) > GraphicSourcePixelLimit do
        return {}

    loaded[] += info.size
    return path
}

// Returns the image source of a frame, from its embedded pixels or a local linked file, without fetching.
//
// A direct file URI wins; a same-folder basename is a portable fallback for a document moved
// together with its links after InDesign saved host paths. A relative URI such as
// `file:images/title.png` names a file beside the document, never one under the working directory.
private func linkedGraphicSource(documentFileName, item: string, loaded: *u64)->String
{
    let embedded = embeddedGraphicDataUri(item)
    if not embedded.isEmpty() do
        return embedded

    let imageStart = Utf8.indexOf(item, "<Image ")
    let imageEnd   = imageStart == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(item, "</Image>", imageStart)
    let linkStart  = imageStart == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(item, "<Link ", imageStart)
    let linkEnd    = linkStart == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(item, '>'rune, linkStart)
    if imageEnd == Swag.U64.Max or linkEnd == Swag.U64.Max or linkStart > imageEnd do
        return {}

    var linkedPath = fileUriPath(attribute(item[linkStart until linkEnd + 1], "LinkResourceURI"))
    if linkedPath.isEmpty() do
        return {}
    let folder = Path.directoryName(documentFileName)
    if not Path.isRooted(linkedPath)
    {
        if folder == null do
            return {}
        linkedPath = Path.combine(folder, linkedPath)
    }

    let direct = localGraphicSource(linkedPath, loaded)
    if not direct.isEmpty() do
        return direct

    let name = Path.fileName(linkedPath)
    return folder != null and name != null ? localGraphicSource(Path.combine(folder, name), loaded) : String{}
}

// Decodes the name of an XML character reference, without its `&` and `;`: the five predefined
// entities and decimal or hexadecimal code points. Anything else decodes to U+FFFD.
private func entity(text: string)->rune
{
    if text == "amp" do
        return '&'
    if text == "lt" do
        return '<'
    if text == "gt" do
        return '>'
    if text == "quot" do
        return '"'
    if text == "apos" do
        return '\''
    if text.count > 2 and text[0] == '#' and (text[1] == 'x' or text[1] == 'X')
    {
        var value: u32
        for digit in text[2 to]
        {
            let nibble = cast(u32, hexNibble(digit))
            if nibble == Swag.U8.Max or value > (Swag.U32.Max - nibble) / 16 do
                return 0xFFFD
            value = value * 16 + nibble
        }

        if value <= 0x10FFFF do
            return cast(rune, value)
    }
    elif text.count > 1 and text[0] == '#'
    {
        let parsed = catch StrConv.parseU32(text[1 to]) as parseError
        if parseError == null and not parsed.ovf and parsed.eat == text.count - 1 do
            return cast(rune, parsed.value)
    }

    return 0xFFFD
}

// Replaces the character references in `text` by their characters. An `&` without a closing `;` is
// kept as written.
private func decodeEntities(text: string)->String
{
    var result: retval
    var cursor = 0'u64
    while cursor < text.count
    {
        let entityStart = Utf8.indexOf(text, '&'rune, cursor)
        if entityStart == Swag.U64.Max
        {
            result += text[cursor to]
            break
        }

        result += text[cursor until entityStart]
        let entityEnd = Utf8.indexOf(text, ';'rune, entityStart + 1)
        if entityEnd == Swag.U64.Max
        {
            result += text[entityStart to]
            break
        }

        result += entity(text[entityStart + 1 until entityEnd])
        cursor = entityEnd + 1
    }

    return result
}

// Extracts the plain text of a story: `Content` runs with their entities decoded, a line break for
// each `Br`, and one line break closing each paragraph.
private func storyText(source: string)->String
{
    var result: retval
    var cursor = 0'u64
    while cursor < source.count
    {
        let contentStart = Utf8.indexOf(source, "<Content", cursor)
        let breakStart   = Utf8.indexOf(source, "<Br", cursor)
        let paragraphEnd = Utf8.indexOf(source, "</ParagraphStyleRange>", cursor)
        let next         = Math.min(contentStart, breakStart, paragraphEnd)
        if next == Swag.U64.Max do
            break

        if next == contentStart
        {
            let openEnd = Utf8.indexOf(source, '>'rune, contentStart)
            let close   = openEnd == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(source, "</Content>", openEnd + 1)
            if close == Swag.U64.Max do
                break
            result += decodeEntities(source[openEnd + 1 until close])
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

        if not result.isEmpty() and result.back() != '\n' do
            result += '\n'
        cursor = paragraphEnd + ("</ParagraphStyleRange>").count
    }

    return result
}

private func textAlignment(value: string)->string
{
    if value == "CenterAlign" do
        return "center"
    if value == "RightAlign" do
        return "right"
    if value == "JustifyAll" or value == "JustifyLeft" or value == "JustifyRight" or value == "JustifyCenter" do
        return "justify"
    return "left"
}

private func fontStyleBold(value: string)->bool   => Utf8.contains(value, "Bold") or Utf8.contains(value, "bold") or value == "W6" or value == "W7" or value == "W8" or value == "W9"
private func fontStyleItalic(value: string)->bool => Utf8.contains(value, "Italic") or Utf8.contains(value, "italic") or Utf8.contains(value, "Oblique") or Utf8.contains(value, "oblique")

// Reports whether `text` holds a CJK, Hangul or full-width character, which needs the CJK font.
private func containsCjk(text: string)->bool
{
    var cursor = 0'u64
    while cursor < text.count
    {
        let {c, eat} = Utf8.decodeRune(text[cursor to])
        if (c >= 0x2E80 and c <= 0x9FFF) or
           (c >= 0xAC00 and c <= 0xD7A3) or
           (c >= 0xF900 and c <= 0xFAFF) or
           (c >= 0xFE30 and c <= 0xFE4F) or
           (c >= 0xFF00 and c <= 0xFFEF) or
           (c >= 0x20000 and c <= 0x3FFFD) do
            return true
        cursor += eat
    }

    return false
}

// Converts a paragraph style into inline CSS, with sizes and spacing in `em` relative to the
// style's own font size, or 12 points when it has none.
private func textStyleCss(style: const *TextStyle)->String
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
    if not style.fill.isEmpty() do
        result += Format.toString("color:%;", style.fill)
    if not style.alignment.isEmpty() do
        result += Format.toString("text-align:%;", style.alignment)
    if style.bold do
        result += "font-weight:bold;"
    if style.italic do
        result += "font-style:italic;"
    result += style.cjk ? "font-family:cjk;" : style.serif ? "font-family:serif;" : "font-family:sans-serif;"
    return result
}

// Converts the attributes of a `CharacterStyleRange` tag into inline CSS, sizes relative to 12
// points and tracking in thousandths of an em.
private func characterStyleCss(tag: string, colors: const *HashTable'(String, String))->String
{
    var result: retval
    let fontSize = parseNumber(attribute(tag, "PointSize")).value
    if fontSize > 0 do
        result += Format.toString("font-size:%em;", fontSize / 12)
    let color = resolveColor(colors, attribute(tag, "FillColor"), attribute(tag, "FillTint"))
    if not color.isEmpty() do
        result += Format.toString("color:%;", color)
    let fontStyle = attribute(tag, "FontStyle")
    if fontStyleBold(fontStyle) do
        result += "font-weight:bold;"
    if fontStyleItalic(fontStyle) do
        result += "font-style:italic;"
    if attribute(tag, "Capitalization") == "AllCaps" do
        result += "text-transform:uppercase;"
    // Both lines share the one `text-decoration` declaration; a second one would replace the first.
    let underline = attribute(tag, "Underline") == "true"
    let strike    = attribute(tag, "StrikeThru") == "true"
    if underline and strike do
        result += "text-decoration:underline line-through;"
    elif underline do
        result += "text-decoration:underline;"
    elif strike do
        result += "text-decoration:line-through;"
    let tracking = parseNumber(attribute(tag, "Tracking")).value
    if tracking != 0 do
        result += Format.toString("letter-spacing:%em;", tracking / 1_000)
    if attribute(tag, "Position") == "Superscript" do
        result += "vertical-align:super;"
    if attribute(tag, "Position") == "Subscript" do
        result += "vertical-align:sub;"
    return result
}

// Renders the character style ranges of a paragraph as styled `span` elements, or as escaped plain
// text when the paragraph has none.
private func characterRangeHtml(source: string, colors: const *HashTable'(String, String))->String
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
        result += characterStyleCss(source[rangeStart until openEnd + 1], colors)
        result += "\">"
        result += escapeHtml(storyText(source[openEnd + 1 until close]))
        result += "</span>"
        cursor = close + ("</CharacterStyleRange>").count
    }

    return result.isEmpty() ? escapeHtml(storyText(source)) : result
}

// Renders a story as HTML, one `div` per paragraph style range carrying its resolved style, bullet
// and CJK font. Falls back to escaped plain text when the story has no paragraph range.
private func storyHtml(source: string, styles: const *HashTable'(String, TextStyle), colors: const *HashTable'(String, String))->String
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
        let styleKey = attribute(tag, "AppliedParagraphStyle")
        let style    = styles.tryFind(styleKey)
        result += "<div style=\"margin:0;"
        if style do
            result += textStyleCss(&style.value)
        if containsCjk(content) do
            result += "font-family:cjk;"
        result += "\">"
        if style and style.value.bullet do
            result += "&#x2022;&nbsp;"
        result += characterRangeHtml(content, colors)
        result += "</div>"
        cursor = close + ("</ParagraphStyleRange>").count
    }

    return result.isEmpty() ? escapeHtml(storyText(source)) : result
}

// Escapes `text` for HTML, turning the IDML line and paragraph separators U+2028 and U+2029 into
// `<br>`.
private func escapeHtml(text: string)->String
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
        case '&': result += "&amp;"
        case '<': result += "&lt;"
        case '>': result += "&gt;"
        case '"': result += "&quot;"
        default:  result += value
        }

        cursor += 1
    }

    return result
}

// Escapes `text` as the value of a double-quoted HTML attribute. A linked file path is chosen by the
// document author, so it may hold any character a file system accepts, such as `&`.
private func escapeHtmlAttribute(text: string)->String
{
    var result: retval
    for value in text
    {
        switch value
        {
        case '&': result += "&amp;"
        case '<': result += "&lt;"
        case '>': result += "&gt;"
        case '"': result += "&quot;"
        default:  result += value
        }
    }

    return result
}

// The CSS `rgb()` of components in 0..255, rounded and clamped.
private func cssChannel(value: f32)->u32 => cast(u32, Math.round(Math.clamp(value, 0, 255)))
private func cssRgb(red, green, blue: f32)->String => Format.toString("rgb(%, %, %)", cssChannel(red), cssChannel(green), cssChannel(blue))

// The CSS color of an InDesign color value: RGB components, or CMYK percentages.
private func cssColor(space, value: string)->String
{
    let values = parseNumbers(value)
    if space == "RGB" and values.count == 3 do
        return cssRgb(values[0], values[1], values[2])
    if space == "CMYK" and values.count == 4
    {
        let cyan    = Math.clamp(values[0] / 100, 0, 1)
        let magenta = Math.clamp(values[1] / 100, 0, 1)
        let yellow  = Math.clamp(values[2] / 100, 0, 1)
        let black   = Math.clamp(values[3] / 100, 0, 1)
        return cssRgb(255 * (1 - cyan) * (1 - black), 255 * (1 - magenta) * (1 - black), 255 * (1 - yellow) * (1 - black))
    }

    return {}
}

// Reads the document swatches of `Resources/Graphic.xml` as CSS colors keyed by `Self`, the first
// definition winning. Paper and Black are supplied when the document omits them.
private func loadColors(fileName: string, archive: const *Archive.Zip)->HashTable'(String, String)
{
    var result: retval
    let entry = archive.tryFindEntry("Resources/Graphic.xml")
    if not entry do
        return result
    let source = catch readEntry(fileName, archive, entry.path) as readError
    if readError != null do
        return result

    var cursor = 0'u64
    while true
    {
        let start = Utf8.indexOf(source, "<Color ", cursor)
        if start == Swag.U64.Max do
            break
        let end = Utf8.indexOf(source, '>'rune, start)
        if end == Swag.U64.Max do
            break
        let tag   = source.toString()[start until end + 1]
        let self  = attribute(tag, "Self")
        let color = cssColor(attribute(tag, "Space"), attribute(tag, "ColorValue"))
        if self.count and not color.isEmpty() and not result.tryFind(self) do
            result.add(self, color)
        cursor = end + 1
    }

    if not result.tryFind("Color/Paper") do
        result.add("Color/Paper", "rgb(255, 255, 255)")
    if not result.tryFind("Color/Black") do
        result.add("Color/Black", "rgb(0, 0, 0)")
    return result
}

// Applies an IDML tint percentage to an `rgb(...)` color by mixing it with white. Returns `color`
// unchanged when the tint is missing or at least 100, or the color is not plain RGB.
private func tintedColor(color, tint: string)->String
{
    let percentage = parseNumber(tint)
    if not percentage.valid or percentage.value >= 100 do
        return color

    let open  = Utf8.indexOf(color, '('rune)
    let close = Utf8.indexOf(color, ')'rune, open == Swag.U64.Max ? 0 : open + 1)
    if open == Swag.U64.Max or close == Swag.U64.Max do
        return color
    var channels: Array'f32
    for channel in Tokenize.split(color[open + 1 until close], ','rune)
    {
        let value = parseNumber(Latin1.trim(channel))
        if not value.valid do
            return color
        channels.add(value.value)
    }

    if channels.count != 3 do
        return color

    let factor = Math.clamp(percentage.value / 100, 0, 1)
    return Format.toString("rgb(%, %, %)",
                           cast(u32, Math.round(255 + (channels[0] - 255) * factor)),
                           cast(u32, Math.round(255 + (channels[1] - 255) * factor)),
                           cast(u32, Math.round(255 + (channels[2] - 255) * factor)))
}

private func resolveColor(colors: const *HashTable'(String, String), name: string, tint = "")->String
{
    if name == "Swatch/None" or not name.count do
        return ""
    let found = colors.tryFind(name)
    return found ? tintedColor(found.value, tint) : ""
}

// Reads the paragraph styles of `Resources/Styles.xml`, keyed by `Self`, keeping only what the HTML
// rendering of stories uses. A missing or unreadable entry gives no styles.
private func loadTextStyles(fileName: string, archive: const *Archive.Zip, colors: const *HashTable'(String, String))->HashTable'(String, TextStyle)
{
    var result: retval
    let entry = archive.tryFindEntry("Resources/Styles.xml")
    if not entry do
        return result
    let source = catch readEntry(fileName, archive, entry.path) as readError
    if readError != null do
        return result

    var cursor = 0'u64
    while true
    {
        let start = Utf8.indexOf(source, "<ParagraphStyle ", cursor)
        if start == Swag.U64.Max do
            break
        let openEnd = Utf8.indexOf(source, '>'rune, start)
        if openEnd == Swag.U64.Max do
            break
        let tag     = source.toString()[start until openEnd + 1]
        let self    = attribute(tag, "Self")
        let close   = Utf8.indexOf(source, "</ParagraphStyle>", openEnd + 1)
        let bodyEnd = close == Swag.U64.Max ? openEnd + 1 : close
        if self.count and not result.tryFind(self)
        {
            var style: TextStyle
            style.fontSize        = parseNumber(attribute(tag, "PointSize")).value
            style.autoLeading     = parseNumber(attribute(tag, "AutoLeading")).value
            style.spaceBefore     = parseNumber(attribute(tag, "SpaceBefore")).value
            style.spaceAfter      = parseNumber(attribute(tag, "SpaceAfter")).value
            style.leftIndent      = parseNumber(attribute(tag, "LeftIndent")).value
            style.rightIndent     = parseNumber(attribute(tag, "RightIndent")).value
            style.firstLineIndent = parseNumber(attribute(tag, "FirstLineIndent")).value
            style.fill            = resolveColor(colors, attribute(tag, "FillColor"), attribute(tag, "FillTint"))
            style.alignment       = textAlignment(attribute(tag, "Justification"))
            style.cjk             = attribute(tag, "AppliedLanguage") == "$ID/Japanese"
            style.bold            = fontStyleBold(attribute(tag, "FontStyle"))
            style.italic          = fontStyleItalic(attribute(tag, "FontStyle"))
            style.bullet          = attribute(tag, "BulletsAndNumberingListType") == "BulletList"
            let fontStart = Utf8.indexOf(source, "<AppliedFont", openEnd + 1)
            if fontStart != Swag.U64.Max and fontStart < bodyEnd
            {
                let fontOpenEnd = Utf8.indexOf(source, '>'rune, fontStart)
                let fontClose   = fontOpenEnd == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(source, "</AppliedFont>", fontOpenEnd + 1)
                if fontClose != Swag.U64.Max and fontClose < bodyEnd do
                    style.serif = Utf8.contains(source.toString()[fontOpenEnd + 1 until fontClose], "Minion")
            }

            result.add(self, #move style)
        }

        cursor = close == Swag.U64.Max ? openEnd + 1 : close + ("</ParagraphStyle>").count
    }

    return result
}

// Collects the pages of a spread with their bounds in spread coordinates and their applied master,
// while the document-wide page budget lasts.
private func appendPages(source: string, pages: *Array'Page, limits: *LoadLimits)
{
    var cursor = 0'u64
    while limits.pages
    {
        let start = Utf8.indexOf(source, "<Page ", cursor)
        if start == Swag.U64.Max do
            break
        let end = Utf8.indexOf(source, '>'rune, start)
        if end == Swag.U64.Max do
            break
        let tag = source[start until end + 1]
        var bounds: Bounds
        if boundsFromGeometric(attribute(tag, "GeometricBounds"), &bounds)
        {
            let transform = parseTransform(tag)
            bounds.left += transform.x
            bounds.top  += transform.y
            var page: Page
            page.name   = attribute(tag, "Name")
            page.master = attribute(tag, "AppliedMaster")
            page.bounds = bounds
            pages.add(#move page)
            limits.pages -= 1
        }

        cursor = end + 1
    }
}

private func pageIndexOf(pages: const *Array'Page, bounds: const *Bounds)->u64
{
    let centerX = bounds.left + bounds.width * 0.5
    let centerY = bounds.top + bounds.height * 0.5
    for page, index in pages where page.bounds.contains(centerX, centerY) do
        return index

    return Swag.U64.Max
}

// Collects the drawable frames of a spread (text, rectangle, oval, polygon and line) into the page
// each one falls on, in page coordinates, with the transforms of enclosing groups applied. Each
// item read spends one frame of the document-wide budget, and reading stops when it is spent.
private func appendItems(fileName, source: string, colors: const *HashTable'(String, String), linkedGraphicBytes: *u64, pages: *Array'Page, limits: *LoadLimits)
{
    var cursor = 0'u64
    var groupCursor:     u64
    var groupTransforms: Array'Transform
    while limits.frames
    {
        let textStart    = Utf8.indexOf(source, "<TextFrame ", cursor)
        let rectStart    = Utf8.indexOf(source, "<Rectangle ", cursor)
        let ovalStart    = Utf8.indexOf(source, "<Oval ", cursor)
        let polygonStart = Utf8.indexOf(source, "<Polygon ", cursor)
        let lineStart    = Utf8.indexOf(source, "<GraphicLine ", cursor)
        let shapeStart   = Math.min(rectStart, ovalStart, polygonStart, lineStart)
        let start        = Math.min(textStart, shapeStart)
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
                groupTransforms.add(parseTransform(source[open until end + 1]))
                groupCursor = end + 1
                continue
            }

            if close < start
            {
                if not groupTransforms.isEmpty() do
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
        let tag       = source[start until openEnd + 1]
        let content   = source[start until close + closing.count]
        var transform = parseTransform(tag)
        var inherited: Transform
        for groupTransform in groupTransforms do
            inherited = composeTransform(&inherited, groupTransform)
        transform = composeTransform(&inherited, &transform)
        var bounds: Bounds
        if boundsFromPath(content, &transform, &bounds, line)
        {
            let pageIndex = pageIndexOf(pages, &bounds)
            if pageIndex != Swag.U64.Max
            {
                // Item transforms are expressed in the spread coordinate system. The local page
                // scene begins at its own top-left corner, so remove the selected page origin
                // before handing the rectangle to the renderer.
                bounds.left -= pages[pageIndex].bounds.left
                bounds.top  -= pages[pageIndex].bounds.top
                var item: Item
                item.bounds            = bounds
                item.self              = attribute(tag, "Self")
                item.fill              = resolveColor(colors, attribute(tag, "FillColor"), attribute(tag, "FillTint"))
                item.stroke            = resolveColor(colors, attribute(tag, "StrokeColor"), attribute(tag, "StrokeTint"))
                item.strokeSize        = parseNumber(attribute(tag, "StrokeWeight")).value
                item.oval              = oval
                item.line              = line
                item.imageFrame        = Utf8.indexOf(content, "<Image ") != Swag.U64.Max
                item.cornerTopLeft     = roundedCornerRadius(tag, "TopLeft")
                item.cornerTopRight    = roundedCornerRadius(tag, "TopRight")
                item.cornerBottomRight = roundedCornerRadius(tag, "BottomRight")
                item.cornerBottomLeft  = roundedCornerRadius(tag, "BottomLeft")
                if line
                {
                    item.lineStartArrow = attribute(tag, "LeftLineEnd") == "TriangleArrowHead"
                    item.lineEndArrow   = attribute(tag, "RightLineEnd") == "TriangleArrowHead"
                    let padding = Math.max(item.strokeSize * 2, 4)
                    item.bounds.left   -= padding
                    item.bounds.top    -= padding
                    item.bounds.width  += 2 * padding
                    item.bounds.height += 2 * padding
                    item.clipPath      = lineClipPath(content, &transform, pages[pageIndex].bounds.left, pages[pageIndex].bounds.top, &item.bounds, item.strokeSize, item.lineStartArrow, item.lineEndArrow)
                }
                elif polygon
                {
                    item.clipPath = polygonClipPath(content, &transform)
                }

                if item.imageFrame
                {
                    item.image = linkedGraphicSource(fileName, content, linkedGraphicBytes)
                    var imageBounds: Bounds
                    if boundsFromGraphic(content, &transform, &imageBounds)
                    {
                        imageBounds.left    -= pages[pageIndex].bounds.left
                        imageBounds.top     -= pages[pageIndex].bounds.top
                        item.imageBounds    = imageBounds
                        item.imageHasBounds = true
                    }
                }

                if textItem
                {
                    item.story         = attribute(tag, "ParentStory")
                    item.previousFrame = attribute(tag, "PreviousTextFrame")
                    item.nextFrame     = attribute(tag, "NextTextFrame")
                    textFrameLayout(content, &item)
                    pages[pageIndex].textFrameCount += 1
                }

                pages[pageIndex].items.add(#move item)
            }
        }

        limits.frames -= 1
        cursor        = close + closing.count
    }
}

// Adds to each page the items of the master it applies, taken from the master page at the same
// position, or from its last page. Each copy spends one frame of the document-wide budget.
private func appendMasterItems(masters: const *Array'Master, pages: *Array'Page, limits: *LoadLimits)
{
    for &page, pageIndex in pages where not page.master.isEmpty()
    {
        for master in masters where master.self == page.master
        {
            if master.pages.isEmpty() do
                break
            let index = Math.min(pageIndex, master.pages.count - 1)
            for item in master.pages[index].items
            {
                if not limits.frames do
                    return
                page.items.add(item)
                limits.frames -= 1
                if not item.story.isEmpty() do
                    page.textFrameCount += 1
            }

            break
        }
    }
}

// A text frame found in a chain, with the index of the page that holds it.
private struct FoundFrame
{
    item:      *Item?
    pageIndex: u64
}

// Returns the text frame whose `Self` identifier is `self`, searching from page `startPage` onward
// and then wrapping to the pages before it, or a null item when no page holds it.
//
// Every page applying a master holds its own copy of the master's frames, under the same `Self`
// identifiers. Searching from the page where the chain currently is keeps a master chain on the
// copies of that page, or of the next page of its spread, instead of the first page's copies.
private func findTextFrame(pages: *Array'Page, self: string, startPage: u64)->FoundFrame
{
    for offset in pages.count
    {
        let pageIndex = (startPage + offset) % pages.count
        for &item in pages[pageIndex].items where item.self == self do
            return {item, pageIndex}
    }

    return {}
}

private func storyBlockEnd(source: string, start: u64)->u64
{
    let close = Utf8.indexOf(source, "</div>", start)
    return close == Swag.U64.Max ? source.count : close + ("</div>").count
}

// Returns the text area of a frame, which weights the share of a story the frame receives.
//
// The local HTML renderer owns line breaking, but a text frame's area is a reliable first-order
// capacity signal. Paragraph blocks are weighted by that area so an editorial chain with unequal
// columns does not place the same amount of prose into a caption-sized frame and a body-sized frame.
private func textFrameCapacity(frame: const *Item)->f32
{
    let width  = frame.bounds.width - frame.textInsetLeft - frame.textInsetRight
    let height = frame.bounds.height - frame.textInsetTop - frame.textInsetBottom
    return Math.max(width, 1) * Math.max(height, 1)
}

// Partitions the paragraph blocks of one story markup across its chain of linked frames.
private func flowStory(source: string, frames: const *Array'*Item)
{
    if frames.isEmpty() or not source.count do
        return

    var blockCount: u64
    var cursor = 0'u64
    while cursor < source.count
    {
        cursor     = storyBlockEnd(source, cursor)
        blockCount += 1
    }

    var totalCapacity: f32
    for frame in frames do
        totalCapacity += textFrameCapacity(frame)

    cursor = 0
    var allocatedBlocks:  u64
    var remainingBlocks = blockCount
    var consumedCapacity: f32
    for frame, index in frames
    {
        let remainingFrames = frames.count - index
        consumedCapacity += textFrameCapacity(frame)
        let target  = cast(u64, Math.round(cast(f32, blockCount) * consumedCapacity / totalCapacity))
        let minimum = remainingBlocks >= remainingFrames ? 1 : 0
        let maximum = remainingBlocks - (remainingBlocks >= remainingFrames ? remainingFrames - 1 : 0)
        let desired = target > allocatedBlocks ? target - allocatedBlocks : 0
        let take    = Math.clamp(desired, minimum, maximum)
        var text: String
        for take
        {
            let end = storyBlockEnd(source, cursor)
            text   += source[cursor until end]
            cursor = end
        }

        allocatedBlocks += take
        remainingBlocks -= take
        frame.text      = #move text
    }
}

// Distributes the text of each story over its chain of linked text frames.
//
// A story is one text flow, potentially crossing several positioned text frames and pages. The
// package stores its text once; duplicating it in every frame is both visually wrong and expensive
// for long editorial copy, so the paragraph markup is partitioned across the linked frames.
private func flowTextStories(pages: *Array'Page, stories: const *HashTable'(String, String))
{
    for &page in pages
    {
        for &item in page.items where not item.story.isEmpty() do
            item.text.clear()
    }

    for &page, startPage in pages
    {
        for &item in page.items where not item.story.isEmpty() and item.previousFrame == "n"
        {
            let story = stories.tryFind(item.story)
            if not story do
                continue

            var frames:    Array'*Item
            var frame:     *Item? = item
            var pageIndex = startPage
            while frame and frames.count < FrameLimit
            {
                var repeated: bool
                for existing in frames where existing == frame
                {
                    repeated = true
                    break
                }

                if repeated do
                    break
                frames.add(frame)
                if frame.nextFrame.isEmpty() or frame.nextFrame == "n" do
                    break
                let next = findTextFrame(pages, frame.nextFrame, pageIndex)
                frame     = next.item
                pageIndex = next.pageIndex
            }

            flowStory(story.value, &frames)
        }
    }
}

// Loads every master spread listed in `designMap` with its pages and items, so the pages applying a
// master can draw its items. A master that cannot be read is skipped.
private func loadMasters(fileName: string, archive: const *Archive.Zip, designMap: string, colors: const *HashTable'(String, String), linkedGraphicBytes: *u64, limits: *LoadLimits)->Array'Master
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
        let path   = attribute(designMap[start until end + 1], "src")
        let source = catch readEntry(fileName, archive, path) as readError
        if readError == null
        {
            let masterStart = Utf8.indexOf(source, "<MasterSpread ")
            let masterEnd   = masterStart == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(source, '>'rune, masterStart)
            if masterEnd != Swag.U64.Max
            {
                let self = attribute(source.toString()[masterStart until masterEnd + 1], "Self")
                if self.count
                {
                    var master: Master
                    master.self = self
                    appendPages(source, &master.pages, limits)
                    appendItems(fileName, source, colors, linkedGraphicBytes, &master.pages, limits)
                    result.add(#move master)
                }
            }
        }

        cursor = end + 1
    }

    return result
}

// Reads an IDML package into positioned pages, text frames, and vector frame backgrounds.
//
// Linked external assets deliberately remain offline; a missing link never causes the viewer to
// fetch it. `limits` bounds the pages and frames of the whole document, masters included.
func load(fileName: string, limits: LoadLimits = {})->Document fail
{
    let archive = try Archive.Zip.load(fileName)
    if archive.uncompressedSize > DocumentByteLimit do
        fail UnsupportedFormatError{texts().err_TooLarge}
    let mimetype = try readEntry(fileName, &archive, "mimetype")
    if Latin1.trim(mimetype) != "application/vnd.adobe.indesign-idml-package" do
        fail InvalidFormatError{texts().err_NotIdml}

    let designMap  = try readEntry(fileName, &archive, "designmap.xml")
    let colors     = loadColors(fileName, &archive)
    let textStyles = loadTextStyles(fileName, &archive, &colors)
    var stories: HashTable'(String, String)
    for entry in archive.entries where Utf8.startsWith(entry.path, "Stories/") and Utf8.endsWith(entry.path, ".xml")
    {
        let source = catch readEntry(fileName, &archive, entry.path) as readError
        if readError != null do
            continue
        let storyStart = Utf8.indexOf(source, "<Story ")
        let storyEnd   = storyStart == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(source, '>'rune, storyStart)
        if storyEnd == Swag.U64.Max do
            continue
        let self = attribute(source.toString()[storyStart until storyEnd + 1], "Self")
        if self.count and not stories.tryFind(self) do
            stories.add(self, storyHtml(source, &textStyles, &colors))
    }

    var linkedGraphicBytes: u64
    var remaining = limits
    let masters   = loadMasters(fileName, &archive, designMap, &colors, &linkedGraphicBytes, &remaining)
    var result: retval
    result.fileName = fileName
    var cursor = 0'u64
    var spreadCount: u64
    while spreadCount < SpreadLimit and remaining.pages
    {
        let start = Utf8.indexOf(designMap, "<idPkg:Spread ", cursor)
        if start == Swag.U64.Max do
            break
        let end = Utf8.indexOf(designMap, '>'rune, start)
        if end == Swag.U64.Max do
            break
        let spreadPath = attribute(designMap.toString()[start until end + 1], "src")
        let spread     = try readEntry(fileName, &archive, spreadPath)
        var spreadPages: Array'Page
        appendPages(spread, &spreadPages, &remaining)
        if not spreadPages.isEmpty()
        {
            appendMasterItems(&masters, &spreadPages, &remaining)
            appendItems(fileName, spread, &colors, &linkedGraphicBytes, &spreadPages, &remaining)
            for page in spreadPages do
                result.pages.add(page[])
        }

        cursor      = end + 1
        spreadCount += 1
    }

    if result.pages.isEmpty() do
        fail InvalidFormatError{texts().err_NoPages}
    flowTextStories(&result.pages, &stories)
    return result
}
