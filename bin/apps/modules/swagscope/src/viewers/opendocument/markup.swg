#global internal
#global namespace Viewers.OpenDocument

using Core, Core.Errors, Gui

private
{
    const TableColumnLimit        = 256'u64
    const TableRowLimit           = 100_000'u64
    const TableCellLimit          = 1_000_000'u64
    const RepeatedCellLimit       = 4_096'u64
    const HtmlRepeatedRowLimit    = 4_096'u64     // Rows that repetition may give one HTML table.
    const TextStyleLimit          = 4_096'u64
    const BookmarkLimit           = 4_096'u64
    const InlineImagePayloadLimit = ((ImageLimit + 2) / 3) * 4
    const ImageDimensionLimit     = 4_096.0
}

// The baseline a run of text sits on.
enum TextPosition
{
    Normal
    Subscript
    Superscript
}

// Captures the portable text emphasis that the offline HTML surface can render without a style engine.
struct TextStyle
{
    name:      String
    bold:      bool
    italic:    bool
    underline: bool
    strike:    bool
    position:  TextPosition
    alignment: String
    fontSize:  String
}

// Records whether a named ODF list asks the reader for ordered markers.
struct ListStyle
{
    name:     String
    numbered: bool
}

// Maps a source bookmark name to an HTML-only fragment identifier.
struct Bookmark
{
    name:   String
    target: String
}

// One validated picture of the ODF package, converted to a data URI and keyed by its entry path.
struct EmbeddedImage
{
    path:      String
    uri:       String
    byteCount: u64
}

// The frame size of an image, reduced to a known safe pixel spelling before it becomes HTML attributes.
struct ImageSize
{
    width:  String
    height: String
}

// Returns a positive integer attribute clamped to `maximum`, or 1 when it is absent or malformed.
func positiveAttribute(attributes, name: string, maximum: u64)->u64
{
    let value = attribute(attributes, name)
    if value.isEmpty() do
        return 1
    let parsed = catch StrConv.parseU64(value) as parseError
    if parseError != null or parsed.eat != value.count or not parsed.value do
        return 1
    return Math.min(parsed.value, maximum)
}

func repeatCount(attributes, name: string)->u64 => positiveAttribute(attributes, name, RepeatedCellLimit)

func cellValue(attributes: string)->String
{
    for name in ["office:string-value", "office:value", "office:date-value", "office:time-value", "office:boolean-value"]
    {
        let value = attribute(attributes, name)
        if not value.isEmpty() do
            return value
    }

    return {}
}

// Converts the length attribute `name`, with an optional unit, into whole CSS pixels. Returns an
// empty string when the value is missing, malformed, or outside 1 to `ImageDimensionLimit` pixels.
func imageDimension(attributes, name: string)->String
{
    let value = attribute(attributes, name)
    if value.isEmpty() do
        return {}

    var end = 0'u64
    while end < value.count and Latin1.isDigit(value[end]) do
        end += 1
    if end < value.count and value[end] == '.'
    {
        end += 1
        while end < value.count and Latin1.isDigit(value[end]) do
            end += 1
    }

    if not end do
        return {}

    let parsed = catch StrConv.parseF64(value[0 until end]) as parseError
    if parseError != null or parsed.ovf do
        return {}

    let unit = String.from(value[end to]).toLower()
    var pixels: f64
    switch unit.toString()
    {
    case "", "px": pixels = parsed.value
    case "pt":     pixels = parsed.value * 96 / 72
    case "pc":     pixels = parsed.value * 16
    case "in":     pixels = parsed.value * 96
    case "cm":     pixels = parsed.value * 96 / 2.54
    case "mm":     pixels = parsed.value * 96 / 25.4
    case "q":      pixels = parsed.value * 96 / 101.6
    default:       return {}
    }

    if pixels < 1 or pixels > ImageDimensionLimit do
        return {}
    return Format.toString("%px", Math.round(cast(f32, pixels)))
}

func imageSize(attributes: string)->ImageSize
{
    var result: retval
    result.width  = imageDimension(attributes, "svg:width")
    result.height = imageDimension(attributes, "svg:height")
    return result
}

// Returns the media type of a base64 raster data URI the offline image decoder renders, or an empty string.
func inlineImageMediaType(uri: string)->string
{
    let lowercase = String.from(uri).toLower()
    for mediaType in ["bmp", "gif", "x-icon", "jpeg", "png", "tiff", "webp"]
    {
        let prefix = Format.toString("data:image/%;base64,", mediaType)
        if Utf8.startsWith(lowercase, prefix) do
            return mediaType
    }

    return ""
}

