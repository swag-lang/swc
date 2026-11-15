#global internal
#global namespace Viewers.Docx

using Core

// A paragraph and its formatted runs are assembled before their HTML tags are chosen.
private struct Reader
{
    document:              Document
    images:                Package.ImageCatalog
    paragraph:             String
    run:                   String
    styles:                StyleCatalog
    theme:                 Package.OfficeTheme
    paragraphId:           String
    characterId:           String
    directParagraph:       ParagraphFormat
    paragraphFormat:       ParagraphFormat
    baseRun:               RunFormat
    directRun:             RunFormat
    paragraphReady:        bool
    inBody:                bool
    inParagraph:           bool
    inParagraphProperties: bool
    inRun:                 bool
    inRunProperties:       bool
    inText:                bool
    inImage:               bool
    imageId:               String
    imageDescription:      String
    imageWidth:            u32
    imageHeight:           u32
}

private impl Reader
{
    mtd appendInline(value: string)
    {
        if .inRun do
            .run += value
        else do
            .paragraph += value
    }

    mtd finishImage()
    {
        if not .inImage do
            return
        let image = .images.html(.imageId, .imageWidth, .imageHeight, .imageDescription)
        if image.isEmpty()
        {
            .document.omittedImages += 1
            var notice: String
            Package.appendHtmlEscaped(&notice, texts().ui_ImageOmitted)
            if not .imageDescription.isEmpty()
            {
                notice += ": "
                Package.appendHtmlEscaped(&notice, .imageDescription)
            }

            .appendInline(notice)
        }
        else
        {
            .appendInline(image)
        }

        .inImage = false
        .imageId.clear()
        .imageDescription.clear()
        .imageWidth  = 0
        .imageHeight = 0
    }

    mtd prepareParagraph()
    {
        if .paragraphReady do
            return
        .paragraphFormat = .styles.defaultParagraph
        .baseRun         = .styles.defaultRun
        if .styles.loaded
        {
            if .baseRun.bold == .Inherit do
                .baseRun.bold = .Off
            if .baseRun.italic == .Inherit do
                .baseRun.italic = .Off
        }

        let id = .paragraphId.isEmpty() ? .styles.defaultParagraphId : .paragraphId
        if not id.isEmpty()
        {
            if let style = .styles.lookup(id, .Paragraph)
            {
                .paragraphFormat.overlay(&style.paragraph)
                .baseRun.applyStyle(&style.run)
                if style.limited do
                    .document.stylesSimplified = true
            }
            else
            {
                if .styles.loaded do
                    .document.stylesSimplified = true

                // Minimal producers sometimes omit the style part but retain built-in heading IDs.
                let value = id.toString()
                if Utf8.startsWith(value, "Heading") and
                   value.count == 8 and
                   value[7] >= '1'u8 and
                   value[7] <= '6'u8 do
                    .paragraphFormat.outline = cast(s32, value[7] - '1'u8)
            }
        }

        .paragraphFormat.overlay(&.directParagraph)
        if .paragraphFormat.limited or .baseRun.limited do
            .document.stylesSimplified = true
        .paragraphReady = true
    }

    mtd finishRun()
    {
        if not .inRun do
            return
        .prepareParagraph()
        var format = .baseRun
        if not .characterId.isEmpty()
        {
            if let style = .styles.lookup(.characterId, .Character)
            {
                format.applyStyle(&style.run)
                if style.limited do
                    .document.stylesSimplified = true
            }
            else
            {
                .document.stylesSimplified = true
            }
        }

        format.overlay(&.directRun)
        if format.limited do
            .document.stylesSimplified = true
        if not format.color.isEmpty() or not format.highlight.isEmpty() do
            .document.usePaperColors = true
        format.appendHtml(&.paragraph, .run)
        .run.clear()
        .inRun  = false
        .inRunProperties = false
        .inText = false
    }

    mtd finishParagraph()
    {
        if not .inParagraph do
            return
        .finishRun()
        .prepareParagraph()
        if .paragraphFormat.pageBefore == .On do
            .document.html += "<hr>"
        var tag: string = "p"
        switch .paragraphFormat.heading()
        {
        case 1: tag = "h1"
        case 2: tag = "h2"
        case 3: tag = "h3"
        case 4: tag = "h4"
        case 5: tag = "h5"
        case 6: tag = "h6"
        }

        .document.html += "<"
        .document.html += tag
        let css = .paragraphFormat.css()
        if not css.isEmpty()
        {
            .document.html += " style=\""
            Package.appendHtmlEscaped(&.document.html, css)
            .document.html += "\""
        }

        .document.html += ">"
        .document.html += .paragraph
        .document.html += "</"
        .document.html += tag
        .document.html += ">"
        .paragraph.clear()
        .document.paragraphs   += 1
        .inParagraph           = false
        .inParagraphProperties = false
    }

