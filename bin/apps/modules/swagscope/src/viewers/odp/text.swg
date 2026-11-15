#global internal
#global namespace Viewers.Odp

using Core

private struct Inline
{
    run: Docx.RunFormat
}

// Slide text uses viewport-relative type so authored sizes scale with the fitted canvas.
struct Text
{
    html:    String
    plain:   String
    limited: bool
}

func readText(source: string, styles: const *Odf.StyleCatalog, base: Docx.RunFormat, width: f32, readerStyle = false)->Text fail
{
    var result: Text
    var scan        = Package.Scanner.create(source)
    var token:  Package.Token
    var run         = base
    var stack:  Array'Inline
    var text:   String
    var inParagraph = false
    var depth       = 0'u64
    var skip        = Swag.U64.Max
    var lists:  Array'bool

    func flush(result: *Text, text: *String, run: Docx.RunFormat, width: f32, readerStyle: bool)
    {
        if text.isEmpty() do
            return
        if run.hidden != .On
        {
            result.plain += text[]
            var escaped: String
            Package.appendHtmlEscaped(&escaped, text[])
            let pixels = cast(f32, run.size ? run.size : 36) / 2 * 4 / 3
            if not readerStyle do
                result.html += Format.toString("<span style=\"font-size:%{f4}vw;\">", pixels / width * 100)
            var inner = run
            inner.size = 0
            if readerStyle
            {
                inner.family.clear()
                inner.color.clear()
                inner.highlight.clear()
            }

            inner.appendHtml(&result.html, escaped)
            if not readerStyle do
                result.html += "</span>"
        }

        text.clear()
    }

    while scan.next(&token)
    {
        if token.kind == .Start
        {
            depth += 1
            if skip == Swag.U64.Max
            {
                if token.isElement("notes") or
                   token.isElement("annotation") or
                   token.isElement("scripts") or
                   token.isElement("binary-data") or
                   token.isElement("event-listeners")
                {
                    skip = depth
                }
                elif token.isElement("p") or token.isElement("h")
                {
                    if inParagraph do
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    run = base
                    let properties = styles.lookup(token.attribute("style-name") orelse "", .Paragraph)
                    properties.applyRun(&run)
                    result.limited = result.limited or properties.limited
                    result.html    += "<p"
                    if not properties.paragraph.alignment.isEmpty() do
                        result.html += Format.toString(" style=\"text-align:%\"", properties.paragraph.alignment)
                    result.html += ">"
                    inParagraph = true
                }
                elif inParagraph
                {
                    if token.isElement("span")
                    {
                        flush(&result, &text, run, width, readerStyle)
                        stack.add(Inline{run})
                        let properties = styles.lookup(token.attribute("style-name") orelse "", .Text)
                        properties.applyRun(&run)
                        result.limited = result.limited or properties.limited
                    }
                    elif token.isElement("line-break")
                    {
                        flush(&result, &text, run, width, readerStyle)
                        result.html  += "<br>"
                        result.plain += "\n"
                    }
                    elif token.isElement("tab")
                    {
                        text += "\t"
                    }
                    elif token.isElement("s")
                    {
                        let count = catch StrConv.toU32(token.attribute("c") orelse "1") orelse 0
                        if count > 8192 do
                            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                        for count do
                            text += "\u00A0"
                    }
                }
                elif token.isElement("list")
                {
                    let entry   = styles.lists.tryFind(String.from(token.attribute("style-name") orelse ""))
                    let ordered = entry and entry.value
                    lists.add(ordered)
                    result.html += ordered ? "<ol>" : "<ul>"
                }
                elif token.isElement("list-item")
                {
                    result.html += "<li>"
                }
            }
        }
        elif token.kind == .Text and inParagraph and skip == Swag.U64.Max
        {
            text += token.text
        }

        if text.count + result.html.count > 1024 * 1024 do
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        if token.kind == .End or token.empty
        {
            if skip == depth
            {
                skip = Swag.U64.Max
            }
            elif skip == Swag.U64.Max
            {
                if token.isElement("span") and not stack.isEmpty()
                {
                    flush(&result, &text, run, width, readerStyle)
                    run = stack.popBack().run
                }
                elif (token.isElement("p") or token.isElement("h")) and inParagraph
                {
                    flush(&result, &text, run, width, readerStyle)
                    result.html  += "</p>"
                    result.plain += "\n"
                    inParagraph  = false
                }
                elif token.isElement("list-item")
                {
                    result.html += "</li>"
                }
                elif token.isElement("list") and not lists.isEmpty()
                {
                    result.html += lists.popBack() ? "</ol>" : "</ul>"
                }
            }

            depth -= 1
        }
    }

    if scan.damaged or inParagraph or not stack.isEmpty() do
        fail Errors.InvalidFormatError{texts().err_Invalid}
    return result
}
