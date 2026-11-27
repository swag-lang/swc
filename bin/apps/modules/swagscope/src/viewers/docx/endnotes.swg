#global internal
#global namespace Viewers.Docx

using Core

private struct Endnote
{
    id:      String
    html:    String
    limited: bool
}

struct EndnoteResult
{
    html:    String
    found:   bool
    limited: bool
}

struct EndnoteCatalog
{
    private notes: Array!{Endnote}
}

private struct EndnoteReader
{
    catalog:         EndnoteCatalog
    paragraph:       String
    run:             String
    currentHtml:     String
    currentId:       String
    currentType:     String
    inEndnote:       bool
    inParagraph:     bool
    inText:          bool
    inRun:           bool
    inRunProperties: bool
    bold:            bool
    italic:          bool
    underline:       bool
    strike:          bool
    skipEndnote:     bool
    limited:         bool
}

private impl EndnoteReader
{
    mtd appendInline(value: string)
    {
        if .inRun
        {
            .run += value
        }
        else
        {
            .paragraph += value
        }
    }

    mtd finishRun()
    {
        if not .inRun
        {
            return
        }

        if .bold
        {
            .paragraph += "<b>"
        }

        if .italic
        {
            .paragraph += "<i>"
        }

        if .underline
        {
            .paragraph += "<u>"
        }

        if .strike
        {
            .paragraph += "<s>"
        }

        .paragraph += .run
        if .strike
        {
            .paragraph += "</s>"
        }

        if .underline
        {
            .paragraph += "</u>"
        }

        if .italic
        {
            .paragraph += "</i>"
        }

        if .bold
        {
            .paragraph += "</b>"
        }

        .run.clear()
        .bold            = false
        .italic          = false
        .underline       = false
        .strike          = false
        .inRun           = false
        .inRunProperties = false
    }

    mtd finishParagraph()
    {
        if not .inParagraph
        {
            return
        }

        .finishRun()
        .currentHtml += "<p>"
        .currentHtml += .paragraph
        .currentHtml += "</p>"
        .paragraph.clear()
        .inParagraph = false
    }

    mtd finishEndnote() fail
    {
        if not .inEndnote
        {
            return
        }

        .finishParagraph()
        if not .skipEndnote
        {
            for &note in .catalog.notes where note.id == .currentId
            {
                fail Errors.InvalidFormatError{texts().err_Invalid}
            }

            .catalog.notes.add(Endnote{.currentId, #move .currentHtml, .limited})
            if .catalog.notes.count > 4096
            {
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
            }
        }

        .currentHtml.clear()
        .currentId.clear()
        .currentType.clear()
        .limited     = false
        .skipEndnote = false
        .inEndnote   = false
    }
}

impl EndnoteCatalog
{
    // Reads a bounded endnotes part as escaped prose; separator and continuation markers are metadata.
    func parse(source: string)->EndnoteCatalog fail
    {
        var scan    = Package.Scanner.create(source)
        var token:  Package.Token
        var reader: EndnoteReader
        var sawRoot = false

        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if not sawRoot
                {
                    if not token.isElement("endnotes")
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    sawRoot = true
                }

                if token.isElement("endnote")
                {
                    if reader.inEndnote
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    let rawId = token.attribute("id") orelse ""
                    var idError: Swag.Error
                    let id    = catch StrConv.toS32(rawId) as idError orelse 0
                    if rawId.count == 0 or idError.value() != null
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    reader.currentId   = Format.toString("%", id)
                    reader.currentType = token.attribute("type") orelse ""
                    let special = (reader.currentType == "separator" and id == 0) or
                                  (reader.currentType == "continuationSeparator" and id == -1) or
                                  (reader.currentType == "continuationNotice" and id == -2)
                    let specialType = reader.currentType == "separator" or
                                      reader.currentType == "continuationSeparator" or
                                      reader.currentType == "continuationNotice"
                    if (id < 0 or id == 0 or specialType) and not special
                    {
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    }

                    reader.skipEndnote = special
                    reader.limited     = not reader.skipEndnote and not reader.currentType.isEmpty()
                    reader.inEndnote   = not token.empty
                    if token.empty
                    {
                        try reader.finishEndnote()
                    }
                }
                else if reader.inEndnote and token.isElement("r")
                {
                    reader.inRun = true
                    if token.empty
                    {
                        reader.finishRun()
                    }
                }
                else if reader.inEndnote and reader.inRun and token.isElement("rPr")
                {
                    reader.inRunProperties = not token.empty
                }
                else if reader.inEndnote and
                        reader.inRunProperties and
                        (token.isElement("b") or token.isElement("i") or token.isElement("u") or token.isElement("strike"))
                {
                    let value   = token.attribute("val") orelse ""
                    let enabled = value != "0" and value != "false" and value != "off" and value != "none"
                    if token.isElement("b")
                    {
                        reader.bold = enabled
                    }
                    else if token.isElement("i")
                    {
                        reader.italic = enabled
                    }
                    else if token.isElement("u")
                    {
                        reader.underline = enabled
                    }
                    else
                    {
                        reader.strike = enabled
                    }

                    if token.isElement("u") and enabled and value.count and value != "single"
                    {
                        reader.limited = true
                    }
                }
                else if reader.inEndnote and token.isElement("p")
                {
                    reader.inParagraph = true
                    if token.empty
                    {
                        reader.finishParagraph()
                    }
                }
                else if reader.inEndnote and token.isElement("t")
                {
                    reader.inText = not token.empty
                }
                else if reader.inEndnote and reader.inParagraph and token.isElement("tab")
                {
                    reader.appendInline("&emsp;")
                }
                else if reader.inEndnote and reader.inParagraph and token.isElement("br")
                {
                    reader.appendInline("<br>")
                }
                else if reader.inEndnote and
                        (token.isElement("tbl") or token.isElement("drawing") or token.isElement("pict") or token.isElement("fldChar") or token.isElement("instrText") or token.isElement("commentReference") or token.isElement("pPr"))
                {
                    reader.limited = true
                }
                else if reader.inEndnote and reader.inRunProperties
                {
                    reader.limited = true
                }
            }
            else if token.kind == .Text and reader.inEndnote and reader.inParagraph and reader.inText
            {
                if reader.inRun
                {
                    Package.appendHtmlEscaped(&reader.run, token.text)
                }
                else
                {
                    Package.appendHtmlEscaped(&reader.paragraph, token.text)
                }
            }
            else if token.kind == .End
            {
                if token.isElement("t")
                {
                    reader.inText = false
                }
                else if token.isElement("rPr")
                {
                    reader.inRunProperties = false
                }
                else if token.isElement("r")
                {
                    reader.finishRun()
                }
                else if token.isElement("p")
                {
                    reader.finishParagraph()
                }
                else if token.isElement("endnote")
                {
                    try reader.finishEndnote()
                }
            }
        }

        if scan.damaged or reader.inEndnote or reader.inParagraph or (source.count and not sawRoot)
        {
            fail Errors.InvalidFormatError{texts().err_Invalid}
        }

        return #move reader.catalog
    }

    mtd const lookup(id: string)->EndnoteResult
    {
        for &note in .notes where note.id == id
        {
            return EndnoteResult{note.html, true, note.limited}
        }

        return {}
    }
}