// Re-encodes XML text as one generated HTML attribute without preserving markup syntax.
func htmlAttribute(value: string)->String
{
    let decoded = decodeXmlText(value)
    var result: retval
    for character in decoded
    {
        switch character
        {
        case '&': result += "&amp;"
        case '<': result += "&lt;"
        case '>': result += "&gt;"
        case '"': result += "&quot;"
        default:  result += character
        }
    }

    return result
}

// Keeps user-activated outbound links to ordinary web URLs; all other URI schemes stay inert.
func externalHref(href: string)->String
{
    let decoded = decodeXmlText(href)
    if not Utf8.startsWith(decoded, "http://", .Latin1NoCase) and not Utf8.startsWith(decoded, "https://", .Latin1NoCase) do
        return {}
    for character in decoded
    {
        if character <= ' ' or character == '"' or character == '<' or character == '>' do
            return {}
    }

    return htmlAttribute(href)
}

// Converts common ODF absolute sizes to relative HTML sizes, allowing the reader zoom to scale them.
func fontSize(attributes: string)->String
{
    let value = attribute(attributes, "fo:font-size")
    if value.isEmpty() do
        return {}

    var end = 0'u64
    while end < value.count and Latin1.isDigit(value[end]) do
        end += 1
    if end < value.count and value[end] == '.'
    {
        end += 1
        while end < value.count and Latin1.isDigit(value[end]) do
            end += 1
    }

    if not end do
        return {}

    let parsed = catch StrConv.parseF64(value[0 until end]) as parseError
    if parseError != null or parsed.ovf do
        return {}

    let unit = String.from(value[end to]).toLower()
    var percent: f64
    switch unit.toString()
    {
    case "%":      percent = parsed.value
    case "", "px": percent = parsed.value * 100 / 16
    case "pt":     percent = parsed.value * 100 / 12
    case "pc":     percent = parsed.value * 100
    case "in":     percent = parsed.value * 600
    case "cm":     percent = parsed.value * 600 / 2.54
    case "mm":     percent = parsed.value * 60 / 2.54
    case "q":      percent = parsed.value * 15 / 2.54
    default:       return {}
    }

    if percent < 50 or percent > 400 do
        return {}
    return Format.toString("%{f0}%%", percent)
}

// A table being written as HTML: its rows so far, and the empty rows held back until a row with
// content follows them.
struct HtmlTable
{
    rows:        u64
    pendingRows: u64
}

// A row being written as HTML, from the output offset of its `<tr>`.
struct HtmlRow
{
    start:        u64
    repeat:       u64 = 1
    cells:        u64
    pendingCells: u64
    hasContent:   bool
}

// A cell being written as HTML, from the output offset of its opening tag and of its content.
struct HtmlCell
{
    start:        u64
    contentStart: u64
    repeat:       u64 = 1
}

// Reports whether an element holds no body content: comments, the record of tracked deletions,
// and speaker notes are document apparatus that a reader shows elsewhere, if at all.
func isApparatus(name: string)->bool
{
    switch name
    {
    case "office:annotation", "text:tracked-changes", "table:tracked-changes", "presentation:notes":
        return true
    default:
        return false
    }
}

// Turns one ODF body into reading HTML, one virtual table model per sheet, or isolated slide markup.
//
// Repeated rows and cells are written out, but an empty one is held back until content follows it.
// Spreadsheets repeat empty cells and rows to the end of the sheet, and that padding is dropped.
struct Reader
{
    kind:     Kind
    metadata: Metadata
    html:     String

    inBody:            bool
    sawBody:           bool
    skipDepth:         u64
    activeSheet:       bool
    cellActive:        bool
    cellRepeat:        u64 = 1
    pendingEmptyCells: u64
    rowRepeat:         u64 = 1
    pendingEmptyRows:  u64
    headingLevel:      u64 = 1
    slideActive:       bool
    cell:              String
    cellFallback:      String
    sheetCellCount:    u64
    row:               Table.Row
    sheet:             Sheet
    sheets:            Array'Sheet
    slide:             Slide
    slides:            Array'Slide
    styleActive:       bool
    style:             TextStyle
    textStyles:        Array'TextStyle
    styleStack:        Array'TextStyle
    listStyleActive:   bool
    listStyle:         ListStyle
    listStyles:        Array'ListStyle
    listStack:         Array'bool
    bookmarks:         Array'Bookmark
    tableHeaderRows:   u64
    htmlTables:        Array'HtmlTable
    htmlRows:          Array'HtmlRow
    htmlCells:         Array'HtmlCell
    imageSizeStack:    Array'ImageSize
    images:            Array'EmbeddedImage
    imageByteCount:    u64
    imageCount:        u64
}

