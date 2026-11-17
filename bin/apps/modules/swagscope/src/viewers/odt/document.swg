#global internal
#global namespace Viewers.Odt

using Core, Pixel

// A self-contained reading projection of an OpenDocument text package.
struct Document
{
    html:       String
    paragraphs: u64
    tables:     u64
    images:     u64
    omitted:    u64
    simplified: bool
    properties: Package.DocumentProperties     // What the package says of the document.
}

private struct Inline
{
    name: String
    run:  Docx.RunFormat
    link: bool
}

private struct Frame
{
    width:       u32
    height:      u32
    description: String
    paths:       Array'String
}

private struct Repeated
{
    start:      u64
    paragraphs: u64
    images:     u64
    omitted:    u64
    count:      u32 = 1
}

private struct Reader
{
    fileName:     string = ""
    late archive: const *Archive.Zip
    styles:       Odf.StyleCatalog
    document:     Document
    paragraph:    String
    tag:          String
    runText:      String
    run:          Docx.RunFormat
    inlines:      Array'Inline
    frames:       Array'Frame
    cells:        Array'Repeated
    rows:         Array'Repeated
    lists:        Array'bool
    listNames:    Array'String
    titleDepth:   u64    = Swag.U64.Max
    encodedBytes: u64
}

impl Document
{
    mtd const details()->String
    {
        var result = .paragraphs == 1 ? String.from(texts().ui_OneParagraph) : Format.toString(texts().ui_Details, .paragraphs)
        if .tables do
            result += .tables == 1 ? String.from(texts().ui_OneTable) : Format.toString(texts().ui_Tables, .tables)
        if .images do
            result += .images == 1 ? String.from(texts().ui_OneImage) : Format.toString(texts().ui_Images, .images)
        if .omitted do
            result += .omitted == 1 ? String.from(texts().ui_OneOmitted) : Format.toString(texts().ui_Omitted, .omitted)
        if .simplified do
            result += texts().ui_LayoutSimplified
        return result
    }

    func load(fileName: string)->Document fail
    {
        let archive = try Odf.openPackage(fileName, "application/vnd.oasis.opendocument.text", texts().err_Invalid, texts().err_TooLarge, texts().err_Encrypted)
        let parts   = Package.PartReader{fileName, &archive, texts().err_Invalid, texts().err_TooLarge}
        let content = try parts.text("content.xml")
        var reader: Reader
        reader.fileName = fileName
        reader.archive  = &archive
        try reader.styles.read(try parts.text("styles.xml", required: false, limit: 8 * 1024 * 1024))
        try reader.styles.read(content)
        reader.styles.finish()
        var result = try reader.read(content)
        result.properties = Package.DocumentProperties.read(fileName, &archive)
        return result
    }
}

private impl Reader
{
    mtd checkSize() fail
    {
        if .document.html.count + .paragraph.count + .runText.count > 32 * 1024 * 1024 or .document.paragraphs > 100_000 do
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
    }

    mtd ensureParagraph()
    {
        if not .tag.isEmpty() do
            return
        .tag                 = "p"
        .document.html       += "<p>"
        .run                 = {}
        .run.size            = 24
        .document.simplified = true
    }

    mtd flushRun()
    {
        if .runText.isEmpty() do
            return
        var escaped: String
        Package.appendHtmlEscaped(&escaped, .runText)
        .run.appendHtml(&.paragraph, escaped)
        .runText.clear()
    }

    mtd appendTrusted(source: string)
    {
        .ensureParagraph()
        .flushRun()
        .run.appendHtml(&.paragraph, source)
    }

    mtd finishParagraph()
    {
        if .tag.isEmpty() and (not .paragraph.isEmpty() or not .runText.isEmpty()) do
            .ensureParagraph()
        if .tag.isEmpty() do
            return
        .flushRun()
        .document.html       += .paragraph.isEmpty() ? "<br>" : .paragraph.toString()
        .document.html       += Format.toString("</%>", .tag)
        .document.paragraphs += 1
        .paragraph.clear()
        .tag.clear()
        .inlines.clear()
    }

