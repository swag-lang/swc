using Core

enum HtmlBlockKind
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
    Details
    Rule
}

struct HtmlBlock
{
    kind:  HtmlBlockKind
    text:  String
    style: HtmlCssStyle
}

private func htmlBlockKind(name: string)->HtmlBlockKind
{
    switch name
    {
    case "h1": return .Heading1
    case "h2": return .Heading2
    case "h3": return .Heading3
    case "h4": return .Heading4
    case "h5": return .Heading5
    case "h6": return .Heading6
    case "ul", "ol": return .List
    case "blockquote": return .Quote
    case "pre": return .Code
    case "table": return .Table
    case "details": return .Details
    case "hr": return .Rule
    default: return .Paragraph
    }
}

private func htmlIsBlock(name: string)->bool
{
    switch name
    {
    case "h1", "h2", "h3", "h4", "h5", "h6", "p", "ul", "ol", "blockquote", "pre", "table", "details", "figure", "hr": return true
    }
    return false
}

func parseHtmlBlocks(source: string, rules: const [..] HtmlCssRule)->Array'HtmlBlock
{
    var result: retval
    var index = 0'u64
    while index < @countof(source)
    {
        let open = Utf8.indexOf(source, '<'rune, index)
        if open == Swag.U64.Max do
            break
        let close = Utf8.indexOf(source, '>'rune, open + 1)
        if close == Swag.U64.Max do
            break

        let tag  = source[open + 1 until close]
        let name = htmlTagName(tag)
        if name.isEmpty() or tag[0] == '/'
        {
            index = close + 1
            continue
        }
        if name == "script" or name == "style" or name == "head"
        {
            let closing = Format.toString("</%", name)
            let end = Utf8.indexOf(source, closing.toString(), close + 1, .Latin1NoCase)
            if end == Swag.U64.Max do
                break
            let endClose = Utf8.indexOf(source, '>'rune, end)
            index = endClose == Swag.U64.Max ? @countof(source) : endClose + 1
            continue
        }
        if !htmlIsBlock(name.toString())
        {
            index = close + 1
            continue
        }

        var fragmentEnd = close + 1
        if name != "hr"
        {
            let closing = Format.toString("</%", name)
            let end = Utf8.indexOf(source, closing.toString(), close + 1, .Latin1NoCase)
            if end == Swag.U64.Max
            {
                index = close + 1
                continue
            }
            let endClose = Utf8.indexOf(source, '>'rune, end)
            fragmentEnd = endClose == Swag.U64.Max ? @countof(source) : endClose + 1
        }

        let kind = htmlBlockKind(name.toString())
        let rendered = kind == .Rule ? String.from("────────────") : HtmlTextRenderer.render(source[open until fragmentEnd])
        let text = String.from(Latin1.trim(rendered.toString()))
        if !text.isEmpty()
        {
            var block: HtmlBlock
            block.kind  = kind
            block.text  = #move text
            block.style = htmlCssStyle(tag, name.toString(), rules)
            result.add(#move block)
        }
        index = fragmentEnd
    }

    if result.isEmpty()
    {
        let rendered = HtmlTextRenderer.render(source)
        if !rendered.isEmpty()
        {
            var block: HtmlBlock
            block.kind = .Paragraph
            block.text = #move rendered
            result.add(#move block)
        }
    }
    return result
}

func htmlBodyCssStyle(source: string, rules: const [..] HtmlCssRule)->HtmlCssStyle
{
    let body = Utf8.indexOf(source, "<body", 0, .Latin1NoCase)
    if body == Swag.U64.Max do
        return htmlCssStyle("", "body", rules)
    let close = Utf8.indexOf(source, '>'rune, body + 5)
    if close == Swag.U64.Max do
        return htmlCssStyle("", "body", rules)
    return htmlCssStyle(source[body + 1 until close], "body", rules)
}
