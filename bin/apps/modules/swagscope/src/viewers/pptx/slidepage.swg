#global internal
#global namespace Viewers.Pptx

using Core

// One slide and its safely decoded objects, before viewport fitting.
struct SlidePage
{
    shapes:           Array'SlideShape
    notesHtml:        String
    title:            String
    background:       String
    simplified:       bool
    omittedImages:    u64
    showMasterShapes: bool = true
}

impl SlidePage
{
    func parse(source: string, theme: const *SlideTheme, images: *Package.ImageCatalog? = null, pageWidth = 960.0, charts: const [..] SlideChart = [])->SlidePage fail
    {
        var result:    #returntype
        var scan         = Package.Scanner.create(source)
        var token:     Package.Token
        var shapeStart   = Swag.U64.Max
        var shapeName: String
        var inBackground = false
        while true
        {
            let at = scan.offset
            if not scan.next(&token) do
                break
            if token.kind == .Start
            {
                if token.isElement("sld") do
                    result.showMasterShapes = token.attribute("showMasterSp") != "0" and token.attribute("showMasterSp") != "false"
                if shapeStart == Swag.U64.Max and
                   (token.isElement("sp") or token.isElement("pic") or token.isElement("cxnSp") or token.isElement("graphicFrame"))
                {
                    shapeStart = at
                    shapeName  = token.name
                }

                if token.isElement("grpSp") or token.isElement("cxnSp") do
                    result.simplified = true
                if token.isElement("bgPr")
                {
                    inBackground = not token.empty
                }
                elif inBackground and (token.isElement("srgbClr") or token.isElement("schemeClr"))
                {
                    let value = token.attribute("val") orelse ""
                    let color = token.isElement("schemeClr") ? theme.color(value) : String.from(value)
                    if Package.isRgbHex(color) do
                        result.background = color
                }
            }

            if token.kind == .End and token.isElement("bgPr") do
                inBackground = false
            if shapeStart != Swag.U64.Max and
               token.name == shapeName and
               (token.kind == .End or token.empty)
            {
                let shapeSource = source[shapeStart until scan.offset]
                var shape = try SlideShape.parse(shapeSource, theme, images, pageWidth)
                if token.isElement("graphicFrame")
                {
                    if let chart = findSlideChart(charts, shapeSource)
                    {
                        shape.html      = chart.html.toString()
                        shape.plainText = chart.plainText.toString()
                    }
                    else
                    {
                        let table = try SlideTable.parse(shapeSource, theme, pageWidth)
                        if not table.html.isEmpty()
                        {
                            shape.html      = table.html.toString()
                            shape.plainText = table.plainText.toString()
                            result.simplified = result.simplified or table.requiresSimplified
                        }
                        else do
                            result.simplified = true
                    }
                }

                if not shape.hidden
                {
                    result.omittedImages += shape.omittedImages
                    result.shapes.add(shape)
                    if result.shapes.count > 2048 do
                        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
                }

                shapeStart = Swag.U64.Max
                shapeName.clear()
            }
        }

        if scan.damaged or shapeStart != Swag.U64.Max do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        return result
    }

    // Resolves inherited placeholder bounds without copying a layout's sample text into the slide.
    func load(parts: const *Package.PartReader, path: string, pageWidth: f32)->SlidePage fail
    {
        let relations  = try parts.relationships(path)
        let layoutPath = Package.relationshipPath(relations.toSlice(), "/slideLayout")
        var layoutSource: String
        var masterSource: String
        var masterPath:   String
        var theme      = SlideTheme.defaults()
        if not layoutPath.isEmpty()
        {
            layoutSource = try parts.text(layoutPath, required: false)
            let layoutRelations = try parts.relationships(layoutPath)
            masterPath = Package.relationshipPath(layoutRelations.toSlice(), "/slideMaster")
            if not masterPath.isEmpty()
            {
                masterSource = try parts.text(masterPath, required: false)
                theme.read(masterSource)
                let masterRelations = try parts.relationships(masterPath)
                let themePath       = Package.relationshipPath(masterRelations.toSlice(), "/theme")
                if not themePath.isEmpty() do
                    theme.read(try parts.text(themePath, required: false))
            }
        }

        func imageCatalog(parts: const *Package.PartReader, path: string)->Package.ImageCatalog fail
        {
            let directory = Package.parentPath(path)
            let relations = Format.toString("%/_rels/%.rels", directory, Path.fileName(path) orelse "")
            return try Package.ImageCatalog.load(parts.fileName,
                                                 parts.archive,
                                                 directory,
                                                 relations,
                                                 parts.invalidMessage,
                                                 parts.tooLargeMessage)
        }

        var masterImages = try imageCatalog(parts, masterPath)
        var layoutImages = try imageCatalog(parts, layoutPath)
        var master       = try SlidePage.parse(masterSource, &theme, &masterImages, pageWidth)
        var layout       = try SlidePage.parse(layoutSource, &theme, &layoutImages, pageWidth)
        for &shape in layout.shapes
        {
            if let parent = shape.placeholderIn(master.shapes.toSlice()) do
                shape.inherit(parent)
        }

        let source = try parts.text(path)
        let charts = try chartsForSlide(source, parts, path)
        theme.read(layoutSource)
        theme.read(source)
        var images    = try imageCatalog(parts, path)
        var result    = try SlidePage.parse(source, &theme, &images, pageWidth, charts.toSlice())
        let notesPath = Package.relationshipPath(relations.toSlice(), "/notesSlide")
        if not notesPath.isEmpty() do
            result.notesHtml = try readSpeakerNotes(try parts.text(notesPath), &theme)
        if result.background.isEmpty() do
            result.background = layout.background.isEmpty() ? master.background : layout.background
        if result.background.isEmpty() do
            result.background = theme.color("bg1")
        for &shape in result.shapes
        {
            if let parent = shape.placeholderIn(layout.shapes.toSlice()) do
                shape.inherit(parent)
            if let parent = shape.placeholderIn(master.shapes.toSlice()) do
                shape.inherit(parent)
            if not shape.fontSize do
                shape.fontSize = shape.isTitle() ? theme.titleSize : theme.bodySize
            if shape.textColor.isEmpty() do
                shape.textColor = theme.color("tx1")
            if (not shape.positioned and not shape.html.isEmpty()) or shape.unsupported do
                result.simplified = true
        }

        result.simplified = result.simplified or layout.simplified or (master.simplified and result.showMasterShapes)

        // Static master/layout shapes form the back of the slide; placeholder sample text does not.
        var inherited: Array'SlideShape
        for shape in master.shapes where not shape.placeholder and result.showMasterShapes do
            inherited.add(shape)
        for shape in layout.shapes where not shape.placeholder do
            inherited.add(shape)
        for &shape in inherited
        {
            result.omittedImages += shape.omittedImages
            if not shape.fontSize do
                shape.fontSize = theme.otherSize
            if shape.textColor.isEmpty() do
                shape.textColor = theme.color("tx1")
            if (not shape.positioned and not shape.html.isEmpty()) or shape.unsupported do
                result.simplified = true
        }

        result.shapes.insertAt(0, inherited.toSlice())
        if result.shapes.count > 2048 do
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        for shape in result.shapes where not shape.plainText.isEmpty()
        {
            if result.title.isEmpty() or shape.isTitle()
            {
                result.title = shape.plainText
                result.title.trim()
                let end = Utf8.indexOf(result.title, '\n'rune)
                if end != Swag.U64.Max do
                    result.title = result.title.toString()[0 until end]
            }

            if shape.isTitle() do
                break
        }

        return result
    }