    mtd startParagraph(token: const *Package.Token)
    {
        .finishParagraph()
        let properties = .styles.lookup(token.attribute("style-name") orelse "", .Paragraph)
        .document.simplified = .document.simplified or properties.limited
        .run      = {}
        .run.size = 24
        properties.applyRun(&.run)
        var level = properties.paragraph.heading()
        if token.isElement("h")
        {
            level = catch StrConv.toU32(token.attribute("outline-level") orelse "1") orelse 1
            level = Math.clamp(level, 1, 6)
        }

        .tag = level ? Format.toString("h%", level) : String.from("p")
        if properties.paragraph.pageBefore == .On and .document.paragraphs do
            .document.html += "<hr>"
        var css = properties.paragraph.css()
        css += .run.css()
        if .run.bold == .On do
            css += "font-weight:bold;"
        if .run.italic == .On do
            css += "font-style:italic;"
        .document.html += Format.toString("<% style=\"", .tag)
        Package.appendHtmlEscaped(&.document.html, css)
        .document.html += "\">"
    }

    mtd repeated(token: const *Package.Token, attribute: string)->Repeated fail
    {
        var result: #returntype
        result.start      = .document.html.count
        result.paragraphs = .document.paragraphs
        result.images     = .document.images
        result.omitted    = .document.omitted
        result.count      = catch StrConv.toU32(token.attribute(attribute) orelse "1") orelse 0
        if not result.count do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        if result.count > 512 do
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        return result
    }

    mtd repeatContent(item: Repeated) fail
    {
        if item.count <= 1 do
            return
        let content = String.from(.document.html.toString()[item.start to])
        for item.count - 1
        {
            .document.html += content
            try .checkSize()
        }

        .document.paragraphs += (.document.paragraphs - item.paragraphs) * (item.count - 1)
        .document.images     += (.document.images - item.images) * (item.count - 1)
        .document.omitted    += (.document.omitted - item.omitted) * (item.count - 1)
    }

    mtd image(path: string, width, height: u32, description: string)->String
    {
        return Odf.imageHtml(.fileName, .archive, path, width, height, description, &.encodedBytes)
    }

    mtd finishFrame()
    {
        if .frames.isEmpty() do
            return
        let frame       = .frames.popBack()
        let description = frame.description.isEmpty() ? String.from(texts().ui_ImageDescription) : frame.description
        for path in frame.paths
        {
            let html = .image(path.toString(), frame.width, frame.height, description)
            if html.isEmpty() do
                continue
            .appendTrusted(html)
            .document.images += 1
            return
        }

        if not frame.paths.isEmpty()
        {
            .runText += texts().ui_ImageOmitted
            .document.omitted += 1
        }
    }

