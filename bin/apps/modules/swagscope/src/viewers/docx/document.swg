#global internal
#global namespace Viewers.Docx

using Core

// The readable body of one WordprocessingML document.
struct Document
{
    html:             String
    pageWidth:        s32
    pageHeight:       s32
    marginTop:        s32
    marginRight:      s32
    marginBottom:     s32
    marginLeft:       s32
    marginMask:       u8
    paragraphs:       u64
    tables:           u64
    omittedImages:    u64
    usePaperColors:   bool
    paperColor:       String
    stylesSimplified: bool
    properties:       Package.DocumentProperties     // What the package says of the document.
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
        return result
    }

    // Applies one final-section page box in CSS pixels; Word stores dimensions as twentieths of a point.
    mtd const pageCss()->String
    {
        var result:  #returntype
        let numbers: Globalization.NumberFormatInfo
        if .pageWidth > 0 do
            result += Format.toString("max-width:%px;", numbers.format(cast(f64, .pageWidth) / 15, 2))
        if .pageHeight > 0 do
            result += Format.toString("min-height:%px;", numbers.format(cast(f64, .pageHeight) / 15, 2))
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

        if .pageWidth > 0 or .pageHeight > 0 or .marginMask do
            result += "box-sizing:border-box;"
        if .pageWidth > 0 do
            result += "margin-left:auto;margin-right:auto;"
        return result
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
        var scan   = Package.Scanner.create(source)
        var token: Package.Token
        var images = try Package.ImageCatalog.load(fileName,
                                                   &archive,
                                                   "word",
                                                   "word/_rels/document.xml.rels",
                                                   texts().err_Invalid,
                                                   texts().err_TooLarge)
        var reader = Reader{document: Document{usePaperColors: styles.loaded, stylesSimplified: limited},
                            images: #move images, styles: #move styles, theme: #move theme}

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

            if reader.document.html.count + reader.paragraph.count + reader.run.count > 32 * 1024 * 1024 do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }

        if scan.damaged or reader.inBody or reader.inParagraph or not reader.document.paragraphs and not reader.document.tables do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        var html: String = "<html>"
        var bodyStyle    = reader.document.pageCss()
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

        html += reader.document.html
        html += "</body></html>"
        reader.document.html = #move html

        reader.document.properties = Package.DocumentProperties.read(fileName, &archive)
        return #move reader.document
    }
}
