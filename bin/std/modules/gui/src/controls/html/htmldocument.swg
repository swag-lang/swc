#global public

using Core

#[Swag.NoDoc]
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

#[Swag.NoDoc]
struct HtmlBlock
{
    kind:  HtmlBlockKind
    text:  String
    style: HtmlCssStyle
}

#[Swag.NoDoc]
struct HtmlBlockParseResult
{
    blocks:   Array'HtmlBlock
    consumed: u64
}

private func htmlBlockKind(tag, name: string)->HtmlBlockKind
{
    if name == "div"
    {
        let className = htmlAttribute(tag, "class")
        if Utf8.contains(className.toString(), "code-block") do
            return .Code
    }

    switch name
    {
    case "h1":         return .Heading1
    case "h2":         return .Heading2
    case "h3":         return .Heading3
    case "h4":         return .Heading4
    case "h5":         return .Heading5
    case "h6":         return .Heading6
    case "ul", "ol":   return .List
    case "blockquote": return .Quote
    case "pre":        return .Code
    case "table":      return .Table
    case "details":    return .Details
    case "hr":         return .Rule
    default:           return .Paragraph
    }
}

private func htmlIsBlock(name: string)->bool
{
    switch name
    {
    case "h1", "h2", "h3", "h4", "h5", "h6", "p", "div", "ul", "ol", "blockquote", "pre", "table", "details", "figure", "hr": return true
    }

    return false
}

// A document control renders the document, not the surrounding web-site application. Hidden
// containers must be skipped as a whole as well: merely ignoring their opening tag would still
// let a nested paragraph escape into the visible block stream.
private func htmlSkipContainer(name: string)->bool
{
    switch name
    {
    case "script", "style", "head", "template", "iframe", "object", "header", "nav", "aside", "footer": return true
    }

    return false
}

internal func htmlBlockStartBefore(source: string, target: u64)->u64
{
    var result = 0'u64
    var index  = 0'u64
    let end    = Math.min(target, @countof(source))
    while index < end
    {
        let open = Utf8.indexOf(source, '<'rune, index)
        if open == Swag.U64.Max or open >= end do
            break
        let close = Utf8.indexOf(source, '>'rune, open + 1)
        if close == Swag.U64.Max or close >= end do
            break
        let tag  = source[open + 1 until close]
        let name = htmlTagName(tag)
        if !name.isEmpty() and tag[0] != '/' and htmlIsBlock(name.toString()) do
            result = open
        index = close + 1
    }

    return result
}

internal func parseHtmlBlockChunk(source: string, rules: const [..] HtmlCssRule, final: bool)->HtmlBlockParseResult
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
            index           = close + 1
            result.consumed = index
            continue
        }

        if htmlSkipContainer(name.toString())
        {
            let closing = Format.toString("</%", name)
            let end     = Utf8.indexOf(source, closing.toString(), close + 1, .Latin1NoCase)
            if end == Swag.U64.Max do
                break
            let endClose = Utf8.indexOf(source, '>'rune, end)
            index           = endClose == Swag.U64.Max ? @countof(source) : endClose + 1
            result.consumed = index
            continue
        }

        if !htmlIsBlock(name.toString())
        {
            index           = close + 1
            result.consumed = index
            continue
        }

        var fragmentEnd = close + 1
        if name != "hr"
        {
            let closing = Format.toString("</%", name)
            let end     = Utf8.indexOf(source, closing.toString(), close + 1, .Latin1NoCase)
            if end == Swag.U64.Max
            {
                index = close + 1
                continue
            }

            let endClose = Utf8.indexOf(source, '>'rune, end)
            fragmentEnd = endClose == Swag.U64.Max ? @countof(source) : endClose + 1
        }

        let kind     = htmlBlockKind(tag, name.toString())
        let rendered = kind == .Rule ? String.from("────────────") : HtmlTextRenderer.render(source[open until fragmentEnd])
        let text     = String.from(Latin1.trim(rendered.toString()))
        if !text.isEmpty()
        {
            var block: HtmlBlock
            block.kind  = kind
            block.text  = #move text
            block.style = htmlCssStyle(tag, name.toString(), rules)
            result.blocks.add(#move block)
        }

        index           = fragmentEnd
        result.consumed = index
    }

    if final and result.consumed < @countof(source)
    {
        let rendered = HtmlTextRenderer.render(source[result.consumed to])
        if !rendered.isEmpty()
        {
            var block: HtmlBlock
            block.kind = .Paragraph
            block.text = #move rendered
            result.blocks.add(#move block)
        }

        result.consumed = @countof(source)
    }

    return result
}

internal func parseHtmlBlocks(source: string, rules: const [..] HtmlCssRule)->Array'HtmlBlock
{
    return parseHtmlBlockChunk(source, rules, final: true).blocks
}

internal func htmlBodyCssStyle(source: string, rules: const [..] HtmlCssRule)->HtmlCssStyle
{
    let body = Utf8.indexOf(source, "<body", 0, .Latin1NoCase)
    if body == Swag.U64.Max do
        return htmlCssStyle("", "body", rules)
    let close = Utf8.indexOf(source, '>'rune, body + 5)
    if close == Swag.U64.Max do
        return htmlCssStyle("", "body", rules)
    return htmlCssStyle(source[body + 1 until close], "body", rules)
}
