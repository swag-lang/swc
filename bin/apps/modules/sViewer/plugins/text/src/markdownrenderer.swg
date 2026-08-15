#global internal

using Core

private func markdownClosing(text: string, marker: string, start: u64)->u64
{
    return Utf8.indexOf(text, marker, start)
}

private func markdownUnderscoreCanOpen(text: string, index: u64)->bool
{
    return index == 0 or !Latin1.isWord(text[index - 1])
}

private func renderMarkdownInline(text: string)->String
{
    var result: retval
    var index = 0'u64
    while index < @countof(text)
    {
        if text[index] == '\\' and index + 1 < @countof(text)
        {
            result += viewerRichText(text[index + 1 until index + 2])
            index += 2
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
                    result += "<p3>[Image: "
                    result += viewerRichText(text[index + 2 until labelEnd], true)
                    result += "]</p> (<url>"
                    result += viewerRichText(text[labelEnd + 2 until urlEnd])
                    result += "</url>)"
                    index = urlEnd + 1
                    continue
                }
            }
        }

        if text[index] == '['
        {
            let labelEnd = Utf8.indexOf(text, ']'rune, index + 1)
            if labelEnd != Swag.U64.Max and labelEnd + 1 < @countof(text) and text[labelEnd + 1] == '('
            {
                let urlEnd = Utf8.indexOf(text, ')'rune, labelEnd + 2)
                if urlEnd != Swag.U64.Max
                {
                    result += "<u>"
                    result += renderMarkdownInline(text[index + 1 until labelEnd])
                    result += "</u> (<url>"
                    result += viewerRichText(text[labelEnd + 2 until urlEnd])
                    result += "</url>)"
                    index = urlEnd + 1
                    continue
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
                    result += "<url>"
                    result += viewerRichText(target)
                    result += "</url>"
                    index = end + 1
                    continue
                }
            }
        }

        if index + 1 < @countof(text) and ((text[index] == '*' and text[index + 1] == '*') or (text[index] == '_' and text[index + 1] == '_' and markdownUnderscoreCanOpen(text, index)))
        {
            let marker = text[index until index + 2]
            let end    = markdownClosing(text, marker, index + 2)
            if end != Swag.U64.Max
            {
                result += "<b>"
                result += renderMarkdownInline(text[index + 2 until end])
                result += "</b>"
                index = end + 2
                continue
            }
        }

        if text[index] == '*' or (text[index] == '_' and markdownUnderscoreCanOpen(text, index))
        {
            let marker = text[index until index + 1]
            let end    = markdownClosing(text, marker, index + 1)
            if end != Swag.U64.Max and end > index + 1
            {
                result += "<i>"
                result += renderMarkdownInline(text[index + 1 until end])
                result += "</i>"
                index = end + 1
                continue
            }
        }

        if text[index] == '`'
        {
            let end = Utf8.indexOf(text, '`'rune, index + 1)
            if end != Swag.U64.Max
            {
                result += "<p2>"
                result += viewerRichText(text[index + 1 until end])
                result += "</p>"
                index = end + 1
                continue
            }
        }

        if text[index] == '&'
        {
            let entity = viewerDecodedEntity(text, index)
            result += entity.value
            index  += entity.eat
            continue
        }

        result += viewerRichText(text[index until index + 1])
        index += 1
    }
    return result
}

private struct MarkdownHeadingInfo
{
    level: u32
    text:  string = ""
}

private struct MarkdownListInfo
{
    found:   bool
    ordered: bool
    content: string = ""
    marker:  string = ""
    indent:  u32
}

private struct MarkdownFenceInfo
{
    found:  bool
    marker: u8
    info:   string = ""
}

private func markdownHeading(line: string)->MarkdownHeadingInfo
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

private func markdownSetextLevel(line: string)->u32
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

