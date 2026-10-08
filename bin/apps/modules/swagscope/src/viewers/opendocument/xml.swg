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
