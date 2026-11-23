#global internal
#global namespace Viewers.Docx

using Core

private struct Comment
{
    id:      String
    author:  String
    html:    String
    limited: bool
}

struct CommentResult
{
    author:  String
    html:    String
    found:   bool
    limited: bool
}

struct CommentCatalog
{
    private comments: Array'Comment
}

private struct CommentReader
{
    catalog:     CommentCatalog
    paragraph:   String
    currentHtml: String
    currentId:   String
    author:      String
    inComment:   bool
    inParagraph: bool
    inText:      bool
    limited:     bool
}

private impl CommentReader
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

    mtd finishComment() fail
    {
        if not .inComment do
            return
        .finishParagraph()
        for &comment in .catalog.comments where comment.id == .currentId do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        .catalog.comments.add(Comment{.currentId, .author, #move .currentHtml, .limited})
        if .catalog.comments.count > 4096 do
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        .currentHtml.clear()
        .currentId.clear()
        .author.clear()
        .limited   = false
        .inComment = false
    }
}

impl CommentCatalog
{
    // Reads a bounded comments part as escaped paragraphs; rich objects and fields stay inert.
    func parse(source: string)->CommentCatalog fail
    {
        var scan    = Package.Scanner.create(source)
        var token:  Package.Token
        var reader: CommentReader
        var sawRoot = false

        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if not sawRoot
                {
                    if not token.isElement("comments") do
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    sawRoot = true
                }

                if token.isElement("comment")
                {
                    if reader.inComment do
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    let rawId = token.attribute("id") orelse ""
                    var idError: Swag.Error
                    let id    = catch StrConv.toS32(rawId) as idError orelse -1
                    if rawId.count == 0 or idError.value() != null or id < 0 do
                        fail Errors.InvalidFormatError{texts().err_Invalid}
                    reader.currentId = Format.toString("%", id)
                    reader.author    = token.attribute("author") orelse ""
                    if reader.author.count > 4096 do
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                    reader.limited   = token.attribute("date") != null or token.attribute("initials") != null
                    reader.inComment = true
                    if token.empty do
                        try reader.finishComment()
                }
                elif reader.inComment and token.isElement("p")
                {
                    reader.inParagraph = true
                    if token.empty do
                        reader.finishParagraph()
                }
                elif reader.inComment and token.isElement("t")
                {
                    reader.inText = not token.empty
                }
                elif reader.inComment and reader.inParagraph and token.isElement("tab")
                {
                    reader.paragraph += "&emsp;"
                }
                elif reader.inComment and reader.inParagraph and token.isElement("br")
                {
                    reader.paragraph += "<br>"
                }
                elif reader.inComment and
                     (token.isElement("tbl") or token.isElement("drawing") or token.isElement("pict") or token.isElement("fldChar") or token.isElement("instrText") or token.isElement("commentReference") or token.isElement("commentRangeStart") or token.isElement("commentRangeEnd"))
                {
                    reader.limited = true
                }
            }
            elif token.kind == .Text and reader.inComment and reader.inParagraph and reader.inText
            {
                Package.appendHtmlEscaped(&reader.paragraph, token.text)
            }
            elif token.kind == .End
            {
                if token.isElement("t") do
                    reader.inText = false
                elif token.isElement("p") do
                    reader.finishParagraph()
                elif token.isElement("comment") do
                    try reader.finishComment()
            }
        }

        if scan.damaged or reader.inComment or reader.inParagraph or (source.count and not sawRoot) do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        return #move reader.catalog
    }

    mtd const lookup(id: string)->CommentResult
    {
        for &comment in .comments where comment.id == id do
            return CommentResult{comment.author, comment.html, true, comment.limited}
        return {}
    }
}
