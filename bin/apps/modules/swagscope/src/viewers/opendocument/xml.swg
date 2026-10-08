#global internal
#global namespace Viewers.OpenDocument

using Core, Core.Errors, Gui

private const Apostrophe = 39'u8

// One XML tag read from the content: its name, its raw attribute text, and whether it closes an
// element or closes itself.
struct Tag
{
    name:        String
    attributes:  String
    closing:     bool
    selfClosing: bool
}

func xmlSpace(value: u8)->bool => value == ' ' or value == '\t' or value == '\r' or value == '\n'

// Finds a closing angle bracket without mistaking one inside a quoted XML attribute for a tag end.
func tagEnd(source: string, start: u64)->u64 fail
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
func parseTag(raw: string)->Tag
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

// Returns the prefix this reader matches names of the ODF namespace `uri` with, or an empty string
// for a namespace it does not read.
func odfPrefix(uri: string)->string
{
    switch uri
    {
    case "urn:oasis:names:tc:opendocument:xmlns:office:1.0":             return "office"
    case "urn:oasis:names:tc:opendocument:xmlns:style:1.0":              return "style"
    case "urn:oasis:names:tc:opendocument:xmlns:text:1.0":               return "text"
    case "urn:oasis:names:tc:opendocument:xmlns:table:1.0":              return "table"
    case "urn:oasis:names:tc:opendocument:xmlns:drawing:1.0":            return "draw"
    case "urn:oasis:names:tc:opendocument:xmlns:presentation:1.0":       return "presentation"
    case "urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0":  return "fo"
    case "urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0":     return "svg"
    case "http://www.w3.org/1999/xlink":                                 return "xlink"
    case "http://purl.org/dc/elements/1.1/":                             return "dc"
    default:                                                             return ""
    }
}

// One `xmlns` declaration in scope: the prefix a document chose, empty for the default namespace,
// and the prefix this reader uses for the same ODF namespace.
struct NamespaceBinding
{
    prefix:    String
    canonical: string = ""
    depth:     u64
}

// The namespace declarations in scope while one XML stream is read.
//
// The reader matches names by their conventional ODF prefixes. A document may bind those namespaces
// to any prefix, so names are rewritten to the conventional spelling of their namespace. A prefix
// bound to a namespace this reader does not know keeps its spelling. When every ODF declaration in
// scope already uses its conventional prefix, as almost every document does, no name is rewritten.
struct Namespaces
{
    bindings: Array'NamespaceBinding
    depth:    u64
    renaming: u64     // Bindings in scope whose prefix differs from the conventional one.
}

impl Namespaces
{
    // Records the declarations of an opening `tag`, then rewrites its names. A self-closing tag
    // leaves the scope immediately, as the same rewritten tag also stands for its closing tag.
    mtd open(tag: *Tag)
    {
        .depth += 1
        if Utf8.indexOf(tag.attributes, "xmlns") != Swag.U64.Max do
            .declare(tag.attributes)
        if .renaming
        {
            tag.name       = .rename(tag.name, true)
            tag.attributes = .renameAttributes(tag.attributes)
        }

        if tag.selfClosing do
            .leave()
    }

    // Rewrites the name of a closing `tag`, then leaves the scope of its element.
    mtd close(tag: *Tag)
    {
        if .renaming do
            tag.name = .rename(tag.name, true)
        .leave()
    }

    mtd leave()
    {
        while not .bindings.isEmpty() and .bindings.backPtr().depth == .depth
        {
            let binding = .bindings.popBack()
            if binding.canonical.count and binding.prefix != binding.canonical do
                .renaming -= 1
        }

        if .depth do
            .depth -= 1
    }