private func markdownRule(line: string)->bool
{
    let trimmed = Latin1.trim(line)
    var marker = 0'u8
    var count  = 0'u32
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

private func markdownHardBreak(line: string)->bool
{
    return @countof(line) >= 2 and line[@countof(line) - 1] == ' ' and line[@countof(line) - 2] == ' '
}

private func markdownListItem(line: string)->MarkdownListInfo
{
    var result: retval
    var index = 0'u64
    while index < @countof(line) and (line[index] == ' ' or line[index] == '\t')
    {
        result.indent += line[index] == '\t' ? 4 : 1
        index += 1
    }
    if index >= @countof(line) do
        return result

    if (line[index] == '-' or line[index] == '*' or line[index] == '+') and index + 1 < @countof(line) and line[index + 1] == ' '
    {
        result.found   = true
        result.content = line[index + 2 to]
        return result
    }

    let digitStart = index
    while index < @countof(line) and Latin1.isDigit(line[index]) do
        index += 1
    if index > digitStart and index + 1 < @countof(line) and (line[index] == '.' or line[index] == ')') and line[index + 1] == ' '
    {
        result.found   = true
        result.ordered = true
        result.marker  = line[digitStart until index]
        result.content = line[index + 2 to]
    }
    return result
}

private func markdownTableSeparator(line: string)->bool
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

private func renderMarkdownTableLine(line: string, header: bool)->String
{
    var result: retval
    let cells = Tokenize.split(Latin1.trim(line), cast(u8) '|', removeEmpty: false)
    var first = true
    for cell in cells
    {
        let trimmed = Latin1.trim(cell)
        if !@countof(trimmed) do
            continue
        if !first do
            result += "  <p3>|</p>  "
        if header do
            result += "<b>"
        result += renderMarkdownInline(trimmed)
        if header do
            result += "</b>"
        first = false
    }
    return result
}

private func markdownFence(line: string)->MarkdownFenceInfo
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

struct MarkdownTextRenderer
{
}

impl MarkdownTextRenderer
{
    func render(source: string)->String
    {
        var result: retval
        let lines = Tokenize.splitLines(source)
        var index = 0'u64
        var fenceMarker = 0'u8
        while index < lines.count
        {
            let rawLine = lines[index]
            let trimmed = Latin1.trim(rawLine)
            let fence   = markdownFence(rawLine)
            if fence.found and (!fenceMarker or fence.marker == fenceMarker)
            {
                if !fenceMarker
                {
                    fenceMarker = fence.marker
                    result += "\n<p2>"
                    if @countof(fence.info)
                    {
                        result += "<b>CODE · "
                        let info = String.from(fence.info).toUpper()
                        result += viewerRichText(info.toString())
                        result += "</b>\n"
                    }
                }
                else
                {
                    fenceMarker = 0
                    result += "</p>\n\n"
                }
                index += 1
                continue
            }

            if fenceMarker
            {
                result += "    "
                result += viewerRichText(rawLine)
                result += "\n"
                index += 1
                continue
            }

            let heading = markdownHeading(rawLine)
            if heading.level
            {
                let palette = heading.level == 1 ? 1 : (heading.level == 2 ? 2 : 3)
                result += Format.toString("\n<p%><b>%</b></p>\n\n", palette, renderMarkdownInline(heading.text))
                index += 1
                continue
            }

            if index + 1 < lines.count
            {
                let setext = markdownSetextLevel(lines[index + 1])
                if setext and @countof(trimmed)
                {
                    result += Format.toString("\n<p%><b>%</b></p>\n\n", setext, renderMarkdownInline(trimmed))
                    index += 2
                    continue
                }
                if Utf8.contains(rawLine, '|'rune) and markdownTableSeparator(lines[index + 1])
                {
                    result += renderMarkdownTableLine(rawLine, true)
                    result += "\n"
                    index += 2
                    while index < lines.count and Utf8.contains(lines[index], '|'rune) and @countof(Latin1.trim(lines[index]))
                    {
                        result += renderMarkdownTableLine(lines[index], false)
                        result += "\n"
                        index += 1
                    }
                    result += "\n"
                    continue
                }
            }

            if markdownRule(rawLine)
            {
                result += "\n<p3>------------------------</p>\n\n"
                index += 1
                continue
            }

            let item = markdownListItem(rawLine)
            if item.found
            {
                for item.indent / 2 do
                    result += "  "
                if item.ordered do
                    result += Format.toString("  <p3>%.</p> ", item.marker)
                else do
                    result += "  <p1>•</p> "
                var content = item.content
                if Utf8.startsWith(content, "[ ] ")
                {
                    result += "[ ] "
                    content = content[4 to]
                }
                elif Utf8.startsWith(content, "[x] ") or Utf8.startsWith(content, "[X] ")
                {
                    result += "<p1>[x]</p> "
                    content = content[4 to]
                }
                result += renderMarkdownInline(content)
                result += "\n"
                index += 1
                continue
            }

            if Utf8.startsWith(trimmed, ">")
            {
                var quote = trimmed
                var depth = 0'u32
                while @countof(quote) and quote[0] == '>'
                {
                    depth += 1
                    quote = Latin1.trim(quote[1 to])
                }
                for depth do
                    result += "<p3>></p> "
                result += "<i>"
                result += renderMarkdownInline(quote)
                result += "</i>\n"
                index += 1
                continue
            }

            if !@countof(trimmed)
            {
                result += "\n"
                index += 1
                continue
            }

            // Join wrapped source lines into a single paragraph. Markdown treats a single newline
            // as whitespace; preserving it made ordinary README files look fragmented.
            var paragraph = String.from(trimmed)
            index += 1
            while index < lines.count
            {
                let next = Latin1.trim(lines[index])
                if !@countof(next) or markdownHeading(lines[index]).level or markdownRule(lines[index]) or markdownListItem(lines[index]).found or Utf8.startsWith(next, ">") or markdownFence(lines[index]).found do
                    break
                if index + 1 < lines.count and markdownSetextLevel(lines[index + 1]) do
                    break
                paragraph += markdownHardBreak(lines[index - 1]) ? "\n" : " "
                paragraph += next
                index += 1
            }
            result += renderMarkdownInline(paragraph.toString())
            result += "\n"
        }

        if fenceMarker do
            result += "</p>"
        return result
    }
}
