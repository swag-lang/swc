#global internal

using Core, Core.Errors, Gui

// Describes OpenDocument text, spreadsheet, presentation, and drawing files to the host.
func openDocumentViewerPlugin()->Viewer.Plugin
{
    var result: retval
    result.key          = "opendocument"
    result.resolveName  = func()->string { return openDocumentStrings().ui_Name }
    result.attach       = &registerOpenDocumentStrings
    result.iconAtlas    = viewerIcons()
    result.iconIndex    = cast(s32) ViewerIcons.OpenDocument
    result.create       = &createOpenDocumentViewer
    result.smokeFixture = "viewer.odt"
    result.addSelectors(".odt;.ott;.fodt;.ods;.ots;.fods;.odp;.otp;.fodp;.odg;.otg;.fodg")
    return result
}

private const OpenDocumentContentLimit            = 32 * 1024 * 1024'u64
private const OpenDocumentTableColumnLimit        = 256'u64
private const OpenDocumentTableRowLimit           = 100_000'u64
private const OpenDocumentTableCellLimit          = 1_000_000'u64
private const OpenDocumentRepeatedCellLimit       = 4_096'u64
private const OpenDocumentTextStyleLimit          = 4_096'u64
private const OpenDocumentBookmarkLimit           = 4_096'u64
private const OpenDocumentImageLimit              = 16 * 1024 * 1024'u64
private const OpenDocumentImageCountLimit         = 256'u64
private const OpenDocumentInlineImagePayloadLimit = ((OpenDocumentImageLimit + 2) / 3) * 4
private const OpenDocumentImageDimensionLimit     = 4_096.0
private const OpenDocumentMetadataLimit           = 256 * 1024'u64
private const OpenDocumentMetadataValueLimit      = 512'u64
private const OpenDocumentApostrophe              = 39'u8
private const OpenDocumentPageComboWidth          = 224.0

// Distinguishes the document surfaces that share the OpenDocument container.
internal enum OpenDocumentKind
{
    Text
    Spreadsheet
    Presentation
    Drawing
}

// One spreadsheet sheet, retaining its source name beside its reusable table model.
internal struct OpenDocumentSheet
{
    name:  String
    table: TableDocument
}

// One presentation slide, retaining its source name beside the isolated reader markup.
internal struct OpenDocumentSlide
{
    name: String
    html: String
}

private enum OpenDocumentTextPosition
{
    Normal
    Subscript
    Superscript
}

// Captures the portable text emphasis that the offline HTML surface can render without a style engine.
private struct OpenDocumentTextStyle
{
    name:      String
    bold:      bool
    italic:    bool
    underline: bool
    strike:    bool
    position:  OpenDocumentTextPosition
    alignment: String
    fontSize:  String
}

// Records whether a named ODF list asks the reader for ordered markers.
private struct OpenDocumentListStyle
{
    name:     String
    numbered: bool
}

// Maps a source bookmark name to an HTML-only fragment identifier.
private struct OpenDocumentBookmark
{
    name:   String
    target: String
}

// An image comes only from a validated local ODF package entry or an inline raster data URI.
private struct OpenDocumentImage
{
    path:      String
    uri:       String
    byteCount: u64
}

// Dimensions are reduced to a known safe pixel spelling before becoming generated HTML attributes.
private struct OpenDocumentImageSize
{
    width:  String
    height: String
}

// Preserves the display-safe document properties without treating metadata as executable content.
internal struct OpenDocumentMetadata
{
    title:   String
    subject: String
    creator: String
}

// One decoded document, ready for the reader surface appropriate to its kind.
internal struct OpenDocumentContent
{
    kind:     OpenDocumentKind
    metadata: OpenDocumentMetadata
    html:     String
    sheets:   Array'OpenDocumentSheet
    slides:   Array'OpenDocumentSlide
}

private struct OpenDocumentTag
{
    name:        String
    attributes:  String
    closing:     bool
    selfClosing: bool
}

private func openDocumentXmlSpace(value: u8)->bool => value == ' ' or value == '\t' or value == '\r' or value == '\n'

// Finds a closing angle bracket without mistaking one inside a quoted XML attribute for a tag end.
private func openDocumentTagEnd(source: string, start: u64)->u64 fail
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
        elif value == '"' or value == OpenDocumentApostrophe do
            quoted = value
        elif value == '>' do
            return at
        at += 1
    }

    fail InvalidFormatError{Errors.mkString(openDocumentStrings().err_Xml)}
}

// Splits one XML element into the qualified name and the raw attribute text it carries.
private func parseOpenDocumentTag(raw: string)->OpenDocumentTag
{
    var result: retval
    var at = 0'u64
    while at < raw.count and openDocumentXmlSpace(raw[at]) do
        at += 1
    if at == raw.count or raw[at] == '!' or raw[at] == '?' do
        return result

    if raw[at] == '/'
    {
        result.closing = true
        at             += 1
        while at < raw.count and openDocumentXmlSpace(raw[at]) do
            at += 1
    }

    let nameStart = at
    while at < raw.count and !openDocumentXmlSpace(raw[at]) and raw[at] != '/' do
        at += 1
    if at == nameStart do
        return result

    result.name       = String.from(raw[nameStart until at])
    result.attributes = String.from(raw[at to])

    var tail = raw.count
    while tail > at and openDocumentXmlSpace(raw[tail - 1]) do
        tail -= 1
    result.selfClosing = !result.closing and tail > at and raw[tail - 1] == '/'
    return result
}

