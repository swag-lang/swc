#global internal
#global namespace Viewers.Docx

using Core

// Only Word bookmark names made of ASCII letters, digits and underscores become HTML fragments.
private func bookmarkFragment(name: string)->String
{
    if not name.count or name.count > 40 do
        return {}
    for byte, index in name
    {
        if byte >= 128 or (not Latin1.isLetterOrDigit(byte) and byte != '_'u8) do
            return {}
        if not index and not Latin1.isLetter(byte) and byte != '_'u8 do
            return {}
    }

    return Format.toString("docx-bookmark-%", name)
}

// A paragraph and its formatted runs are assembled before their HTML tags are chosen.
private struct Reader
{
    document:              Document
    images:                Package.ImageCatalog
    numbering:             NumberingCatalog
    footnotes:             FootnoteCatalog
    comments:              CommentCatalog
    sectionLayout:         PageLayout
    sectionHtml:           String
    sectionBreak:          String
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
    inSectionProperties:   bool
    inCellProperties:      bool
    cellTagOpen:           bool
    cellWidthSet:          bool
    cellAlignmentSet:      bool
    cellStyle:             String
    imageId:               String
    imageDescription:      String
    imageWidth:            u32
    imageHeight:           u32
    headerId:              String
    footerId:              String
    paragraphNumId:        String
    paragraphNumLevel:     u8
    inNumberProperties:    bool
    paragraphEndsSection:  bool
    openListIds:           Array'String
    openListLevels:        Array'u8
    openListTags:          Array'String
    numberingLimited:      bool
    paragraphHasNumPr:     bool
    footnoteReferences:    Array'String
    footnotesLimited:      bool
    commentReferences:     Array'String
    commentRangeStarts:    Array's32
    commentRangeEnds:      Array's32
    commentsLimited:       bool
    bookmarkNames:         Array'String
    bookmarkReferences:    Array'String
    hyperlinkOpen:         bool
}

private impl Reader
{
    mtd readPageSize(token: const *Package.Token)
    {
        let width  = catch StrConv.toS32(token.attribute("w") orelse "") orelse 0
        let height = catch StrConv.toS32(token.attribute("h") orelse "") orelse 0
        if width < 3600 or width > 43200 or height < 3600 or height > 43200
        {
            .document.sectionLayoutSimplified = true
            return
        }

        .sectionLayout.width  = width
        .sectionLayout.height = height
    }

    mtd readPageMargins(token: const *Package.Token)
    {
        let gutter = catch StrConv.toS32(token.attribute("gutter") orelse "0") orelse -1
        if gutter != 0 do
            .document.sectionLayoutSimplified = true

        let names: [4] string = ["top", "right", "bottom", "left"]
        for name, index in names
        {
            let value = catch StrConv.toS32(token.attribute(name) orelse "") orelse -1
            if value < 0 or value > 31680
            {
                .document.sectionLayoutSimplified = true
                continue
            }

            switch index
            {
            case 0: .sectionLayout.marginTop = value
            case 1: .sectionLayout.marginRight = value
            case 2: .sectionLayout.marginBottom = value
            case 3: .sectionLayout.marginLeft = value
            }

            .sectionLayout.marginMask |= cast(u8, 1 << index)
        }
    }

    mtd readSectionType(token: const *Package.Token)
    {
        .sectionBreak = token.attribute("val") orelse "nextPage"
        if .sectionBreak != "nextPage" and
           .sectionBreak != "continuous" and
           .sectionBreak != "evenPage" and
           .sectionBreak != "oddPage"
        {
            .document.sectionLayoutSimplified = true
            .sectionBreak = "nextPage"
        }
        elif .sectionBreak == "evenPage" or .sectionBreak == "oddPage"
        {
            // A continuous HTML flow cannot preserve which physical page parity Word starts on.
            .document.sectionLayoutSimplified = true
        }
    }

    mtd closeCellTag()
    {
        if not .cellTagOpen do
            return
        if not .cellStyle.isEmpty()
        {
            .sectionHtml += " style=\""
            Package.appendHtmlEscaped(&.sectionHtml, .cellStyle.toString())
            .sectionHtml += "\""
        }

        .sectionHtml += ">"
        .cellTagOpen = false
    }

