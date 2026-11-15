#global internal
#global namespace Viewers.Pptx

using Core

private struct SlideReference
{
    id:   String
    path: String
}

// Bounded slide canvases and their reading text in declared presentation order.
struct Presentation
{
    slides:        Array'SlidePage
    omittedImages: u64
    width:         f32 = 960
    height:        f32 = 720
}

private func readSlides(source, relationships: string)->Array'SlideReference fail
{
    var scan = Package.Scanner.create(relationships)
    var token:  Package.Token
    var linked: Array'SlideReference
    while scan.next(&token)
    {
        if token.kind != .Start or not token.isElement("Relationship") do
            continue
        let id     = token.attribute("Id")
        let target = token.attribute("Target")
        let kind   = token.attribute("Type")
        if not id or not target or not kind do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        if Utf8.endsWith(kind, "/slide") and token.attribute("TargetMode") != "External"
        {
            let path = Package.resolveRelationshipTarget("ppt", target)
            if path.isEmpty() do
                fail Errors.InvalidFormatError{texts().err_Invalid}
            linked.add(SlideReference{id, path})
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

impl Presentation
{
    // Reads slide canvases without evaluating actions, links or embedded objects.
    func load(fileName: string)->Presentation fail
    {
        let archive = try Archive.Zip.load(fileName)
        let parts   = Package.PartReader{fileName, &archive, texts().err_Invalid, texts().err_TooLarge}
        let source  = try parts.text("ppt/presentation.xml")
        let order   = try readSlides(source, try parts.text("ppt/_rels/presentation.xml.rels"))
        var result: #returntype
        var scan    = Package.Scanner.create(source)
        var token:  Package.Token
        while scan.next(&token)
        {
            if token.kind == .Start and token.isElement("sldSz")
            {
                let cx = catch StrConv.toU64(token.attribute("cx") orelse "") orelse 0
                let cy = catch StrConv.toU64(token.attribute("cy") orelse "") orelse 0
                if cx < 9525 or cy < 9525 or cx > 100_000_000 or cy > 100_000_000 do
                    fail Errors.InvalidFormatError{texts().err_Invalid}
                result.width  = cast(f32, cx) / 9525
                result.height = cast(f32, cy) / 9525
            }
        }

        var textBytes = 0'u64
        for slide in order
        {
            let page = try SlidePage.load(&parts, slide.path, result.width)
            for shape in page.shapes do
                textBytes += shape.html.count
            result.omittedImages += page.omittedImages
            result.slides.add(page)
            if textBytes > 32 * 1024 * 1024 do
                fail Errors.UnsupportedFormatError{texts().err_TooLarge}
        }

        return result
    }
}
