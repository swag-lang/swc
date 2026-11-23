#global internal
#global namespace Viewers.Docx

using Core

private struct Footnote
{
    id:      String
    html:    String
    limited: bool
}

struct FootnoteResult
{
    html:    String
    found:   bool
    limited: bool
}

struct FootnoteCatalog
{
    private notes: Array'Footnote
}

private struct FootnoteReader
{
    catalog:      FootnoteCatalog
    paragraph:    String
    currentHtml:  String
    currentId:    String
    currentType:  String
    inFootnote:   bool
    inParagraph:  bool
    inText:       bool
    skipFootnote: bool
    limited:      bool
}

private impl FootnoteReader
{
    mtd finishParagraph()
    {
        if not .inParagraph do
            return
        .currentHtml += "<p>"
        .currentHtml += .paragraph
        .currentHtml += "</p>"
        .paragraph.clear()
        .inParagraph = false
    }

    mtd finishFootnote() fail
    {
        if not .inFootnote do
            return
        .finishParagraph()
        if not .skipFootnote
        {
            for &note in .catalog.notes where note.id == .currentId do
                fail Errors.InvalidFormatError{texts().err_Invalid}
            .catalog.notes.add(Footnote{.currentId, #move .currentHtml, .limited})
            if .catalog.notes.count > 4096 do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }

        .currentHtml.clear()
        .currentId.clear()
        .currentType.clear()
        .limited      = false
        .skipFootnote = false
        .inFootnote   = false
    }
}

impl FootnoteCatalog
{
    // Reads a bounded footnotes part as escaped prose; separator and continuation markers are metadata.
    func parse(source: string)->FootnoteCatalog fail
    {
        var scan    = Package.Scanner.create(source)
        var token:  Package.Token
        var reader: FootnoteReader
        var sawRoot = false

        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if not sawRoot
                {
                    if not token.isElement("footnotes") do
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    sawRoot = true
                }

                if token.isElement("footnote")
                {
                    if reader.inFootnote do
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    let rawId = token.attribute("id") orelse ""
                    var idError: Swag.Error
                    let id    = catch StrConv.toS32(rawId) as idError orelse 0
                    if rawId.count == 0 or idError.value() != null do
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    reader.currentId   = Format.toString("%", id)
                    reader.currentType = token.attribute("type") orelse ""
                    let special = (reader.currentType == "separator" and id == 0) or
                                  (reader.currentType == "continuationSeparator" and id == -1) or
                                  (reader.currentType == "continuationNotice" and id == -2)
                    let specialType = reader.currentType == "separator" or
                                      reader.currentType == "continuationSeparator" or
                                      reader.currentType == "continuationNotice"
                    if (id < 0 or id == 0 or specialType) and not special do
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    reader.skipFootnote = special
                    reader.limited      = not reader.skipFootnote and not reader.currentType.isEmpty()
                    reader.inFootnote   = not token.empty
                    if token.empty do
                        try reader.finishFootnote()
                }
                elif reader.inFootnote and token.isElement("p")
                {
                    reader.inParagraph = true
                    if token.empty do
                        reader.finishParagraph()
                }
                elif reader.inFootnote and token.isElement("t")
                {
                    reader.inText = not token.empty
                }
                elif reader.inFootnote and reader.inParagraph and token.isElement("tab")
                {
                    reader.paragraph += "&emsp;"
                }
                elif reader.inFootnote and reader.inParagraph and token.isElement("br")
                {
                    reader.paragraph += "<br>"
                }
                elif reader.inFootnote and
                     (token.isElement("tbl") or token.isElement("drawing") or token.isElement("pict") or token.isElement("fldChar") or token.isElement("instrText") or token.isElement("commentReference") or token.isElement("pPr") or token.isElement("rPr"))
                {
                    reader.limited = true
                }
            }
            elif token.kind == .Text and reader.inFootnote and reader.inParagraph and reader.inText
            {
                Package.appendHtmlEscaped(&reader.paragraph, token.text)
            }
            elif token.kind == .End
            {
                if token.isElement("t") do
                    reader.inText = false
                elif token.isElement("p") do
                    reader.finishParagraph()
                elif token.isElement("footnote") do
                    try reader.finishFootnote()
            }
        }

        if scan.damaged or reader.inFootnote or reader.inParagraph or (source.count and not sawRoot) do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        return #move reader.catalog
    }

    mtd const lookup(id: string)->FootnoteResult
    {
        for &note in .notes where note.id == id do
            return FootnoteResult{note.html, true, note.limited}
        return {}
    }
}