    mtd flushSection()
    {
        .closeLists()
        if .sectionHtml.count do
            .document.html += .sectionHtml

        // HtmlView exposes one flowing page box. Keep the final section's geometry on
        // the document body and disclose that earlier section geometry is a projection.
        if .paragraphEndsSection do
            .document.sectionLayoutSimplified = true

        .document.pageWidth    = .sectionLayout.width
        .document.pageHeight   = .sectionLayout.height
        .document.marginTop    = .sectionLayout.marginTop
        .document.marginRight  = .sectionLayout.marginRight
        .document.marginBottom = .sectionLayout.marginBottom
        .document.marginLeft   = .sectionLayout.marginLeft
        .document.marginMask   = .sectionLayout.marginMask
        .sectionHtml.clear()
        if .paragraphEndsSection and .sectionBreak != "continuous" do
            .document.html += "<hr>"
        .sectionBreak         = "nextPage"
        .paragraphEndsSection = false
    }

    mtd appendInline(value: string)
    {
        if .inRun do
            .run += value
        else do
            .paragraph += value
    }

    mtd readFootnoteReference(token: const *Package.Token)
    {
        let rawId     = token.attribute("id") orelse ""
        var idError: Swag.Error
        let numericId = catch StrConv.toS32(rawId) as idError orelse 0
        if rawId.count == 0 or idError.value() != null or numericId <= 0
        {
            .appendInline(texts().ui_FootnoteOmitted)
            .document.footnotesSimplified = true
            return
        }

        let id   = Format.toString("%", numericId)
        let note = .footnotes.lookup(id.toString())
        .appendInline("<sup>")
        .appendInline(id.toString())
        .appendInline("</sup>")
        if not note.found
        {
            .appendInline(texts().ui_FootnoteOmitted)
            .document.footnotesSimplified = true
            return
        }

        if note.limited or .footnotesLimited do
            .document.footnotesSimplified = true
        for reference in .footnoteReferences where reference == id do
            return
        .footnoteReferences.add(id)
    }

    mtd readCommentReference(token: const *Package.Token)
    {
        let rawId     = token.attribute("id") orelse ""
        var idError: Swag.Error
        let numericId = catch StrConv.toS32(rawId) as idError orelse -1
        if rawId.count == 0 or idError.value() != null or numericId < 0
        {
            .appendInline(texts().ui_CommentOmitted)
            .document.commentsSimplified = true
            return
        }

        let id      = Format.toString("%", numericId)
        let comment = .comments.lookup(id.toString())
        if not comment.found
        {
            .appendInline(texts().ui_CommentOmitted)
            .document.commentsSimplified = true
            return
        }

        .appendInline(Format.toString("<sup class=\"docx-comment-reference\"><a href=\"#docx-comment-%\">", id))
        .appendInline(id.toString())
        .appendInline("</a>")
        .appendInline("</sup>")
        .document.commentsSimplified = true
        if comment.limited or .commentsLimited do
            .document.commentsSimplified = true
        for reference in .commentReferences where reference == id do
            return
        if .commentReferences.count >= 4096 do
            return
        .commentReferences.add(id)
    }

    mtd readCommentRange(token: const *Package.Token, start: bool)
    {
        let rawId     = token.attribute("id") orelse ""
        var idError: Swag.Error
        let numericId = catch StrConv.toS32(rawId) as idError orelse -1
        if rawId.count == 0 or idError.value() != null or numericId < 0
        {
            .document.commentsSimplified = true
            return
        }

        if start
        {
            for value in .commentRangeStarts where value == numericId
            {
                .document.commentsSimplified = true
                return
            }

            if .commentRangeStarts.count >= 4096
            {
                .document.commentsSimplified = true
                return
            }

            .commentRangeStarts.add(numericId)
            .appendInline(Format.toString("<a id=\"docx-comment-range-%\"></a>", numericId))
            return
        }

        var foundStart = false
        for value in .commentRangeStarts where value == numericId do
            foundStart = true
        if not foundStart
        {
            .document.commentsSimplified = true
            return
        }

        for value in .commentRangeEnds where value == numericId
        {
            .document.commentsSimplified = true
            return
        }

        .commentRangeEnds.add(numericId)
    }

    mtd readBookmark(token: const *Package.Token)
    {
        let name     = token.attribute("name") orelse ""
        let fragment = bookmarkFragment(name)
        if fragment.isEmpty()
        {
            .document.linksSimplified = true
            return
        }

        for bookmark in .bookmarkNames where Utf8.compare(bookmark.toString(), name) == 0
        {
            .document.linksSimplified = true
            return
        }

        if .bookmarkNames.count >= 4096
        {
            .document.linksSimplified = true
            return
        }

        .bookmarkNames.add(name)
        .appendInline(Format.toString("<a id=\"%\"></a>", fragment))
    }

