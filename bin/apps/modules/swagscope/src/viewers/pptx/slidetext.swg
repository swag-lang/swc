#global internal
#global namespace Viewers.Pptx

using Core

// A safe reading projection of one slide or shape, including bounded raster pictures.
struct SlideText
{
    html:          String
    plainText:     String
    omittedImages: u64
}

private struct RunStyle
{
    bold:      bool
    italic:    bool
    underline: bool
    strike:    bool
    size:      u32
    color:     String
}

private impl RunStyle
{
    mtd append(paragraph, run: *String, pageWidth: f32, readerStyle: bool)
    {
        if not readerStyle and (.size or not .color.isEmpty())
        {
            paragraph[] += "<span style=\""
            if .size
            {
                let pixels = cast(f32, Math.clamp(.size, 100'u32, 40000)) / 100 * 96 / 72
                paragraph[] += Format.toString("font-size:%{f4}vw;", pixels / pageWidth * 100)
            }

            if not .color.isEmpty() do
                paragraph[] += Format.toString("color:#%;", .color)
            paragraph[] += "\">"
        }

        if .bold do
            paragraph[] += "<b>"
        if .italic do
            paragraph[] += "<i>"
        if .underline do
            paragraph[] += "<u>"
        if .strike do
            paragraph[] += "<s>"
        paragraph[] += run[]
        if .strike do
            paragraph[] += "</s>"
        if .underline do
            paragraph[] += "</u>"
        if .italic do
            paragraph[] += "</i>"
        if .bold do
            paragraph[] += "</b>"
        if not readerStyle and (.size or not .color.isEmpty()) do
            paragraph[] += "</span>"
        run[].clear()
    }
}

impl SlideText
{
    func parse(source: string, images: *Package.ImageCatalog, theme: const *SlideTheme, pageWidth: f32, readerStyle = false)->SlideText fail
    {
        func readPictureExtent(token: const *Package.Token, width, height: *u32)
        {
            let cx = catch StrConv.toU64(token.attribute("cx") orelse "") { return; }
            let cy = catch StrConv.toU64(token.attribute("cy") orelse "") { return; }
            if cx >= 9525 and cy >= 9525 and cx <= 39_014_400 and cy <= 39_014_400
            {
                width[]  = cast(u32, (cx + 4762) / 9525)
                height[] = cast(u32, (cy + 4762) / 9525)
            }
        }

        var result:             #returntype
        var scan            = Package.Scanner.create(source)
        var token:              Package.Token
        var inText          = false
        var inParagraph     = false
        var inRun           = false
        var runStyle:           RunStyle
        var inRunProperties = false
        var inRunFill       = false
        var alignment:          string = ""
        var paragraph:          String
        var run:                String
        var inPicture       = false
        var pictureId:          String
        var pictureDescription: String
        var pictureWidth:       u32
        var pictureHeight:      u32
        while scan.next(&token)
        {
            if token.kind == .Start
            {
                if token.isElement("p")
                {
                    inParagraph = true
                    paragraph.clear()
                    alignment = ""
                }
                elif inParagraph and token.isElement("pPr")
                {
                    let value = token.attribute("algn") orelse ""
                    if value == "ctr" do
                        alignment = "center"
                    elif value == "r" do
                        alignment = "right"
                    elif value == "just" or value == "dist" do
                        alignment = "justify"
                }
                elif inParagraph and token.isElement("r")
                {
                    inRun = true
                    run.clear()
                    runStyle = {}
                }
                elif inRun and token.isElement("rPr")
                {
                    let b = token.attribute("b") orelse "0"
                    let i = token.attribute("i") orelse "0"
                    runStyle.bold      = b == "1" or b == "true" or b == "on"
                    runStyle.italic    = i == "1" or i == "true" or i == "on"
                    runStyle.underline = token.attribute("u") != null and token.attribute("u") != "none"
                    runStyle.strike    = token.attribute("strike") != null and token.attribute("strike") != "noStrike"
                    runStyle.size      = catch StrConv.toU32(token.attribute("sz") orelse "") orelse 0
                    inRunProperties    = not token.empty
                }
                elif inRunProperties and token.isElement("solidFill")
                {
                    inRunFill = not token.empty
                }
                elif inRunFill and (token.isElement("srgbClr") or token.isElement("schemeClr"))
                {
                    let value = token.attribute("val") orelse ""
                    let color = token.isElement("schemeClr") ? theme.color(value) : String.from(value)
                    if Package.isRgbHex(color) do
                        runStyle.color = color
                }
                elif token.isElement("t")
                {
                    inText = true
                }
                elif token.isElement("br")
                {
                    result.plainText += '\n'u8
                    if inRun do
                        run += "<br>"
                    else do
                        paragraph += "<br>"
                }
                elif token.isElement("pic")
                {
                    inPicture = true
                    pictureId.clear()
                    pictureDescription.clear()
                    pictureWidth  = 0
                    pictureHeight = 0
                }
                elif inPicture and token.isElement("blip")
                {
                    pictureId = token.attribute("r:embed") orelse ""
                }
                elif inPicture and token.isElement("cNvPr")
                {
                    pictureDescription = token.attribute("descr") orelse token.attribute("title") orelse ""
                }
                elif inPicture and token.isElement("ext") and not pictureWidth
                {
                    readPictureExtent(&token, &pictureWidth, &pictureHeight)
                }

                if token.empty and token.isElement("pic")
                {
                    inPicture   = false
                    result.omittedImages += 1
                    result.html += "<p>"
                    Package.appendHtmlEscaped(&result.html, texts().ui_ImageOmitted)
                    result.html += "</p>"
                }

                if token.empty and token.isElement("t") do
                    inText = false
                if token.empty and token.isElement("p")
                {
                    result.html += "<p></p>"
                    inParagraph = false
                }

                if token.empty and token.isElement("r")
                {
                    runStyle.append(&paragraph, &run, pageWidth, readerStyle)
                    inRun = false
                }
            }
            elif token.kind == .End
            {
                if token.isElement("p")
                {
                    result.plainText += '\n'u8
                    if inRun do
                        runStyle.append(&paragraph, &run, pageWidth, readerStyle)
                    result.html += "<p"
                    if alignment.count
                    {
                        result.html += " style=\"text-align:"
                        result.html += alignment
                        result.html += "\""
                    }

                    result.html += ">"
                    result.html += paragraph
                    result.html += "</p>"
                    inParagraph = false
                    inRun       = false
                }
                elif token.isElement("r")
                {
                    runStyle.append(&paragraph, &run, pageWidth, readerStyle)
                    inRun = false
                }
                elif token.isElement("rPr")
                {
                    inRunProperties = false
                }
                elif token.isElement("solidFill")
                {
                    inRunFill = false
                }
                elif token.isElement("t")
                {
                    inText = false
                }
                elif token.isElement("pic")
                {
                    inPicture   = false
                    result.html += "<p>"
                    let image = images.html(pictureId, pictureWidth, pictureHeight, pictureDescription)
                    if image.isEmpty()
                    {
                        result.omittedImages += 1
                        Package.appendHtmlEscaped(&result.html, texts().ui_ImageOmitted)
                        if not pictureDescription.isEmpty()
                        {
                            result.html += ": "
                            Package.appendHtmlEscaped(&result.html, pictureDescription)
                        }
                    }
                    else
                    {
                        result.html += image
                    }

                    result.html += "</p>"
                }
            }
            elif inText
            {
                result.plainText += token.text
                if inRun do
                    Package.appendHtmlEscaped(&run, token.text)
                else do
                    Package.appendHtmlEscaped(&paragraph, token.text)
            }

            if result.html.count + paragraph.count + run.count > 32 * 1024 * 1024 do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }

        if scan.damaged do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        return result
    }
}
