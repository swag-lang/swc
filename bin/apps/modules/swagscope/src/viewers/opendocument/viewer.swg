#global internal
#global namespace Viewers.OpenDocument

using Core, Core.Errors, Gui

// Describes OpenDocument text, spreadsheet, presentation, and drawing files to the host.
func viewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "opendocument"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.OpenDocument)
        .create       = &createViewer
        .smokeFixture = "viewer.odt"
        .addSelectors(".odt;.ott;.fodt;.ods;.ots;.fods;.odp;.otp;.fodp;.odg;.otg;.fodg")
    }

    return result
}

private
{
    const ContentLimit            = 32 * 1024 * 1024'u64
    const TableColumnLimit        = 256'u64
    const TableRowLimit           = 100_000'u64
    const TableCellLimit          = 1_000_000'u64
    const RepeatedCellLimit       = 4_096'u64
    const TextStyleLimit          = 4_096'u64
    const BookmarkLimit           = 4_096'u64
    const ImageLimit              = 16 * 1024 * 1024'u64
    const ImageCountLimit         = 256'u64
    const InlineImagePayloadLimit = ((ImageLimit + 2) / 3) * 4
    const ImageDimensionLimit     = 4_096.0
    const MetadataLimit           = 256 * 1024'u64
    const MetadataValueLimit      = 512'u64
    const Apostrophe              = 39'u8
    const PageComboWidth          = 224.0
}

// Distinguishes the document surfaces that share the OpenDocument container.
enum Kind
{
    Text
    Spreadsheet
    Presentation
    Drawing
}

// One spreadsheet sheet, retaining its source name beside its reusable table model.
struct Sheet
{
    name:  String
    table: Table.Document
}

// One presentation slide, retaining its source name beside the isolated reader markup.
struct Slide
{
    name: String
    html: String
}

private enum TextPosition
{
    Normal
    Subscript
    Superscript
}

// Captures the portable text emphasis that the offline HTML surface can render without a style engine.
private struct TextStyle
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
private struct ListStyle
{
    name:     String
    numbered: bool
}

// Maps a source bookmark name to an HTML-only fragment identifier.
private struct Bookmark
{
    name:   String
    target: String
}

// One validated picture of the ODF package, converted to a data URI and keyed by its entry path.
private struct EmbeddedImage
{
    path:      String
    uri:       String
    byteCount: u64
}

// The frame size of an image, reduced to a known safe pixel spelling before it becomes HTML attributes.
private struct ImageSize
{
    width:  String
    height: String
}

// Preserves the display-safe document properties without treating metadata as executable content.
struct Metadata
{
    title:   String
    subject: String
    creator: String
}

// One decoded document, ready for the reader surface appropriate to its kind.
struct Content
{
    kind:     Kind
    metadata: Metadata
    html:     String
    sheets:   Array'Sheet
    slides:   Array'Slide
}

private struct Tag
{
    name:        String
    attributes:  String
    closing:     bool
    selfClosing: bool
}

private func xmlSpace(value: u8)->bool => value == ' ' or value == '\t' or value == '\r' or value == '\n'

// Finds a closing angle bracket without mistaking one inside a quoted XML attribute for a tag end.
private func tagEnd(source: string, start: u64)->u64 fail
{
    var at = start + 1
    var quoted: u8
    while at < source.count
    {
        let value = source[at]
        if quoted
        {
            if value == quoted do
                quoted = 0
        }
        elif value == '"' or value == Apostrophe
        {
            quoted = value
        }
        elif value == '>'
        {
            return at
        }

        at += 1
    }

    fail InvalidFormatError{Errors.mkString(texts().err_Xml)}
}

// Splits one XML element into the qualified name and the raw attribute text it carries.
private func parseTag(raw: string)->Tag
{
    var result: retval
    var at = 0'u64
    while at < raw.count and xmlSpace(raw[at]) do
        at += 1
    if at == raw.count or raw[at] == '!' or raw[at] == '?' do
        return result

    if raw[at] == '/'
    {
        result.closing = true
        at += 1
        while at < raw.count and xmlSpace(raw[at]) do
            at += 1
    }

    let nameStart = at
    while at < raw.count and not xmlSpace(raw[at]) and raw[at] != '/' do
        at += 1
    if at == nameStart do
        return result

    result.name       = raw[nameStart until at]
    result.attributes = raw[at to]

    var tail = raw.count
    while tail > at and xmlSpace(raw[tail - 1]) do
        tail -= 1
    result.selfClosing = not result.closing and tail > at and raw[tail - 1] == '/'
    return result
}

