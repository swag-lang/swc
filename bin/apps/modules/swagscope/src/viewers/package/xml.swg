#global internal
#global namespace Viewers.Package

using Core

// One XML attribute, with its entity references resolved.
struct Attribute
{
    name:  String
    value: String
}

enum TokenKind
{
    Start
    End
    Text
}

// A bounded XML token. Empty elements have no separate end token.
struct Token
{
    kind:       TokenKind
    name:       String
    attributes: Array'Attribute
    text:       String
    empty:      bool
}

impl Token
{
    // Matches a qualified element name by its local part.
    mtd const isElement(name: string)->bool
    {
        let source = .name.toSlice()
        var start = 0'u64
        for value, index in source where value == ':'u8 do
            start = index + 1
        return cast(string, source[start to]) == name
    }

    // Returns one attribute by its qualified or local name.
    mtd const attribute(name: string)->string?
    {
        for &item in .attributes
        {
            if item.name == name do
                return item.value
            let source = item.name.toSlice()
            var start = 0'u64
            for value, index in source where value == ':'u8 do
                start = index + 1
            if cast(string, source[start to]) == name do
                return item.value
        }
        return null
    }
}

// Scans XML without DTDs, external entities, or an object tree. The caller owns `source`.
struct Scanner
{
    source:  string
    offset:  u64
    damaged: bool
}

private impl Scanner
{
    mtd space(value: u8)->bool => value == ' 'u8 or value == '\t'u8 or value == '\r'u8 or value == '\n'u8

    mtd skipSpace()
    {
        while .offset < .source.count and .space(.source[.offset]) do
            .offset += 1
    }

    mtd nameEnd()->u64
    {
        let start = .offset
        while .offset < .source.count
        {
            let value = .source[.offset]
            if .space(value) or value == '/'u8 or value == '>'u8 or value == '='u8 or value == '?'u8 do
                break
            .offset += 1
        }
        if .offset == start do
            .damaged = true
        return .offset
    }

    mtd decode(source: string)->String
    {
        var result: #returntype
        var at = 0'u64
        while at < source.count
        {
            if source[at] != '&'u8
            {
                result += source[at]
                at += 1
                continue
            }

            let start = at + 1
            var end = start
            while end < source.count and end - start <= 12 and source[end] != ';'u8 do
                end += 1
            if end >= source.count or source[end] != ';'u8
            {
                .damaged = true
                return {}
            }

            let entity = source[start until end]
            switch entity
            {
            case "amp":  result += '&'u8
            case "lt":   result += '<'u8
            case "gt":   result += '>'u8
            case "quot": result += '"'u8
            case "apos": result += '\''u8
            default:
                if entity.count < 2 or entity[0] != '#'u8
                {
                    .damaged = true
                    return {}
                }
                let hex = entity.count > 2 and (entity[1] == 'x'u8 or entity[1] == 'X'u8)
                let digits = hex ? entity[2 to] : entity[1 to]
                if not digits.count
                {
                    .damaged = true
                    return {}
                }
                var code = 0'u32
                for digit in digits
                {
                    var value: u32
                    if digit >= '0'u8 and digit <= '9'u8 do
                        value = digit - '0'u8
                    elif hex and digit >= 'a'u8 and digit <= 'f'u8 do
                        value = digit - 'a'u8 + 10
                    elif hex and digit >= 'A'u8 and digit <= 'F'u8 do
                        value = digit - 'A'u8 + 10
                    else
                    {
                        .damaged = true
                        return {}
                    }
                    let base = hex ? 16'u32 : 10'u32
                    if code > (0x10FFFF'u32 - value) / base
                    {
                        .damaged = true
                        return {}
                    }
                    code = code * base + value
                }
                if not code or code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF)
                {
                    .damaged = true
                    return {}
                }
                result += cast(rune, code)
            }
            at = end + 1
        }
        return result
    }

    mtd skipUntil(marker: string)->bool
    {
        while .offset + marker.count <= .source.count
        {
            if .source[.offset until .offset + marker.count] == marker
            {
                .offset += marker.count
                return true
            }
            .offset += 1
        }
        .damaged = true
        return false
    }
}

impl Scanner
{
    // Starts at the beginning of a valid UTF-8 XML fragment or document.
    func create(source: string)->Scanner
    {
        var result: #returntype = {source: source}
        result.damaged = not Utf8.isValid(cast(const [..] u8, source))
        return result
    }

    // Reads the next token; false means EOF or malformed input, distinguished by `damaged`.
    mtd next(token: *Token)->bool
    {
        if .damaged do
            return false
        while .offset < .source.count
        {
            token[] = {}
            if .source[.offset] != '<'u8
            {
                let start = .offset
                while .offset < .source.count and .source[.offset] != '<'u8 do
                    .offset += 1
                token.kind = .Text
                token.text = .decode(.source[start until .offset])
                return not .damaged
            }

            if .offset + 4 <= .source.count and .source[.offset until .offset + 4] == "<!--"
            {
                .offset += 4
                if not .skipUntil("-->") do
                    return false
                continue
            }
            if .offset + 9 <= .source.count and .source[.offset until .offset + 9] == "<![CDATA["
            {
                .offset += 9
                let start = .offset
                if not .skipUntil("]]>") do
                    return false
                token.kind = .Text
                token.text = .source[start until .offset - 3]
                return true
            }
            if .offset + 2 <= .source.count and .source[.offset + 1] == '?'u8
            {
                .offset += 2
                if not .skipUntil("?>") do
                    return false
                continue
            }
            if .offset + 2 <= .source.count and .source[.offset + 1] == '!'u8
            {
                .damaged = true
                return false
            }

            .offset += 1
            if .offset < .source.count and .source[.offset] == '/'u8
            {
                token.kind = .End
                .offset += 1
            }
            else do
                token.kind = .Start
            let start = .offset
            let end = .nameEnd()
            if .damaged do
                return false
            token.name = .source[start until end]

            while .offset < .source.count
            {
                .skipSpace()
                if .offset >= .source.count do
                    break
                if .source[.offset] == '>'u8
                {
                    .offset += 1
                    return true
                }
                if token.kind == .Start and .source[.offset] == '/'u8 and
                   .offset + 1 < .source.count and .source[.offset + 1] == '>'u8
                {
                    token.empty = true
                    .offset += 2
                    return true
                }
                if token.kind == .End do
                    break

                let attrStart = .offset
                let attrEnd   = .nameEnd()
                if .damaged do
                    return false
                .skipSpace()
                if .offset >= .source.count or .source[.offset] != '='u8 do
                    break
                .offset += 1
                .skipSpace()
                if .offset >= .source.count or (.source[.offset] != '"'u8 and .source[.offset] != '\''u8) do
                    break
                let quote = .source[.offset]
                .offset += 1
                let valueStart = .offset
                while .offset < .source.count and .source[.offset] != quote do
                    .offset += 1
                if .offset >= .source.count do
                    break
                let value = .decode(.source[valueStart until .offset])
                if .damaged do
                    return false
                token.attributes.add(Attribute{.source[attrStart until attrEnd], value})
                .offset += 1
            }
            .damaged = true
            return false
        }
        return false
    }
}
