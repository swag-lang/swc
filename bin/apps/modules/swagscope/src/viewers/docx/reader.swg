#global internal
#global namespace Viewers.Docx

using Core

// A paragraph and its formatted runs are assembled before their HTML tags are chosen.
private struct Reader
{
    document:              Document
    images:                ImageCatalog
    paragraph:             String
    run:                   String
    alignment:             string = ""
    heading:               u32
    bold:                  bool
    italic:                bool
    underline:             bool
    strike:                bool
    inBody:                bool
    inParagraph:           bool
    inParagraphProperties: bool
    inRun:                 bool
    inRunProperties:       bool
    inText:                bool
    inImage:               bool
    imageId:               String
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
        let image = .images.html(.imageId, .imageWidth, .imageHeight)
        if image.isEmpty()
        {
            .document.omittedImages += 1
            var notice: String
            Package.appendHtmlEscaped(&notice, texts().ui_ImageOmitted)
            .appendInline(notice)
        }
        else do
            .appendInline(image)
        .inImage = false
        .imageId.clear()
        .imageWidth = 0
        .imageHeight = 0
    }

    mtd finishRun()
    {
        if not .inRun do
            return
        if .bold do
            .paragraph += "<b>"
        if .italic do
            .paragraph += "<i>"
        if .underline do
            .paragraph += "<u>"
        if .strike do
            .paragraph += "<s>"
        .paragraph += .run
        if .strike do
            .paragraph += "</s>"
        if .underline do
            .paragraph += "</u>"
        if .italic do
            .paragraph += "</i>"
        if .bold do
            .paragraph += "</b>"
        .run.clear()
        .inRun = false
        .inRunProperties = false
        .inText = false
    }

    mtd finishParagraph()
    {
        if not .inParagraph do
            return
        .finishRun()
        var tag: string = "p"
        switch .heading
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
        if .alignment.count
        {
            .document.html += " style=\"text-align:"
            .document.html += .alignment
            .document.html += "\""
        }
        .document.html += ">"
        .document.html += .paragraph
        .document.html += "</"
        .document.html += tag
        .document.html += ">"
        .paragraph.clear()
        .document.paragraphs += 1
        .inParagraph = false
        .inParagraphProperties = false
    }

    mtd setParagraphProperty(token: const *Package.Token)
    {
        let value = token.attribute("val") orelse ""
        if token.isElement("jc")
        {
            switch value
            {
            case "center": .alignment = "center"
            case "right", "end": .alignment = "right"
            case "both", "distribute": .alignment = "justify"
            case "left", "start": .alignment = "left"
            }
        }
        elif token.isElement("outlineLvl")
        {
            if value.count == 1 and value[0] >= '0'u8 and value[0] <= '5'u8 do
                .heading = cast(u32, value[0] - '0'u8) + 1
        }
        elif token.isElement("pStyle")
        {
            if Utf8.startsWith(value, "Heading") and value.count == 8 and
               value[7] >= '1'u8 and value[7] <= '6'u8 do
                .heading = cast(u32, value[7] - '0'u8)
        }
    }

    mtd setRunProperty(token: const *Package.Token)
    {
        let value = token.attribute("val") orelse ""
        let enabled = value != "0" and value != "false" and value != "off"
        if token.isElement("b") do
            .bold = enabled
        elif token.isElement("i") do
            .italic = enabled
        elif token.isElement("u") do
            .underline = enabled and value != "none"
        elif token.isElement("strike") do
            .strike = enabled
    }

    internal mtd start(token: const *Package.Token)
    {
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
                    .imageWidth = cast(u32, (cx + 4762) / 9525)
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
            .document.html += "<table>"
        }
        elif token.isElement("tr") do
            .document.html += "<tr>"
        elif token.isElement("tc") do
            .document.html += "<td>"
        elif token.isElement("p")
        {
            .inParagraph = true
            .alignment = ""
            .heading = 0
            if token.empty do
                .finishParagraph()
        }
        elif .inParagraph and token.isElement("pPr") do
            .inParagraphProperties = not token.empty
        elif .inParagraphProperties do
            .setParagraphProperty(token)
        elif .inParagraph and token.isElement("r")
        {
            .inRun = true
            .bold = false
            .italic = false
            .underline = false
            .strike = false
            if token.empty do
                .finishRun()
        }
        elif .inRun and token.isElement("rPr") do
            .inRunProperties = not token.empty
        elif .inRunProperties do
            .setRunProperty(token)
        elif token.isElement("t") do
            .inText = not token.empty
        elif token.isElement("br") do
            .appendInline("<br>")
        elif token.isElement("tab") do
            .appendInline("&emsp;")
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
