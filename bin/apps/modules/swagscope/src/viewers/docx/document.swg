#global internal
#global namespace Viewers.Docx

using Core

func relationshipPart(relationships: const [..] Package.Relationship, id, kind: string)->String
{
    for relationship in relationships
    {
        if relationship.id == id and Utf8.endsWith(relationship.kind, kind) do
            return relationship.path
    }

    return {}
}

// The readable body of one WordprocessingML document.
struct PageLayout
{
    width:        s32
    height:       s32
    marginTop:    s32
    marginRight:  s32
    marginBottom: s32
    marginLeft:   s32
    marginMask:   u8
}

impl PageLayout
{
    mtd const css()->String
    {
        var result:  #returntype
        let numbers: Globalization.NumberFormatInfo
        if .width > 0 do
            result += Format.toString("max-width:%px;", numbers.format(cast(f64, .width) / 15, 2))
        if .height > 0 do
            result += Format.toString("min-height:%px;", numbers.format(cast(f64, .height) / 15, 2))
        if .marginMask
        {
            result += "padding:"
            result += numbers.format(cast(f64, .marginTop) / 15, 2)
            result += "px "
            result += numbers.format(cast(f64, .marginRight) / 15, 2)
            result += "px "
            result += numbers.format(cast(f64, .marginBottom) / 15, 2)
            result += "px "
            result += numbers.format(cast(f64, .marginLeft) / 15, 2)
            result += "px;"
        }

        if .width > 0 or .height > 0 or .marginMask do
            result += "box-sizing:border-box;"
        if .width > 0 do
            result += "margin-left:auto;margin-right:auto;"
        return result
    }
}

struct Document
{
    html:                    String
    headerHtml:              String
    footerHtml:              String
    pageWidth:               s32
    pageHeight:              s32
    marginTop:               s32
    marginRight:             s32
    marginBottom:            s32
    marginLeft:              s32
    marginMask:              u8
    paragraphs:              u64
    tables:                  u64
    omittedImages:           u64
    usePaperColors:          bool
    paperColor:              String
    stylesSimplified:        bool
    pageElementsSimplified:  bool
    sectionLayoutSimplified: bool
    footnotesSimplified:     bool
    commentsSimplified:      bool
    linksSimplified:         bool
    properties:              Package.DocumentProperties     // What the package says of the document.
}

impl Document
{
    mtd const details()->String
    {
        var result = .paragraphs == 1 ? String.from(texts().ui_OneParagraph) : Format.toString(texts().ui_Details, .paragraphs)
        if .tables do
            result += .tables == 1 ? String.from(texts().ui_OneTable) : Format.toString(texts().ui_Tables, .tables)
        if .omittedImages do
            result += .omittedImages == 1 ? String.from(texts().ui_OneImageOmitted) : Format.toString(texts().ui_ImagesOmitted, .omittedImages)
        if .stylesSimplified do
            result += texts().ui_StylesSimplified
        if .pageElementsSimplified do
            result += texts().ui_PageElementsSimplified
        if .sectionLayoutSimplified do
            result += texts().ui_SectionLayoutSimplified
        if .footnotesSimplified do
            result += texts().ui_FootnotesSimplified
        if .commentsSimplified do
            result += texts().ui_CommentsSimplified
        if .linksSimplified do
            result += texts().ui_LinksSimplified
        return result
    }

    // Applies one final-section page box in CSS pixels; Word stores dimensions as twentieths of a point.
    mtd const pageCss()->String
    {
        return PageLayout{.pageWidth, .pageHeight, .marginTop, .marginRight, .marginBottom, .marginLeft, .marginMask}.css()
    }

