#global internal
#global namespace Viewers.Odp

using Core

private struct Reader
{
    fileName:     string = ""
    late archive: const *Archive.Zip
    late styles:  const *Styles
    width:        f32    = 960
    height:       f32    = 720
    encodedBytes: u64
    textBytes:    u64
}

private impl Reader
{
    mtd shape(source: string)->Pptx.SlideShape fail
    {
        var result: Pptx.SlideShape
        var scan = Package.Scanner.create(source)
        var root:   Package.Token
        if not scan.next(&root) or root.kind != .Start do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        result.hidden = root.attribute("placeholder") == "true" or root.attribute("visibility") == "hidden"
        result.placeholderKind = root.attribute("class") orelse ""
        if root.attribute("transform") != null do
            result.unsupported = true
        let x      = Odf.points(root.attribute("x") orelse "0pt")
        let y      = Odf.points(root.attribute("y") orelse "0pt")
        let width  = Odf.points(root.attribute("width") orelse "")
        let height = Odf.points(root.attribute("height") orelse "")
        result.positioned = x.valid and
                            y.valid and
                            width.valid and
                            height.valid and
                            width.value > 0 and
                            height.value > 0
        result.bounds = {cast(f32, x.value * 4 / 3), cast(f32, y.value * 4 / 3), cast(f32, width.value * 4 / 3), cast(f32, height.value * 4 / 3)}
        var drawStyle         = root.attribute("draw:style-name") orelse ""
        var presentationStyle = root.attribute("presentation:style-name") orelse ""
        if not drawStyle.count and not presentationStyle.count
        {
            let local = root.attribute("style-name") orelse ""
            if root.attribute("class") != null do
                presentationStyle = local
            else do
                drawStyle = local
        }

        var paint = .styles.paint(drawStyle, "graphic")
        var base: Docx.RunFormat
        base.size  = 36
        base.color = "000000"
        let graphic = .styles.typography.lookup(drawStyle, .Graphic)
        graphic.applyRun(&base)
        if presentationStyle.count
        {
            let other = .styles.paint(presentationStyle, "presentation")
            paint.overlay(&other)
            let properties = .styles.typography.lookup(presentationStyle, .Presentation)
            properties.applyRun(&base)
        }

        let textStyle = .styles.typography.lookup(root.attribute("text-style-name") orelse "", .Paragraph)
        textStyle.applyRun(&base)
        result.fontSize    = base.size * 50
        result.textColor   = base.color
        result.fill        = paint.fillEnabled == .Off ? String{} : paint.fill
        result.line        = paint.lineEnabled == .Off ? String{} : paint.line
        result.lineWidth   = paint.lineWidth
        result.inset       = {paint.inset[0], paint.inset[1], paint.inset[2], paint.inset[3]}
        result.centered    = paint.centered == .On
        result.unsupported = result.unsupported or paint.limited
        if root.isElement("custom-shape")
        {
            var kind:  String
            var token: Package.Token
            while scan.next(&token) do
                if token.kind == .Start and token.isElement("enhanced-geometry") do
                    kind = token.attribute("type") orelse ""
            result.round = kind == "round-rectangle" or kind == "round-rect"
            if kind != "rectangle" and kind != "rect" and not result.round do
                result.unsupported = true
        }
        elif not root.isElement("frame") and not root.isElement("rect")
        {
            result.unsupported = true
        }

        let text = try readText(source, &.styles.typography, base, .width)
        result.html        = text.html
        result.plainText   = text.plain
        result.unsupported = result.unsupported or text.limited
        if not root.isElement("frame") and
           not root.isElement("rect") and
           not root.isElement("custom-shape") and
           result.html.isEmpty() do
            result.html = texts().ui_ObjectOmitted
        var paths:       Array'String
        var description: String
        scan = Package.Scanner.create(source)
        var token: Package.Token
        var inDescription = false
        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if token.isElement("image")
                {
                    paths.add(String.from(token.attribute("href") orelse ""))
                    if paths.count > 8 do
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                }

                if token.isElement("title") or token.isElement("desc") do
                    inDescription = true
                if token.isElement("object") or
                   token.isElement("object-ole") or
                   token.isElement("plugin") or
                   token.isElement("table")
                {
                    result.html        += texts().ui_ObjectOmitted
                    result.unsupported = true
                }
            }
            elif token.kind == .Text and inDescription
            {
                description += token.text
            }