    mtd startHyperlink(token: const *Package.Token)
    {
        if token.empty do
            return
        if token.attribute("r:id")
        {
            .document.linksSimplified = true
            return
        }

        let name     = token.attribute("anchor") orelse ""
        let fragment = bookmarkFragment(name)
        if fragment.isEmpty() or .hyperlinkOpen
        {
            .document.linksSimplified = true
            return
        }

        .hyperlinkOpen = true
        var known = false
        for reference in .bookmarkReferences where Utf8.compare(reference.toString(), name) == 0 do
            known = true
        if not known and .bookmarkReferences.count < 4096 do
            .bookmarkReferences.add(name)
        elif not known do
            .document.linksSimplified = true

        .appendInline(Format.toString("<a href=\"#%\">", fragment))
    }

    mtd finishHyperlink()
    {
        if not .hyperlinkOpen do
            return
        .appendInline("</a>")
        .hyperlinkOpen = false
    }

    internal mtd footnotesHtml()->String
    {
        if not .footnoteReferences.count do
            return {}
        var result: String = "<section><h2>"
        result += texts().ui_FootnotesTitle
        result += "</h2>"
        for id in .footnoteReferences
        {
            let note = .footnotes.lookup(id.toString())
            if not note.found
            {
                .document.footnotesSimplified = true
                continue
            }

            if note.limited or .footnotesLimited do
                .document.footnotesSimplified = true
            result += "<div><sup>"
            Package.appendHtmlEscaped(&result, id.toString())
            result += "</sup>"
            result += note.html
            result += "</div>"
        }

        result += "</section>"
        return result
    }

    internal mtd commentsHtml()->String
    {
        if not .commentReferences.count do
            return {}
        var result: String = "<section class=\"docx-comments\"><h2>"
        result += texts().ui_CommentsTitle
        result += "</h2>"
        var rendered = false
        for id in .commentReferences
        {
            let comment = .comments.lookup(id.toString())
            if not comment.found do
                continue

            rendered = true
            result   += Format.toString("<div id=\"docx-comment-%\"><p class=\"docx-comment-author\"><strong>", id)
            Package.appendHtmlEscaped(&result, comment.author.toString())
            result += "</strong></p>"
            result += comment.html
            var hasRange  = false
            let numericId = catch StrConv.toS32(id.toString()) orelse -1
            for start in .commentRangeStarts where start == numericId do
                hasRange = true

            if hasRange
            {
                result += Format.toString("<p><a href=\"#docx-comment-range-%\">", id)
                result += texts().ui_CommentReturn
                result += "</a></p>"
            }

            result += "</div>"
            if comment.limited or .commentsLimited do
                .document.commentsSimplified = true
        }

        if not rendered do
            return {}
        result += "</section>"
        return result
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
        let isList = not .paragraphNumId.isEmpty()
        var listStyle: ListStyle
        if isList
        {
            listStyle = .numbering.lookup(.paragraphNumId.toString(), .paragraphNumLevel)
            if listStyle.limited or .numberingLimited do
                .document.stylesSimplified = true
        }
        elif .paragraphHasNumPr
        {
            .document.stylesSimplified = true
        }

        if .paragraphFormat.pageBefore == .On
        {
            .closeLists()
            .sectionHtml += "<hr>"
        }

        if isList
        {
            while .openListLevels.count and .openListLevels[.openListLevels.count - 1] > .paragraphNumLevel do
                .closeListLevel()

            if .openListLevels.count and
               .openListLevels[.openListLevels.count - 1] == .paragraphNumLevel and
               .openListIds[.openListIds.count - 1] == .paragraphNumId
            {
                .sectionHtml += "</li><li>"
            }
            else
            {
                if .openListLevels.count and .openListLevels[.openListLevels.count - 1] == .paragraphNumLevel do
                    .closeListLevel()
                if .openListLevels.count and .paragraphNumLevel > .openListLevels[.openListLevels.count - 1] + 1
                {
                    .document.stylesSimplified = true
                    .closeLists()
                }

                .sectionHtml += "<"
                .sectionHtml += listStyle.tag
                if not listStyle.type.isEmpty()
                {
                    .sectionHtml += " type=\""
                    .sectionHtml += listStyle.type
                    .sectionHtml += "\""
                }

                if listStyle.tag == "ol" and listStyle.start != 1 do
                    .sectionHtml += Format.toString(" start=\"%\"", listStyle.start)
                .sectionHtml += ">"
                .sectionHtml += "<li>"
                .openListIds.add(.paragraphNumId)
                .openListLevels.add(.paragraphNumLevel)
                .openListTags.add(listStyle.tag)
            }
        }
        else
        {
            .closeLists()
        }

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

        .sectionHtml += "<"
        .sectionHtml += tag
        let css = .paragraphFormat.css()
        if not css.isEmpty()
        {
            .sectionHtml += " style=\""
            Package.appendHtmlEscaped(&.sectionHtml, css)
            .sectionHtml += "\""
        }

        .sectionHtml += ">"
        .sectionHtml += .paragraph
        .sectionHtml += "</"
        .sectionHtml += tag
        .sectionHtml += ">"
        .paragraph.clear()
        .document.paragraphs += 1
        if isList do
            .paragraphNumId.clear()
        .inParagraph = false
        .inParagraphProperties = false
        if .paragraphEndsSection do
            .flushSection()
    }