// Returns the raw XML attribute value. XML entities remain encoded until the HTML reader consumes
// the generated document, preserving the document's literal text without reimplementing decoding.
private func openDocumentAttribute(attributes, wanted: string)->String
{
    var at = 0'u64
    while at < attributes.count
    {
        while at < attributes.count and openDocumentXmlSpace(attributes[at]) do
            at += 1
        if at == attributes.count or attributes[at] == '/' do
            break

        let nameStart = at
        while at < attributes.count and !openDocumentXmlSpace(attributes[at]) and attributes[at] != '=' and attributes[at] != '/' do
            at += 1
        let nameEnd = at
        while at < attributes.count and openDocumentXmlSpace(attributes[at]) do
            at += 1
        if at == attributes.count or attributes[at] != '='
        {
            while at < attributes.count and !openDocumentXmlSpace(attributes[at]) do
                at += 1
            continue
        }

        at += 1
        while at < attributes.count and openDocumentXmlSpace(attributes[at]) do
            at += 1
        if at == attributes.count or attributes[at] != '"' and attributes[at] != OpenDocumentApostrophe
        {
            while at < attributes.count and !openDocumentXmlSpace(attributes[at]) do
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
            return String.from(attributes[valueStart until at])
        at += 1
    }

    return {}
}

private enum OpenDocumentMetadataField
{
    None
    Title
    Subject
    Creator
}

// Decodes the XML character references legal in document properties without accepting markup.
private func openDocumentDecodeXmlText(source: string)->String
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
                    if parseError == null and !parsed.ovf and parsed.eat == digits.count and parsed.value
                    {
                        let character = cast(rune) parsed.value
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
                        let character = cast(rune) parsed.value
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
private func openDocumentMetadataValue(source: string)->String
{
    let decoded = openDocumentDecodeXmlText(source)
    var result:       retval
    var pendingSpace: bool
    for character in decoded
    {
        if character == ' ' or character == '\t' or character == '\r' or character == '\n'
        {
            if !result.isEmpty() do
                pendingSpace = true
            continue
        }

        if pendingSpace
        {
            result.append(cast(rune) ' ')
            pendingSpace = false
        }

        result.append(character)
        if result.count >= OpenDocumentMetadataValueLimit do
            return result
    }

    return result
}

// Collects the small display-safe property set that applies to every OpenDocument family.
private struct OpenDocumentMetadataReader
{
    metadata: OpenDocumentMetadata
    field:    OpenDocumentMetadataField
    depth:    u64
    text:     String
}

private impl OpenDocumentMetadataReader
{
    mtd startTag(tag: const *OpenDocumentTag)
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
        if .field == .None or .text.count >= OpenDocumentMetadataValueLimit do
            return
        let count = Math.min(text.count, OpenDocumentMetadataValueLimit - .text.count)
        .text += text[0 until count]
    }

    mtd endTag(tag: const *OpenDocumentTag)
    {
        discard tag
        if .field == .None do
            return
        .depth -= 1
        if .depth do
            return

        let value = openDocumentMetadataValue(.text.toString())
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

// Reads an optional `meta.xml` payload with the same tag boundary checks as document content.
private func parseOpenDocumentMetadata(source: string)->OpenDocumentMetadata fail
{
    var reader: OpenDocumentMetadataReader
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
        let end = try openDocumentTagEnd(source, at)
        let tag = parseOpenDocumentTag(source[at + 1 until end])
        if !tag.name.isEmpty()
        {
            if tag.closing do
                reader.endTag(&tag)
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

private func openDocumentPositiveAttribute(attributes, name: string, maximum: u64)->u64
{
    let value = openDocumentAttribute(attributes, name)
    if value.isEmpty() do
        return 1
    let parsed = catch StrConv.parseU64(value.toString()) as parseError
    if parseError != null or parsed.eat != value.count or !parsed.value do
        return 1
    return Math.min(parsed.value, maximum)
}

private func openDocumentRepeated(attributes, name: string)->u64 => openDocumentPositiveAttribute(attributes, name, OpenDocumentRepeatedCellLimit)

private func openDocumentCellValue(attributes: string)->String
{
    for name in ["office:string-value", "office:value", "office:date-value", "office:time-value", "office:boolean-value"]
    {
        let value = openDocumentAttribute(attributes, name)
        if !value.isEmpty() do
            return value
    }

    return {}
}

private func openDocumentImageDimension(attributes, name: string)->String
{
    let value = openDocumentAttribute(attributes, name)
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

    if !end do
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

    if pixels < 1 or pixels > OpenDocumentImageDimensionLimit do
        return {}
    return Format.toString("%px", Math.round(cast(f32) pixels))
}

private func openDocumentImageSize(attributes: string)->OpenDocumentImageSize
{
    var result: retval
    result.width  = openDocumentImageDimension(attributes, "svg:width")
    result.height = openDocumentImageDimension(attributes, "svg:height")
    return result
}

// Accepts only the raster data-URI forms the offline image decoder can render.
private func openDocumentInlineImageMediaType(uri: string)->string
{
    let lowercase = String.from(uri).toLower()
    for mediaType in ["bmp", "gif", "x-icon", "jpeg", "png", "tiff", "webp"]
    {
        let prefix = Format.toString("data:image/%;base64,", mediaType)
        if Utf8.startsWith(lowercase.toString(), prefix.toString()) do
            return mediaType
    }

    return ""
}

// Re-encodes XML text as one generated HTML attribute without preserving markup syntax.
private func openDocumentHtmlAttribute(value: string)->String
{
    let decoded = openDocumentDecodeXmlText(value)
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
private func openDocumentExternalHref(href: string)->String
{
    let decoded = openDocumentDecodeXmlText(href)
    if !Utf8.startsWith(decoded.toString(), "http://", .Latin1NoCase) and !Utf8.startsWith(decoded.toString(), "https://", .Latin1NoCase) do
        return {}
    for character in decoded
    {
        if character <= ' ' or character == '"' or character == '<' or character == '>' do
            return {}
    }

    return openDocumentHtmlAttribute(href)
}

// Converts common ODF absolute sizes to relative HTML sizes, allowing the reader zoom to scale them.
private func openDocumentFontSize(attributes: string)->String
{
    let value = openDocumentAttribute(attributes, "fo:font-size")
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

    if !end do
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
private struct OpenDocumentReader
{
    kind:     OpenDocumentKind
    metadata: OpenDocumentMetadata
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
    row:             TableRow
    sheet:           OpenDocumentSheet
    sheets:          Array'OpenDocumentSheet
    slide:           OpenDocumentSlide
    slides:          Array'OpenDocumentSlide
    styleActive:     bool
    style:           OpenDocumentTextStyle
    textStyles:      Array'OpenDocumentTextStyle
    styleStack:      Array'OpenDocumentTextStyle
    listStyleActive: bool
    listStyle:       OpenDocumentListStyle
    listStyles:      Array'OpenDocumentListStyle
    listStack:       Array'bool
    bookmarks:       Array'OpenDocumentBookmark
    tableHeaderRows: u64
    imageSizeStack:  Array'OpenDocumentImageSize
    images:          Array'OpenDocumentImage
    imageByteCount:  u64
    imageCount:      u64
}

private impl OpenDocumentReader
{
    mtd namedTextStyle(name: string)->OpenDocumentTextStyle
    {
        for style in .textStyles where style.name == name do
            return style
        return {}
    }

    mtd namedListStyle(name: string)->OpenDocumentListStyle
    {
        for style in .listStyles where style.name == name do
            return style
        return {}
    }

    mtd applyTextStyleProperties(style: *OpenDocumentTextStyle, attributes: string)
    {
        let weight = openDocumentAttribute(attributes, "fo:font-weight")
        if !weight.isEmpty() do
            style.bold = weight == "bold" or weight == "bolder" or weight == "600" or weight == "700" or weight == "800" or weight == "900"

        let fontStyle = openDocumentAttribute(attributes, "fo:font-style")
        if !fontStyle.isEmpty() do
            style.italic = fontStyle == "italic" or fontStyle == "oblique"

        let underline = openDocumentAttribute(attributes, "style:text-underline-style")
        if !underline.isEmpty() do
            style.underline = underline != "none"

        let strike = openDocumentAttribute(attributes, "style:text-line-through-style")
        if !strike.isEmpty() do
            style.strike = strike != "none"

        let position = openDocumentAttribute(attributes, "style:text-position")
        if Utf8.startsWith(position.toString(), "sub") do
            style.position = .Subscript
        elif Utf8.startsWith(position.toString(), "super") do
            style.position = .Superscript
        elif !position.isEmpty() do
            style.position = .Normal

        let fontSize = openDocumentFontSize(attributes)
        if !fontSize.isEmpty() do
            style.fontSize = #move fontSize
    }

    mtd applyParagraphStyleProperties(style: *OpenDocumentTextStyle, attributes: string)
    {
        switch openDocumentAttribute(attributes, "fo:text-align").toString()
        {
        case "left", "start": style.alignment = "left"
        case "center":        style.alignment = "center"
        case "right", "end":  style.alignment = "right"
        case "justify":       style.alignment = "justify"
        }
    }

    mtd startTextStyle(tag: const *OpenDocumentTag)
    {
        if tag.name == "text:list-style"
        {
            let name = openDocumentAttribute(tag.attributes.toString(), "style:name")
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
            let family     = openDocumentAttribute(attributes, "style:family")
            let name       = openDocumentAttribute(attributes, "style:name")
            if (family != "text" and family != "paragraph") or name.isEmpty() do
                return

            .styleActive = true
            .style       = .namedTextStyle(openDocumentAttribute(attributes, "style:parent-style-name").toString())
            .style.name  = name
            .applyTextStyleProperties(&.style, attributes)
            return
        }

        if !.styleActive do
            return
        if tag.name == "style:text-properties" do
            .applyTextStyleProperties(&.style, tag.attributes.toString())
        elif tag.name == "style:paragraph-properties" do
            .applyParagraphStyleProperties(&.style, tag.attributes.toString())
    }

    mtd finishTextStyle(tag: const *OpenDocumentTag)
    {
        if tag.name == "text:list-style" and .listStyleActive
        {
            if .listStyles.count < OpenDocumentTextStyleLimit do
                .listStyles.add(#move .listStyle)
            .listStyleActive = false
            .listStyle       = {}
            return
        }

        if tag.name != "style:style" or !.styleActive do
            return
        if .textStyles.count < OpenDocumentTextStyleLimit do
            .textStyles.add(#move .style)
        .styleActive = false
        .style       = {}
    }

    mtd appendTextStyleStart(attributes: string)
    {
        let style = .namedTextStyle(openDocumentAttribute(attributes, "text:style-name").toString())
        .styleStack.add(style)
        if !style.fontSize.isEmpty()
        {
            .appendHtml("<span style=\"font-size:")
            .appendHtml(style.fontSize.toString())
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
        if !style.fontSize.isEmpty() do
            .appendHtml("</span>")
    }

    mtd listUsesNumbers(attributes: string)->bool
    {
        let style = .namedListStyle(openDocumentAttribute(attributes, "text:style-name").toString())
        return style.numbered
    }

    mtd bookmarkTarget(name: string)->String
    {
        if !name.count do
            return {}
        for bookmark in .bookmarks where bookmark.name == name do
            return bookmark.target
        if .bookmarks.count == OpenDocumentBookmarkLimit do
            return {}

        let target = Format.toString("odf-bookmark-%", .bookmarks.count + 1)
        var bookmark: OpenDocumentBookmark
        bookmark.name   = String.from(name)
        bookmark.target = target
        .bookmarks.add(#move bookmark)
        return target
    }

    mtd appendBookmark(attributes: string)
    {
        let target = .bookmarkTarget(openDocumentAttribute(attributes, "text:name").toString())
        if !target.isEmpty() do
            .appendHtml(Format.toString("<span id=\"%\"></span>", target.toString()))
    }

    mtd linkHref(attributes: string)->String
    {
        let href = openDocumentAttribute(attributes, "xlink:href")
        if href.isEmpty() do
            return {}
        if Utf8.startsWith(href.toString(), "#")
        {
            let target = .bookmarkTarget(href[1 to])
            return target.isEmpty() ? "" : Format.toString("#%", target.toString())
        }

        return openDocumentExternalHref(href.toString())
    }

    mtd appendParagraphAlignment(attributes: string)
    {
        let alignment = .namedTextStyle(openDocumentAttribute(attributes, "text:style-name").toString()).alignment
        if !alignment.isEmpty()
        {
            .appendHtml(" align=\"")
            .appendHtml(alignment.toString())
            .appendHtml("\"")
        }
    }

    // Validates inline images before they cross from XML into generated HTML.
    mtd inlineImageUri(href: string)->String
    {
        let mediaType = openDocumentInlineImageMediaType(href)
        if mediaType == "" or .imageCount == OpenDocumentImageCountLimit do
            return {}

        let prefix  = Format.toString("data:image/%;base64,", mediaType)
        let payload = href[prefix.count to]
        if payload.count > OpenDocumentInlineImagePayloadLimit do
            return {}

        let bytes = catch Base64.decode(payload) as decodeError
        if decodeError != null or bytes.isEmpty() or bytes.count > OpenDocumentImageLimit or bytes.count > OpenDocumentImageLimit - .imageByteCount do
            return {}

        .imageCount     += 1
        .imageByteCount += bytes.count
        return String.from(href)
    }

    mtd imageUri(attributes: string)->String
    {
        let href = openDocumentAttribute(attributes, "xlink:href")
        if Utf8.startsWith(href.toString(), "data:image/", .Latin1NoCase) do
            return .inlineImageUri(href.toString())
        for image in .images where image.path == href do
            return image.uri
        return {}
    }

    mtd appendImage(attributes: string)
    {
        let uri = .imageUri(attributes)
        if uri.isEmpty() do
            return
        var size: OpenDocumentImageSize
        if !.imageSizeStack.isEmpty() do
            size = .imageSizeStack.back()
        .appendHtml("<img src=\"")
        .appendHtml(uri.toString())
        if !size.width.isEmpty()
        {
            .appendHtml("\" width=\"")
            .appendHtml(size.width.toString())
        }

        if !size.height.isEmpty()
        {
            .appendHtml("\" height=\"")
            .appendHtml(size.height.toString())
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
        let count = openDocumentRepeated(attributes, "text:c")
        if .kind == .Spreadsheet and .cellActive
        {
            for count do
                .cell += ' '
            return
        }

        for count do
            .appendHtml("&#160;")
    }

    mtd startHtml(tag: const *OpenDocumentTag)
    {
        switch tag.name.toString()
        {
        case "text:h":
            .headingLevel = openDocumentPositiveAttribute(tag.attributes.toString(), "text:outline-level", 6)
            .appendHtml(Format.toString("<h%", .headingLevel))
            .appendParagraphAlignment(tag.attributes.toString())
            .appendHtml(">")
            .appendTextStyleStart(tag.attributes.toString())

        case "text:p":
            .appendHtml("<p")
            .appendParagraphAlignment(tag.attributes.toString())
            .appendHtml(">")
            .appendTextStyleStart(tag.attributes.toString())

        case "text:span":
            .appendTextStyleStart(tag.attributes.toString())

        case "text:note-citation":
            .appendHtml("<sup>")

        case "text:note-body":
            .appendHtml("<blockquote>")

        case "text:a":
            .appendHtml("<a")
            let href = .linkHref(tag.attributes.toString())
            if !href.isEmpty()
                do
                .appendHtml(Format.toString(" href=\"%\"", href.toString()))
            .appendHtml(">")

        case "text:bookmark", "text:bookmark-start":
            .appendBookmark(tag.attributes.toString())

        case "text:list":
            let numbered = .listUsesNumbers(tag.attributes.toString())
            .listStack.add(numbered)
            .appendHtml(numbered ? "<ol>" : "<ul>")

        case "text:list-item":
            .appendHtml("<li>")

        case "text:line-break":
            .appendHtml("<br/>")

        case "text:tab":
            .appendHtml("&#9;")

        case "text:s":
            .appendSpaces(tag.attributes.toString())

        case "draw:frame":
            .imageSizeStack.add(openDocumentImageSize(tag.attributes.toString()))

        case "draw:image":
            .appendImage(tag.attributes.toString())

        case "table:table":
            let name = openDocumentAttribute(tag.attributes.toString(), "table:name")
            .appendHtml("<section><h2>")
            .appendHtml(name.toString())
            .appendHtml("</h2><table>")

        case "table:table-header-rows":
            .tableHeaderRows += 1

        case "table:table-row":
            .appendHtml("<tr>")

        case "table:table-cell", "table:covered-table-cell":
            let repeated = openDocumentRepeated(tag.attributes.toString(), "table:number-columns-repeated")
            if .tableHeaderRows do
                .appendHtml(repeated == 1 ? "<th>" : Format.toString("<th colspan=\"%\">", repeated))
            else
                    do
                .appendHtml(repeated == 1 ? "<td>" : Format.toString("<td colspan=\"%\">", repeated))
            if tag.selfClosing do
                .appendHtml(openDocumentCellValue(tag.attributes.toString()).toString())

        case "draw:page":
            if !.slideActive
            {
                .slideActive = true
                .slide.name  = openDocumentAttribute(tag.attributes.toString(), "draw:name")
                .appendHtml("<article><section>")
            }
        }
    }

    mtd endHtml(tag: const *OpenDocumentTag)
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
            if !.listStack.isEmpty() do
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

        case "draw:frame" where !.imageSizeStack.isEmpty():
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
        if !.cellActive do
            return
        if .cellRepeat > OpenDocumentTableColumnLimit - .row.cells.count do
            fail UnsupportedFormatError{Errors.mkString(openDocumentStrings().err_Columns)}
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
        if .rowRepeat > OpenDocumentTableRowLimit - .sheet.table.rows.count do
            fail UnsupportedFormatError{Errors.mkString(openDocumentStrings().err_Rows)}
        if .rowRepeat > (OpenDocumentTableCellLimit - .sheetCellCount) / .row.cells.count do
            fail UnsupportedFormatError{Errors.mkString(openDocumentStrings().err_Cells)}
        let cells = .row.cells.count
        .sheet.table.rows.add(#move .row)
        for repeated in .rowRepeat - 1
        {
            discard repeated
            .sheet.table.rows.add(.sheet.table.rows.back())
        }

        .sheetCellCount += cells * .rowRepeat
        .row            = {}
        .rowRepeat      = 1
    }

    mtd startSheet(tag: const *OpenDocumentTag)
    {
        switch tag.name.toString()
        {
        case "table:table":
            if !.activeSheet
            {
                .activeSheet = true
                .sheet.name  = openDocumentAttribute(tag.attributes.toString(), "table:name")
            }

        case "table:table-row" where .activeSheet:
            .row       = {}
            .rowRepeat = openDocumentRepeated(tag.attributes.toString(), "table:number-rows-repeated")

        case "table:table-cell", "table:covered-table-cell" where .activeSheet:
            .cell.clear()
            .cellFallback = openDocumentCellValue(tag.attributes.toString())
            .cellActive   = true
            .cellRepeat   = openDocumentRepeated(tag.attributes.toString(), "table:number-columns-repeated")
            if tag.selfClosing do
                .cell += .cellFallback

        case "text:p" where .cellActive and !.cell.isEmpty():
            .cell += '\n'

        case "text:tab" where .cellActive:
            .cell += '\t'

        case "text:s" where .cellActive:
            .appendSpaces(tag.attributes.toString())
        }
    }

    mtd endSheet(tag: const *OpenDocumentTag) fail
    {
        if !.activeSheet do
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
            .sheet          = {}
            .sheetCellCount = 0
        }
    }

    mtd startTag(tag: const *OpenDocumentTag)
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

        if !.inBody do
            return

        if .kind == .Spreadsheet do
            .startSheet(tag)
        else do
            .startHtml(tag)
    }

    mtd endTag(tag: const *OpenDocumentTag) fail
    {
        .finishTextStyle(tag)
        if tag.name == "office:body"
        {
            if .kind == .Text do
                .appendHtml("</article>")
            .inBody = false
            return
        }

        if !.inBody do
            return

        if .kind == .Spreadsheet do
            try .endSheet(tag)
        else do
            .endHtml(tag)
    }

    mtd appendText(text: string)
    {
        if !.inBody do
            return
        if .kind == .Spreadsheet
        {
            if .cellActive do
                .cell += text
            return
        }

        .appendHtml(text)
    }

    mtd normalizeSheet(sheet: *OpenDocumentSheet) fail
    {
        if sheet.table.rows.isEmpty() do
            return

        sheet.table.columns = #move sheet.table.rows[0].cells
        sheet.table.rows.removeAtOrdered(0)
        var count = sheet.table.columns.count
        for row in sheet.table.rows do
            count = Math.max(count, row.cells.count)
        if count > OpenDocumentTableColumnLimit do
            fail UnsupportedFormatError{Errors.mkString(openDocumentStrings().err_Columns)}

        while sheet.table.columns.count < count do
            sheet.table.columns.add(Format.toString(openDocumentStrings().ui_Column, sheet.table.columns.count + 1))
        for column, columnIndex in sheet.table.columns where column.isEmpty() do
            sheet.table.columns[columnIndex] = Format.toString(openDocumentStrings().ui_Column, columnIndex + 1)
    }

    mtd finish()->OpenDocumentContent fail
    {
        if !.sawBody or .inBody do
            fail InvalidFormatError{Errors.mkString(.sawBody ? openDocumentStrings().err_Xml : openDocumentStrings().err_Body)}

        var result: retval
        result.kind     = .kind
        result.metadata = #move .metadata
        if .kind == .Presentation or .kind == .Drawing
        {
            if .slideActive do
                fail InvalidFormatError{Errors.mkString(openDocumentStrings().err_Xml)}
            if .slides.isEmpty() do
                fail InvalidFormatError{Errors.mkString(.kind == .Presentation ? openDocumentStrings().err_Slide : openDocumentStrings().err_Page)}
            result.slides = #move .slides
            return result
        }

        if .kind == .Text
        {
            result.html = #move .html
            return result
        }

        if .activeSheet do
            fail InvalidFormatError{Errors.mkString(openDocumentStrings().err_Xml)}
        if .sheets.isEmpty() do
            fail InvalidFormatError{Errors.mkString(openDocumentStrings().err_Sheet)}
        for &sheet in .sheets do
            .normalizeSheet(sheet)
        result.sheets = #move .sheets
        return result
    }
}

// Parses ODF's XML body without executing linked resources, macros, or scripts.
internal func parseOpenDocumentContent(source: string, kind: OpenDocumentKind)->OpenDocumentContent fail
{
    var images: Array'OpenDocumentImage
    let metadata = try parseOpenDocumentMetadata(source)
    return try parseOpenDocumentContentWithImages(source, "", kind, #move images, #move metadata)
}

private func appendOpenDocumentXml(reader: *OpenDocumentReader, source: string) fail
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
        let end = try openDocumentTagEnd(source, at)
        let tag = parseOpenDocumentTag(source[at + 1 until end])
        if !tag.name.isEmpty()
        {
            if tag.closing do
                try reader.endTag(&tag)
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
private func parseOpenDocumentContentWithImages(source, styles: string, kind: OpenDocumentKind, images: Array'OpenDocumentImage, metadata: OpenDocumentMetadata)->OpenDocumentContent fail
{
    var reader: OpenDocumentReader
    reader.kind     = kind
    reader.images   = #move images
    reader.metadata = #move metadata
    for image in reader.images
    {
        reader.imageCount     += 1
        reader.imageByteCount += image.byteCount
    }

    if styles.count do
        try appendOpenDocumentXml(&reader, styles)
    try appendOpenDocumentXml(&reader, source)
    return try reader.finish()
}

private func openDocumentKindFromMime(mimeType: string)->OpenDocumentKind fail
{
    switch mimeType
    {
    case "application/vnd.oasis.opendocument.text", "application/vnd.oasis.opendocument.text-template":                 return .Text
    case "application/vnd.oasis.opendocument.spreadsheet", "application/vnd.oasis.opendocument.spreadsheet-template":   return .Spreadsheet
    case "application/vnd.oasis.opendocument.presentation", "application/vnd.oasis.opendocument.presentation-template": return .Presentation
    case "application/vnd.oasis.opendocument.graphics", "application/vnd.oasis.opendocument.graphics-template":         return .Drawing
    default: fail InvalidFormatError{Errors.mkString(openDocumentStrings().err_MimeType)}
    }
}

private func openDocumentFlatKind(fileName: string)->OpenDocumentKind fail
{
    switch Path.lowercaseExtension(fileName).toString()
    {
    case ".fodt": return .Text
    case ".fods": return .Spreadsheet
    case ".fodp": return .Presentation
    case ".fodg": return .Drawing
    default:      fail InvalidFormatError{Errors.mkString(openDocumentStrings().err_MimeType)}
    }
}

private func loadOpenDocumentFlatContent(fileName: string)->OpenDocumentContent fail
{
    let info = try File.info(fileName)
    if info.size > OpenDocumentContentLimit do
        fail UnsupportedFormatError{Errors.mkString(openDocumentStrings().err_TooLarge)}

    let bytes = try File.readAllBytes(fileName)
    if bytes.count > OpenDocumentContentLimit do
        fail UnsupportedFormatError{Errors.mkString(openDocumentStrings().err_TooLarge)}
    if !Utf8.isValid(bytes.toSlice()) do
        fail InvalidFormatError{Errors.mkString(openDocumentStrings().err_Encoding)}
    return try parseOpenDocumentContent(cast(string) bytes.toSlice(), try openDocumentFlatKind(fileName))
}

private func openDocumentImageMediaType(path: string)->string
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
private func loadOpenDocumentImages(fileName: string, archive: const *ZipArchive)->Array'OpenDocumentImage
{
    var result: retval
    var total = 0'u64
    for &entry in archive.entries
    {
        if result.count == OpenDocumentImageCountLimit do
            break
        if !entry.path.startsWith("Pictures/", .Latin1NoCase) do
            continue
        let mediaType = openDocumentImageMediaType(entry.path.toString())
        if mediaType == "" or entry.uncompressedSize > OpenDocumentImageLimit or entry.uncompressedSize > OpenDocumentImageLimit - total do
            continue

        let bytes = catch loadZipEntry(fileName, entry) as imageError
        if imageError != null do
            continue

        var image: OpenDocumentImage
        image.path      = entry.path
        image.uri       = Format.toString("data:image/%;base64,%", mediaType, Base64.encode(bytes.toSlice()).toString())
        image.byteCount = bytes.count
        result.add(#move image)
        total += bytes.count
    }

    return result
}

private func loadOpenDocumentContent(fileName: string)->OpenDocumentContent fail
{
    switch Path.lowercaseExtension(fileName).toString()
    {
    case ".fodt", ".fods", ".fodp", ".fodg": return try loadOpenDocumentFlatContent(fileName)
    }

    let archive = try loadZipArchive(fileName)
    var mime:    *ZipEntry?
    var content: *ZipEntry?
    var styles:  *ZipEntry?
    var meta:    *ZipEntry?
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
        fail InvalidFormatError{Errors.mkString(openDocumentStrings().err_MimeType)}
    if content == null do
        fail InvalidFormatError{Errors.mkString(openDocumentStrings().err_Content)}
    if content!.uncompressedSize > OpenDocumentContentLimit do
        fail UnsupportedFormatError{Errors.mkString(openDocumentStrings().err_TooLarge)}

    let mimeBytes = try loadZipEntry(fileName, mime!)
    let kind      = try openDocumentKindFromMime(cast(string) mimeBytes.toSlice())
    let bytes     = try loadZipEntry(fileName, content!)
    if !Utf8.isValid(bytes.toSlice()) do
        fail InvalidFormatError{Errors.mkString(openDocumentStrings().err_Encoding)}
    var images: Array'OpenDocumentImage
    if kind != .Spreadsheet do
        images = loadOpenDocumentImages(fileName, &archive)
    var styleSource: String
    if styles != null and styles!.uncompressedSize <= OpenDocumentContentLimit
    {
        let styleBytes = catch loadZipEntry(fileName, styles!) as stylesError
        if stylesError == null and Utf8.isValid(styleBytes.toSlice()) do
            styleSource = String.from(cast(string) styleBytes.toSlice())
    }

    var metadata: OpenDocumentMetadata
    if meta != null and meta!.uncompressedSize <= OpenDocumentMetadataLimit
    {
        let metadataBytes = catch loadZipEntry(fileName, meta!) as metadataError
        if metadataError == null and Utf8.isValid(metadataBytes.toSlice()) do
            metadata = catch parseOpenDocumentMetadata(cast(string) metadataBytes.toSlice()) as metadataParseError
    }

    return try parseOpenDocumentContentWithImages(cast(string) bytes.toSlice(), styleSource.toString(), kind, #move images, #move metadata)
}

// Hosts the format reader while its ZIP payload is decoded away from the GUI thread.
internal struct OpenDocumentViewer
{
    using wnd: Wnd

        late
    {
        html:      *HtmlView
        table:     *TableViewer
        commands:  *Wnd
        pageCombo: *ComboBox
        info:      *Wnd
        zoomLabel: *IconButton
    }

    document:             OpenDocumentContent
    sheetIndex:           u64
    slideIndex:           u64
    zoomPercent:          u32 = 100
    load:                 Viewer.BackgroundLoad'OpenDocumentContent
    loadTimer:            *Timer?
    reportFailure:        Viewer.ReportFailure?
    reportDetails:        Viewer.ReportDetails?
    reportChromeChanged:  Viewer.ReportChromeChanged?
    reportLoadingChanged: Viewer.ReportLoadingChanged?
    failureReason:        String
}

private impl IWnd for OpenDocumentViewer
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .loadTimer
        {
            evt.accepted = false
            return
        }

        if !.load.isDone() do
            return

        .removeTimer(evt.timer)
        .loadTimer     = null
        .failureReason = .load.finish(&.document)
        if !.failureReason.isEmpty()
        {
            if .reportFailure do
                .reportFailure!(me, .failureReason.toString())
            return
        }

        .publishDocument()
        .reportDocumentDetails()
        if .reportLoadingChanged do
            .reportLoadingChanged!(me)
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged and .loadTimer == null and .failureReason.isEmpty()
        {
            .fillPageChoices()
            .zoomLabel.toolTip = openDocumentStrings().ui_ZoomMenu
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

        if evt.modifiers.has(.Control) and .document.kind != .Spreadsheet
        {
            switch evt.key
            {
            case .Add, .OemPlus:       .setZoom(.zoomPercent + 25)
            case .Subtract, .OemMinus: .setZoom(.zoomPercent > 50 ? .zoomPercent - 25 : 50)
            case .D0:                  .setZoom(100)
            default:                   evt.accepted = false
            }

            return
        }

        if evt.modifiers != .None or !.navigatePagedDocument(evt.key)
        {
            evt.accepted = false
        }
    }
}

private impl OpenDocumentViewer
{
    mtd applyZoom()
    {
        if !(.html != null) do
            return
        var style = HtmlStyle.theme()
        style.bodyFontSize = cast(u32) Math.max(Math.round(16.0 * cast(f32) .zoomPercent / 100), 1)
        style.codeFontSize = cast(u32) Math.max(Math.round(14.0 * cast(f32) .zoomPercent / 100), 1)
        .html.setDocumentStyle(style)
    }

    mtd setZoom(percent: u32)
    {
        .zoomPercent = Math.clamp(percent, 50'u32, 300'u32)
        .applyZoom()
        .zoomLabel.setText(Format.toString("% %", .zoomPercent, "%"))
    }

    mtd showZoomMenu()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem("75%", "scope.opendocument.zoom75")
        menu.addItem("100%", "scope.opendocument.zoom100")
        menu.addItem("125%", "scope.opendocument.zoom125")
        menu.addItem("150%", "scope.opendocument.zoom150")
        menu.addItem("200%", "scope.opendocument.zoom200")
        switch menu.doModal(.zoomLabel, autoDestroy: true) orelse ""
        {
        case "scope.opendocument.zoom75":  .setZoom(75)
        case "scope.opendocument.zoom100": .setZoom(100)
        case "scope.opendocument.zoom125": .setZoom(125)
        case "scope.opendocument.zoom150": .setZoom(150)
        case "scope.opendocument.zoom200": .setZoom(200)
        }
    }

    mtd refreshZoomChrome()
    {
        let visible = .document.kind != .Spreadsheet
        .info.show(visible)
        if visible do
            .setZoom(.zoomPercent)
        if .reportChromeChanged do
            .reportChromeChanged!(me)
    }

    mtd kindName()->string
    {
        switch .document.kind
        {
        case .Text:         return openDocumentStrings().ui_Text
        case .Spreadsheet:  return openDocumentStrings().ui_Spreadsheet
        case .Presentation: return openDocumentStrings().ui_Presentation
        case .Drawing:      return openDocumentStrings().ui_Drawing
        }
    }

    mtd documentDetails(details: string)->String
    {
        if .document.metadata.title.isEmpty() do
            return String.from(details)
        return Format.toString("% · %", details, .document.metadata.title)
    }

    mtd reportDocumentDetails()
    {
        if !.reportDetails do
            return
        if .document.kind == .Spreadsheet and .sheetIndex < .document.sheets.count
        {
            .reportDetails!(me, .documentDetails(Format.toString(openDocumentStrings().ui_DetailsSheet, .sheetName(.sheetIndex)).toString()))
            return
        }

        if (.document.kind == .Presentation or .document.kind == .Drawing) and .slideIndex < .document.slides.count
        {
            let details = .document.kind == .Presentation ? openDocumentStrings().ui_DetailsSlide : openDocumentStrings().ui_DetailsPage
            .reportDetails!(me, .documentDetails(Format.toString(details, .slideName(.slideIndex)).toString()))
            return
        }

        .reportDetails!(me, .documentDetails(Format.toString(openDocumentStrings().ui_Details, .kindName()).toString()))
    }

    mtd sheetName(index: u64)->String
    {
        var result: retval
        let name = .document.sheets[index].name
        if !name.isEmpty() do
            result += name
        else
        {
            result += Format.toString(openDocumentStrings().ui_Sheet, index + 1)
        }

        return result
    }

    mtd slideName(index: u64)->String
    {
        var result: retval
        let name = .document.slides[index].name
        if !name.isEmpty() do
            result += name
        else
        {
            result += Format.toString(.document.kind == .Drawing ? openDocumentStrings().ui_Page : openDocumentStrings().ui_Slide, index + 1)
        }

        return result
    }

    mtd fillPageChoices()
    {
        .pageCombo.clear()

        var count:  u64
        var active: u64
        switch .document.kind
        {
        case .Spreadsheet:
            .pageCombo.toolTip = openDocumentStrings().ui_TipSheet
            count              = .document.sheets.count
            active             = .sheetIndex
            for index in count do
                .pageCombo.addItem(.sheetName(index))

        case .Presentation:
            .pageCombo.toolTip = openDocumentStrings().ui_TipSlide
            count              = .document.slides.count
            active             = .slideIndex
            for index in count do
                .pageCombo.addItem(.slideName(index))

        case .Drawing:
            .pageCombo.toolTip = openDocumentStrings().ui_TipPage
            count              = .document.slides.count
            active             = .slideIndex
            for index in count do
                .pageCombo.addItem(.slideName(index))

        case .Text:
            count = 0
        }

        if count do
            .pageCombo.setSelectedIndex(cast(u32) active, notify: false)
        let hasChoices = count > 1
        .pageCombo.show(hasChoices)
        .commands.show(hasChoices)
        if .reportChromeChanged do
            .reportChromeChanged!(me)
    }

    mtd showSheet(index: u64, clearSearch: bool)->bool
    {
        if index >= .document.sheets.count or !(.table != null) do
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
        .table           = TableViewer.createDocument(me, #move .document.sheets[index].table)
        .table.dockStyle = .Center
        .pageCombo.setSelectedIndex(cast(u32) index, notify: false)
        if clearSearch do
            .table.clearSearch()
        .applyLayout()
        .setInitialFocus(.table)
        .reportDocumentDetails()
        return true
    }

    mtd showSlide(index: u64, clearSearch: bool)->bool
    {
        if index >= .document.slides.count do
            return false
        if index == .slideIndex and (.html != null)
        {
            if clearSearch do
                .html.clearSearch()
            return true
        }

        if .html != null do
            .html.destroy()
        .slideIndex     = index
        .html           = HtmlView.createText(me, .document.slides[index].html.toString())
        .html.dockStyle = .Center
        .applyZoom()
        .html.sigLinkActivated += func(html, url)
        {
            discard html
            Env.openUrl(url)
        }
        .pageCombo.setSelectedIndex(cast(u32) index, notify: false)
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
        case .Left, .PageUp where .slideIndex:                                 return .showSlide(.slideIndex - 1, true)
        case .Right, .PageDown where .slideIndex + 1 < .document.slides.count: return .showSlide(.slideIndex + 1, true)
        case .Home where .slideIndex:                                          return .showSlide(0, true)
        case .End where .slideIndex + 1 < .document.slides.count:              return .showSlide(.document.slides.count - 1, true)
        }

        return false
    }

    mtd showPage(index: u64, clearSearch: bool)->bool
    {
        switch .document.kind
        {
        case .Spreadsheet:  return .showSheet(index, clearSearch)
        case .Presentation: return .showSlide(index, clearSearch)
        case .Drawing:      return .showSlide(index, clearSearch)
        case .Text:         return false
        }
    }

    mtd collectTableMatches(document: const *TableDocument, sheetIndex: u64, text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
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
            if index == .sheetIndex and (.table != null) do
                .collectTableMatches(&.table.document, index, text, options, result)
            else do
                .collectTableMatches(&sheet.table, index, text, options, result)
        }
    }

    mtd collectPresentationMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        for slide, index in .document.slides do
            Viewer.collectTextMatches(slide.html.toString(), text, options, index, 0, 0, result)
    }

    mtd publishDocument()
    {
        if .document.kind == .Spreadsheet
        {
            .table           = TableViewer.createDocument(me, #move .document.sheets[0].table)
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
            .html           = HtmlView.createText(me, .document.html.toString())
            .html.dockStyle = .Center
            .applyZoom()
            .html.sigLinkActivated += func(html, url)
            {
                discard html
                Env.openUrl(url)
            }
            .setInitialFocus(.html)
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
            Viewer.collectTextMatches(.document.html.toString(), text, options, 0, 0, 0, result)
    }

    mtd revealMatch(match: Viewer.SearchMatch, text: string)->bool
    {
        if .document.kind == .Spreadsheet
        {
            if !.showSheet(match.major, false) do
                return false
            var tableMatch = match
            tableMatch.major = match.minor >> 32
            tableMatch.minor = match.minor & 0xFFFF_FFFF'u64
            return .table.revealMatch(tableMatch)
        }

        if .document.kind == .Presentation or .document.kind == .Drawing
        {
            if !.showSlide(match.major, false) do
                return false
            return .html.revealFileOffset(match.offset, text)
        }

        if !(.html != null) do
            return false
        return .html.revealFileOffset(match.offset, text)
    }

    mtd searchBounds(result: *Math.Rectangle)->bool
    {
        if .document.kind == .Spreadsheet
        {
            if !(.table != null) do
                return false
            return .table.searchBounds(result)
        }

        if !(.html != null) do
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
        if !.load.retire() do
            return false
        if .loadTimer
        {
            .removeTimer(.loadTimer!)
            .loadTimer = null
        }

        return true
    }

    func create(host: Viewer.Host)->*OpenDocumentViewer
    {
        let services = host.services()
        let result   = Wnd.create'OpenDocumentViewer(host.contentParent(), "scope.opendocument")
        result.backgroundStyle      = .View
        result.reportFailure        = services.reportFailure
        result.reportDetails        = services.reportDetails
        result.reportChromeChanged  = services.reportChromeChanged
        result.reportLoadingChanged = services.reportLoadingChanged
        result.info                 = host.createInfoGroup(ViewerZoomSlotWidth)
        result.info.hide()
        with result.zoomLabel = IconButton.create(result.info, {}, {0, 0, ViewerZoomButtonWidth, 32}, "scope.opendocument.zoom", .CenterContent)
        {
            .dockStyle = .Center
            .margin    = {ViewerInfoControlInset, 0, ViewerInfoControlInset, 0}
            .setText("100%")
            .setArrowPosition(.RightDownward)
            .setForm(.Rectangle)
            .style.setFont(result.theme().createDefaultFontFS(11), .Regular)
            .toolTip    = openDocumentStrings().ui_ZoomMenu
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.showZoomMenu()
            }
        }

        result.hookOnChildEvent = func|view = result|(wnd, evt)
        {
            discard wnd
            switch evt
            {
            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.modifiers.has(.Control) and view.document.kind != .Spreadsheet and (keyEvt.key == .Add or keyEvt.key == .OemPlus):
                view.setZoom(view.zoomPercent + 25)
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.modifiers.has(.Control) and view.document.kind != .Spreadsheet and (keyEvt.key == .Subtract or keyEvt.key == .OemMinus):
                view.setZoom(view.zoomPercent > 50 ? view.zoomPercent - 25 : 50)
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.modifiers.has(.Control) and view.document.kind != .Spreadsheet and keyEvt.key == .D0:
                view.setZoom(100)
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.modifiers == .None:
                return view.navigatePagedDocument(keyEvt.key)

            default:
                return false
            }
        }
        result.commands = host.createCommandGroup(OpenDocumentPageComboWidth)
        result.commands.hide()
        with result.pageCombo = ComboBox.create(result.commands, {0, 0, OpenDocumentPageComboWidth, 36})
        {
            .dockStyle = .Left
            .hide()
            .toolTip    = openDocumentStrings().ui_TipSheet
            .sigChanged += func|view = result|(combo, index)
            {
                discard combo
                discard view.showPage(index, true)
            }
        }

        result.load.start(host.fileName(), &loadOpenDocumentContent)
        result.loadTimer = result.addTimer(Viewer.BackgroundPollInterval)
        return result
    }
}

// Creates the integrated reader for OpenDocument files.
func createOpenDocumentViewer(host: Viewer.Host)
{
    let view = OpenDocumentViewer.create(host)
    host.attachView(view)
    host.setDetails(openDocumentStrings().ui_Name)
    host.setSearch({
        collectMatches: func(wnd, text, options, progress, matches)->bool
    {
        discard progress
        (cast(*OpenDocumentViewer) wnd).collectMatches(text, options, matches)
        return true
    },
        revealMatch: func(wnd, match, text)->bool { return (cast(*OpenDocumentViewer) wnd).revealMatch(match, text) },
        matchBounds: func(wnd, match, bounds)->bool
    {
        discard match
        return (cast(*OpenDocumentViewer) wnd).searchBounds(bounds)
    },
        clear: func(wnd) { (cast(*OpenDocumentViewer) wnd).clearSearch() }})
    host.setLifecycle({
        isLoading: func(wnd)->bool { return (cast(*OpenDocumentViewer) wnd).loadTimer != null },
        needsLoadingOverlay: func(wnd)->bool { return (cast(*OpenDocumentViewer) wnd).loadTimer != null },
        retire: func(wnd)->bool { return (cast(*OpenDocumentViewer) wnd).retire() }})
}
