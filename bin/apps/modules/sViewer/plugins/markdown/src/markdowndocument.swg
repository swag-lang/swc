using Core

enum MarkdownBlockKind
{
    Paragraph
    Heading1
    Heading2
    Heading3
    Heading4
    Heading5
    Heading6
    List
    Quote
    Code
    Table
    Math
    Rule
    Metadata
}

struct MarkdownBlock
{
    kind: MarkdownBlockKind
    text: String
}

private func markdownVisualHeading(level: u32)->MarkdownBlockKind
{
    switch level
    {
    case 1: return .Heading1
    case 2: return .Heading2
    case 3: return .Heading3
    case 4: return .Heading4
    case 5: return .Heading5
    default: return .Heading6
    }
}

private func appendMarkdownBlock(blocks: *Array'MarkdownBlock, kind: MarkdownBlockKind, text: String)
{
    if text.isEmpty() do
        return
    var block: MarkdownBlock
    block.kind = kind
    block.text = #move text
    blocks.add(#move block)
}

func parseMarkdownBlocks(source: string)->Array'MarkdownBlock
{
    var result: retval
    let lines = Tokenize.splitLines(source)
    var index = 0'u64

    if lines.count and Latin1.trim(lines[0]) == "---"
    {
        var metadata: String
        index = 1
        while index < lines.count and Latin1.trim(lines[index]) != "---"
        {
            metadata += lines[index]
            metadata += "\n"
            index += 1
        }
        if index < lines.count do
            index += 1
        appendMarkdownBlock(&result, .Metadata, #move metadata)
    }

    while index < lines.count
    {
        let raw     = lines[index]
        let trimmed = Latin1.trim(raw)
        if !@countof(trimmed)
        {
            index += 1
            continue
        }

        let fence = markdownFence(raw)
        if fence.found
        {
            var code: String
            if @countof(fence.info) do
                code += Format.toString("<p3>%</p>\n", viewerRichText(String.from(fence.info).toUpper().toString()))
            index += 1
            while index < lines.count
            {
                let close = markdownFence(lines[index])
                if close.found and close.marker == fence.marker
                {
                    index += 1
                    break
                }
                code += viewerRichText(lines[index])
                code += "\n"
                index += 1
            }
            appendMarkdownBlock(&result, .Code, #move code)
            continue
        }

        if Utf8.startsWith(trimmed, "$$")
        {
            var math: String
            var line = trimmed[2 to]
            if Utf8.endsWith(line, "$$") and @countof(line) >= 2
            {
                math = Latin1.trim(line[0 until @countof(line) - 2])
                index += 1
            }
            else
            {
                if @countof(line) do
                    math += Latin1.trim(line)
                index += 1
                while index < lines.count and !Utf8.startsWith(Latin1.trim(lines[index]), "$$")
                {
                    if !math.isEmpty() do
                        math += "\n"
                    math += Latin1.trim(lines[index])
                    index += 1
                }
                if index < lines.count do
                    index += 1
            }
            appendMarkdownBlock(&result, .Math, #move math)
            continue
        }

        let heading = markdownHeading(raw)
        if heading.level
        {
            appendMarkdownBlock(&result, markdownVisualHeading(heading.level), renderMarkdownInline(heading.text))
            index += 1
            continue
        }

        if index + 1 < lines.count
        {
            let setext = markdownSetextLevel(lines[index + 1])
            if setext
            {
                appendMarkdownBlock(&result, markdownVisualHeading(setext), renderMarkdownInline(trimmed))
                index += 2
                continue
            }
            if Utf8.contains(raw, '|'rune) and markdownTableSeparator(lines[index + 1])
            {
                var table = renderMarkdownTableLine(raw, true)
                index += 2
                while index < lines.count and Utf8.contains(lines[index], '|'rune) and @countof(Latin1.trim(lines[index]))
                {
                    table += "\n"
                    table += renderMarkdownTableLine(lines[index], false)
                    index += 1
                }
                appendMarkdownBlock(&result, .Table, #move table)
                continue
            }
        }

        if markdownRule(raw)
        {
            result.add(MarkdownBlock{.Rule, ""})
            index += 1
            continue
        }

        let item = markdownListItem(raw)
        if item.found
        {
            var list: String
            while index < lines.count
            {
                let current = markdownListItem(lines[index])
                if !current.found do
                    break
                for current.indent / 2 do
                    list += "  "
                if current.ordered do
                    list += Format.toString("<p3>%.</p> ", current.marker)
                else do
                    list += "<p1>◆</p> "
                var content = current.content
                if Utf8.startsWith(content, "[ ] ")
                {
                    list += "☐ "
                    content = content[4 to]
                }
                elif Utf8.startsWith(content, "[x] ") or Utf8.startsWith(content, "[X] ")
                {
                    list += "<p1>☒</p> "
                    content = content[4 to]
                }
                list += renderMarkdownInline(content)
                list += "\n"
                index += 1
            }
            appendMarkdownBlock(&result, .List, #move list)
            continue
        }

        if Utf8.startsWith(trimmed, ">")
        {
            var quote: String
            while index < lines.count and Utf8.startsWith(Latin1.trim(lines[index]), ">")
            {
                let content = Latin1.trim(Latin1.trim(lines[index])[1 to])
                if !quote.isEmpty() do
                    quote += "\n"
                quote += renderMarkdownInline(content)
                index += 1
            }
            appendMarkdownBlock(&result, .Quote, #move quote)
            continue
        }

        var paragraph = String.from(trimmed)
        index += 1
        while index < lines.count
        {
            let next = Latin1.trim(lines[index])
            if !@countof(next) or markdownHeading(lines[index]).level or markdownRule(lines[index]) or markdownListItem(lines[index]).found or Utf8.startsWith(next, ">") or Utf8.startsWith(next, "$$") or markdownFence(lines[index]).found do
                break
            if index + 1 < lines.count and markdownSetextLevel(lines[index + 1]) do
                break
            paragraph += markdownHardBreak(lines[index - 1]) ? "\n" : " "
            paragraph += next
            index += 1
        }
        appendMarkdownBlock(&result, .Paragraph, renderMarkdownInline(paragraph.toString()))
    }
    return result
}