// Returns the raw value of the attribute named `wanted`, or an empty string when it is absent.
//
// HTML output retains its entities; plain model values decode them before reaching a table cell,
// page label, or other non-HTML surface.
private func attribute(attributes, wanted: string)->String
{
    var at = 0'u64
    while at < attributes.count
    {
        while at < attributes.count and xmlSpace(attributes[at]) do
            at += 1
        if at == attributes.count or attributes[at] == '/' do
            break

        let nameStart = at
        while at < attributes.count and not xmlSpace(attributes[at]) and attributes[at] != '=' and attributes[at] != '/' do
            at += 1
        let nameEnd = at
        while at < attributes.count and xmlSpace(attributes[at]) do
            at += 1
        if at == attributes.count or attributes[at] != '='
        {
            while at < attributes.count and not xmlSpace(attributes[at]) do
                at += 1
            continue
        }

        at += 1
        while at < attributes.count and xmlSpace(attributes[at]) do
            at += 1
        if at == attributes.count or attributes[at] != '"' and attributes[at] != Apostrophe
        {
            while at < attributes.count and not xmlSpace(attributes[at]) do
                at += 1
            continue
        }

        let quote = attributes[at]
        at += 1
        let valueStart = at
        while at < attributes.count and attributes[at] != quote do
            at += 1
        if at == attributes.count do
            break
        if attributes[nameStart until nameEnd] == wanted do
            return attributes[valueStart until at]
        at += 1
    }

    return {}
}

private enum MetadataField
{
    None
    Title
    Subject
    Creator
}

// Decodes the XML character references legal in document properties without accepting markup.
private func decodeXmlText(source: string)->String
{
    var result: retval
    var at = 0'u64
    while at < source.count
    {
        if source[at] != '&'
        {
            result += source[at until at + 1]
            at     += 1
            continue
        }

        var close = at + 1
        while close < source.count and close - at <= 16 and source[close] != ';' do
            close += 1
        if close == source.count or close - at > 16 or source[close] != ';'
        {
            result += "&"
            at     += 1
            continue
        }

        let entity = source[at + 1 until close]
        switch entity
        {
        case "amp":
            result += "&"

        case "apos":
            result += "'"

        case "gt":
            result += ">"

        case "lt":
            result += "<"

        case "quot":
            result += "\""

        default:
            if entity.count > 1 and entity[0] == '#'
            {
                let hexadecimal = entity.count > 2 and (entity[1] == 'x' or entity[1] == 'X')
                let digits      = hexadecimal ? entity[2 to] : entity[1 to]
                if hexadecimal
                {
                    let parsed = catch StrConv.parseX64(digits) as parseError
                    if parseError == null and not parsed.ovf and parsed.eat == digits.count and parsed.value
                    {
                        let character = cast(rune, parsed.value)
                        if Utf8.isValidRune(character)
                        {
                            result.append(character)
                            at = close + 1
                            continue
                        }
                    }
                }
                else
                {
                    let parsed = catch StrConv.parseU64(digits) as parseError
                    if parseError == null and parsed.eat == digits.count and parsed.value
                    {
                        let character = cast(rune, parsed.value)
                        if Utf8.isValidRune(character)
                        {
                            result.append(character)
                            at = close + 1
                            continue
                        }
                    }
                }
            }

            result += source[at until close + 1]
        }

        at = close + 1
    }

    return result
}

// Collapses metadata whitespace after XML entity decoding, keeping a title suitable for window chrome.
private func metadataValue(source: string)->String
{
    let decoded = decodeXmlText(source)
    var result:       retval
    var pendingSpace: bool
    for character in decoded
    {
        if character == ' ' or character == '\t' or character == '\r' or character == '\n'
        {
            if not result.isEmpty() do
                pendingSpace = true
            continue
        }

        if pendingSpace
        {
            result.append(cast(rune, ' '))
            pendingSpace = false
        }

        result.append(character)
        if result.count >= MetadataValueLimit do
            return result
    }

    return result
}

// Collects the small display-safe property set that applies to every OpenDocument family.
private struct MetadataReader
{
    metadata: Metadata
    field:    MetadataField
    depth:    u64
    text:     String
}

private impl MetadataReader
{
    mtd startTag(tag: const *Tag)
    {
        if .field != .None
        {
            .depth += 1
            return
        }

        switch tag.name.toString()
        {
        case "dc:title":   .field = .Title
        case "dc:subject": .field = .Subject
        case "dc:creator": .field = .Creator
        default:           return
        }

        .depth = 1
        .text.clear()
    }

    mtd appendText(text: string)
    {
        if .field == .None or .text.count >= MetadataValueLimit do
            return
        let count = Math.min(text.count, MetadataValueLimit - .text.count)
        .text += text[0 until count]
    }

