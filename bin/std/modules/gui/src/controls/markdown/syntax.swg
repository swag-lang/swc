#global internal
#global namespace Markdown

using Core

private func findClosing(text: string, marker: string, start: u64, wordBoundaryClose = false)->u64
{
    let markerLength = marker.count
    var index        = start
    while index < text.count
    {
        if text[index] != marker[0]
        {
            index += 1
            continue
        }

        var runEnd = index + 1
        while runEnd < text.count and text[runEnd] == marker[0] do
            runEnd += 1
        let runLength = runEnd - index

        // Underscore emphasis never closes inside a word, so 'foo_bar' in '_foo_bar_' stays plain
        // and the emphasis closes on the word-final run instead.
        let boundary = !wordBoundaryClose or runEnd >= text.count or !Latin1.isWord(text[runEnd])
        if markerLength == 1 and runLength & 1 and boundary do
            return runEnd - 1
        if markerLength > 1 and runLength >= markerLength and boundary do
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
    if start >= text.count or Latin1.isSpace(text[start]) do
        return Swag.U64.Max

    var index = start
    while index < text.count
    {
        if text[index] != '$'
        {
            index += 1
            continue
        }

        let escaped     = index > start and text[index - 1] == '\\'
        let spaceBefore = index == start or Latin1.isSpace(text[index - 1])
        let digitAfter  = index + 1 < text.count and Latin1.isDigit(text[index + 1])
        if !escaped and !spaceBefore and !digitAfter do
            return index
        index += 1
    }

    return Swag.U64.Max
}

private func findBareUrlEnd(text: string, start: u64)->u64
{
    var end = start
    while end < text.count and !Latin1.isSpace(text[end]) and text[end] != '<' and text[end] != '>' do
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

struct LinkTargetInfo
{
    found:  bool
    target: string = ""
    end:    u64
}

// Parses an inline link destination starting right after its opening parenthesis: an optional
// '<...>' form, balanced or backslash-escaped parentheses, and an optional quoted title that
// never joins the activated target. `end` is the index of the closing parenthesis.
func parseLinkTarget(text: string, start: u64)->LinkTargetInfo
{
    var result: retval
    var index = start
    while index < text.count and text[index] == ' ' do
        index += 1

    var targetStart = index
    var targetEnd   = index
    if index < text.count and text[index] == '<'
    {
        targetStart = index + 1
        let close = Utf8.indexOf(text, '>'rune, targetStart)
        if close == Swag.U64.Max do
            return result
        targetEnd = close
        index     = close + 1
    }
    else
    {
        var depth = 0
        while index < text.count
        {
            let value = text[index]
            if value == '\\' and index + 1 < text.count
            {
                index += 2
                continue
            }

            if value == '(' do
                depth += 1
            elif value == ')'
            {
                if !depth do
                    break
                depth -= 1
            }
            elif value == ' ' or value == '\t' do
                break
            index += 1
        }

        targetEnd = index
    }

    while index < text.count and (text[index] == ' ' or text[index] == '\t') do
        index += 1

    if index < text.count and (text[index] == '"' or text[index] == '\'')
    {
        let quote = text[index]
        var close = index + 1
        while close < text.count and text[close] != quote do
            close += 1
        if close >= text.count do
            return result
        index = close + 1
        while index < text.count and (text[index] == ' ' or text[index] == '\t') do
            index += 1
    }

    if index >= text.count or text[index] != ')' do
        return result
    result.found  = true
    result.target = text[targetStart until targetEnd]
    result.end    = index
    return result
}

// Extracts the destination of a reference definition's raw value, dropping an optional quoted
// title so '[guide]: url "Title"' activates the same target as its inline form.
func referenceTarget(value: string)->string
{
    if value.count and value[0] == '<'
    {
        let close = Utf8.indexOf(value, '>'rune, 1)
        if close != Swag.U64.Max do
            return value[1 until close]
    }

    var end = 0'u64
    while end < value.count and value[end] != ' ' and value[end] != '\t' do
        end += 1
    return value[0 until end]
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
    if trimmed.count < 4 or trimmed[0] != '[' do
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

private struct HtmlInlineInfo
{
    found: bool
    eat:   u64
    text:  String
}

private func appendHtmlInlineChildren(output: *String, document: const *HtmlDocument, node: u32, references: #null const [..] Reference)
{
    for child in document.children(node) do
        appendHtmlInlineNode(output, document, child, references)
}

// Translates the HTML parser's semantic tree into the smaller rich-text protocol understood by
// Markdown inline views. Layout-bearing HTML is kept as an Html block instead.
private func appendHtmlInlineNode(output: *String, document: const *HtmlDocument, node: u32, references: #null const [..] Reference)
{
    let current = document.constNode(node)
    if current.kind == .Text
    {
        output[] += renderInline(document.text(current.text), references, true)
        return
    }

    switch current.tag
    {
    case .Br:
        output[] += "\n"

    case .Wbr:
        return

    case .Img:
        let source = document.attribute(node, "src")
        let alt    = document.attribute(node, "alt")
        output[] += "<a><p3>[Image"
        if alt.count
        {
            output[] += ": "
            output[] += richText(alt)
        }

        output[] += "]</p></a><t>"
        output[] += richText(source)
        output[] += "</t>"

    case .A:
        output[] += "<a>"
        appendHtmlInlineChildren(output, document, node, references)
        output[] += "</a><t>"
        output[] += richText(document.attribute(node, "href"))
        output[] += "</t>"

    case .B, .Strong:
        output[] += "<b>"
        appendHtmlInlineChildren(output, document, node, references)
        output[] += "</b>"

    case .I, .Em, .Cite, .Dfn, .Var:
        output[] += "<i>"
        appendHtmlInlineChildren(output, document, node, references)
        output[] += "</i>"

    case .Del, .S:
        output[] += "<s>"
        appendHtmlInlineChildren(output, document, node, references)
        output[] += "</s>"

    case .Code, .Kbd, .Samp:
        output[] += "<c>"
        appendHtmlInlineChildren(output, document, node, references)
        output[] += "</c>"

    case .Mark:
        output[] += "<h>"
        appendHtmlInlineChildren(output, document, node, references)
        output[] += "</h>"

    case .Sub:
        output[] += "<sub>"
        appendHtmlInlineChildren(output, document, node, references)
        output[] += "</sub>"

    case .Sup:
        output[] += "<sup>"
        appendHtmlInlineChildren(output, document, node, references)
        output[] += "</sup>"

    default:
        appendHtmlInlineChildren(output, document, node, references)
    }
}

// Parses exactly one complete inline element at `start`. Feeding one UTF-8 character at a time
// lets the streaming HTML parser identify the matching close without duplicating its quote,
// entity, raw-text, void-element, or nesting rules here.
private func parseHtmlInline(text: string, start: u64, references: #null const [..] Reference)->HtmlInlineInfo
{
    var result: retval
    // A fragment: inline markup belongs to the Markdown paragraph around it, not to a document.
    var document = HtmlDocument.create()
    var parser: HtmlParser
    parser.start(&document, .Fragment)

    var end = start
    while end < text.count
    {
        let decoded = Utf8.decodeRune(text[end to])
        parser.feed(text[end until end + decoded.eat])
        end += decoded.eat
        if parser.hasPendingSource() or parser.stack.count != 1 or document.childCount(0) != 1 do
            continue

        let node = document.constNode(0).firstChild
        let root = document.constNode(node)
        if root.kind != .Element or root.tag == .Unknown or HtmlParser.startsBlock(root.tag) do
            return result

        result.found = true
        result.eat   = end - start
        appendHtmlInlineNode(&result.text, &document, node, references)
        return result
    }

    return result
}

func renderInline(text: string, references: #null const [..] Reference = null, parsedHtmlText = false)->String
{
    var result: retval
    var index = 0'u64
    while index < text.count
    {
        if text[index] == '\\' and index + 1 < text.count and text[index + 1] == '('
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

        if text[index] == '\\' and index + 1 < text.count
        {
            result += richText(text[index + 1 until index + 2])
            index  += 2
            continue
        }

        if text[index] == '!' and index + 1 < text.count and text[index + 1] == '['
        {
            let labelEnd = Utf8.indexOf(text, ']'rune, index + 2)
            if labelEnd != Swag.U64.Max and labelEnd + 1 < text.count and text[labelEnd + 1] == '('
            {
                let target = parseLinkTarget(text, labelEnd + 2)
                if target.found
                {
                    result += "<a><p3>[Image: "
                    result += richText(text[index + 2 until labelEnd], true)
                    result += "]</p></a><t>"
                    result += richText(target.target)
                    result += "</t>"
                    index  = target.end + 1
                    continue
                }
            }

            if labelEnd != Swag.U64.Max and labelEnd + 1 < text.count and text[labelEnd + 1] == '['
            {
                let referenceEnd = Utf8.indexOf(text, ']'rune, labelEnd + 2)
                if referenceEnd != Swag.U64.Max
                {
                    let referenceName = referenceEnd == labelEnd + 2 ? text[index + 2 until labelEnd] : text[labelEnd + 2 until referenceEnd]
                    let target        = resolveReferenceTarget(references, referenceName)
                    if target.count
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

            if labelEnd != Swag.U64.Max and labelEnd + 1 < text.count and text[labelEnd + 1] == '('
            {
                let target = parseLinkTarget(text, labelEnd + 2)
                if target.found
                {
                    result += "<a>"
                    result += renderInline(text[index + 1 until labelEnd], references, parsedHtmlText)
                    result += "</a><t>"
                    result += richText(target.target)
                    result += "</t>"
                    index  = target.end + 1
                    continue
                }
            }

            if labelEnd != Swag.U64.Max
            {
                var referenceEnd  = labelEnd
                var referenceName = text[index + 1 until labelEnd]
                if labelEnd + 1 < text.count and text[labelEnd + 1] == '['
                {
                    referenceEnd = Utf8.indexOf(text, ']'rune, labelEnd + 2)
                    if referenceEnd != Swag.U64.Max and referenceEnd > labelEnd + 2 do
                        referenceName = text[labelEnd + 2 until referenceEnd]
                }

                if referenceEnd != Swag.U64.Max
                {
                    let target = resolveReferenceTarget(references, referenceName)
                    if target.count
                    {
                        result += "<a>"
                        result += renderInline(text[index + 1 until labelEnd], references, parsedHtmlText)
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
            if parsedHtmlText
            {
                result += "<<"
                index  += 1
                continue
            }

            let html = parseHtmlInline(text, index, references)
            if html.found
            {
                result += html.text
                index  += html.eat
                continue
            }

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

        if index + 1 < text.count and text[index] == '~' and text[index + 1] == '~'
        {
            let end = Utf8.indexOf(text, "~~", index + 2)
            if end != Swag.U64.Max
            {
                result += "<s>"
                result += renderInline(text[index + 2 until end], references, parsedHtmlText)
                result += "</s>"
                index  = end + 2
                continue
            }
        }

        if index + 1 < text.count and text[index] == '=' and text[index + 1] == '='
        {
            let end = Utf8.indexOf(text, "==", index + 2)
            if end != Swag.U64.Max
            {
                result += "<h>"
                result += renderInline(text[index + 2 until end], references, parsedHtmlText)
                result += "</h>"
                index  = end + 2
                continue
            }
        }

        if index + 2 < text.count and ((text[index] == '*' and text[index + 1] == '*' and text[index + 2] == '*') or (text[index] == '_' and text[index + 1] == '_' and text[index + 2] == '_' and canOpenUnderscore(text, index)))
        {
            let marker = text[index until index + 3]
            let end    = findClosing(text, marker, index + 3, wordBoundaryClose: text[index] == '_')
            if end != Swag.U64.Max and end > index + 3
            {
                result += "<b><i>"
                result += renderInline(text[index + 3 until end], references, parsedHtmlText)
                result += "</i></b>"
                index  = end + 3
                continue
            }
        }

        if index + 1 < text.count and ((text[index] == '*' and text[index + 1] == '*') or (text[index] == '_' and text[index + 1] == '_' and canOpenUnderscore(text, index)))
        {
            let marker = text[index until index + 2]
            let end    = findClosing(text, marker, index + 2, wordBoundaryClose: text[index] == '_')
            if end != Swag.U64.Max
            {
                result += "<b>"
                result += renderInline(text[index + 2 until end], references, parsedHtmlText)
                result += "</b>"
                index  = end + 2
                continue
            }
        }

        if text[index] == '*' or (text[index] == '_' and canOpenUnderscore(text, index))
        {
            let marker = text[index until index + 1]
            let end    = findClosing(text, marker, index + 1, wordBoundaryClose: text[index] == '_')
            if end != Swag.U64.Max and end > index + 1
            {
                result += "<i>"
                result += renderInline(text[index + 1 until end], references, parsedHtmlText)
                result += "</i>"
                index  = end + 1
                continue
            }
        }

        if text[index] == '`'
        {
            var open = index + 1
            while open < text.count and text[open] == '`' do
                open += 1
            let runLength = open - index

            // A code span closes on a backtick run of the same length, so a longer opener can
            // quote literal backticks.
            var end    = Swag.U64.Max
            var search = open
            while search < text.count
            {
                if text[search] != '`'
                {
                    search += 1
                    continue
                }

                var runEnd = search + 1
                while runEnd < text.count and text[runEnd] == '`' do
                    runEnd += 1
                if runEnd - search == runLength
                {
                    end = search
                    break
                }

                search = runEnd
            }

            if end != Swag.U64.Max
            {
                var content = text[open until end]
                if content.count >= 2 and content[0] == ' ' and content[content.count - 1] == ' ' and (Latin1.trim(content)).count do
                    content = content[1 until content.count - 1]
                result += "<c>"
                result += richText(content)
                result += "</c>"
                index  = end + runLength
                continue
            }

            result += richText(text[index until open])
            index  = open
            continue
        }

        if text[index] == '^'
        {
            let end = Utf8.indexOf(text, '^'rune, index + 1)
            if end != Swag.U64.Max and end > index + 1
            {
                result += "<sup>"
                result += renderInline(text[index + 1 until end], references, parsedHtmlText)
                result += "</sup>"
                index  = end + 1
                continue
            }
        }

        if text[index] == '~' and (index + 1 >= text.count or text[index + 1] != '~')
        {
            let end = Utf8.indexOf(text, '~'rune, index + 1)
            if end != Swag.U64.Max and end > index + 1
            {
                result += "<sub>"
                result += renderInline(text[index + 1 until end], references, parsedHtmlText)
                result += "</sub>"
                index  = end + 1
                continue
            }
        }

        if text[index] == '&'
        {
            if parsedHtmlText
            {
                result += "&"
                index  += 1
                continue
            }

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
    length: u32
    info:   string = ""
}

func parseHeading(line: string)->HeadingInfo
{
    var result: retval
    let trimmed = Latin1.trim(line)
    while result.level < trimmed.count and result.level < 6 and trimmed[result.level] == '#' do
        result.level += 1
    if !result.level or result.level >= trimmed.count or trimmed[result.level] != ' '
    {
        result.level = 0
        return result
    }

    var end = trimmed.count
    while end and (trimmed[end - 1] == ' ' or trimmed[end - 1] == '#') do
        end -= 1
    result.text = trimmed[result.level + 1 until end]
    return result
}

func setextLevel(line: string)->u32
{
    let trimmed = Latin1.trim(line)
    if trimmed.count < 3 do
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
    let count = line.count
    if count >= 2 and line[count - 1] == ' ' and line[count - 2] == ' ' do
        return true

    // A backslash ending the line is a hard break too, unless it is itself escaped.
    return count >= 1 and line[count - 1] == '\\' and (count == 1 or line[count - 2] != '\\')
}

func parseListItem(line: string)->ListInfo
{
    var result: retval
    var index = 0'u64
    while index < line.count and (line[index] == ' ' or line[index] == '\t')
    {
        result.indent += line[index] == '\t' ? 4 : 1
        index         += 1
    }

    if index >= line.count do
        return result

    if (line[index] == '-' or line[index] == '*' or line[index] == '+') and index + 1 < line.count and line[index + 1] == ' '
    {
        result.found         = true
        result.content       = line[index + 2 to]
        result.contentIndent = result.indent + 2
        return result
    }

    let digitStart = index
    while index < line.count and Latin1.isDigit(line[index]) do
        index += 1
    if index > digitStart and index + 1 < line.count and (line[index] == '.' or line[index] == ')') and line[index + 1] == ' '
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
    if trimmed.count < 3 or (trimmed[0] != '`' and trimmed[0] != '~') do
        return result

    var run = 1'u64
    while run < trimmed.count and trimmed[run] == trimmed[0] do
        run += 1
    if run < 3 do
        return result
    result.found  = true
    result.marker = trimmed[0]
    result.length = cast(u32) run
    result.info   = Latin1.trim(trimmed[run to])
    return result
}
