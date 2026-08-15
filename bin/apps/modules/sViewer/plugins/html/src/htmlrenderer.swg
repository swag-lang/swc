#global internal

using Core

internal func htmlTagName(tag: string)->String
{
    var result = String.from(Latin1.trim(tag))
    result = result.toLower()
    if result.isEmpty() do
        return result
    let space = Utf8.indexOfAny(result.toSlice(), " \t\r\n/")
    if space != Swag.U64.Max and result[0] != '/' do
        result = result[0 until space]
    elif result[0] == '/'
    {
        let after = Utf8.indexOfAny(result.toSlice(), " \t\r\n", 1)
        if after != Swag.U64.Max do
            result = result[0 until after]
    }
    return result
}

internal func htmlAttribute(tag, wanted: string)->String
{
    var index = 0'u64
    while index < @countof(tag) and !Latin1.isSpace(tag[index]) do
        index += 1

    while index < @countof(tag)
    {
        while index < @countof(tag) and Latin1.isSpace(tag[index]) do
            index += 1
        let nameStart = index
        while index < @countof(tag) and (Latin1.isLetterOrDigit(tag[index]) or tag[index] == '-' or tag[index] == '_' or tag[index] == ':') do
            index += 1
        if index == nameStart
        {
            index += 1
            continue
        }

        var name = String.from(tag[nameStart until index]).toLower()
        while index < @countof(tag) and Latin1.isSpace(tag[index]) do
            index += 1
        if index >= @countof(tag) or tag[index] != '='
        {
            if name == wanted do
                return ""
            continue
        }

        index += 1
        while index < @countof(tag) and Latin1.isSpace(tag[index]) do
            index += 1
        if index >= @countof(tag) do
            return ""

        let quote = tag[index]
        var valueStart = index
        var valueEnd   = index
        if quote == '\'' or quote == '"'
        {
            valueStart = index + 1
            valueEnd   = valueStart
            while valueEnd < @countof(tag) and tag[valueEnd] != quote do
                valueEnd += 1
            index = Math.min(valueEnd + 1, @countof(tag))
        }
        else
        {
            valueStart = index
            valueEnd   = index
            while valueEnd < @countof(tag) and !Latin1.isSpace(tag[valueEnd]) and tag[valueEnd] != '>' do
                valueEnd += 1
            index = valueEnd
        }

        if name == wanted do
            return viewerRichText(tag[valueStart until valueEnd], true)
    }
    return ""
}

private func htmlHasAttribute(tag, wanted: string)->bool
{
    let lower = String.from(tag).toLower()
    var start = 0'u64
    while start < lower.length
    {
        let found = Utf8.indexOf(lower.toString(), wanted, start)
        if found == Swag.U64.Max do
            return false
        let before = found == 0 or Latin1.isSpace(lower[found - 1])
        let end    = found + @countof(wanted)
        let after  = end == lower.length or Latin1.isSpace(lower[end]) or lower[end] == '=' or lower[end] == '/'
        if before and after do
            return true
        start = found + 1
    }
    return false
}

private struct HtmlRenderState
{
    output:       String
    pendingSpace: bool
    preDepth:     u32
    listOrdered:  Array'bool
    listCounter:  Array'u32
    tableCell:    u32
    anchorHref:   String
}

private impl HtmlRenderState
{
    mtd endsWithNewLine()->bool
    {
        return .output.isEmpty() or .output[.output.length - 1] == '\n'
    }