    mtd endTag(?: const *Tag)
    {
        if .field == .None do
            return
        .depth -= 1
        if .depth do
            return

        let value = metadataValue(.text)
        switch .field
        {
        case .Title where .metadata.title.isEmpty():     .metadata.title = #move value
        case .Subject where .metadata.subject.isEmpty(): .metadata.subject = #move value
        case .Creator where .metadata.creator.isEmpty(): .metadata.creator = #move value
        default: discard value
        }

        .field = .None
    }
}

// Reads the document properties of a `meta.xml` payload or of a flat XML document.
//
// The same tag boundary checks apply as for document content.
private func parseMetadata(source: string)->Metadata fail
{
    var reader: MetadataReader
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
        let tag = parseTag(source[at + 1 until end])
        if not tag.name.isEmpty()
        {
            if tag.closing
            {
                reader.endTag(&tag)
            }
            else
            {
                reader.startTag(&tag)
                if tag.selfClosing do
                    reader.endTag(&tag)
            }
        }

        at        = end + 1
        textStart = at
    }

    if textStart < source.count do
        reader.appendText(source[textStart to])
    return #move reader.metadata
}

// Returns a positive integer attribute clamped to `maximum`, or 1 when it is absent or malformed.
private func positiveAttribute(attributes, name: string, maximum: u64)->u64
{
    let value = attribute(attributes, name)
    if value.isEmpty() do
        return 1
    let parsed = catch StrConv.parseU64(value) as parseError
    if parseError != null or parsed.eat != value.count or not parsed.value do
        return 1
    return Math.min(parsed.value, maximum)
}

private func repeatCount(attributes, name: string)->u64 => positiveAttribute(attributes, name, RepeatedCellLimit)

private func cellValue(attributes: string)->String
{
    for name in ["office:string-value", "office:value", "office:date-value", "office:time-value", "office:boolean-value"]
    {
        let value = attribute(attributes, name)
        if not value.isEmpty() do
            return value
    }

    return {}
}

private func imageDimension(attributes, name: string)->String
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

private func imageSize(attributes: string)->ImageSize
{
    var result: retval
    result.width  = imageDimension(attributes, "svg:width")
    result.height = imageDimension(attributes, "svg:height")
    return result
}

// Returns the media type of a base64 raster data URI the offline image decoder renders, or an empty string.
private func inlineImageMediaType(uri: string)->string
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
private func htmlAttribute(value: string)->String
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
private func externalHref(href: string)->String
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
private func fontSize(attributes: string)->String
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

// Turns one ODF body into reading HTML, one virtual table model per sheet, or isolated slide markup.
private struct Reader
{
    kind:     Kind
    metadata: Metadata
    html:     String

    inBody:          bool
    sawBody:         bool
    activeSheet:     bool
    cellActive:      bool
    cellRepeat:      u64 = 1
    rowRepeat:       u64 = 1
    headingLevel:    u64 = 1
    slideActive:     bool
    cell:            String
    cellFallback:    String
    sheetCellCount:  u64
    row:             Table.Row
    sheet:           Sheet
    sheets:          Array'Sheet
    slide:           Slide
    slides:          Array'Slide
    styleActive:     bool
    style:           TextStyle
    textStyles:      Array'TextStyle
    styleStack:      Array'TextStyle
    listStyleActive: bool
    listStyle:       ListStyle
    listStyles:      Array'ListStyle
    listStack:       Array'bool
    bookmarks:       Array'Bookmark
    tableHeaderRows: u64
    imageSizeStack:  Array'ImageSize
    images:          Array'EmbeddedImage
    imageByteCount:  u64
    imageCount:      u64
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

        case "table:table-header-rows":
            .tableHeaderRows += 1

        case "table:table-row":
            .appendHtml("<tr>")

        case "table:table-cell", "table:covered-table-cell":
            let repeated = repeatCount(tag.attributes, "table:number-columns-repeated")
            if .tableHeaderRows do
                .appendHtml(repeated == 1 ? "<th>" : Format.toString("<th colspan=\"%\">", repeated))
            else do
                .appendHtml(repeated == 1 ? "<td>" : Format.toString("<td colspan=\"%\">", repeated))
            if tag.selfClosing do
                .appendHtml(cellValue(tag.attributes))

