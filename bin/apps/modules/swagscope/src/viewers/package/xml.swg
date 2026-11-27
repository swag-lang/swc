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
    attributes: Array!{Attribute}
    text:       String
    empty:      bool
}

impl Token
{
    // Matches a qualified element name by its local part.
    mtd const isElement(name: string)->bool
    {
        let source = .name.toSlice()
        var start  = 0_u64
        for value, index in source where value == ':'_u8
        {
            start = index + 1
        }

        return cast(string, source[start to ]) == name
    }

    // Returns one attribute by its qualified or local name.
    mtd const attribute(name: string)->string?
    {
        for &item in .attributes
        {
            if item.name == name
            {
                return item.value
            }
        }

        for &item in .attributes
        {
            let source = item.name.toSlice()
            var start  = 0_u64
            for value, index in source where value == ':'_u8
            {
                start = index + 1
            }

            if cast(string, source[start to ]) == name
            {
                return item.value
            }
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
    allowDocumentType: bool     // Skips one DOCTYPE without an internal subset; external identifiers are never read.
}

private impl Scanner
{
    mtd space(value: u8)->bool => value == ' '_u8 or value == '\t'_u8 or value == '\r'_u8 or value == '\n'_u8

    mtd skipSpace()
    {
        while .offset < .source.count and .space(.source[.offset])
        {
            .offset += 1
        }
    }

    mtd nameEnd()->u64
    {
        let start = .offset
        while .offset < .source.count
        {
            let value = .source[.offset]
            if .space(value) or
               value == '/'_u8 or
               value == '>'_u8 or
               value == '='_u8 or
               value == '?'_u8
            {
                break
            }

            .offset += 1
        }

        if .offset == start
        {
            .damaged = true
        }

        return .offset
    }

    mtd decode(source: string)->String
    {
        var result: #returntype
        var at = 0_u64
        while at < source.count
        {
            if source[at] != '&'_u8
            {
                result += source[at]
                at     += 1
                continue
            }

            let start = at + 1
            var end   = start
            while end < source.count and end - start <= 12 and source[end] != ';'_u8
            {
                end += 1
            }

            if end >= source.count or source[end] != ';'_u8
            {
                .damaged = true
                return {}
            }

            let entity = source[start until end]
            switch entity
            {
            case "amp":
                result += '&'_u8

            case "lt":
                result += '<'_u8

            case "gt":
                result += '>'_u8

            case "quot":
                result += '"'_u8

            case "apos":
                result += '\''_u8

            default:
                if entity.count < 2 or entity[0] != '#'_u8
                {
                    .damaged = true
                    return {}
                }

                let hex    = entity.count > 2 and (entity[1] == 'x'_u8 or entity[1] == 'X'_u8)
                let digits = hex ? entity[2 to] : entity[1 to]
                if not digits.count
                {
                    .damaged = true
                    return {}
                }

                var code = 0_u32
                for digit in digits
                {
                    var value: u32
                    if digit >= '0'_u8 and digit <= '9'_u8
                    {
                        value = digit - '0'_u8
                    }
                    else if hex and digit >= 'a'_u8 and digit <= 'f'_u8
                    {
                        value = digit - 'a'_u8 + 10
                    }
                    else if hex and digit >= 'A'_u8 and digit <= 'F'_u8
                    {
                        value = digit - 'A'_u8 + 10
                    }
                    else
                    {
                        .damaged = true
                        return {}
                    }

                    let base = hex ? 16_u32 : 10_u32
                    if code > (0x10FFFF_u32 - value) / base
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
        if .damaged
        {
            return false
        }

        while .offset < .source.count
        {
            token[] = {}
            if .source[.offset] != '<'_u8
            {
                let start = .offset
                while .offset < .source.count and .source[.offset] != '<'_u8
                {
                    .offset += 1
                }

                token.kind = .Text
                token.text = .decode(.source[start until .offset])
                return not .damaged
            }

            if .offset + 4 <= .source.count and .source[.offset until .offset + 4] == "<!--"
            {
                .offset += 4
                if not .skipUntil("-->")
                {
                    return false
                }

                continue
            }

            if .offset + 9 <= .source.count and .source[.offset until .offset + 9] == "<![CDATA["
            {
                .offset += 9
                let start = .offset
                if not .skipUntil("]]>")
                {
                    return false
                }

                token.kind = .Text
                token.text = .source[start until .offset - 3]
                return true
            }

            if .offset + 2 <= .source.count and .source[.offset + 1] == '?'_u8
            {
                .offset += 2
                if not .skipUntil("?>")
                {
                    return false
                }

                continue
            }

            if .allowDocumentType and
               .offset + 10 <= .source.count and
               .source[.offset until .offset + 9] == "<!DOCTYPE" and
               .space(.source[.offset + 9])
            {
                .allowDocumentType = false
                .offset += 9
                var quote  = 0_u8
                var closed = false
                while .offset < .source.count
                {
                    let value = .source[.offset]
                    .offset += 1
                    if quote
                    {
                        if value == quote
                        {
                            quote = 0
                        }
                    }
                    else if value == '\''_u8 or value == '"'_u8
                    {
                        quote = value
                    }
                    else if value == '['_u8
                    {
                        break
                    }
                    else if value == '>'_u8
                    {
                        closed = true
                        break
                    }
                }

                if closed
                {
                    continue
                }

                .damaged = true
                return false
            }

            if .offset + 2 <= .source.count and .source[.offset + 1] == '!'_u8
            {
                .damaged = true
                return false
            }

            .offset += 1
            if .offset < .source.count and .source[.offset] == '/'_u8
            {
                token.kind = .End
                .offset    += 1
            }
            else
            {
                token.kind = .Start
            }

            let start = .offset
            let end   = .nameEnd()
            if .damaged
            {
                return false
            }

            token.name = .source[start until end]

            while .offset < .source.count
            {
                .skipSpace()
                if .offset >= .source.count
                {
                    break
                }

                if .source[.offset] == '>'_u8
                {
                    .offset += 1
                    return true
                }

                if token.kind == .Start and
                   .source[.offset] == '/'_u8 and
                   .offset + 1 < .source.count and
                   .source[.offset + 1] == '>'_u8
                {
                    token.empty = true
                    .offset     += 2
                    return true
                }

                if token.kind == .End
                {
                    break
                }

                let attrStart = .offset
                let attrEnd   = .nameEnd()
                if .damaged
                {
                    return false
                }

                .skipSpace()
                if .offset >= .source.count or .source[.offset] != '='_u8
                {
                    break
                }

                .offset += 1
                .skipSpace()
                if .offset >= .source.count or (.source[.offset] != '"'_u8 and .source[.offset] != '\''_u8)
                {
                    break
                }

                let quote = .source[.offset]
                .offset += 1
                let valueStart = .offset
                while .offset < .source.count and .source[.offset] != quote
                {
                    .offset += 1
                }

                if .offset >= .source.count
                {
                    break
                }

                let value = .decode(.source[valueStart until .offset])
                if .damaged
                {
                    return false
                }

                token.attributes.add(Attribute{.source[attrStart until attrEnd], value})
                .offset += 1
            }

            .damaged = true
            return false
        }

        return false
    }
}