            if token.kind == .End and (token.isElement("title") or token.isElement("desc")) do
                inDescription = false
            if description.count > 1024 do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }

        if not paths.isEmpty()
        {
            result.picture = true
            result.html.clear()
            for path in paths
            {
                let image = Odf.imageHtml(.fileName, .archive, path.toString(), 0, 0, description, &.encodedBytes)
                if image.isEmpty() do
                    continue
                result.html = image
                break
            }

            if result.html.isEmpty()
            {
                result.html          = Pptx.texts().ui_ImageOmitted
                result.picture       = false
                result.omittedImages = 1
            }
        }

        .textBytes += result.html.count
        if .textBytes > 32 * 1024 * 1024 do
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        return result
    }

    mtd page(source: string, masterMode = false)->Pptx.SlidePage fail
    {
        var result: Pptx.SlidePage
        result.background = "FFFFFF"
        var scan       = Package.Scanner.create(source)
        var token: Package.Token
        var depth      = 0'u64
        var skip       = Swag.U64.Max
        var shapeAt    = Swag.U64.Max
        var shapeDepth = Swag.U64.Max
        var notesAt    = Swag.U64.Max
        while true
        {
            let at = scan.offset
            if not scan.next(&token) do
                break
            if token.kind == .Start
            {
                depth += 1
                if skip == Swag.U64.Max
                {
                    if token.isElement("notes") and not masterMode do
                        notesAt = at
                    if token.isElement("notes") or
                       token.isElement("annotation") or
                       token.isElement("animations") or
                       token.isElement("scripts") or
                       token.isElement("event-listeners")
                    {
                        skip = depth
                    }
                    elif shapeAt == Swag.U64.Max
                    {
                        if token.isElement("g")
                        {
                            result.simplified = true
                        }
                        elif token.isElement("frame") or
                             token.isElement("rect") or
                             token.isElement("custom-shape") or
                             token.isElement("ellipse") or
                             token.isElement("path") or
                             token.isElement("line") or
                             token.isElement("connector")
                        {
                            if masterMode and (token.attribute("placeholder") == "true" or token.attribute("class") != null)
                            {
                                skip = depth
                            }
                            else
                            {
                                shapeAt    = at
                                shapeDepth = depth
                            }
                        }
                    }
                }
            }

            if token.kind == .End or token.empty
            {
                if skip == depth
                {
                    if notesAt != Swag.U64.Max
                    {
                        result.notesHtml += try readSpeakerNotes(source[notesAt until scan.offset], &.styles.typography)
                        .textBytes       += result.notesHtml.count
                        if .textBytes > 32 * 1024 * 1024 do
                            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                        notesAt = Swag.U64.Max
                    }

                    skip = Swag.U64.Max
                }
                elif skip == Swag.U64.Max and shapeDepth == depth
                {
                    let shape = try .shape(source[shapeAt until scan.offset])
                    if not shape.hidden
                    {
                        result.shapes.add(shape)
                        result.simplified    = result.simplified or shape.unsupported or not shape.positioned
                        result.omittedImages += shape.omittedImages
                        if result.shapes.count > 2048 do
                            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                    }

                    shapeAt    = Swag.U64.Max
                    shapeDepth = Swag.U64.Max
                }

                depth -= 1
            }
        }

        if scan.damaged do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        return result
    }
}