    // Adds each `xmlns` or `xmlns:prefix` attribute of `attributes` to the scope.
    mtd declare(attributes: string)
    {
        var at = 0'u64
        while at < attributes.count
        {
            let start = Utf8.indexOf(attributes, "xmlns", at)
            if start == Swag.U64.Max do
                return
            at = start + ("xmlns").count
            if start > 0 and not xmlSpace(attributes[start - 1]) do
                continue

            var nameEnd = at
            while nameEnd < attributes.count and not xmlSpace(attributes[nameEnd]) and attributes[nameEnd] != '=' do
                nameEnd += 1
            let name = attributes[start until nameEnd]
            if name != "xmlns" and not Utf8.startsWith(name, "xmlns:") do
                continue

            var binding: NamespaceBinding
            binding.prefix    = name == "xmlns" ? "" : name[("xmlns:").count to]
            binding.canonical = odfPrefix(decodeXmlText(attribute(attributes, name)))
            binding.depth     = .depth
            if binding.canonical.count and binding.prefix != binding.canonical do
                .renaming += 1
            .bindings.add(#move binding)
        }
    }

    // Returns `name` with its prefix replaced by the conventional prefix of its namespace. An
    // unprefixed element name is in the default namespace; an unprefixed attribute is in none.
    mtd rename(name: string, element: bool)->String
    {
        let colon  = Utf8.indexOf(name, ':'rune)
        let prefix = colon == Swag.U64.Max ? "" : name[until colon]
        if colon == Swag.U64.Max and not element do
            return name
        if prefix == "xmlns" do
            return name

        for index in .bindings.count
        {
            let binding = &.bindings[.bindings.count - 1 - index]
            if binding.prefix != prefix do
                continue
            if not binding.canonical.count or binding.canonical == prefix do
                return name

            var result: String
            result += binding.canonical
            result += ':'rune
            result += colon == Swag.U64.Max ? name : name[colon + 1 to]
            return result
        }

        return name
    }

    // Returns `attributes` with every attribute name rewritten by `rename`, values unchanged.
    mtd renameAttributes(attributes: string)->String
    {
        var result: retval
        var at = 0'u64
        while at < attributes.count
        {
            if xmlSpace(attributes[at]) or attributes[at] == '=' or attributes[at] == '/'
            {
                result += attributes[at]
                at     += 1
                continue
            }

            if attributes[at] == '"' or attributes[at] == Apostrophe
            {
                let quote = attributes[at]
                var end   = at + 1
                while end < attributes.count and attributes[end] != quote do
                    end += 1
                end    = Math.min(end + 1, attributes.count)
                result += attributes[at until end]
                at     = end
                continue
            }

            let nameStart = at
            while at < attributes.count and not xmlSpace(attributes[at]) and attributes[at] != '=' and attributes[at] != '/' do
                at += 1
            result += .rename(attributes[nameStart until at], false)
        }

        return result
    }
}

// Returns the raw value of the attribute named `wanted`, or an empty string when it is absent.
//
// HTML output retains its entities; plain model values decode them before reaching a table cell,
// page label, or other non-HTML surface.
func attribute(attributes, wanted: string)->String
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

// The character a numeric entity names, `#65` or `#x41`; 0 when it names none.
private func numericEntity(entity: string)->rune
{
    if entity.count < 2 or entity[0] != '#' do
        return 0

    let hexadecimal = entity.count > 2 and (entity[1] == 'x' or entity[1] == 'X')
    let digits      = hexadecimal ? entity[2 to] : entity[1 to]
    var value       = 0'u64
    if hexadecimal
    {
        let parsed = catch StrConv.parseX64(digits) as parseError
        if parseError != null or parsed.ovf or parsed.eat != digits.count do
            return 0
        value = parsed.value
    }
    else
    {
        let parsed = catch StrConv.parseU64(digits) as parseError
        if parseError != null or parsed.eat != digits.count do
            return 0
        value = parsed.value
    }

    let character = cast(rune, value)
    return value != 0 and Utf8.isValidRune(character) ? character : 0
}

// Decodes the XML character references legal in document properties without accepting markup.
func decodeXmlText(source: string)->String
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
            let character = numericEntity(entity)
            if character do
                result.append(character)
            else do
                result += source[at until close + 1]
        }

        at = close + 1
    }

    return result
}