    mtd const readingHtml()->String
    {
        var result: #returntype
        for shape in .shapes
        {
            // Author colors and canvas-relative font sizes belong to the slide, not the text view.
            let source = shape.html.toString()
            var at     = 0'u64
            while at < source.count
            {
                let span = Utf8.indexOf(source[at to], "<span style=")
                if span == Swag.U64.Max
                {
                    result += source[at to]
                    break
                }

                result += source[at until at + span]
                at     += span
                let end = Utf8.indexOf(source[at to], '>'rune)
                if end == Swag.U64.Max do
                    break
                at += end + 1
            }
        }

        result.replace("</span>", "")
        return result
    }

    // Percent geometry and viewport-relative type scale together as the canvas is fitted.
    mtd const canvasHtml(width, height: f32)->String
    {
        if .simplified
        {
            var result: String = "<html><body>"
            result += .readingHtml()
            result += "</body></html>"
            return result
        }

        var result: String = "<html><head><style>"
        result += "html,body{margin:0;padding:0;width:100vw;height:100vh;overflow:hidden}"
        result += "p{margin:0;line-height:1.15}"
        result += "</style></head>"
        result += Format.toString("<body style=\"background-color:#%;color:#000000\">", .background)
        for shape in .shapes where shape.positioned
        {
            let bounds = shape.bounds
            result += Format.toString("<div style=\"position:absolute;box-sizing:border-box;left:%{f4}%%;top:%{f4}%%;width:%{f4}%%;height:%{f4}%%;",
                                      bounds.x / width * 100,
                                      bounds.y / height * 100,
                                      bounds.width / width * 100,
                                      bounds.height / height * 100)
            let fontPixels = cast(f32, Math.clamp(shape.fontSize, 100'u32, 40000)) / 100 * 96 / 72
            result += Format.toString("font-size:%{f4}vw;color:#%;", fontPixels / width * 100, shape.textColor)
            if not shape.picture
            {
                let inset = shape.inset
                result += Format.toString("padding:%{f4}vw %{f4}vw %{f4}vw %{f4}vw;",
                                          inset.y / width * 100,
                                          inset.z / width * 100,
                                          inset.w / width * 100,
                                          inset.x / width * 100)
            }

            if not shape.fill.isEmpty() do
                result += Format.toString("background-color:#%;", shape.fill)
            if not shape.line.isEmpty() do
                result += Format.toString("border:%{f4}vw solid #%;", shape.lineWidth / width * 100, shape.line)
            if shape.ellipse
            {
                result += "border-radius:50%;"
            }
            elif shape.round
            {
                result += Format.toString("border-radius:%{f4}vw;", Math.min(bounds.width, bounds.height) / width * 16.67)
            }
            if shape.rotation or shape.flipHorizontal or shape.flipVertical
            {
                result += "transform:"
                if shape.rotation do
                    result += Format.toString("rotate(%{f2}deg) ", shape.rotation)
                if shape.flipHorizontal do
                    result += "scaleX(-1) "
                if shape.flipVertical do
                    result += "scaleY(-1) "
                result += ";transform-origin:center;"
            }
            if shape.centered do
                result += "display:flex;flex-direction:column;justify-content:center;"
            result += "\">"
            if shape.picture
            {
                var image = shape.html

                // Explicit viewport lengths avoid percentage image heights resolving against width.
                image.replace("max-width:100%;height:auto",
                              Format.toString("width:%{f4}vw;height:%{f4}vh;max-width:none", bounds.width / width * 100, bounds.height / height * 100))
                image.replace("<p>", "")
                image.replace("</p>", "")
                result += image
            }
            else
            {
                result += shape.html
            }

            result += "</div>"
        }

        result += "</body></html>"
        return result
    }
}