    mtd read(source: string)->Document fail
    {
        .document.html = ""
        var scan    = Package.Scanner.create(source)
        var token: Package.Token
        var depth   = 0'u64
        var body    = Swag.U64.Max
        var skip    = Swag.U64.Max
        var sawBody = false
        while scan.next(&token)
        {
            if token.kind == .Start
            {
                depth += 1
                if token.isElement("body")
                {
                    body    = depth
                    sawBody = true
                }
                elif skip == Swag.U64.Max and body != Swag.U64.Max
                {
                    if token.isElement("scripts") or
                       token.isElement("script") or
                       token.isElement("event-listeners") or
                       token.isElement("tracked-changes") or
                       token.isElement("annotation") or
                       token.isElement("binary-data") or
                       (token.isElement("section") and (token.attribute("display") == "none" or token.attribute("is-hidden") == "true"))
                    {
                        skip = depth
                    }
                    elif token.isElement("note") or
                         token.isElement("object") or
                         token.isElement("object-ole") or
                         token.isElement("plugin") or
                         token.isElement("applet")
                    {
                        .runText += token.isElement("note") ? texts().ui_NoteOmitted : texts().ui_ObjectOmitted
                        .document.omitted += 1
                        skip     = depth
                    }
                    elif token.isElement("p") or token.isElement("h")
                    {
                        .startParagraph(&token)
                    }
                    elif token.isElement("span") or token.isElement("a")
                    {
                        .flushRun()
                        var item       = Inline{name: token.name, run: .run}
                        let properties = .styles.lookup(token.attribute("style-name") orelse "", .Text)
                        properties.applyRun(&.run)
                        .document.simplified = .document.simplified or properties.limited
                        if token.isElement("a")
                        {
                            let href = token.attribute("href") orelse ""
                            item.link = href.count > 0 and href[0] == '#'u8
                            if item.link
                            {
                                .paragraph += "<a href=\""
                                Package.appendHtmlEscaped(&.paragraph, href)
                                .paragraph += "\">"
                            }
                        }

                        .inlines.add(item)
                    }
                    elif token.isElement("line-break")
                    {
                        .appendTrusted("<br>")
                    }
                    elif token.isElement("tab")
                    {
                        .appendTrusted("&emsp;")
                    }
                    elif token.isElement("s")
                    {
                        let count = catch StrConv.toU32(token.attribute("c") orelse "1") orelse 0
                        if count > 8192 do
                            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                        for count do
                            .runText += "\u00A0"
                    }
                    elif token.isElement("bookmark") or token.isElement("bookmark-start")
                    {
                        .flushRun()
                        .paragraph += "<a id=\""
                        Package.appendHtmlEscaped(&.paragraph, token.attribute("name") orelse "")
                        .paragraph += "\"></a>"
                    }
                    elif token.isElement("frame")
                    {
                        var frame: Frame
                        if (token.attribute("anchor-type") orelse "as-char") != "as-char" do
                            .document.simplified = true
                        let width  = Odf.points(token.attribute("width") orelse "")
                        let height = Odf.points(token.attribute("height") orelse "")
                        if width.valid and height.valid and width.value > 0 and height.value > 0
                        {
                            frame.width  = cast(u32, Math.round(width.value * 4 / 3))
                            frame.height = cast(u32, Math.round(height.value * 4 / 3))
                        }

                        .frames.add(frame)
                    }
                    elif token.isElement("image")
                    {
                        let href = String.from(token.attribute("href") orelse "")
                        if .frames.isEmpty()
                        {
                            let html = .image(href, 0, 0, texts().ui_ImageDescription)
                            if html.isEmpty()
                            {
                                .runText += texts().ui_ImageOmitted
                                .document.omitted += 1
                            }
                            else
                            {
                                .appendTrusted(html)
                                .document.images += 1
                            }
                        }
                        else
                        {
                            if .frames.backPtr().paths.count >= 8 do
                                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                            .frames.backPtr().paths.add(href)
                        }
                    }
                    elif token.isElement("title") or token.isElement("desc")
                    {
                        if not .frames.isEmpty() do
                            .titleDepth = depth
                    }
                    elif token.isElement("table")
                    {
                        .finishParagraph()
                        let properties = .styles.lookup(token.attribute("style-name") orelse "", .Table)
                        .document.html += "<table style=\""
                        Package.appendHtmlEscaped(&.document.html, properties.cellCss)
                        .document.html       += "\">"
                        .document.tables     += 1
                        .document.simplified = .document.simplified or properties.limited
                    }
                    elif token.isElement("table-row")
                    {
                        .finishParagraph()
                        .rows.add(try .repeated(&token, "number-rows-repeated"))
                        .document.html += "<tr>"
                    }
                    elif token.isElement("table-cell")
                    {
                        .finishParagraph()
                        .cells.add(try .repeated(&token, "number-columns-repeated"))
                        let properties = .styles.lookup(token.attribute("style-name") orelse "", .Cell)
                        .document.html += "<td style=\""
                        Package.appendHtmlEscaped(&.document.html, properties.cellCss)
                        .document.html       += "\">"
                        .document.simplified = .document.simplified or
                                               properties.limited or
                                               (token.attribute("number-columns-spanned") orelse "1") != "1" or
                                               (token.attribute("number-rows-spanned") orelse "1") != "1"
                    }
                    elif token.isElement("list")
                    {
                        .finishParagraph()
                        var name = String.from(token.attribute("style-name") orelse "")
                        if name.isEmpty() and not .listNames.isEmpty() do
                            name = .listNames.back()
                        let kind     = .styles.lists.tryFind(name)
                        let numbered = kind and kind.value
                        .lists.add(numbered)
                        .listNames.add(name)
                        .document.html += numbered ? "<ol>" : "<ul>"
                        if token.attribute("continue-list") != null or token.attribute("continue-numbering") == "true" do
                            .document.simplified = true
                    }
                    elif token.isElement("list-item")
                    {
                        .finishParagraph()
                        .document.html += "<li>"
                    }
                }
            }
            elif token.kind == .Text and body != Swag.U64.Max and skip == Swag.U64.Max
            {
                if .titleDepth != Swag.U64.Max and not .frames.isEmpty()
                {
                    .frames.backPtr().description += token.text
                    if .frames.backPtr().description.count > 1024 do
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                }
                elif not .tag.isEmpty()
                {
                    .runText += token.text
                }
            }

            if token.kind == .End or token.empty
            {
                if skip == depth
                {
                    skip = Swag.U64.Max
                }
                elif skip == Swag.U64.Max and body != Swag.U64.Max
                {
                    if token.isElement("p") or token.isElement("h")
                    {
                        .finishParagraph()
                    }
                    elif (token.isElement("span") or token.isElement("a")) and not .inlines.isEmpty()
                    {
                        .flushRun()
                        let item = .inlines.popBack()
                        if item.link do
                            .paragraph += "</a>"
                        .run = item.run
                    }
                    elif token.isElement("frame")
                    {
                        .finishFrame()
                    }
                    elif token.isElement("table-cell") and not .cells.isEmpty()
                    {
                        .finishParagraph()
                        .document.html += "</td>"
                        try .repeatContent(.cells.popBack())
                    }
                    elif token.isElement("table-row") and not .rows.isEmpty()
                    {
                        .finishParagraph()
                        .document.html += "</tr>"
                        try .repeatContent(.rows.popBack())
                    }
                    elif token.isElement("table")
                    {
                        .finishParagraph()
                        .document.html += "</table>"
                    }
                    elif token.isElement("list-item")
                    {
                        .finishParagraph()
                        .document.html += "</li>"
                    }
                    elif token.isElement("list") and not .lists.isEmpty()
                    {
                        .finishParagraph()
                        .document.html += .lists.popBack() ? "</ol>" : "</ul>"
                        discard .listNames.popBack()
                    }
                }

                if .titleDepth == depth do
                    .titleDepth = Swag.U64.Max
                if body == depth do
                    body = Swag.U64.Max
                depth -= 1
            }

            try .checkSize()
        }

        .finishParagraph()
        if scan.damaged or
           not sawBody or
           not .inlines.isEmpty() or
           not .frames.isEmpty() or
           not .rows.isEmpty() or
           not .cells.isEmpty() or
           not .lists.isEmpty() do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        let background   = .styles.pageColor.isEmpty() ? String.from("FFFFFF") : .styles.pageColor
        var html: String = "<html><head><style>p,h1,h2,h3,h4,h5,h6{margin:0;font-size:inherit;font-weight:normal}table{border-collapse:collapse}td{vertical-align:top}</style></head><body style=\"padding:24px;box-sizing:border-box;"
        let rgb          = catch StrConv.toU32(Format.toString("0x%", background)) orelse 0xFFFFFF'u32
        let luma         = ((rgb >> 16) & 255) * 299 + ((rgb >> 8) & 255) * 587 + (rgb & 255) * 114
        html += Format.toString("background-color:#%;color:#%\">", background, luma < 128000 ? "FFFFFF" : "202024")
        html += .document.html
        html += "</body></html>"
        .document.html = #move html
        return #move .document
    }
}