        case "draw:page":
            if not .slideActive
            {
                .slideActive = true
                .slide.name  = decodeXmlText(attribute(tag.attributes, "draw:name"))
                .appendHtml("<article><section>")
            }
        }
    }

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

        case "table:table-header-rows":
            if .tableHeaderRows do
                .tableHeaderRows -= 1

        case "table:table-row":
            .appendHtml("</tr>")

        case "table:table-cell", "table:covered-table-cell":
            .appendHtml(.tableHeaderRows ? "</th>" : "</td>")

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

    mtd finishCell() fail
    {
        if not .cellActive do
            return
        if .cellRepeat > TableColumnLimit - .row.cells.count do
            fail UnsupportedFormatError{Errors.mkString(texts().err_Columns)}
        if .cell.isEmpty() do
            .cell = #move .cellFallback
        for .cellRepeat do
            .row.cells.add(.cell)
        .cell.clear()
        .cellFallback.clear()
        .cellActive = false
        .cellRepeat = 1
    }

    mtd finishRow() fail
    {
        if .row.cells.isEmpty() do
            return
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
            .sheet = {}
            .sheetCellCount = 0
        }
    }

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

        if .kind == .Spreadsheet do
            .startSheet(tag)
        else do
            .startHtml(tag)
    }

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

        if .kind == .Spreadsheet do
            try .endSheet(tag)
        else do
            .endHtml(tag)
    }

    mtd appendText(text: string)
    {
        if not .inBody do
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
        if sheet.table.rows.isEmpty() do
            return

        sheet.table.columns = #move sheet.table.rows[0].cells
        sheet.table.rows.removeAtOrdered(0)
        var count = sheet.table.columns.count
        for row in sheet.table.rows do
            count = Math.max(count, row.cells.count)
        if count > TableColumnLimit do
            fail UnsupportedFormatError{Errors.mkString(texts().err_Columns)}

        while sheet.table.columns.count < count do
            sheet.table.columns.add(String{})
        for column, columnIndex in sheet.table.columns where column.isEmpty()
        {
            sheet.table.columns[columnIndex] = Format.toString(texts().ui_Column, columnIndex + 1)
            sheet.table.generatedColumns.add(cast(u32, columnIndex))
        }
    }

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