private impl Reader
{
    mtd namedTextStyle(name: string)->TextStyle
    {
        for style in .textStyles where style.name == name do
            return style
        return {}
    }

    mtd namedListStyle(name: string)->ListStyle
    {
        for style in .listStyles where style.name == name do
            return style
        return {}
    }

    // Applies the text properties present in `attributes` to `style`. Properties the element does
    // not mention keep the value the style inherited.
    mtd applyTextStyleProperties(style: *TextStyle, attributes: string)
    {
        let weight = attribute(attributes, "fo:font-weight")
        if not weight.isEmpty() do
            style.bold = weight == "bold" or weight == "bolder" or weight == "600" or weight == "700" or weight == "800" or weight == "900"

        let fontStyle = attribute(attributes, "fo:font-style")
        if not fontStyle.isEmpty() do
            style.italic = fontStyle == "italic" or fontStyle == "oblique"

        let underline = attribute(attributes, "style:text-underline-style")
        if not underline.isEmpty() do
            style.underline = underline != "none"

        let strike = attribute(attributes, "style:text-line-through-style")
        if not strike.isEmpty() do
            style.strike = strike != "none"

        let position = attribute(attributes, "style:text-position")
        if Utf8.startsWith(position, "sub") do
            style.position = .Subscript
        elif Utf8.startsWith(position, "super") do
            style.position = .Superscript
        elif not position.isEmpty() do
            style.position = .Normal

        let fontSize = fontSize(attributes)
        if not fontSize.isEmpty() do
            style.fontSize = #move fontSize
    }

    mtd applyParagraphStyleProperties(style: *TextStyle, attributes: string)
    {
        switch attribute(attributes, "fo:text-align").toString()
        {
        case "left", "start": style.alignment = "left"
        case "center":        style.alignment = "center"
        case "right", "end":  style.alignment = "right"
        case "justify":       style.alignment = "justify"
        }
    }

    // Opens the style definition that `tag` starts, a list style or a text or paragraph style
    // inheriting its parent, and applies the property elements nested in the open style.
    mtd startTextStyle(tag: const *Tag)
    {
        if tag.name == "text:list-style"
        {
            let name = attribute(tag.attributes, "style:name")
            if name.isEmpty() do
                return
            .listStyleActive = true
            .listStyle       = {}
            .listStyle.name  = name
            return
        }

        if tag.name == "text:list-level-style-number" and .listStyleActive
        {
            .listStyle.numbered = true
            return
        }

        if tag.name == "style:style"
        {
            let attributes = tag.attributes.toString()
            let family     = attribute(attributes, "style:family")
            let name       = attribute(attributes, "style:name")
            if (family != "text" and family != "paragraph") or name.isEmpty() do
                return

            .styleActive = true
            .style       = .namedTextStyle(attribute(attributes, "style:parent-style-name"))
            .style.name  = name
            .applyTextStyleProperties(&.style, attributes)
            return
        }

        if not .styleActive do
            return
        if tag.name == "style:text-properties" do
            .applyTextStyleProperties(&.style, tag.attributes)
        elif tag.name == "style:paragraph-properties" do
            .applyParagraphStyleProperties(&.style, tag.attributes)
    }