    mtd lineBreak(count = 1'u32)
    {
        .pendingSpace = false
        if .output.isEmpty() do
            return
        var existing = 0'u32
        var index = .output.length
        while index and .output[index - 1] == '\n'
        {
            existing += 1
            index    -= 1
        }
        for count - Math.min(count, existing) do
            .output += "\n"
    }

    mtd appendVisible(value: string)
    {
        if !@countof(value) do
            return
        if .pendingSpace and !.endsWithNewLine() do
            .output += " "
        .pendingSpace = false
        .output      += value
    }

    mtd appendText(value: string)
    {
        var index = 0'u64
        while index < @countof(value)
        {
            if !.preDepth and Latin1.isSpace(value[index])
            {
                .pendingSpace = !.endsWithNewLine()
                index += 1
                continue
            }

            if value[index] == '&'
            {
                let entity = viewerDecodedEntity(value, index)
                if !.preDepth and entity.value == " "
                {
                    .pendingSpace = !.endsWithNewLine()
                }
                else do
                    .appendVisible(entity.value.toString())
                index += entity.eat
                continue
            }

            if .preDepth
            {
                .output += viewerRichText(value[index until index + 1])
            }
            else do
                .appendVisible(viewerRichText(value[index until index + 1]))
            index += 1
        }
    }

    mtd openList(ordered: bool)
    {
        .lineBreak()
        .listOrdered.add(ordered)
        .listCounter.add(0)
    }

    mtd closeList()
    {
        if .listOrdered.count
        {
            .listOrdered.removeBack()
            .listCounter.removeBack()
        }
        .lineBreak(2)
    }

    mtd listItem()
    {
        .lineBreak()
        if .listOrdered.count > 1
        {
            for .listOrdered.count - 1 do
                .output += "  "
        }
        if .listOrdered.count and .listOrdered.back()
        {
            let index = .listCounter.count - 1
            .listCounter[index] += 1
            .output += Format.toString("  <p3>%.</p> ", .listCounter[index])
        }
        else do
            .output += "  <p1>•</p> "
    }
}

private func htmlHiddenElement(name: string)->bool
{
    return name == "script" or name == "style" or name == "head" or name == "template" or name == "iframe" or name == "object"
}

private func renderHtmlTag(state: *HtmlRenderState, tag: string)
{
    let name = htmlTagName(tag)
    switch name.toString()
    {
    case "b", "strong":              state.appendVisible("<b>")
    case "/b", "/strong":            state.appendVisible("</b>")
    case "i", "em", "cite", "var":  state.appendVisible("<i>")
    case "/i", "/em", "/cite", "/var": state.appendVisible("</i>")
    case "u", "ins":                 state.appendVisible("<u>")
    case "/u", "/ins":               state.appendVisible("</u>")

    case "h1": state.lineBreak(2); state.appendVisible("<p1><b>")
    case "h2": state.lineBreak(2); state.appendVisible("<p2><b>")
    case "h3", "h4", "h5", "h6": state.lineBreak(2); state.appendVisible("<p3><b>")
    case "/h1", "/h2", "/h3", "/h4", "/h5", "/h6": state.appendVisible("</b></p>"); state.lineBreak(2)

    case "p", "div", "section", "article", "header", "footer", "main", "nav", "aside": state.lineBreak()
    case "/p", "/div", "/section", "/article", "/header", "/footer", "/main", "/nav", "/aside": state.lineBreak(2)
    case "br": state.lineBreak()
    case "hr": state.lineBreak(); state.appendVisible("<p3>------------------------</p>"); state.lineBreak(2)

    case "ul": state.openList(false)
    case "ol": state.openList(true)
    case "/ul", "/ol": state.closeList()
    case "li": state.listItem()
    case "/li": state.lineBreak()

    case "blockquote": state.lineBreak(); state.appendVisible("<p3>></p> <i>")
    case "/blockquote": state.appendVisible("</i>"); state.lineBreak(2)

    case "pre": state.lineBreak(); state.appendVisible("<p2>"); state.preDepth += 1
    case "/pre":
        if state.preDepth do
            state.preDepth -= 1
        state.appendVisible("</p>")
        state.lineBreak(2)
    case "code", "kbd", "samp":
        if !state.preDepth do
            state.appendVisible("<p2>")
    case "/code", "/kbd", "/samp":
        if !state.preDepth do
            state.appendVisible("</p>")

    case "a":
        state.anchorHref = htmlAttribute(tag, "href")
        state.appendVisible("<u>")
    case "/a":
        state.appendVisible("</u>")
        if !state.anchorHref.isEmpty()
        {
            state.appendVisible(" (<url>")
            state.appendVisible(state.anchorHref.toString())
            state.appendVisible("</url>)")
            state.anchorHref.clear()
        }

    case "img":
        let alt = htmlAttribute(tag, "alt")
        let src = htmlAttribute(tag, "src")
        state.appendVisible("<p3>[Image")
        if !alt.isEmpty()
        {
            state.appendVisible(": ")
            state.appendVisible(alt.toString())
        }
        state.appendVisible("]</p>")
        if !src.isEmpty()
        {
            state.appendVisible(" (<url>")
            state.appendVisible(src.toString())
            state.appendVisible("</url>)")
        }

    case "table": state.lineBreak(2)
    case "/table": state.lineBreak(2)
    case "caption": state.lineBreak(); state.appendVisible("<p2><b>")
    case "/caption": state.appendVisible("</b></p>"); state.lineBreak()
    case "tr": state.lineBreak(); state.tableCell = 0
    case "/tr": state.lineBreak()
    case "th":
        if state.tableCell do
            state.appendVisible("  <p3>|</p>  ")
        state.appendVisible("<b>")
    case "/th": state.appendVisible("</b>"); state.tableCell += 1
    case "td":
        if state.tableCell do
            state.appendVisible("  <p3>|</p>  ")
    case "/td": state.tableCell += 1

    case "dl": state.lineBreak()
    case "/dl": state.lineBreak(2)
    case "dt": state.lineBreak(); state.appendVisible("<b>")
    case "/dt": state.appendVisible("</b>"); state.lineBreak()
    case "dd": state.appendVisible("    ")
    case "/dd": state.lineBreak()

    case "summary": state.lineBreak(); state.appendVisible("<p1>></p> <b>")
    case "/summary": state.appendVisible("</b>"); state.lineBreak()
    case "details", "/details": state.lineBreak()

    case "input":
        let inputType = htmlAttribute(tag, "type")
        if inputType == "checkbox"
        {
            state.appendVisible(htmlHasAttribute(tag, "checked") ? "[x]" : "[ ]")
        }
    }
}

struct HtmlTextRenderer
{
}

impl HtmlTextRenderer
{
    // Produces a fast, offline semantic rendering. Scripts, styles, embedded documents, and hidden
    // metadata never execute and never become visible text.
    func render(source: string)->String
    {
        var state: HtmlRenderState
        var index = 0'u64
        while index < @countof(source)
        {
            if source[index] != '<'
            {
                let next = Utf8.indexOf(source, '<'rune, index)
                let end  = next == Swag.U64.Max ? @countof(source) : next
                state.appendText(source[index until end])
                index = end
                continue
            }

            if Utf8.startsWith(source[index to], "<!--")
            {
                let endComment = Utf8.indexOf(source, "-->", index + 4)
                index = endComment == Swag.U64.Max ? @countof(source) : endComment + 3
                continue
            }
            if Utf8.startsWith(source[index to], "<![CDATA[")
            {
                let endCdata = Utf8.indexOf(source, "]]>", index + 9)
                let end      = endCdata == Swag.U64.Max ? @countof(source) : endCdata
                state.appendText(source[index + 9 until end])
                index = endCdata == Swag.U64.Max ? end : end + 3
                continue
            }

            let close = Utf8.indexOf(source, '>'rune, index + 1)
            if close == Swag.U64.Max
            {
                state.appendVisible("‹")
                index += 1
                continue
            }

            let tag  = source[index + 1 until close]
            let name = htmlTagName(tag)
            if htmlHiddenElement(name.toString())
            {
                let closingName = Format.toString("</%", name)
                let closing = Utf8.indexOf(source, closingName.toString(), close + 1, .Latin1NoCase)
                if closing == Swag.U64.Max
                {
                    index = @countof(source)
                    continue
                }
                let closingEnd = Utf8.indexOf(source, '>'rune, closing + @countof(closingName))
                index = closingEnd == Swag.U64.Max ? @countof(source) : closingEnd + 1
                continue
            }

            if !Utf8.startsWith(tag, "!") and !Utf8.startsWith(tag, "?") do
                renderHtmlTag(&state, tag)
            index = close + 1
        }

        return state.output
    }
}