    // Reads paragraphs and tables from the main document part without executing embedded content.
    func load(fileName: string)->Document fail
    {
        let archive   = try Archive.Zip.load(fileName)
        let parts     = Package.PartReader{fileName, &archive, texts().err_Invalid, texts().err_TooLarge}
        let source    = try parts.text("word/document.xml")
        let relations = try parts.relationships("word/document.xml")
        var theme     = Package.OfficeTheme.defaults()
        let themePath = Package.relationshipPath(relations.toSlice(), "/theme")
        var themeError: Swag.Error
        if not themePath.isEmpty() do
            theme.read(catch parts.text(themePath, required: false) as themeError orelse {})
        var stylePath      = Package.relationshipPath(relations.toSlice(), "/styles")
        let declaredStyles = not stylePath.isEmpty()
        if stylePath.isEmpty() do
            stylePath = "word/styles.xml"
        var styleReadError:  Swag.Error
        let styleSource = catch parts.text(stylePath, required: false, limit: 4 * 1024 * 1024) as styleReadError orelse {}
        var styleParseError: Swag.Error
        var styles      = catch StyleCatalog.parse(styleSource, &theme) as styleParseError orelse {}
        let limited     = themeError.value() != null or
                          styleReadError.value() != null or
                          styleParseError.value() != null or
                          (declaredStyles and styleSource.isEmpty())
        var numberingPath = Package.relationshipPath(relations.toSlice(), "/numbering")
        if numberingPath.isEmpty() do
            numberingPath = "word/numbering.xml"
        var numberingReadError:  Swag.Error
        let numberingSource = catch parts.text(numberingPath, required: false, limit: 4 * 1024 * 1024) as numberingReadError orelse {}
        var numberingParseError: Swag.Error
        var numbering       = catch NumberingCatalog.parse(numberingSource) as numberingParseError orelse {}
        var footnotesPath   = Package.relationshipPath(relations.toSlice(), "/footnotes")
        if footnotesPath.isEmpty() do
            footnotesPath = "word/footnotes.xml"
        var footnotesReadError:  Swag.Error
        let footnotesSource = catch parts.text(footnotesPath, required: false, limit: 4 * 1024 * 1024) as footnotesReadError orelse {}
        var footnotesParseError: Swag.Error
        var footnotes       = catch FootnoteCatalog.parse(footnotesSource) as footnotesParseError orelse {}
        var commentsPath    = Package.relationshipPath(relations.toSlice(), "/comments")
        if commentsPath.isEmpty() do
            commentsPath = "word/comments.xml"
        var commentsReadError:  Swag.Error
        let commentsSource = catch parts.text(commentsPath, required: false, limit: 4 * 1024 * 1024) as commentsReadError orelse {}
        var commentsParseError: Swag.Error
        var comments       = catch CommentCatalog.parse(commentsSource) as commentsParseError orelse {}
        var scan           = Package.Scanner.create(source)
        var token: Package.Token
        var images         = try Package.ImageCatalog.load(fileName,
                                                           &archive,
                                                           "word",
                                                           "word/_rels/document.xml.rels",
                                                           texts().err_Invalid,
                                                           texts().err_TooLarge)
        var reader = Reader{document: Document{usePaperColors: styles.loaded, stylesSimplified: limited},
                            images: #move images, numbering: #move numbering, footnotes: #move footnotes, comments: #move comments,
                            styles: #move styles, theme: #move theme,
                            numberingLimited: numberingReadError.value() != null or numberingParseError.value() != null,
                            footnotesLimited: footnotesReadError.value() != null or footnotesParseError.value() != null,
                            commentsLimited: commentsReadError.value() != null or commentsParseError.value() != null}
        while scan.next(&token)
        {
            if token.kind == .Start
            {
                reader.start(&token)
            }
            elif token.kind == .End
            {
                reader.end(&token)
            }
            elif reader.inBody and reader.inText
            {
                if reader.inRun do
                    Package.appendHtmlEscaped(&reader.run, token.text)
                else do
                    Package.appendHtmlEscaped(&reader.paragraph, token.text)
            }

            if reader.document.html.count + reader.sectionHtml.count + reader.paragraph.count + reader.run.count > 32 * 1024 * 1024 do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }

        for reference in reader.bookmarkReferences
        {
            var found = false
            for name in reader.bookmarkNames where Utf8.compare(name.toString(), reference.toString()) == 0 do
                found = true
            if not found do
                reader.document.linksSimplified = true
        }

        for id in reader.commentRangeStarts
        {
            var found = false
            for end in reader.commentRangeEnds where end == id do
                found = true
            if not found do
                reader.document.commentsSimplified = true
        }

        if scan.damaged or reader.inBody or reader.inParagraph or not reader.document.paragraphs and not reader.document.tables do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        reader.document.html += reader.footnotesHtml()
        reader.document.html += reader.commentsHtml()
        if reader.document.html.count > 32 * 1024 * 1024 do
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        var html: String = "<html>"
        if not reader.headerId.isEmpty()
        {
            reader.document.pageElementsSimplified = true
            let path = relationshipPart(relations.toSlice(), reader.headerId.toString(), "/header")
            if path.isEmpty()
            {
                reader.document.pageElementsSimplified = true
            }
            else
            {
                var readError: Swag.Error
                let source = catch parts.text(path, required: false, limit: 4 * 1024 * 1024) as readError orelse {}
                if source.isEmpty() or readError.value() != null
                {
                    reader.document.pageElementsSimplified = true
                }
                else
                {
                    var parseError: Swag.Error
                    let content = catch HeaderFooterReader.parse(source) as parseError orelse {}
                    if parseError.value() != null
                    {
                        reader.document.pageElementsSimplified = true
                    }
                    else
                    {
                        reader.document.headerHtml = #move content.html
                        reader.document.pageElementsSimplified = reader.document.pageElementsSimplified or content.limited
                    }
                }
            }
        }

        if not reader.footerId.isEmpty()
        {
            reader.document.pageElementsSimplified = true
            let path = relationshipPart(relations.toSlice(), reader.footerId.toString(), "/footer")
            if path.isEmpty()
            {
                reader.document.pageElementsSimplified = true
            }
            else
            {
                var readError: Swag.Error
                let source = catch parts.text(path, required: false, limit: 4 * 1024 * 1024) as readError orelse {}
                if source.isEmpty() or readError.value() != null
                {
                    reader.document.pageElementsSimplified = true
                }
                else
                {
                    var parseError: Swag.Error
                    let content = catch HeaderFooterReader.parse(source) as parseError orelse {}
                    if parseError.value() != null
                    {
                        reader.document.pageElementsSimplified = true
                    }
                    else
                    {
                        reader.document.footerHtml = #move content.html
                        reader.document.pageElementsSimplified = reader.document.pageElementsSimplified or content.limited
                    }
                }
            }
        }

        var bodyStyle = reader.document.pageCss()
        if reader.document.usePaperColors
        {
            html += "<head><style>p,h1,h2,h3,h4,h5,h6{margin:0;font-size:inherit;font-weight:normal}</style></head>"
            let background = reader.document.paperColor.isEmpty() ? String.from("FFFFFF") : reader.document.paperColor
            let rgb        = catch StrConv.toU32(Format.toString("0x%", background)) orelse 0xFFFFFF'u32
            let luma       = ((rgb >> 16) & 255) * 299 + ((rgb >> 8) & 255) * 587 + (rgb & 255) * 114
            bodyStyle += Format.toString("background-color:#%;color:#%;", background, luma < 128000 ? "FFFFFF" : "000000")
        }

        if bodyStyle.isEmpty()
        {
            html += "<body>"
        }
        else
        {
            html += "<body style=\""
            Package.appendHtmlEscaped(&html, bodyStyle)
            html += "\">"
        }

        if not reader.document.headerHtml.isEmpty()
        {
            html += "<header>"
            html += reader.document.headerHtml
            html += "</header>"
        }

        html += reader.document.html
        if not reader.document.footerHtml.isEmpty()
        {
            html += "<footer>"
            html += reader.document.footerHtml
            html += "</footer>"
        }

        html += "</body></html>"
        if html.count > 32 * 1024 * 1024 do
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        reader.document.html = #move html

        reader.document.properties = Package.DocumentProperties.read(fileName, &archive)
        return #move reader.document
    }
}