private func appendXml(reader: *Reader, source: string) fail
{
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
        let tag = parseTag(source[at + 1 until end])
        if not tag.name.isEmpty()
        {
            if tag.closing
            {
                try reader.endTag(&tag)
            }
            else
            {
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
private func parseContentWithImages(source, styles: string, kind: Kind, images: Array'EmbeddedImage, metadata: Metadata)->Content fail
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

private func kindFromMime(mimeType: string)->Kind fail
{
    switch mimeType
    {
    case "application/vnd.oasis.opendocument.text", "application/vnd.oasis.opendocument.text-template":                 return .Text
    case "application/vnd.oasis.opendocument.spreadsheet", "application/vnd.oasis.opendocument.spreadsheet-template":   return .Spreadsheet
    case "application/vnd.oasis.opendocument.presentation", "application/vnd.oasis.opendocument.presentation-template": return .Presentation
    case "application/vnd.oasis.opendocument.graphics", "application/vnd.oasis.opendocument.graphics-template":         return .Drawing
    default: fail InvalidFormatError{Errors.mkString(texts().err_MimeType)}
    }
}

private func flatKind(fileName: string)->Kind fail
{
    switch Path.lowercaseExtension(fileName).toString()
    {
    case ".fodt": return .Text
    case ".fods": return .Spreadsheet
    case ".fodp": return .Presentation
    case ".fodg": return .Drawing
    default:      fail InvalidFormatError{Errors.mkString(texts().err_MimeType)}
    }
}

private func loadFlatContent(fileName: string)->Content fail
{
    let info = try File.info(fileName)
    if info.size > ContentLimit do
        fail UnsupportedFormatError{Errors.mkString(texts().err_TooLarge)}

    let bytes = try File.readAllBytes(fileName)
    if bytes.count > ContentLimit do
        fail UnsupportedFormatError{Errors.mkString(texts().err_TooLarge)}
    if not Utf8.isValid(bytes.toSlice()) do
        fail InvalidFormatError{Errors.mkString(texts().err_Encoding)}
    return try parseContent(cast(string, bytes.toSlice()), try flatKind(fileName))
}

private func imageMediaType(path: string)->string
{
    switch Path.lowercaseExtension(path).toString()
    {
    case ".bmp":          return "bmp"
    case ".gif":          return "gif"
    case ".ico":          return "x-icon"
    case ".jpg", ".jpeg": return "jpeg"
    case ".png":          return "png"
    case ".tif", ".tiff": return "tiff"
    case ".webp":         return "webp"
    default:              return ""
    }
}

// Converts only bounded picture-package entries into data URIs; external references stay inert.
private func loadImages(fileName: string, archive: const *Archive.Zip)->Array'EmbeddedImage
{
    var result: retval
    var total = 0'u64
    for &entry in archive.entries
    {
        if result.count == ImageCountLimit do
            break
        if not entry.path.startsWith("Pictures/", .Latin1NoCase) do
            continue
        let mediaType = imageMediaType(entry.path)
        if mediaType == "" or entry.uncompressedSize > ImageLimit or entry.uncompressedSize > ImageLimit - total do
            continue

        let bytes = catch Archive.Zip.loadEntry(fileName, entry) as imageError
        if imageError != null do
            continue

        var image: EmbeddedImage
        image.path      = entry.path
        image.uri       = Format.toString("data:image/%;base64,%", mediaType, Base64.encode(bytes.toSlice()))
        image.byteCount = bytes.count
        result.add(#move image)
        total += bytes.count
    }

    return result
}

private func loadContent(fileName: string)->Content fail
{
    switch Path.lowercaseExtension(fileName).toString()
    {
    case ".fodt", ".fods", ".fodp", ".fodg": return try loadFlatContent(fileName)
    }

    let archive = try Archive.Zip.load(fileName)
    var mime:    *Archive.ZipEntry?
    var content: *Archive.ZipEntry?
    var styles:  *Archive.ZipEntry?
    var meta:    *Archive.ZipEntry?
    for &entry in archive.entries
    {
        if entry.path == "mimetype" do
            mime = entry
        elif entry.path == "content.xml" do
            content = entry
        elif entry.path == "styles.xml" do
            styles = entry
        elif entry.path == "meta.xml" do
            meta = entry
    }

    if mime == null do
        fail InvalidFormatError{Errors.mkString(texts().err_MimeType)}
    if content == null do
        fail InvalidFormatError{Errors.mkString(texts().err_Content)}
    if content.uncompressedSize > ContentLimit do
        fail UnsupportedFormatError{Errors.mkString(texts().err_TooLarge)}

    let mimeBytes = try Archive.Zip.loadEntry(fileName, mime)
    let kind      = try kindFromMime(cast(string, mimeBytes.toSlice()))
    let bytes     = try Archive.Zip.loadEntry(fileName, content)
    if not Utf8.isValid(bytes.toSlice()) do
        fail InvalidFormatError{Errors.mkString(texts().err_Encoding)}
    var images: Array'EmbeddedImage
    if kind != .Spreadsheet do
        images = loadImages(fileName, &archive)
    var styleSource: String
    if styles != null and styles.uncompressedSize <= ContentLimit
    {
        let styleBytes = catch Archive.Zip.loadEntry(fileName, styles) as stylesError
        if stylesError == null and Utf8.isValid(styleBytes.toSlice()) do
            styleSource = cast(string, styleBytes.toSlice())
    }

    var metadata: Metadata
    if meta != null and meta.uncompressedSize <= MetadataLimit
    {
        let metadataBytes = catch Archive.Zip.loadEntry(fileName, meta) as metadataError
        if metadataError == null and Utf8.isValid(metadataBytes.toSlice()) do
            metadata = catch parseMetadata(cast(string, metadataBytes.toSlice()))
    }

    return try parseContentWithImages(cast(string, bytes.toSlice()), styleSource, kind, #move images, #move metadata)
}

// Shows an OpenDocument file on the reader surface of its kind, decoding it away from the GUI thread.
struct Panel
{
    using wnd: Wnd

    late
    {
        html:      *HtmlView
        table:     *Table.Panel
        commands:  *Wnd
        pageCombo: *ComboBox
        info:      *Wnd
        zoomLabel: *IconButton
    }

    document:             Content
    outline:              *DocumentOutline?
    sheetIndex:           u64
    slideIndex:           u64
    zoomPercent:          u32 = 100
    load:                 Viewer.BackgroundLoad'Content
    loadTimer:            *Timer?
    reportFailure:        Viewer.ReportFailure?
    reportDetails:        Viewer.ReportDetails?
    reportChromeChanged:  Viewer.ReportChromeChanged?
    reportLoadingChanged: Viewer.ReportLoadingChanged?
    failureReason:        String
}

private impl IWnd for Panel
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .loadTimer
        {
            evt.accepted = false
            return
        }

        if not .load.isDone() do
            return

        .removeTimer(evt.timer)
        .loadTimer     = null
        .failureReason = .load.finish(&.document)
        if not .failureReason.isEmpty()
        {
            if .reportFailure do
                .reportFailure(me, .failureReason)
            return
        }

        .publishDocument()
        .reportDocumentDetails()
        if .reportLoadingChanged do
            .reportLoadingChanged(me)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged and .loadTimer == null and .failureReason.isEmpty()
        {
            .fillPageChoices()
            .zoomLabel.toolTip = texts().ui_ZoomMenu
            .reportDocumentDetails()
        }

        .wnd.IWnd.onNotifyEvent(evt)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        if Viewer.isZoomKey(evt) and .document.kind != .Spreadsheet do
            .setZoom(Viewer.zoomAfterKey(evt, .zoomPercent))
        elif evt.modifiers != .None or not .navigatePagedDocument(evt.key) do
            evt.accepted = false
    }
}

private impl Panel
{
    mtd applyZoom()
    {
        if .html == null do
            return
        var style = HtmlStyle.theme()
        style.bodyFontSize = cast(u32, Math.max(Math.round(16.0 * cast(f32, .zoomPercent) / 100), 1))
        style.codeFontSize = cast(u32, Math.max(Math.round(14.0 * cast(f32, .zoomPercent) / 100), 1))
        .html.setDocumentStyle(style)
    }

    internal mtd setZoom(percent: u32)
    {
        .zoomPercent = Viewer.clampZoom(percent)
        .applyZoom()
        .zoomLabel.setText(Viewer.zoomText(.zoomPercent))
    }

    mtd showZoomMenu()
    {
        let percent = Viewer.pickZoom(me, .zoomLabel, .zoomPercent)
        if percent do
            .setZoom(percent)
    }

    mtd refreshZoomChrome()
    {
        let visible = .document.kind != .Spreadsheet
        .info.show(visible)
        if visible do
            .setZoom(.zoomPercent)
        if .reportChromeChanged do
            .reportChromeChanged(me)
    }

    mtd kindName()->string
    {
        switch #complete .document.kind
        {
        case .Text:         return texts().ui_Text
        case .Spreadsheet:  return texts().ui_Spreadsheet
        case .Presentation: return texts().ui_Presentation
        case .Drawing:      return texts().ui_Drawing
        }
    }

    mtd documentDetails(details: string)->String
    {
        if .document.metadata.title.isEmpty() do
            return details
        return Format.toString("% · %", details, .document.metadata.title)
    }

    mtd reportDocumentDetails()
    {
        if not .reportDetails do
            return
        if .document.kind == .Spreadsheet and .sheetIndex < .document.sheets.count
        {
            .reportDetails(me, .documentDetails(Format.toString(texts().ui_DetailsSheet, .sheetName(.sheetIndex))))
            return
        }

        if (.document.kind == .Presentation or .document.kind == .Drawing) and .slideIndex < .document.slides.count
        {
            let details = .document.kind == .Presentation ? texts().ui_DetailsSlide : texts().ui_DetailsPage
            .reportDetails(me, .documentDetails(Format.toString(details, .slideName(.slideIndex))))
            return
        }

        .reportDetails(me, .documentDetails(Format.toString(texts().ui_Details, .kindName())))
    }

    // Returns the source name of a sheet, or a numbered label when the sheet has none.
    mtd sheetName(index: u64)->String
    {
        let name = .document.sheets[index].name
        if not name.isEmpty() do
            return name
        return Format.toString(texts().ui_Sheet, index + 1)
    }

    // Returns the source name of a slide or drawing page, or a numbered label when it has none.
    mtd slideName(index: u64)->String
    {
        let name = .document.slides[index].name
        if not name.isEmpty() do
            return name
        return Format.toString(.document.kind == .Drawing ? texts().ui_Page : texts().ui_Slide, index + 1)
    }

    mtd fillPageChoices()
    {
        .pageCombo.clear()

        var count:  u64
        var active: u64
        switch .document.kind
        {
        case .Spreadsheet:
            .pageCombo.toolTip = texts().ui_TipSheet
            count  = .document.sheets.count
            active = .sheetIndex
            for index in count do
                .pageCombo.addItem(.sheetName(index))

        case .Presentation:
            .pageCombo.toolTip = texts().ui_TipSlide
            count  = .document.slides.count
            active = .slideIndex
            for index in count do
                .pageCombo.addItem(.slideName(index))

        case .Drawing:
            .pageCombo.toolTip = texts().ui_TipPage
            count  = .document.slides.count
            active = .slideIndex
            for index in count do
                .pageCombo.addItem(.slideName(index))

        case .Text:
            count = 0
        }

        if count do
            .pageCombo.setSelectedIndex(cast(u32, active), notify: false)
        let hasChoices = count > 1
        .pageCombo.show(hasChoices)
        .commands.show(hasChoices)
        if .reportChromeChanged do
            .reportChromeChanged(me)
    }

    mtd showSheet(index: u64, clearSearch: bool)->bool
    {
        if index >= .document.sheets.count or .table == null do
            return false
        if index == .sheetIndex
        {
            if clearSearch do
                .table.clearSearch()
            return true
        }

        .document.sheets[.sheetIndex].table = #move .table.document
        .table.destroy()
        .sheetIndex      = index
        .table           = Table.Panel.createDocument(me, #move .document.sheets[index].table)
        .table.dockStyle = .Center
        .pageCombo.setSelectedIndex(cast(u32, index), notify: false)
        if clearSearch do
            .table.clearSearch()
        .applyLayout()
        .setInitialFocus(.table)
        .reportDocumentDetails()
        return true
    }

    // Creates the reading surface for generated markup, whose activated links open in the system browser.
    mtd createHtmlView(markup: string)
    {
        .html = HtmlView.createText(me, markup)
        .html.dockStyle = .Center
        .applyZoom()
        .html.sigLinkActivated += func(?, url)
        {
            Env.openUrl(url)
        }
    }

    mtd showSlide(index: u64, clearSearch: bool)->bool
    {
        if index >= .document.slides.count do
            return false
        if index == .slideIndex and .html != null
        {
            if clearSearch do
                .html.clearSearch()
            return true
        }

        if .html != null do
            .html.destroy()
        .slideIndex = index
        .createHtmlView(.document.slides[index].html)
        .pageCombo.setSelectedIndex(cast(u32, index), notify: false)
        if clearSearch do
            .html.clearSearch()
        .applyLayout()
        .setInitialFocus(.html)
        .reportDocumentDetails()
        return true
    }

    // Preserves the ordinary document-reader keys without stealing scroll keys from text documents.
    mtd navigatePagedDocument(key: Input.Key)->bool
    {
        if .document.kind != .Presentation and .document.kind != .Drawing do
            return false

        switch key
        {
        case .Left, .PageUp where .slideIndex: return .showSlide(.slideIndex - 1, true)
        case .Right, .PageDown where .slideIndex + 1 < .document.slides.count: return .showSlide(.slideIndex + 1, true)
        case .Home where .slideIndex: return .showSlide(0, true)
        case .End where .slideIndex + 1 < .document.slides.count: return .showSlide(.document.slides.count - 1, true)
        }

        return false
    }

    mtd showPage(index: u64, clearSearch: bool)->bool
    {
        switch #complete .document.kind
        {
        case .Spreadsheet:  return .showSheet(index, clearSearch)
        case .Presentation: return .showSlide(index, clearSearch)
        case .Drawing:      return .showSlide(index, clearSearch)
        case .Text:         return false
        }
    }

    mtd collectTableMatches(document: const *Table.Document, sheetIndex: u64, text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        for row, rowIndex in document.rows
        {
            for cell, column in row.cells do
                Viewer.collectTextMatches(cell.toString(), text, options, sheetIndex, (rowIndex << 32) | column, 0, result)
        }
    }

    mtd collectSpreadsheetMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        for &sheet, index in .document.sheets
        {
            if index == .sheetIndex and .table != null do
                .collectTableMatches(&.table.document, index, text, options, result)
            else do
                .collectTableMatches(&sheet.table, index, text, options, result)
        }
    }

    mtd collectPresentationMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        for slide, index in .document.slides do
            Viewer.collectTextMatches(slide.html, text, options, index, 0, 0, result)
    }

    mtd publishDocument()
    {
        if .document.kind == .Spreadsheet
        {
            .table = Table.Panel.createDocument(me, #move .document.sheets[0].table)
            .table.dockStyle = .Center
            .fillPageChoices()
            .setInitialFocus(.table)
        }
        elif .document.kind == .Presentation or .document.kind == .Drawing
        {
            .fillPageChoices()
            discard .showSlide(0, false)
        }
        else
        {
            .createHtmlView(.document.html)
            .setInitialFocus(.html)
        }

        if .outline
        {
            if .document.kind == .Text
            {
                .outline.bindHtml(.html)
            }
            else
            {
                .outline.clear()
                if .document.kind == .Spreadsheet
                {
                    for sheet, index in .document.sheets do
                        .outline.add(sheet.name, 1, index)
                }
                else
                {
                    for slide, index in .document.slides do
                        .outline.add(slide.name, 1, index)
                }

                .outline.refresh()
                .outline.sigSelected += func|view = me|(?, index) { discard view.showPage(index, true) }
            }
        }

        .refreshZoomChrome()
        .applyLayout()
    }

    mtd collectMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        if .document.kind == .Spreadsheet
        {
            if .table != null do
                .collectSpreadsheetMatches(text, options, result)
            return
        }

        if .document.kind == .Presentation or .document.kind == .Drawing
        {
            .collectPresentationMatches(text, options, result)
            return
        }

        if .html != null do
            Viewer.collectTextMatches(.document.html, text, options, 0, 0, 0, result)
    }

    mtd revealMatch(match: Viewer.SearchMatch, text: string)->bool
    {
        if .document.kind == .Spreadsheet
        {
            if not .showSheet(match.major, false) do
                return false
            var tableMatch = match
            tableMatch.major = match.minor >> 32
            tableMatch.minor = match.minor & 0xFFFF_FFFF'u64
            return .table.revealMatch(tableMatch)
        }

        if .document.kind == .Presentation or .document.kind == .Drawing
        {
            if not .showSlide(match.major, false) do
                return false
            return .html.revealFileOffset(match.offset, text)
        }

        if .html == null do
            return false
        return .html.revealFileOffset(match.offset, text)
    }

    mtd searchBounds(result: *Math.Rectangle)->bool
    {
        if .document.kind == .Spreadsheet
        {
            if .table == null do
                return false
            return .table.searchBounds(result)
        }

        if .html == null do
            return false
        return .html.searchMatchRect(result)
    }

    mtd clearSearch()
    {
        if .document.kind == .Spreadsheet
        {
            if .table != null do
                .table.clearSearch()
            return
        }

        if .html != null do
            .html.clearSearch()
    }

    mtd retire()->bool
    {
        if not .load.retire() do
            return false
        if .loadTimer
        {
            .removeTimer(.loadTimer)
            .loadTimer = null
        }

        return true
    }

    func create(host: Viewer.Host)->*Panel
    {
        let services = host.services()

        with let result = Wnd.create'Panel(host.contentParent(), "scope.opendocument")
        {
            .backgroundStyle      = .View
            .reportFailure        = services.reportFailure
            .reportDetails        = services.reportDetails
            .reportChromeChanged  = services.reportChromeChanged
            .reportLoadingChanged = services.reportLoadingChanged
        }

        result.createZoomButton(host)
        result.hookOnChildEvent = func|view = result|(?, evt)
        {
            switch evt
            {
            case KeyEvent as keyEvt where Viewer.isZoomKey(keyEvt) and view.document.kind != .Spreadsheet:
                view.setZoom(Viewer.zoomAfterKey(keyEvt, view.zoomPercent))
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.modifiers == .None:
                return view.navigatePagedDocument(keyEvt.key)

            default:
                return false
            }
        }

        result.createPageSelector(host)
        result.load.start(host.fileName(), &loadContent)
        result.loadTimer = result.addTimer(Viewer.BackgroundPollInterval)
        return result
    }

    // Creates the reading-zoom button, hidden until a document that can zoom is published.
    mtd createZoomButton(host: Viewer.Host)
    {
        .info = host.createInfoGroup(Viewer.ZoomSlotWidth)
        .info.hide()
        .zoomLabel = Viewer.createZoomButton(me.info, "scope.opendocument.zoom", texts().ui_ZoomMenu)
        .zoomLabel.sigPressed += func|view = me|(?) { view.showZoomMenu() }
    }

    // Creates the sheet, slide, or page selector, hidden until a document offers several.
    mtd createPageSelector(host: Viewer.Host)
    {
        .commands = host.createCommandGroup(PageComboWidth)
        .commands.hide()
        with .pageCombo = ComboBox.create(me.commands, {0, 0, PageComboWidth, 36})
        {
            .dockStyle = .Left
            .hide()
            .toolTip    = texts().ui_TipSheet
            .sigChanged += func|view = me|(?, index) { discard view.showPage(index, true) }
        }
    }
}

// Creates the integrated reader for OpenDocument files.
func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)
    view.outline = DocumentOutline.create(host)
    host.attachView(view)
    host.setDetails(texts().ui_Name)

    with var search: Viewer.SearchApi
    {
        .collectMatches = func|view|(text, options, ?, matches)->bool
        {
            view.collectMatches(text, options, matches)
            return true
        }

        .revealMatch = func|view|(match, text)->bool
        {
            return view.revealMatch(match, text)
        }

        .matchBounds = func|view|(?, bounds)->bool
        {
            return view.searchBounds(bounds)
        }

        .clear = func|view|() => view.clearSearch()
    }

    host.setSearch(search)

    with var lifecycle: Viewer.LifecycleApi
    {
        .isLoading = func|view|()->bool => view.loadTimer != null
        .needsLoadingOverlay = func|view|()->bool => view.loadTimer != null
        .retire    = func|view|()->bool => view.retire()
    }

    host.setLifecycle(lifecycle)
}