    mtd closeListLevel()
    {
        if not .openListLevels.count do
            return
        .sectionHtml += "</li></"
        .sectionHtml += .openListTags[.openListTags.count - 1]
        .sectionHtml += ">"
        .openListIds.removeAt(.openListIds.count - 1)
        .openListLevels.removeAt(.openListLevels.count - 1)
        .openListTags.removeAt(.openListTags.count - 1)
    }

    mtd closeLists()
    {
        while .openListLevels.count do
            .closeListLevel()
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

        if token.isElement("sectPr")
        {
            if .inParagraph
            {
                // Word attaches this sectPr to the paragraph that ends the current section.
                .paragraphEndsSection = true
                .sectionBreak         = "nextPage"
                .inSectionProperties  = not token.empty
            }
            else
            {
                .inSectionProperties = not token.empty
                if token.empty do
                    .flushSection()
            }

            return
        }

        if .inSectionProperties
        {
            if token.isElement("headerReference") or token.isElement("footerReference")
            {
                let kind = token.isElement("headerReference") ? "header" : "footer"
                let id   = token.attribute("id") orelse ""
                let type = token.attribute("type") orelse "default"
                if type != "default"
                {
                    .document.pageElementsSimplified = true
                }
                elif kind == "header"
                {
                    if .headerId.isEmpty() do
                        .headerId = id
                    elif .headerId != id do
                        .document.pageElementsSimplified = true
                }
                else
                {
                    if .footerId.isEmpty() do
                        .footerId = id
                    elif .footerId != id do
                        .document.pageElementsSimplified = true
                }
            }
            elif token.isElement("pgSz")
            {
                .readPageSize(token)
            }
            elif token.isElement("pgMar")
            {
                .readPageMargins(token)
            }
            elif token.isElement("type")
            {
                .readSectionType(token)
            }
            elif token.isElement("cols") or token.isElement("docGrid")
            {
                .document.sectionLayoutSimplified = true
            }

            return
        }

        if .cellTagOpen and not .inCellProperties and not token.isElement("tcPr") do
            .closeCellTag()

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
            .closeLists()
            .document.tables += 1
            .sectionHtml     += "<table>"
        }
        elif token.isElement("tr")
        {
            .sectionHtml += "<tr>"
        }
        elif token.isElement("tc")
        {
            .sectionHtml      += "<td"
            .cellTagOpen      = true
            .inCellProperties = false
            .cellWidthSet     = false
            .cellAlignmentSet = false
            .cellStyle.clear()
            if token.empty do
                .closeCellTag()
        }
        elif token.isElement("tcPr")
        {
            .inCellProperties = not token.empty
        }
        elif .inCellProperties and token.isElement("gridSpan")
        {
            let span = catch StrConv.toS32(token.attribute("val") orelse "") orelse 0
            if span > 1 and span <= 63
            {
                .sectionHtml += Format.toString(" colspan=\"%\"", span)
            }
            elif span != 1
            {
                .document.stylesSimplified = true
            }
        }
        elif .inCellProperties and token.isElement("tcW")
        {
            let width = catch StrConv.toS32(token.attribute("w") orelse "") orelse 0
            let kind  = token.attribute("type") orelse "dxa"
            if .cellWidthSet
            {
                .document.stylesSimplified = true
            }
            elif kind == "dxa" and width > 0 and width <= 43200
            {
                let numbers: Globalization.NumberFormatInfo
                .cellStyle    += Format.toString("width:%px;", numbers.format(cast(f64, width) / 15, 2))
                .cellWidthSet = true
            }
            elif kind == "pct" and width > 0 and width <= 10000
            {
                let numbers: Globalization.NumberFormatInfo
                var percent = numbers.format(cast(f64, width) / 50, 2)
                percent       += "%"
                .cellStyle    += Format.toString("width:%;", percent)
                .cellWidthSet = true
            }
            elif kind != "auto"
            {
                .document.stylesSimplified = true
                .cellWidthSet = true
            }
        }
        elif .inCellProperties and token.isElement("vAlign")
        {
            let value = token.attribute("val") orelse "top"
            if .cellAlignmentSet
            {
                .document.stylesSimplified = true
            }
            elif value == "top" or value == "center" or value == "bottom"
            {
                .cellStyle        += Format.toString("vertical-align:%;", value == "center" ? "middle" : value)
                .cellAlignmentSet = true
            }
            else
            {
                .document.stylesSimplified = true
                .cellAlignmentSet = true
            }
        }
        elif token.isElement("p")
        {
            .inParagraph = true
            .paragraphId.clear()
            .paragraphNumId.clear()
            .paragraphNumLevel = 0
            .paragraphHasNumPr = false
            .directParagraph   = {}
            .paragraphReady    = false
            if token.empty do
                .finishParagraph()
        }
        elif .inParagraph and token.isElement("pPr")
        {
            .inParagraphProperties = not token.empty
        }
        elif .inParagraphProperties and token.isElement("numPr")
        {
            .inNumberProperties = not token.empty
            .paragraphHasNumPr  = true
        }
        elif .inNumberProperties and token.isElement("numId")
        {
            let numberId = token.attribute("val") orelse ""
            if numberId == "0"
            {
                .paragraphNumId.clear()
                .paragraphHasNumPr = false
            }
            else
            {
                .paragraphNumId = numberId
            }
        }
        elif .inNumberProperties and token.isElement("ilvl")
        {
            let level = catch StrConv.toS32(token.attribute("val") orelse "") orelse -1
            if level >= 0 and level <= 8
            {
                .paragraphNumLevel = cast(u8, level)
            }
            else
            {
                .document.stylesSimplified = true
            }
        }
        elif .inParagraphProperties
        {
            .setParagraphProperty(token)
        }
        elif .inParagraph and token.isElement("bookmarkStart")
        {
            .readBookmark(token)
        }
        elif .inParagraph and token.isElement("commentRangeStart")
        {
            .readCommentRange(token, true)
        }
        elif .inParagraph and token.isElement("commentRangeEnd")
        {
            .readCommentRange(token, false)
        }
        elif .inParagraph and token.isElement("hyperlink")
        {
            .startHyperlink(token)
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
        elif .inRun and token.isElement("footnoteReference")
        {
            .readFootnoteReference(token)
        }
        elif .inRun and token.isElement("commentReference")
        {
            .readCommentReference(token)
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
            .closeLists()
            .flushSection()
            .inBody = false
            return
        }

        if token.isElement("sectPr")
        {
            .inSectionProperties = false
            if not .inParagraph do
                .flushSection()
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

        if token.isElement("hyperlink")
        {
            .finishHyperlink()
        }
        elif token.isElement("t")
        {
            .inText = false
        }
        elif token.isElement("rPr")
        {
            .inRunProperties = false
        }
        elif token.isElement("r")
        {
            .finishRun()
        }
        elif token.isElement("pPr")
        {
            .inParagraphProperties = false
        }
        elif token.isElement("numPr")
        {
            .inNumberProperties = false
        }
        elif token.isElement("tcPr")
        {
            .inCellProperties = false
            .closeCellTag()
        }
        elif token.isElement("p")
        {
            .finishParagraph()
        }
        elif token.isElement("tc")
        {
            .closeCellTag()
            .sectionHtml += "</td>"
        }
        elif token.isElement("tr")
        {
            .sectionHtml += "</tr>"
        }
        elif token.isElement("tbl")
        {
            .sectionHtml += "</table>"
        }
    }
}