// Impress pages adapt to the same fitted slide and text-reading controls as PowerPoint.
func load(fileName: string)->Pptx.Presentation fail
{
    let archive = try Odf.openPackage(fileName, "application/vnd.oasis.opendocument.presentation", texts().err_Invalid, texts().err_TooLarge, texts().err_Encrypted)
    let parts   = Package.PartReader{fileName, &archive, texts().err_Invalid, texts().err_TooLarge}
    let content = try parts.text("content.xml")
    var styles: Styles
    try styles.read(try parts.text("styles.xml", required: false, limit: 8 * 1024 * 1024))
    try styles.read(content)
    styles.typography.finish()
    var reader: Reader
    reader.fileName = fileName
    reader.archive  = &archive
    reader.styles   = &styles
    var result:     Pptx.Presentation
    var scan         = Package.Scanner.create(content)
    var token:      Package.Token
    var depth        = 0'u64
    var presentation = Swag.U64.Max
    var pageAt       = Swag.U64.Max
    var pageDepth    = Swag.U64.Max
    var title:      String
    var hidden       = false
    var masterName: String
    var pageStyle:  String
    while true
    {
        let at = scan.offset
        if not scan.next(&token) do
            break
        if token.kind == .Start
        {
            depth += 1
            if token.isElement("presentation")
            {
                presentation = depth
            }
            elif presentation != Swag.U64.Max and depth == presentation + 1 and token.isElement("page")
            {
                pageAt     = at
                pageDepth  = depth
                title      = token.attribute("name") orelse ""
                hidden     = token.attribute("visibility") == "hidden"
                masterName = token.attribute("master-page-name") orelse ""
                pageStyle  = token.attribute("style-name") orelse ""
                if let master = styles.masters.tryFind(masterName)
                {
                    if let layout = styles.layouts.tryFind(master.value.layout)
                    {
                        if result.slides.isEmpty()
                        {
                            reader.width  = layout.value.x
                            reader.height = layout.value.y
                            result.width  = reader.width
                            result.height = reader.height
                        }
                    }
                }
            }
        }

        if token.kind == .End or token.empty
        {
            if depth == pageDepth
            {
                var page  = try reader.page(content[pageAt until scan.offset])
                var background: String
                let paint = styles.paint(pageStyle, "drawing-page")
                if let master = styles.masters.tryFind(masterName)
                {
                    if paint.showMaster != .Off
                    {
                        let inherited = try reader.page(master.value.source, true)
                        page.shapes.insertAt(0, inherited.shapes.toSlice())
                        page.simplified    = page.simplified or inherited.simplified
                        page.omittedImages += inherited.omittedImages
                    }

                    let masterPaint = styles.paint(master.value.style, "drawing-page")
                    if masterPaint.fillEnabled != .Off do
                        background = masterPaint.fill
                    if let layout = styles.layouts.tryFind(master.value.layout) do
                        if Math.abs(layout.value.x - reader.width) > 0.1 or Math.abs(layout.value.y - reader.height) > 0.1 do
                            page.simplified = true
                }

                if paint.fillEnabled == .Off do
                    background.clear()
                elif paint.mask & 1 do
                    background = paint.fill
                if paint.showBackground != .Off and not background.isEmpty() do
                    page.background = background
                page.simplified = page.simplified or paint.limited
                if not masterName.isEmpty()
                {
                    let master = styles.masters.tryFind(masterName)
                    if not master do
                        page.simplified = true
                    elif not styles.layouts.tryFind(master.value.layout) do
                        page.simplified = true
                }

                page.title = title
                for shape in page.shapes where not shape.plainText.isEmpty()
                {
                    if shape.isTitle() or page.title.isEmpty()
                    {
                        page.title = shape.plainText
                        page.title.trim()
                        break
                    }
                }

                if hidden do
                    page.title = Format.toString(texts().ui_Hidden, page.title)
                if page.shapes.count > 2048 or page.title.count > 4096 do
                    fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                result.omittedImages += page.omittedImages
                result.slides.add(page)
                if result.slides.count > 200 do
                    fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                pageAt    = Swag.U64.Max
                pageDepth = Swag.U64.Max
            }

            if presentation == depth do
                presentation = Swag.U64.Max
            depth -= 1
        }
    }

    if scan.damaged or result.slides.isEmpty() do
        fail Errors.InvalidFormatError{texts().err_Invalid}
    return result
}
