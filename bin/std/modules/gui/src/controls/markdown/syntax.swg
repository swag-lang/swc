#global internal
#global namespace Markdown

using Core

private func findClosing(text: string, marker: string, start: u64)->u64
{
    let markerLength = @countof(marker)
    var index        = start
    while index < @countof(text)
    {
        if text[index] != marker[0]
        {
            index += 1
            continue
        }

        var runEnd = index + 1
        while runEnd < @countof(text) and text[runEnd] == marker[0] do
            runEnd += 1
        let runLength = runEnd - index
        if markerLength == 1 and runLength & 1 do
            return runEnd - 1
        if markerLength > 1 and runLength >= markerLength do
            return runEnd - markerLength
        index = runEnd
    }

    return Swag.U64.Max
}

private func canOpenUnderscore(text: string, index: u64)->bool
{
    return index == 0 or !Latin1.isWord(text[index - 1])
}

private func findInlineMathEnd(text: string, start: u64)->u64
{
    if start >= @countof(text) or Latin1.isSpace(text[start]) do
        return Swag.U64.Max

    var index = start
    while index < @countof(text)
    {
        if text[index] != '$'
        {
            index += 1
            continue
        }

        let escaped     = index > start and text[index - 1] == '\\'
        let spaceBefore = index == start or Latin1.isSpace(text[index - 1])
        let digitAfter  = index + 1 < @countof(text) and Latin1.isDigit(text[index + 1])
        if !escaped and !spaceBefore and !digitAfter do
            return index
        index += 1
    }

    return Swag.U64.Max
}

private func findBareUrlEnd(text: string, start: u64)->u64
{
    var end = start
    while end < @countof(text) and !Latin1.isSpace(text[end]) and text[end] != '<' and text[end] != '>' do
        end += 1
    while end > start and (text[end - 1] == '.' or text[end - 1] == ',' or text[end - 1] == ';' or text[end - 1] == ':' or text[end - 1] == '!' or text[end - 1] == '?') do
        end -= 1
    return end
}

struct Reference
{
    name:   String
    target: String
}

struct ReferenceInfo
{
    found:    bool
    footnote: bool
    name:     string = ""
    value:    string = ""
}

func parseReferenceDefinition(line: string)->ReferenceInfo
{
    var result: retval
    let trimmed = Latin1.trim(line)
    if @countof(trimmed) < 4 or trimmed[0] != '[' do
        return result
    let close = Utf8.indexOf(trimmed, "]: ")
    let tight = close == Swag.U64.Max ? Utf8.indexOf(trimmed, "]:") : close
    if tight == Swag.U64.Max or tight <= 1 do
        return result
    result.found    = true
    result.footnote = trimmed[1] == '^'
    result.name     = result.footnote ? trimmed[2 until tight] : trimmed[1 until tight]
    result.value    = Latin1.trim(trimmed[tight + 2 to])
    return result
}