    mtd setParagraphProperty(token: const *Package.Token)
    {
        if token.isElement("pStyle") do
            .paragraphId = token.attribute("val") orelse ""
        else do
            .directParagraph.read(token)
    }

    mtd setRunProperty(token: const *Package.Token)
    {
        if token.isElement("rStyle") do
            .characterId = token.attribute("val") orelse ""
        else do
            .directRun.read(token, &.theme)
    }

    internal mtd start(token: const *Package.Token)
    {
        if not .inBody and token.isElement("background")
        {
            let color = token.attribute("color") orelse "auto"
            if Package.isRgbHex(color)
            {
                .document.paperColor     = color
                .document.usePaperColors = true
            }
            elif color != "auto"
            {
                .document.stylesSimplified = true
            }

            if not token.empty do
                .document.stylesSimplified = true
        }

        if token.isElement("body") do
            .inBody = true
        if not .inBody do
            return

        if .inImage
        {
            if token.isElement("extent") and not .imageWidth
            {
                let cx = catch StrConv.toU64(token.attribute("cx") orelse "") { return; }
                let cy = catch StrConv.toU64(token.attribute("cy") orelse "") { return; }
                if cx >= 9525 and cy >= 9525 and cx <= 39_014_400 and cy <= 39_014_400
                {
                    .imageWidth  = cast(u32, (cx + 4762) / 9525)
                    .imageHeight = cast(u32, (cy + 4762) / 9525)
                }
            }
            elif token.isElement("blip")
            {
                let id = token.attribute("r:embed")
                if id do
                    .imageId = id
            }
            elif token.isElement("imagedata")
            {
                let id = token.attribute("r:id")
                if id do
                    .imageId = id
            }
            elif token.isElement("docPr")
            {
                let description = token.attribute("descr") orelse token.attribute("title") orelse ""
                .imageDescription = description
            }

            return
        }

        if token.isElement("drawing") or token.isElement("pict")
        {
            .inImage = true
            if token.empty do
                .finishImage()
            return
        }

        if token.isElement("tbl")
        {
            .document.tables += 1
            .document.html   += "<table>"
        }
        elif token.isElement("tr")
        {
            .document.html += "<tr>"
        }
        elif token.isElement("tc")
        {
            .document.html += "<td>"
        }
        elif token.isElement("p")
        {
            .inParagraph = true
            .paragraphId.clear()
            .directParagraph = {}
            .paragraphReady  = false
            if token.empty do
                .finishParagraph()
        }
        elif .inParagraph and token.isElement("pPr")
        {
            .inParagraphProperties = not token.empty
        }
        elif .inParagraphProperties
        {
            .setParagraphProperty(token)
        }
        elif .inParagraph and token.isElement("r")
        {
            .inRun = true
            .prepareParagraph()
            .directRun = {}
            .characterId.clear()
            if token.empty do
                .finishRun()
        }
        elif .inRun and token.isElement("rPr")
        {
            .inRunProperties = not token.empty
        }
        elif .inRunProperties
        {
            .setRunProperty(token)
        }
        elif token.isElement("t")
        {
            .inText = not token.empty
        }
        elif token.isElement("br")
        {
            if token.attribute("type") == "page" do
                .appendInline("<hr>")
            else do
                .appendInline("<br>")
        }
        elif token.isElement("tab")
        {
            .appendInline("&emsp;")
        }
    }

    internal mtd end(token: const *Package.Token)
    {
        if token.isElement("body")
        {
            .inBody = false
            return
        }

        if not .inBody do
            return
        if .inImage
        {
            if token.isElement("drawing") or token.isElement("pict") do
                .finishImage()
            return
        }

        if token.isElement("t") do
            .inText = false
        elif token.isElement("rPr") do
            .inRunProperties = false
        elif token.isElement("r") do
            .finishRun()
        elif token.isElement("pPr") do
            .inParagraphProperties = false
        elif token.isElement("p") do
            .finishParagraph()
        elif token.isElement("tc") do
            .document.html += "</td>"
        elif token.isElement("tr") do
            .document.html += "</tr>"
        elif token.isElement("tbl") do
            .document.html += "</table>"
    }
}