    // Closes the list or text style that `tag` ends and keeps it, up to `TextStyleLimit` styles of
    // each kind.
    mtd finishTextStyle(tag: const *Tag)
    {
        if tag.name == "text:list-style" and .listStyleActive
        {
            if .listStyles.count < TextStyleLimit do
                .listStyles.add(#move .listStyle)
            .listStyleActive = false
            .listStyle       = {}
            return
        }

        if tag.name != "style:style" or not .styleActive do
            return
        if .textStyles.count < TextStyleLimit do
            .textStyles.add(#move .style)
        .styleActive = false
        .style       = {}
    }

    // Opens the HTML tags for the text style named in `attributes` and pushes the style, so
    // `appendTextStyleEnd` closes the same tags in reverse order.
    mtd appendTextStyleStart(attributes: string)
    {
        let style = .namedTextStyle(attribute(attributes, "text:style-name"))
        .styleStack.add(style)
        if not style.fontSize.isEmpty()
        {
            .appendHtml("<span style=\"font-size:")
            .appendHtml(style.fontSize)
            .appendHtml("\">")
        }

        if style.bold do
            .appendHtml("<strong>")
        if style.italic do
            .appendHtml("<em>")
        if style.underline do
            .appendHtml("<u>")
        if style.strike do
            .appendHtml("<s>")
        switch style.position
        {
        case .Subscript:   .appendHtml("<sub>")
        case .Superscript: .appendHtml("<sup>")
        case .Normal:      break
        }
    }

    // Closes the tags of the innermost style opened by `appendTextStyleStart`, in reverse order.
    mtd appendTextStyleEnd()
    {
        if .styleStack.isEmpty() do
            return
        let style = .styleStack.popBack()
        switch style.position
        {
        case .Subscript:   .appendHtml("</sub>")
        case .Superscript: .appendHtml("</sup>")
        case .Normal:      break
        }

        if style.strike do
            .appendHtml("</s>")
        if style.underline do
            .appendHtml("</u>")
        if style.italic do
            .appendHtml("</em>")
        if style.bold do
            .appendHtml("</strong>")
        if not style.fontSize.isEmpty() do
            .appendHtml("</span>")
    }

    mtd listUsesNumbers(attributes: string)->bool
    {
        let style = .namedListStyle(attribute(attributes, "text:style-name"))
        return style.numbered
    }

    // Returns the HTML anchor of bookmark `name`, assigning the next `odf-bookmark-N` id on first
    // use. Returns an empty string past `BookmarkLimit` bookmarks.
    mtd bookmarkTarget(name: string)->String
    {
        if not name.count do
            return {}
        for bookmark in .bookmarks where bookmark.name == name do
            return bookmark.target
        if .bookmarks.count == BookmarkLimit do
            return {}

        let target = Format.toString("odf-bookmark-%", .bookmarks.count + 1)
        var bookmark: Bookmark
        bookmark.name   = name
        bookmark.target = target
        .bookmarks.add(#move bookmark)
        return target
    }

    mtd appendBookmark(attributes: string)
    {
        let target = .bookmarkTarget(attribute(attributes, "text:name"))
        if not target.isEmpty() do
            .appendHtml(Format.toString("<span id=\"%\"></span>", target))
    }

    mtd linkHref(attributes: string)->String
    {
        let href = attribute(attributes, "xlink:href")
        if href.isEmpty() do
            return {}
        if Utf8.startsWith(href, "#")
        {
            let target = .bookmarkTarget(href[1 to])
            return target.isEmpty() ? "" : Format.toString("#%", target)
        }

        return externalHref(href)
    }

    mtd appendParagraphAlignment(attributes: string)
    {
        let alignment = .namedTextStyle(attribute(attributes, "text:style-name")).alignment
        if not alignment.isEmpty()
        {
            .appendHtml(" align=\"")
            .appendHtml(alignment)
            .appendHtml("\"")
        }
    }

    // Validates inline images before they cross from XML into generated HTML.
    mtd inlineImageUri(href: string)->String
    {
        let mediaType = inlineImageMediaType(href)
        if mediaType == "" or .imageCount == ImageCountLimit do
            return {}

        let prefix  = Format.toString("data:image/%;base64,", mediaType)
        let payload = href[prefix.count to]
        if payload.count > InlineImagePayloadLimit do
            return {}

        let bytes = catch Base64.decode(payload) as decodeError
        if decodeError != null or bytes.isEmpty() or bytes.count > ImageLimit or bytes.count > ImageLimit - .imageByteCount do
            return {}

        .imageCount     += 1
        .imageByteCount += bytes.count
        return href
    }

    mtd imageUri(attributes: string)->String
    {
        let href = attribute(attributes, "xlink:href")
        if Utf8.startsWith(href, "data:image/", .Latin1NoCase) do
            return .inlineImageUri(href)
        for image in .images where image.path == href do
            return image.uri
        return {}
    }

    // Emits an `img` element for an embedded image, sized by the enclosing `draw:frame` when it
    // gave a size. An image the package does not hold emits nothing.
    mtd appendImage(attributes: string)
    {
        let uri = .imageUri(attributes)
        if uri.isEmpty() do
            return
        var size: ImageSize
        if not .imageSizeStack.isEmpty() do
            size = .imageSizeStack.back()
        .appendHtml("<img src=\"")
        .appendHtml(uri)
        if not size.width.isEmpty()
        {
            .appendHtml("\" width=\"")
            .appendHtml(size.width)
        }

        if not size.height.isEmpty()
        {
            .appendHtml("\" height=\"")
            .appendHtml(size.height)
        }

        .appendHtml("\">")
    }

    // Keeps each presentation slide or drawing page self-contained so the viewer can exchange it without parsing again.
    mtd appendHtml(text: string)
    {
        if .kind == .Presentation or .kind == .Drawing
        {
            if .slideActive do
                .slide.html += text
            return
        }

        .html += text
    }

    // Returns the markup `appendHtml` writes to, or null while it writes nowhere.
    mtd htmlTarget()->*String?
    {
        if .kind == .Presentation or .kind == .Drawing do
            return .slideActive ? &.slide.html : null
        return &.html
    }

    // Opens a table row, repeated as many times as it declares once it is complete.
    mtd startHtmlRow(attributes: string)
    {
        let target = .htmlTarget()
        if target do
            .htmlRows.add({start: target.count, repeat: repeatCount(attributes, "table:number-rows-repeated")})
        .appendHtml("<tr>")
    }

    // Opens a table cell, repeated as many times as it declares once it is complete.
    mtd startHtmlCell(tag: const *Tag)
    {
        let target = .htmlTarget()
        var cell: HtmlCell
        if target do
            cell.start = target.count
        .appendHtml(.tableHeaderRows ? "<th>" : "<td>")
        if target do
            cell.contentStart = target.count
        cell.repeat = repeatCount(tag.attributes, "table:number-columns-repeated")
        .htmlCells.add(cell)
        if tag.selfClosing do
            .appendHtml(cellValue(tag.attributes))
    }

    // Closes a cell. An empty cell is held back in its row; a cell with content first writes the
    // empty cells held before it, then its own copies, up to `TableColumnLimit` cells in the row.
    mtd endHtmlCell()
    {
        let closing = .tableHeaderRows ? "</th>" : "</td>"
        let target  = .htmlTarget()
        if not target or .htmlCells.isEmpty() or .htmlRows.isEmpty()
        {
            .appendHtml(closing)
            return
        }

        let cell = .htmlCells.popBack()
        let row  = .htmlRows.backPtr()
        if target.count == cell.contentStart
        {
            target.removeBack(target.count - cell.start)
            row.pendingCells += cell.repeat
            return
        }

        target[] += closing
        let markup = String.from(target.toString()[cell.start to])
        target.removeBack(target.count - cell.start)
        row.hasContent = true

        let emptyCells = Math.min(row.pendingCells, TableColumnLimit - Math.min(row.cells, TableColumnLimit))
        for emptyCells do
            target[] += .tableHeaderRows ? "<th></th>" : "<td></td>"
        row.cells        += emptyCells
        row.pendingCells = 0

        let copies = Math.min(cell.repeat, Math.max(TableColumnLimit - Math.min(row.cells, TableColumnLimit), 1))
        for copies do
            target[] += markup
        row.cells += copies
    }

    // Closes a row. A row without content is held back in its table; a row with content first
    // writes the empty rows held before it, then its own copies, up to `HtmlRepeatedRowLimit` rows.
    mtd endHtmlRow()
    {
        let target = .htmlTarget()
        if not target or .htmlRows.isEmpty() or .htmlTables.isEmpty()
        {
            .appendHtml("</tr>")
            return
        }

        let row   = .htmlRows.popBack()
        let table = .htmlTables.backPtr()
        if not row.hasContent
        {
            target.removeBack(target.count - row.start)
            table.pendingRows += row.repeat
            return
        }

        target[] += "</tr>"
        let markup = String.from(target.toString()[row.start to])
        target.removeBack(target.count - row.start)

        let emptyRows = Math.min(table.pendingRows, HtmlRepeatedRowLimit - Math.min(table.rows, HtmlRepeatedRowLimit))
        for emptyRows do
            target[] += "<tr></tr>"
        table.rows        += emptyRows
        table.pendingRows = 0

        let copies = Math.min(row.repeat, Math.max(HtmlRepeatedRowLimit - Math.min(table.rows, HtmlRepeatedRowLimit), 1))
        for copies do
            target[] += markup
        table.rows += copies
    }

    mtd appendSpaces(attributes: string)
    {
        let count = repeatCount(attributes, "text:c")
        if .kind == .Spreadsheet and .cellActive
        {
            for count do
                .cell += ' '
            return
        }

        for count do
            .appendHtml("&#160;")
    }

    // Emits the opening HTML for an OpenDocument text, table or drawing element. Elements with no
    // HTML counterpart emit nothing.
    mtd startHtml(tag: const *Tag)
    {
        switch tag.name.toString()
        {
        case "text:h":
            .headingLevel = positiveAttribute(tag.attributes, "text:outline-level", 6)
            .appendHtml(Format.toString("<h%", .headingLevel))
            .appendParagraphAlignment(tag.attributes)
            .appendHtml(">")
            .appendTextStyleStart(tag.attributes)

        case "text:p":
            .appendHtml("<p")
            .appendParagraphAlignment(tag.attributes)
            .appendHtml(">")
            .appendTextStyleStart(tag.attributes)

        case "text:span":
            .appendTextStyleStart(tag.attributes)

        case "text:note-citation":
            .appendHtml("<sup>")

        case "text:note-body":
            .appendHtml("<blockquote>")

        case "text:a":
            .appendHtml("<a")
            let href = .linkHref(tag.attributes)
            if not href.isEmpty() do
                .appendHtml(Format.toString(" href=\"%\"", href))
            .appendHtml(">")

        case "text:bookmark", "text:bookmark-start":
            .appendBookmark(tag.attributes)

        case "text:list":
            let numbered = .listUsesNumbers(tag.attributes)
            .listStack.add(numbered)
            .appendHtml(numbered ? "<ol>" : "<ul>")

        case "text:list-item":
            .appendHtml("<li>")

        case "text:line-break":
            .appendHtml("<br/>")

        case "text:tab":
            .appendHtml("&#9;")

        case "text:s":
            .appendSpaces(tag.attributes)

        case "draw:frame":
            .imageSizeStack.add(imageSize(tag.attributes))

        case "draw:image":
            .appendImage(tag.attributes)

        case "table:table":
            let name = attribute(tag.attributes, "table:name")
            .appendHtml("<section><h2>")
            .appendHtml(name)
            .appendHtml("</h2><table>")
            .htmlTables.add({})

        case "table:table-header-rows":
            .tableHeaderRows += 1

        case "table:table-row":
            .startHtmlRow(tag.attributes)

        case "table:table-cell", "table:covered-table-cell":
            .startHtmlCell(tag)

        case "draw:page":
            if not .slideActive
            {
                .slideActive = true
                .slide.name  = decodeXmlText(attribute(tag.attributes, "draw:name"))
                .appendHtml("<article><section>")
            }
        }
    }

    // Emits the closing HTML matching `startHtml`, and completes the slide when its `draw:page`
    // ends.
    mtd endHtml(tag: const *Tag)
    {
        switch tag.name.toString()
        {
        case "text:h":
            .appendTextStyleEnd()
            .appendHtml(Format.toString("</h%>", .headingLevel))

        case "text:p":
            .appendTextStyleEnd()
            .appendHtml("</p>")

        case "text:span":
            .appendTextStyleEnd()

        case "text:note-citation":
            .appendHtml("</sup>")

        case "text:note-body":
            .appendHtml("</blockquote>")

        case "text:a":
            .appendHtml("</a>")

        case "text:list":
            var numbered = false
            if not .listStack.isEmpty() do
                numbered = .listStack.popBack()
            .appendHtml(numbered ? "</ol>" : "</ul>")

        case "text:list-item":
            .appendHtml("</li>")

        case "table:table":
            .appendHtml("</table></section>")
            if not .htmlTables.isEmpty() do
                discard .htmlTables.popBack()

        case "table:table-header-rows":
            if .tableHeaderRows do
                .tableHeaderRows -= 1

        case "table:table-row":
            .endHtmlRow()

        case "table:table-cell", "table:covered-table-cell":
            .endHtmlCell()

        case "draw:frame" where not .imageSizeStack.isEmpty():
            discard .imageSizeStack.popBack()

        case "draw:page":
            if .slideActive
            {
                .appendHtml("</section></article>")
                .slideActive = false
                .slides.add(#move .slide)
                .slide = {}
            }
        }
    }

    // Adds the completed cell to the row, repeated as many times as it declared. An empty cell is
    // held back until a cell with content follows it, so the padding that ends a row costs nothing.
    mtd finishCell() fail
    {
        if not .cellActive do
            return
        if .cell.isEmpty() do
            .cell = #move .cellFallback
        if .cell.isEmpty()
        {
            .pendingEmptyCells += .cellRepeat
        }
        else
        {
            if .pendingEmptyCells > TableColumnLimit - .row.cells.count do
                fail UnsupportedFormatError{Errors.mkString(texts().err_Columns)}
            for .pendingEmptyCells do
                .row.cells.add(String{})
            .pendingEmptyCells = 0

            if .cellRepeat > TableColumnLimit - .row.cells.count do
                fail UnsupportedFormatError{Errors.mkString(texts().err_Columns)}
            for .cellRepeat do
                .row.cells.add(.cell)
        }

        .cell.clear()
        .cellFallback.clear()
        .cellActive = false
        .cellRepeat = 1
    }

    // Adds the completed row to the sheet, repeated as many times as it declared. Fails rather than
    // expand a repeat past `TableRowLimit` rows or `TableCellLimit` cells.
    //
    // A row without content is held back until a row with content follows it, so the empty rows
    // that pad a sheet to its last row cost nothing; empty rows before the first one are dropped.
    mtd finishRow() fail
    {
        .pendingEmptyCells = 0
        if .row.cells.isEmpty()
        {
            if not .sheet.table.rows.isEmpty() do
                .pendingEmptyRows += .rowRepeat
            .row       = {}
            .rowRepeat = 1
            return
        }

        if .pendingEmptyRows > TableRowLimit - .sheet.table.rows.count do
            fail UnsupportedFormatError{Errors.mkString(texts().err_Rows)}
        for .pendingEmptyRows do
            .sheet.table.rows.add(Table.Row{})
        .pendingEmptyRows = 0

        if .rowRepeat > TableRowLimit - .sheet.table.rows.count do
            fail UnsupportedFormatError{Errors.mkString(texts().err_Rows)}
        if .rowRepeat > (TableCellLimit - .sheetCellCount) / .row.cells.count do
            fail UnsupportedFormatError{Errors.mkString(texts().err_Cells)}
        let cells = .row.cells.count
        .sheet.table.rows.add(#move .row)
        for .rowRepeat - 1 do
            .sheet.table.rows.add(.sheet.table.rows.back())
        .sheetCellCount += cells * .rowRepeat
        .row            = {}
        .rowRepeat      = 1
    }

    // Records spreadsheet structure for the table model: a table opens the sheet, rows and cells
    // keep their repeat counts, and paragraphs, tabs and spaces inside a cell build its text.
    mtd startSheet(tag: const *Tag)
    {
        switch tag.name.toString()
        {
        case "table:table":
            if not .activeSheet
            {
                .activeSheet = true
                .sheet.name  = decodeXmlText(attribute(tag.attributes, "table:name"))
            }

        case "table:table-row" where .activeSheet:
            .row       = {}
            .rowRepeat = repeatCount(tag.attributes, "table:number-rows-repeated")

        case "table:table-cell", "table:covered-table-cell" where .activeSheet:
            .cell.clear()
            .cellFallback = decodeXmlText(cellValue(tag.attributes))
            .cellActive   = true
            .cellRepeat   = repeatCount(tag.attributes, "table:number-columns-repeated")
            if tag.selfClosing do
                .cell += .cellFallback

        case "text:p" where .cellActive and not .cell.isEmpty():
            .cell += '\n'

        case "text:tab" where .cellActive:
            .cell += '\t'

        case "text:s" where .cellActive:
            .appendSpaces(tag.attributes)
        }
    }

    // Completes the cell, row or table that `tag` ends while a sheet is open.
    mtd endSheet(tag: const *Tag) fail
    {
        if not .activeSheet do
            return
        switch tag.name.toString()
        {
        case "table:table-cell", "table:covered-table-cell":
            try .finishCell()

        case "table:table-row":
            try .finishRow()

        case "table:table":
            .activeSheet = false
            .sheets.add(#move .sheet)
            .sheet            = {}
            .sheetCellCount   = 0
            .pendingEmptyRows = 0
        }
    }

    // Routes an opening tag: style definitions always, body content to the spreadsheet or HTML
    // builder. Text documents wrap the body in an `article`.
    mtd startTag(tag: const *Tag)
    {
        .startTextStyle(tag)
        if tag.name == "office:body"
        {
            .inBody  = true
            .sawBody = true
            if .kind == .Text do
                .appendHtml("<article>")
            return
        }

        if not .inBody do
            return

        // Comments, tracked deletions and speaker notes are skipped with everything they contain.
        if .skipDepth or isApparatus(tag.name)
        {
            .skipDepth += 1
            return
        }

        if .kind == .Spreadsheet do
            .startSheet(tag)
        else do
            .startHtml(tag)
    }

    // Routes a closing tag the same way as `startTag`, closing the body's `article` for text
    // documents.
    mtd endTag(tag: const *Tag) fail
    {
        .finishTextStyle(tag)
        if tag.name == "office:body"
        {
            if .kind == .Text do
                .appendHtml("</article>")
            .inBody = false
            return
        }

        if not .inBody do
            return
        if .skipDepth
        {
            .skipDepth -= 1
            return
        }

        if .kind == .Spreadsheet do
            try .endSheet(tag)
        else do
            .endHtml(tag)
    }

    mtd appendText(text: string)
    {
        if not .inBody or .skipDepth do
            return
        if .kind == .Spreadsheet
        {
            if .cellActive do
                .cell += decodeXmlText(text)
            return
        }

        .appendHtml(text)
    }

    mtd normalizeSheet(sheet: *Sheet) fail
    {
        if not sheet.table.promoteHeader() do
            fail UnsupportedFormatError{Errors.mkString(texts().err_Columns)}
    }

    // Returns the parsed content for the document kind: slides, HTML or normalized sheets. Fails
    // when the body or a slide or sheet was left open, or no slide, page or sheet was found.
    mtd finish()->Content fail
    {
        if not .sawBody or .inBody do
            fail InvalidFormatError{Errors.mkString(.sawBody ? texts().err_Xml : texts().err_Body)}

        var result: retval
        result.kind     = .kind
        result.metadata = #move .metadata
        if .kind == .Presentation or .kind == .Drawing
        {
            if .slideActive do
                fail InvalidFormatError{Errors.mkString(texts().err_Xml)}
            if .slides.isEmpty() do
                fail InvalidFormatError{Errors.mkString(.kind == .Presentation ? texts().err_Slide : texts().err_Page)}
            result.slides = #move .slides
            return result
        }

        if .kind == .Text
        {
            result.html = #move .html
            return result
        }

        if .activeSheet do
            fail InvalidFormatError{Errors.mkString(texts().err_Xml)}
        if .sheets.isEmpty() do
            fail InvalidFormatError{Errors.mkString(texts().err_Sheet)}
        for &sheet in .sheets do
            try .normalizeSheet(sheet)
        result.sheets = #move .sheets
        return result
    }
}

// Parses ODF's XML body without executing linked resources, macros, or scripts.
func parseContent(source: string, kind: Kind)->Content fail
{
    var images: Array'EmbeddedImage
    let metadata = try parseMetadata(source)
    return try parseContentWithImages(source, "", kind, #move images, #move metadata)
}

// Feeds `source` to `reader` as a flat sequence of text runs and start and end tags, a self-closing
// tag producing both. Only a tag that never closes fails; nesting is the reader's concern. Names
// reach the reader with the conventional ODF prefixes, whatever prefixes the stream declared.
func appendXml(reader: *Reader, source: string) fail
{
    var namespaces: Namespaces
    var textStart = 0'u64
    var at        = 0'u64
    while at < source.count
    {
        if source[at] != '<'
        {
            at += 1
            continue
        }

        if at > textStart do
            reader.appendText(source[textStart until at])
        let end = try tagEnd(source, at)
        var tag = parseTag(source[at + 1 until end])
        if not tag.name.isEmpty()
        {
            if tag.closing
            {
                namespaces.close(&tag)
                try reader.endTag(&tag)
            }
            else
            {
                namespaces.open(&tag)
                reader.startTag(&tag)
                if tag.selfClosing do
                    try reader.endTag(&tag)
            }
        }

        at        = end + 1
        textStart = at
    }

    if textStart < source.count do
        reader.appendText(source[textStart to])
}

// Parses ODF XML after package-resident images have been reduced to safe data URIs.
func parseContentWithImages(source, styles: string, kind: Kind, images: Array'EmbeddedImage, metadata: Metadata)->Content fail
{
    with var reader: Reader
    {
        .kind     = kind
        .images   = #move images
        .metadata = #move metadata
        for image in .images
        {
            .imageCount     += 1
            .imageByteCount += image.byteCount
        }
    }

    if styles.count do
        try appendXml(&reader, styles)
    try appendXml(&reader, source)
    return try reader.finish()
}
