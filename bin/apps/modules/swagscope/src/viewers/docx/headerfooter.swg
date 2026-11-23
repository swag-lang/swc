#global internal
#global namespace Viewers.Docx

using Core

// Converts a simple Word header or footer part into readable paragraphs.
struct HeaderFooterContent
{
    html:    String
    limited: bool
}

struct HeaderFooterReader
{
    html:        String
    paragraph:   String
    inParagraph: bool
    inText:      bool
    limited:     bool
}

impl HeaderFooterReader
{
    mtd finishParagraph()
    {
        if not .inParagraph do
            return
        .html += "<p>"
        .html += .paragraph
        .html += "</p>"
        .paragraph.clear()
        .inParagraph = false
    }

    // Reads text-only paragraph content without interpreting fields or embedded objects.
    func parse(source: string)->HeaderFooterContent fail
    {
        var scan  = Package.Scanner.create(source)
        var token:  Package.Token
        var reader: HeaderFooterReader
        var roots = 0
        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if roots == 0
                {
                    if not token.isElement("hdr") and not token.isElement("ftr") do
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    roots += 1
                }

                if token.isElement("p")
                {
                    reader.inParagraph = true
                    if token.empty do
                        reader.finishParagraph()
                }
                elif token.isElement("t")
                {
                    reader.inText = not token.empty
                }
                elif token.isElement("tab") and reader.inParagraph
                {
                    reader.paragraph += "&emsp;"
                }
                elif token.isElement("br") and reader.inParagraph
                {
                    reader.paragraph += "<br>"
                }
                elif token.isElement("tbl") or
                     token.isElement("drawing") or
                     token.isElement("pict") or
                     token.isElement("fldChar") or
                     token.isElement("instrText") or
                     token.isElement("pPr") or
                     token.isElement("rPr")
                {
                    reader.limited = true
                }
            }
            elif token.kind == .Text and reader.inParagraph and reader.inText
            {
                Package.appendHtmlEscaped(&reader.paragraph, token.text)
            }
            elif token.kind == .End
            {
                if token.isElement("t") do
                    reader.inText = false
                elif token.isElement("p") do
                    reader.finishParagraph()
            }
        }

        if scan.damaged or reader.inParagraph or roots != 1 do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        return HeaderFooterContent{#move reader.html, reader.limited}
    }
}
