#global public

using Core

#[Swag.NoDoc]
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
    TableOfContents
    Footnote
    AlertNote
    AlertTip
    AlertImportant
    AlertWarning
    AlertCaution
}

#[Swag.NoDoc]
struct MarkdownBlock
{
    kind: MarkdownBlockKind
    text: String
}

private func markdownVisualHeading(level: u32)->MarkdownBlockKind
{
    switch level
    {
    case 1:  return .Heading1
    case 2:  return .Heading2
    case 3:  return .Heading3
    case 4:  return .Heading4
    case 5:  return .Heading5
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

private func markdownAlertKind(name: string)->MarkdownBlockKind
{
    if Utf8.compare(name, "NOTE", .Latin1NoCase) == 0 do
        return .AlertNote
    if Utf8.compare(name, "TIP", .Latin1NoCase) == 0 do
        return .AlertTip
    if Utf8.compare(name, "IMPORTANT", .Latin1NoCase) == 0 do
        return .AlertImportant
    if Utf8.compare(name, "WARNING", .Latin1NoCase) == 0 do
        return .AlertWarning
    if Utf8.compare(name, "CAUTION", .Latin1NoCase) == 0 do
        return .AlertCaution
    return .Quote
}

private func markdownAlertTitle(kind: MarkdownBlockKind)->string
{
    switch kind
    {
    case .AlertNote:      return "Note"
    case .AlertTip:       return "Tip"
    case .AlertImportant: return "Important"
    case .AlertWarning:   return "Warning"
    case .AlertCaution:   return "Caution"
    default:              return ""
    }
}

internal func parseMarkdownBlocks(source: string)->Array'MarkdownBlock
{
    var result: retval
    let lines = Tokenize.splitLines(source)
    var index = 0'u64
    var references: Array'MarkdownReference

    for line in lines
    {
        let definition = markdownReferenceDefinition(line)
        if definition.found and !definition.footnote
        {
            var reference: MarkdownReference
            reference.name   = definition.name
            reference.target = definition.value
            references.add(#move reference)
        }
    }

    if lines.count and Latin1.trim(lines[0]) == "---"
    {
        var metadata: String
        index = 1
        while index < lines.count and Latin1.trim(lines[index]) != "---"
        {
            metadata += lines[index]
            metadata += "\n"
            index    += 1
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

        let definition = markdownReferenceDefinition(raw)
        if definition.found
        {
            if definition.footnote
            {
                var footnote = Format.toString("<p3>%.</p> ", markdownRichText(definition.name, true))
                footnote += renderMarkdownInline(definition.value, references.toSlice())
                appendMarkdownBlock(&result, .Footnote, #move footnote)
            }
            index += 1
            continue
        }

        if Utf8.compare(trimmed, "[TOC]", .Latin1NoCase) == 0
        {
            var contents: String
            for line in lines
            {
                let entry = markdownHeading(line)
                if !entry.level do
                    continue
                for entry.level - 1 do
                    contents += "  "
                contents += renderMarkdownInline(entry.text, references.toSlice())
                contents += "\n"
            }
            appendMarkdownBlock(&result, .TableOfContents, #move contents)
            index += 1
            continue
        }

        let fence = markdownFence(raw)
        if fence.found
        {
            var code: String
            if @countof(fence.info) do
                code += Format.toString("<p3>%</p>\n", markdownRichText(String.from(fence.info).toUpper().toString()))
            index += 1
            while index < lines.count
            {
                let close = markdownFence(lines[index])
                if close.found and close.marker == fence.marker
                {
                    index += 1
                    break
                }

                code  += markdownRichText(lines[index])
                code  += "\n"
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
                math  = Latin1.trim(line[0 until @countof(line) - 2])
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
                    math  += Latin1.trim(lines[index])
                    index += 1
                }

                if index < lines.count do
                    index += 1
            }

            appendMarkdownBlock(&result, .Math, #move math)
            continue
        }

        if Utf8.startsWith(trimmed, "\\[")
        {
            var math: String
            var line = Latin1.trim(trimmed[2 to])
            if Utf8.endsWith(line, "\\]")
            {
                math  = Latin1.trim(line[0 until @countof(line) - 2])
                index += 1
            }
            else
            {
                if @countof(line) do
                    math += line
                index += 1
                while index < lines.count and !Utf8.startsWith(Latin1.trim(lines[index]), "\\]")
                {
                    if !math.isEmpty() do
                        math += "\n"
                    math  += Latin1.trim(lines[index])
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
            appendMarkdownBlock(&result, markdownVisualHeading(heading.level), renderMarkdownInline(heading.text, references.toSlice()))
            index += 1
            continue
        }

        if index + 1 < lines.count
        {
            let setext = markdownSetextLevel(lines[index + 1])
            if setext
            {
                appendMarkdownBlock(&result, markdownVisualHeading(setext), renderMarkdownInline(trimmed, references.toSlice()))
                index += 2
                continue
            }

            if Utf8.contains(raw, '|'rune) and markdownTableSeparator(lines[index + 1])
            {
                var table = String.from(raw)
                table += "\n"
                table += lines[index + 1]
                index += 2
                while index < lines.count and Utf8.contains(lines[index], '|'rune) and @countof(Latin1.trim(lines[index]))
                {
                    table += "\n"
                    table += lines[index]
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
                    list    += "☐ "
                    content = content[4 to]
                }
                elif Utf8.startsWith(content, "[x] ") or Utf8.startsWith(content, "[X] ")
                {
                    list    += "<p1>☒</p> "
                    content = content[4 to]
                }

                list  += renderMarkdownInline(content, references.toSlice())
                list  += "\n"
                index += 1
            }

            appendMarkdownBlock(&result, .List, #move list)
            continue
        }

        if Utf8.startsWith(trimmed, ">")
        {
            var quote: String
            var quoteKind = MarkdownBlockKind.Quote
            while index < lines.count and Utf8.startsWith(Latin1.trim(lines[index]), ">")
            {
                var content = Latin1.trim(Latin1.trim(lines[index])[1 to])
                if quote.isEmpty() and Utf8.startsWith(content, "[!")
                {
                    let close = Utf8.indexOf(content, ']'rune, 2)
                    if close != Swag.U64.Max
                    {
                        quoteKind = markdownAlertKind(content[2 until close])
                        if quoteKind != .Quote
                        {
                            quote   += Format.toString("<b><p1>%</p></b>", markdownAlertTitle(quoteKind))
                            content  = Latin1.trim(content[close + 1 to])
                        }
                    }
                }
                if @countof(content)
                {
                    if !quote.isEmpty() do
                        quote += "\n"
                    quote += renderMarkdownInline(content, references.toSlice())
                }
                index += 1
            }

            appendMarkdownBlock(&result, quoteKind, #move quote)
            continue
        }

        var paragraph = String.from(trimmed)
        index += 1
        while index < lines.count
        {
            let next = Latin1.trim(lines[index])
            let nextDefinition = markdownReferenceDefinition(lines[index])
            if !@countof(next) or markdownHeading(lines[index]).level or markdownRule(lines[index]) or markdownListItem(lines[index]).found or Utf8.startsWith(next, ">") or Utf8.startsWith(next, "$$") or Utf8.startsWith(next, "\\[") or Utf8.compare(next, "[TOC]", .Latin1NoCase) == 0 or nextDefinition.found or markdownFence(lines[index]).found do
                break
            if index + 1 < lines.count and markdownSetextLevel(lines[index + 1]) do
                break
            paragraph += markdownHardBreak(lines[index - 1]) ? "\n" : " "
            paragraph += next
            index     += 1
        }

        appendMarkdownBlock(&result, .Paragraph, renderMarkdownInline(paragraph.toString(), references.toSlice()))
    }

    return result
}
