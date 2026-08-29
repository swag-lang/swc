#global public
#global namespace Markdown

using Core

#[Swag.NoDoc]
enum BlockKind
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
    Html
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
struct Block
{
    kind: BlockKind
    text: String
}

private func visualHeadingKind(level: u32)->BlockKind
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

private func appendBlock(blocks: *Array'Block, kind: BlockKind, text: String)
{
    if text.isEmpty() do
        return
    var block: Block
    block.kind = kind
    block.text = #move text
    blocks.add(#move block)
}

private func alertKind(name: string)->BlockKind
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

private func alertTitle(kind: BlockKind)->string
{
    switch kind
    {
    case .AlertNote:      return strings().markdown_AlertNote
    case .AlertTip:       return strings().markdown_AlertTip
    case .AlertImportant: return strings().markdown_AlertImportant
    case .AlertWarning:   return strings().markdown_AlertWarning
    case .AlertCaution:   return strings().markdown_AlertCaution
    default:              return ""
    }
}

// One live ordinal of the ordered list being rendered, per indentation level.
private struct OrderedCounter
{
    indent: u32
    value:  u64
}

// Reports whether a line opens an HTML block by asking the HTML parser what element the source
// actually creates. Inline phrasing tags stay in Markdown paragraphs and are handled by
// renderInline.
private func isHtmlBlockStart(line: string)->bool
{
    let trimmed = Latin1.trim(line)
    if !@countof(trimmed) or trimmed[0] != '<' do
        return false

    // A fragment: this asks the HTML parser what the line starts, not what document it makes.
    var document = HtmlDocument.create()
    var parser: HtmlParser
    parser.start(&document, .Fragment)
    parser.feed(trimmed)
    parser.finish()

    for child in document.children(0)
    {
        let node = document.constNode(child)
        if node.kind != .Element or node.tag == .Unknown do
            continue
        if HtmlParser.startsBlock(node.tag) do
            return true

        switch node.tag
        {
        case .Html, .Head, .Body, .Base, .Link, .Meta, .Style, .Img, .Picture: return true
        default: continue
        }
    }

    return false
}

internal func parseBlocks(source: string)->Array'Block
{
    var result:     retval
    let lines = Tokenize.splitLines(source)
    var index = 0'u64
    var references: Array'Reference

    for line in lines
    {
        let definition = parseReferenceDefinition(line)
        if definition.found and !definition.footnote
        {
            var reference: Reference
            reference.name   = definition.name
            reference.target = referenceTarget(definition.value)
            references.add(#move reference)
        }
    }

    if lines.count and Latin1.trim(lines[0]) == "---"
    {
        var metadata: String
        index = 1
        while index < lines.count and Latin1.trim(lines[index]) != "---"
        {
            metadata += richText(lines[index])
            metadata += "\n"
            index    += 1
        }

        if index < lines.count do
            index += 1
        appendBlock(&result, .Metadata, #move metadata)
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

        let definition = parseReferenceDefinition(raw)
        if definition.found
        {
            if definition.footnote
            {
                var footnote = Format.toString("<p3>%.</p> ", richText(definition.name, true))
                footnote += renderInline(definition.value, references.toSlice())
                appendBlock(&result, .Footnote, #move footnote)
            }

            index += 1
            continue
        }

        if Utf8.compare(trimmed, "[TOC]", .Latin1NoCase) == 0
        {
            var contents: String
            for line in lines
            {
                let entry = parseHeading(line)
                if !entry.level do
                    continue
                for entry.level - 1 do
                    contents += "  "
                contents += renderInline(entry.text, references.toSlice())
                contents += "\n"
            }

            appendBlock(&result, .TableOfContents, #move contents)
            index += 1
            continue
        }

        let fence = parseFence(raw)
        if fence.found
        {
            var code: String
            if @countof(fence.info) do
                code += Format.toString("<p3>%</p>\n", richText(String.from(fence.info).toUpper().toString()))
            index += 1
            while index < lines.count
            {
                // A closing fence carries no info and is at least as long as its opener, so a
                // longer fence can display a shorter one as content.
                let close = parseFence(lines[index])
                if close.found and close.marker == fence.marker and close.length >= fence.length and !@countof(close.info)
                {
                    index += 1
                    break
                }

                code  += richText(lines[index])
                code  += "\n"
                index += 1
            }

            appendBlock(&result, .Code, #move code)
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

            appendBlock(&result, .Math, #move math)
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

            appendBlock(&result, .Math, #move math)
            continue
        }

        if isHtmlBlockStart(raw)
        {
            var html: String
            while index < lines.count and @countof(Latin1.trim(lines[index]))
            {
                if !html.isEmpty() do
                    html += "\n"
                html  += lines[index]
                index += 1
            }

            appendBlock(&result, .Html, #move html)
            continue
        }

        let heading = parseHeading(raw)
        if heading.level
        {
            appendBlock(&result, visualHeadingKind(heading.level), renderInline(heading.text, references.toSlice()))
            index += 1
            continue
        }

        if index + 1 < lines.count
        {
            let setext = setextLevel(lines[index + 1])
            if setext
            {
                appendBlock(&result, visualHeadingKind(setext), renderInline(trimmed, references.toSlice()))
                index += 2
                continue
            }

            if Utf8.contains(raw, '|'rune) and isTableSeparator(lines[index + 1])
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

                appendBlock(&result, .Table, #move table)
                continue
            }
        }

        if isRule(raw)
        {
            result.add(Block{.Rule, ""})
            index += 1
            continue
        }

        let item = parseListItem(raw)
        if item.found
        {
            var list:     String
            var counters: Array'OrderedCounter
            while index < lines.count
            {
                let current = parseListItem(lines[index])
                if !current.found do
                    break

                var content  = String.from(current.content)
                var previous = lines[index]
                index += 1
                while index < lines.count
                {
                    let continuation = parseListItem(lines[index])
                    let next         = Latin1.trim(lines[index])
                    if !@countof(next) or continuation.found or continuation.indent < current.contentIndent or parseFence(lines[index]).found do
                        break

                    content  += hasHardBreak(previous) ? "\n" : " "
                    content  += next
                    previous = lines[index]
                    index    += 1
                }

                for current.indent do
                    list += " "

                // Markers remain semantic atoms so wrapping can hang beneath the item text and
                // geometric markers never depend on optional typeface glyphs.
                if Utf8.startsWith(content, "[ ] ")
                {
                    list += "<p1><lu>*</lu></p> "
                    content.remove(0, 4)
                }
                elif Utf8.startsWith(content, "[x] ") or Utf8.startsWith(content, "[X] ")
                {
                    list += "<p1><lc>*</lc></p> "
                    content.remove(0, 4)
                }
                elif current.ordered
                {
                    // Ordinals count from the first written marker and advance by position, so
                    // '1. 1. 1.' renders 1, 2, 3; a level popped by a shallower item restarts.
                    while counters.count and counters.back().indent > current.indent do
                        counters.removeBack()
                    if counters.count and counters.back().indent == current.indent do
                        counters.backPtr().value += 1
                    else
                    {
                        let parsed = catch StrConv.parseU64(current.marker) as parseError
                        counters.add({current.indent, parseError == null ? parsed.value : 1})
                    }

                    list += Format.toString("<p3><lm>%.</lm></p> ", counters.back().value)
                }
                else
                {
                    while counters.count and counters.back().indent >= current.indent do
                        counters.removeBack()
                    list += "<p1><lb>*</lb></p> "
                }

                list += renderInline(content.toString(), references.toSlice())
                list += "\n"
            }

            appendBlock(&result, .List, #move list)
            continue
        }

        if Utf8.startsWith(trimmed, ">")
        {
            var quote: String
            var quoteKind = BlockKind.Quote
            while index < lines.count and Utf8.startsWith(Latin1.trim(lines[index]), ">")
            {
                var content = Latin1.trim(Latin1.trim(lines[index])[1 to])
                if quote.isEmpty() and Utf8.startsWith(content, "[!")
                {
                    let close = Utf8.indexOf(content, ']'rune, 2)
                    if close != Swag.U64.Max
                    {
                        quoteKind = alertKind(content[2 until close])
                        if quoteKind != .Quote
                        {
                            quote   += Format.toString("<b><p1>%</p></b>", alertTitle(quoteKind))
                            content = Latin1.trim(content[close + 1 to])
                        }
                    }
                }

                if @countof(content)
                {
                    if !quote.isEmpty() do
                        quote += "\n"
                    quote += renderInline(content, references.toSlice())
                }

                index += 1
            }

            appendBlock(&result, quoteKind, #move quote)
            continue
        }

        var paragraph = String.from(trimmed)
        index += 1
        while index < lines.count
        {
            let next           = Latin1.trim(lines[index])
            let nextDefinition = parseReferenceDefinition(lines[index])
            if !@countof(next) or parseHeading(lines[index]).level or isRule(lines[index]) or parseListItem(lines[index]).found or Utf8.startsWith(next, ">") or Utf8.startsWith(next, "$$") or Utf8.startsWith(next, "\\[") or Utf8.compare(next, "[TOC]", .Latin1NoCase) == 0 or nextDefinition.found or parseFence(lines[index]).found do
                break
            if index + 1 < lines.count and setextLevel(lines[index + 1]) do
                break
            paragraph += hasHardBreak(lines[index - 1]) ? "\n" : " "
            paragraph += next
            index     += 1
        }

        appendBlock(&result, .Paragraph, renderInline(paragraph.toString(), references.toSlice()))
    }

    return result
}
