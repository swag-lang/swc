#global internal
#global namespace Viewers.Pptx

using Core

private struct Slide
{
    id:   String
    path: String
}

// The text content of presentation slides in their declared sequence.
struct Presentation
{
    html:          String
    slides:        u64
    omittedImages: u64
}

private func readPart(fileName: string, archive: const *Archive.Zip, path: string)->String fail
{
    let entry = archive.tryFindEntry(path)
    if not entry do
        fail Errors.InvalidFormatError{texts().err_Invalid}
    if entry.uncompressedSize > 16 * 1024 * 1024 do
        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
    let data = try Archive.Zip.loadEntry(fileName, entry)
    return String.from(cast(string, data.toSlice()))
}

private func readSlides(source, relationships: string)->Array'Slide fail
{
    var scan = Package.Scanner.create(relationships)
    var token: Package.Token
    var linked: Array'Slide
    while scan.next(&token)
    {
        if token.kind != .Start or not token.isElement("Relationship") do
            continue
        let id = token.attribute("Id")
        let target = token.attribute("Target")
        let kind = token.attribute("Type")
        if not id or not target or not kind do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        if Utf8.contains(kind, "/slide")
        {
            let path = Package.resolveRelationshipTarget("ppt", target)
            if path.isEmpty() do
                fail Errors.InvalidFormatError{texts().err_Invalid}
            linked.add(Slide{id, path})
        }
    }
    if scan.damaged do
        fail Errors.InvalidFormatError{texts().err_Invalid}

    scan = Package.Scanner.create(source)
    var result: #returntype
    while scan.next(&token)
    {
        if token.kind != .Start or not token.isElement("sldId") do
            continue
        let id = token.attribute("r:id")
        if not id do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        var found = false
        for &slide in linked where slide.id == id
        {
            result.add(slide)
            found = true
            break
        }
        if not found do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        if result.count > 200 do
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
    }
    if scan.damaged or result.isEmpty() do
        fail Errors.InvalidFormatError{texts().err_Invalid}
    return result
}

private func appendSlide(result: *Presentation, source: string) fail
{
    var scan = Package.Scanner.create(source)
    var token: Package.Token
    var inText = false
    var paragraphs = 0'u64
    let imagesBefore = result.omittedImages
    while scan.next(&token)
    {
        if token.kind == .Start
        {
            if token.isElement("p")
            {
                result.html += "<p>"
                paragraphs += 1
            }
            elif token.isElement("t") do
                inText = true
            elif token.isElement("br") do
                result.html += "<br>"
            elif token.isElement("pic")
            {
                result.omittedImages += 1
                result.html += "<p>"
                Package.appendHtmlEscaped(&result.html, texts().ui_ImageOmitted)
                result.html += "</p>"
            }
            if token.empty and token.isElement("t") do
                inText = false
        }
        elif token.kind == .End
        {
            if token.isElement("p") do
                result.html += "</p>"
            elif token.isElement("t") do
                inText = false
        }
        elif inText do
            Package.appendHtmlEscaped(&result.html, token.text)
        if result.html.count > 32 * 1024 * 1024 do
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}
    }
    if scan.damaged or not paragraphs and result.omittedImages == imagesBefore do
        fail Errors.InvalidFormatError{texts().err_Invalid}
}

impl Presentation
{
    // Reads slide order and text without evaluating actions, links or embedded objects.
    func load(fileName: string)->Presentation fail
    {
        let archive = try Archive.Zip.load(fileName)
        let order = try readSlides(
            try readPart(fileName, &archive, "ppt/presentation.xml"),
            try readPart(fileName, &archive, "ppt/_rels/presentation.xml.rels"))
        var result: #returntype
        result.html = "<html><body>"
        for &slide in order
        {
            result.slides += 1
            result.html += "<h2>"
            result.html += Format.toString(texts().ui_Slide, result.slides)
            result.html += "</h2>"
            try appendSlide(&result, try readPart(fileName, &archive, slide.path))
        }
        result.html += "</body></html>"
        return result
    }
}