private func resolveReferenceTarget(references: #null const [..] Reference, name: string)->string
{
    for &reference in references where Utf8.compare(reference.name.toString(), name, .Latin1NoCase) == 0 do
        return reference.target.toString()
    return ""
}

func renderInline(text: string, references: #null const [..] Reference = null)->String
{
    var result: retval
    var index = 0'u64
    while index < @countof(text)
    {
        if text[index] == '\\' and index + 1 < @countof(text) and text[index + 1] == '('
        {
            let end = Utf8.indexOf(text, "\\)", index + 2)
            if end != Swag.U64.Max
            {
                result += "<m>"
                result += richText(text[index + 2 until end])
                result += "</m>"
                index  = end + 2
                continue
            }
        }

        if text[index] == '\\' and index + 1 < @countof(text)
        {
            result += richText(text[index + 1 until index + 2])
            index  += 2
            continue
        }

        if text[index] == '!' and index + 1 < @countof(text) and text[index + 1] == '['
        {
            let labelEnd = Utf8.indexOf(text, ']'rune, index + 2)
            if labelEnd != Swag.U64.Max and labelEnd + 1 < @countof(text) and text[labelEnd + 1] == '('
            {
                let urlEnd = Utf8.indexOf(text, ')'rune, labelEnd + 2)
                if urlEnd != Swag.U64.Max
                {
                    result += "<a><p3>[Image: "
                    result += richText(text[index + 2 until labelEnd], true)
                    result += "]</p></a><t>"
                    result += richText(text[labelEnd + 2 until urlEnd])
                    result += "</t>"
                    index  = urlEnd + 1
                    continue
                }
            }

            if labelEnd != Swag.U64.Max and labelEnd + 1 < @countof(text) and text[labelEnd + 1] == '['
            {
                let referenceEnd = Utf8.indexOf(text, ']'rune, labelEnd + 2)
                if referenceEnd != Swag.U64.Max
                {
                    let referenceName = referenceEnd == labelEnd + 2 ? text[index + 2 until labelEnd] : text[labelEnd + 2 until referenceEnd]
                    let target        = resolveReferenceTarget(references, referenceName)
                    if @countof(target)
                    {
                        result += "<a><p3>[Image: "
                        result += richText(text[index + 2 until labelEnd], true)
                        result += "]</p></a><t>"
                        result += richText(target)
                        result += "</t>"
                        index  = referenceEnd + 1
                        continue
                    }
                }
            }
        }

        if text[index] == '['
        {
            let labelEnd = Utf8.indexOf(text, ']'rune, index + 1)
            if labelEnd != Swag.U64.Max and index + 2 < labelEnd and text[index + 1] == '^'
            {
                result += "<sup><p1>"
                result += richText(text[index + 2 until labelEnd], true)
                result += "</p></sup>"
                index  = labelEnd + 1
                continue
            }

            if labelEnd != Swag.U64.Max and labelEnd + 1 < @countof(text) and text[labelEnd + 1] == '('
            {
                let urlEnd = Utf8.indexOf(text, ')'rune, labelEnd + 2)
                if urlEnd != Swag.U64.Max
                {
                    result += "<a>"
                    result += renderInline(text[index + 1 until labelEnd], references)
                    result += "</a><t>"
                    result += richText(text[labelEnd + 2 until urlEnd])
                    result += "</t>"
                    index  = urlEnd + 1
                    continue
                }
            }

            if labelEnd != Swag.U64.Max
            {
                var referenceEnd  = labelEnd
                var referenceName = text[index + 1 until labelEnd]
                if labelEnd + 1 < @countof(text) and text[labelEnd + 1] == '['
                {
                    referenceEnd = Utf8.indexOf(text, ']'rune, labelEnd + 2)
                    if referenceEnd != Swag.U64.Max and referenceEnd > labelEnd + 2 do
                        referenceName = text[labelEnd + 2 until referenceEnd]
                }

                if referenceEnd != Swag.U64.Max
                {
                    let target = resolveReferenceTarget(references, referenceName)
                    if @countof(target)
                    {
                        result += "<a>"
                        result += renderInline(text[index + 1 until labelEnd], references)
                        result += "</a><t>"
                        result += richText(target)
                        result += "</t>"
                        index  = referenceEnd + 1
                        continue
                    }
                }
            }
        }

        if text[index] == '<'
        {
            let end = Utf8.indexOf(text, '>'rune, index + 1)
            if end != Swag.U64.Max
            {
                let target = text[index + 1 until end]
                if Utf8.startsWith(target, "http://") or Utf8.startsWith(target, "https://") or Utf8.startsWith(target, "mailto:")
                {
                    result += "<a>"
                    result += richText(target)
                    result += "</a><t>"
                    result += richText(target)
                    result += "</t>"
                    index  = end + 1
                    continue
                }
            }
        }

        if Utf8.startsWith(text[index to], "https://") or Utf8.startsWith(text[index to], "http://")
        {
            let end = findBareUrlEnd(text, index)
            if end > index
            {
                let target = text[index until end]
                result += "<a>"
                result += richText(target)
                result += "</a><t>"
                result += richText(target)
                result += "</t>"
                index  = end
                continue
            }
        }

        if text[index] == '$'
        {
            let end = findInlineMathEnd(text, index + 1)
            if end != Swag.U64.Max and end > index + 1
            {
                result += "<m>"
                result += richText(text[index + 1 until end])
                result += "</m>"
                index  = end + 1
                continue
            }
        }

        if index + 1 < @countof(text) and text[index] == '~' and text[index + 1] == '~'
        {
            let end = Utf8.indexOf(text, "~~", index + 2)
            if end != Swag.U64.Max
            {
                result += "<s>"
                result += renderInline(text[index + 2 until end], references)
                result += "</s>"
                index  = end + 2
                continue
            }
        }

        if index + 1 < @countof(text) and text[index] == '=' and text[index + 1] == '='
        {
            let end = Utf8.indexOf(text, "==", index + 2)
            if end != Swag.U64.Max
            {
                result += "<h>"
                result += renderInline(text[index + 2 until end], references)
                result += "</h>"
                index  = end + 2
                continue
            }
        }

        if index + 2 < @countof(text) and ((text[index] == '*' and text[index + 1] == '*' and text[index + 2] == '*') or (text[index] == '_' and text[index + 1] == '_' and text[index + 2] == '_' and canOpenUnderscore(text, index)))
        {
            let marker = text[index until index + 3]
            let end    = findClosing(text, marker, index + 3)
            if end != Swag.U64.Max and end > index + 3
            {
                result += "<b><i>"
                result += renderInline(text[index + 3 until end], references)
                result += "</i></b>"
                index  = end + 3
                continue
            }
        }

        if index + 1 < @countof(text) and ((text[index] == '*' and text[index + 1] == '*') or (text[index] == '_' and text[index + 1] == '_' and canOpenUnderscore(text, index)))
        {
            let marker = text[index until index + 2]
            let end    = findClosing(text, marker, index + 2)
            if end != Swag.U64.Max
            {
                result += "<b>"
                result += renderInline(text[index + 2 until end], references)
                result += "</b>"
                index  = end + 2
                continue
            }
        }

        if text[index] == '*' or (text[index] == '_' and canOpenUnderscore(text, index))
        {
            let marker = text[index until index + 1]
            let end    = findClosing(text, marker, index + 1)
            if end != Swag.U64.Max and end > index + 1
            {
                result += "<i>"
                result += renderInline(text[index + 1 until end], references)
                result += "</i>"
                index  = end + 1
                continue
            }
        }

        if text[index] == '`'
        {
            let end = Utf8.indexOf(text, '`'rune, index + 1)
            if end != Swag.U64.Max
            {
                result += "<c>"
                result += richText(text[index + 1 until end])
                result += "</c>"
                index  = end + 1
                continue
            }
        }

        if text[index] == '^'
        {
            let end = Utf8.indexOf(text, '^'rune, index + 1)
            if end != Swag.U64.Max and end > index + 1
            {
                result += "<sup>"
                result += renderInline(text[index + 1 until end], references)
                result += "</sup>"
                index  = end + 1
                continue
            }
        }

        if text[index] == '~' and (index + 1 >= @countof(text) or text[index + 1] != '~')
        {
            let end = Utf8.indexOf(text, '~'rune, index + 1)
            if end != Swag.U64.Max and end > index + 1
            {
                result += "<sub>"
                result += renderInline(text[index + 1 until end], references)
                result += "</sub>"
                index  = end + 1
                continue
            }
        }

        if text[index] == '&'
        {
            let entity = decodeEntity(text, index)
            result += entity.value
            index  += entity.eat
            continue
        }

        result += richText(text[index until index + 1])
        index  += 1
    }

    return result
}

struct HeadingInfo
{
    level: u32
    text:  string = ""
}

struct ListInfo
{
    found:         bool
    ordered:       bool
    content:       string = ""
    marker:        string = ""
    indent:        u32
    contentIndent: u32
}

struct FenceInfo
{
    found:  bool
    marker: u8
    info:   string = ""
}

func parseHeading(line: string)->HeadingInfo
{
    var result: retval
    let trimmed = Latin1.trim(line)
    while result.level < @countof(trimmed) and result.level < 6 and trimmed[result.level] == '#' do
        result.level += 1
    if !result.level or result.level >= @countof(trimmed) or trimmed[result.level] != ' '
    {
        result.level = 0
        return result
    }

    var end = @countof(trimmed)
    while end and (trimmed[end - 1] == ' ' or trimmed[end - 1] == '#') do
        end -= 1
    result.text = trimmed[result.level + 1 until end]
    return result
}

func setextLevel(line: string)->u32
{
    let trimmed = Latin1.trim(line)
    if @countof(trimmed) < 3 do
        return 0
    let marker = trimmed[0]
    if marker != '=' and marker != '-' do
        return 0
    for value in trimmed where value != marker do
        return 0
    return marker == '=' ? 1 : 2
}

func isRule(line: string)->bool
{
    let trimmed = Latin1.trim(line)
    var marker  = 0'u8
    var count   = 0'u32
    for value in trimmed
    {
        if value == ' ' do
            continue
        if value != '-' and value != '*' and value != '_' do
            return false
        if !marker do
            marker = value
        elif marker != value do
            return false
        count += 1
    }

    return count >= 3
}

func hasHardBreak(line: string)->bool
{
    return @countof(line) >= 2 and line[@countof(line) - 1] == ' ' and line[@countof(line) - 2] == ' '
}

func parseListItem(line: string)->ListInfo
{
    var result: retval
    var index = 0'u64
    while index < @countof(line) and (line[index] == ' ' or line[index] == '\t')
    {
        result.indent += line[index] == '\t' ? 4 : 1
        index         += 1
    }

    if index >= @countof(line) do
        return result

    if (line[index] == '-' or line[index] == '*' or line[index] == '+') and index + 1 < @countof(line) and line[index + 1] == ' '
    {
        result.found         = true
        result.content       = line[index + 2 to]
        result.contentIndent = result.indent + 2
        return result
    }

    let digitStart = index
    while index < @countof(line) and Latin1.isDigit(line[index]) do
        index += 1
    if index > digitStart and index + 1 < @countof(line) and (line[index] == '.' or line[index] == ')') and line[index + 1] == ' '
    {
        result.found         = true
        result.ordered       = true
        result.marker        = line[digitStart until index]
        result.content       = line[index + 2 to]
        result.contentIndent = result.indent + cast(u32) (index - digitStart) + 2
    }

    return result
}

func isTableSeparator(line: string)->bool
{
    let trimmed = Latin1.trim(line)
    if !Utf8.contains(trimmed, '|'rune) do
        return false
    var dashCount = 0'u32
    for value in trimmed
    {
        if value == '-' do
            dashCount += 1
        elif value != '|' and value != ':' and value != ' ' do
            return false
    }

    return dashCount >= 3
}

func parseFence(line: string)->FenceInfo
{
    var result: retval
    let trimmed = Latin1.trim(line)
    if @countof(trimmed) < 3 or (trimmed[0] != '`' and trimmed[0] != '~') do
        return result
    if trimmed[1] != trimmed[0] or trimmed[2] != trimmed[0] do
        return result
    result.found  = true
    result.marker = trimmed[0]
    result.info   = Latin1.trim(trimmed[3 to])
    return result
}
