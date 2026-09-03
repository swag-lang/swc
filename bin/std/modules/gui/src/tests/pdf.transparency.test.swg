#global if #command == Swag.CompilerCommand.Test

using Core, Core.Math, Pixel, Pdf

// Builds a one-page document over a 200 by 100 page and returns it.
private func transparencyDocument(resources, content: string, extra: const [..] u8)->Document
{
    return expect Document.decode(singlePagePdf(resources, cast(const [..] u8) content, extra).toSlice())
}

// A luminosity mask whose group paints white over the lower-left quarter of a 100 by 100 box.
//
// White is full luminosity and therefore full coverage; everywhere else the group paints
// nothing and the black backdrop leaves the coverage at zero. Object 5 is the graphics state
// that selects it and object 6 is the group.
private func luminosityMaskObjects()->Array'u8
{
    var result: retval
    addObject(&result, 5, "<< /Type /ExtGState /SMask << /S /Luminosity /G 6 0 R >> >>")
    addStreamObject(&result, 6, "/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Group << /S /Transparency /CS /DeviceGray >>", cast(const [..] u8) "1 g 0 0 50 50 re f")
    return result
}

// Counts the pixels of a frame the mark's own colour reaches at full coverage.
//
// The mark is painted a saturated red no part of the surrounding window uses, so the count is
// the mark's area on screen and nothing else.
private func markedPixels(frame: const *Image)->u64
{
    var result: retval
    for y in frame.height
    {
        for x in frame.width
        {
            let color = frame.pixelColor(x, y)
            if color.r > 200 and color.g < 60 and color.b < 60 do
                result += 1
        }
    }

    return result
}

// Constant alpha modulates the fill and the stroke independently.
#test
{
    var objects: Array'u8
    addObject(&objects, 5, "<< /Type /ExtGState /ca 0.25 /CA 0.5 >>")

    let document = transparencyDocument("/ExtGState << /GS0 5 0 R >>", "/GS0 gs 1 0 0 rg 0 0 1 RG 0 0 50 50 re B", objects.toSlice())
    let item     = onlyItem(document.pages[0], .Path)
    Swag.assert(item.itemFillColor() == Color.fromArgb(64, 255, 0, 0))
    Swag.assert(item.itemStrokeColor() == Color.fromArgb(128, 0, 0, 255))
}

// `/BM` selects a blend mode by name, from an array of alternatives, and never by a name this
// module cannot express.
#test
{
    var objects: Array'u8
    addObject(&objects, 5, "<< /Type /ExtGState /BM /Multiply >>")
    addObject(&objects, 6, "<< /Type /ExtGState /BM [/Fictional /Screen /Darken] >>")
    addObject(&objects, 7, "<< /Type /ExtGState /BM /Fictional >>")

    let resources = "/ExtGState << /GS0 5 0 R /GS1 6 0 R /GS2 7 0 R >>"
    let content   = "/GS0 gs 0 0 5 5 re f /GS1 gs 0 0 5 5 re f /GS2 gs 0 0 5 5 re f"
    let document  = transparencyDocument(resources, content, objects.toSlice())
    let page      = &document.pages[0]
    Swag.assert(page.items.count == 3)
    Swag.assert(page.items[0].blend == .Multiply)
    Swag.assert(page.items[1].blend == .Screen)

    // An unknown name leaves the mode in force rather than resetting the page to normal.
    Swag.assert(page.items[2].blend == .Screen)
}

// A luminosity soft mask becomes the coverage a filled path is painted through.
#test
{
    let objects  = luminosityMaskObjects()
    let document = transparencyDocument("/ExtGState << /GS0 5 0 R >>", "/GS0 gs 0 g 0 0 100 100 re f", objects.toSlice())
    let item     = onlyItem(document.pages[0], .Path)
    Swag.assert(item.hasMask)

    // The coverage covers exactly the mark's own page-space box, so it is anchored there rather
    // than stretched over whatever shape samples it.
    Swag.assert(item.maskRect == Math.Rectangle{0, 0, 100, 100})
    Swag.assert(item.maskImage.width == 200 and item.maskImage.height == 200)

    // The group's white quarter is the lower left in PDF coordinates, which a page states from
    // its top-left corner: covered below and to the left, clear above and to the right.
    Swag.assert(item.maskImage.pixelColor(20, 180).a == 255)
    Swag.assert(item.maskImage.pixelColor(20, 20).a == 0)
    Swag.assert(item.maskImage.pixelColor(180, 180).a == 0)
    Swag.assert(item.maskImage.pixelColor(180, 20).a == 0)
}

// An image takes its coverage in its own alpha channel rather than through a second texture.
#test
{
    var objects = #move luminosityMaskObjects()
    addStreamObject(&objects, 7, "/Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceGray /BitsPerComponent 8", cast(const [..] u8) "\xFF\xFF\xFF\xFF")

    let resources = "/ExtGState << /GS0 5 0 R >> /XObject << /Im0 7 0 R >>"
    let document  = transparencyDocument(resources, "/GS0 gs q 100 0 0 100 0 0 cm /Im0 Do Q", objects.toSlice())
    let item      = onlyItem(document.pages[0], .Image)
    Swag.assert(!item.hasMask)

    let image = item.imageValue()!
    Swag.assert(image.pixelFormat == .RGBA8)
    Swag.assert(image.pixelColor(0, 1).a == 255)
    Swag.assert(image.pixelColor(1, 0).a == 0)
}

// A graphics state inside a transparency group cannot clear the mask the group is behind.
//
// The mask applies to what the group composites, not to the marks inside it, and the writers
// that produce drop shadows always reset the mask inside the group before filling. Applying it
// per mark instead leaves the shadow as an opaque block over the illustration it sits behind.
#test
{
    var objects = #move luminosityMaskObjects()
    addObject(&objects, 7, "<< /Type /ExtGState /SMask /None /ca 0.5 >>")
    addStreamObject(&objects, 8, "/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Group << /S /Transparency >>", cast(const [..] u8) "/GS1 gs 0 g 0 0 100 100 re f")

    let resources = "/ExtGState << /GS0 5 0 R /GS1 7 0 R >> /XObject << /Fm0 8 0 R >>"
    let document  = transparencyDocument(resources, "/GS0 gs /Fm0 Do", objects.toSlice())
    let item      = onlyItem(document.pages[0], .Path)
    Swag.assert(item.hasMask)
    Swag.assert(item.maskImage.pixelColor(20, 180).a == 255)
    Swag.assert(item.maskImage.pixelColor(180, 20).a == 0)

    // The group's own constant alpha still applies to the marks it contains.
    Swag.assert(item.itemFillColor().a == 128)
}

// A group's own transparency multiplies the one in force around it.
#test
{
    var objects: Array'u8
    addObject(&objects, 5, "<< /Type /ExtGState /ca 0.5 >>")
    addObject(&objects, 6, "<< /Type /ExtGState /ca 0.5 >>")
    addStreamObject(&objects, 7, "/Type /XObject /Subtype /Form /BBox [0 0 100 100] /Group << /S /Transparency >>", cast(const [..] u8) "/GS1 gs 0 0 100 100 re f")

    let resources = "/ExtGState << /GS0 5 0 R /GS1 6 0 R >> /XObject << /Fm0 7 0 R >>"
    let document  = transparencyDocument(resources, "/GS0 gs /Fm0 Do", objects.toSlice())
    Swag.assert(onlyItem(document.pages[0], .Path).itemFillColor().a == 64)
}

// `/SMask /None` clears a mask that was in force.
#test
{
    var objects = #move luminosityMaskObjects()
    addObject(&objects, 7, "<< /Type /ExtGState /SMask /None >>")

    let resources = "/ExtGState << /GS0 5 0 R /GS1 7 0 R >>"
    let document  = transparencyDocument(resources, "/GS0 gs /GS1 gs 0 0 100 100 re f", objects.toSlice())
    Swag.assert(!onlyItem(document.pages[0], .Path).hasMask)
}

// A mask stays registered with the marks it covers whatever transform the view paints under.
//
// The coverage is anchored to the page rectangle it was rasterized over, and the view maps page
// points to the surface itself. Anchoring it in surface coordinates instead would hold the mask
// still while the marks under it moved and grew with the zoom, so the same page painted at two
// scales would show two different shapes.
#test
{
    let objects  = luminosityMaskObjects()
    let fileName = Testing.tempFilePath("gui-pdf-softmask-", ".pdf")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, singlePagePdf("/ExtGState << /GS0 5 0 R >>", cast(const [..] u8) "/GS0 gs 1 0 0 rg 0 0 100 100 re f", objects.toSlice()).toSlice())

    var host: Testing.HeadlessHost
    host.setup(640, 450)
    defer host.shutdown()

    let view = PdfView.create(&host.root)
    expect view.open(fileName.toString())
    view.resize(600, 400)
    view.applyLayout()

    // The mask keeps a fifty-point square of the hundred-point mark, so the mark covers 2500
    // pixels at one pixel per point and four times that at two.
    view.setZoom(1)
    let singleFrame = host.render()
    view.setZoom(2)
    let doubledFrame = host.render()
    Swag.assert(!view.reportedPaintError)
    Swag.assert(Math.isEqualEpsilon(cast(f32) markedPixels(&singleFrame), 2500.0, 400.0))
    Swag.assert(Math.isEqualEpsilon(cast(f32) markedPixels(&doubledFrame), 10_000.0, 1_000.0))
}

// A form with no transparency group passes the mask down to the marks it holds, and a mask
// nested inside another multiplies with it.
#test
{
    var objects = #move luminosityMaskObjects()
    addStreamObject(&objects, 7, "/Type /XObject /Subtype /Form /BBox [0 0 100 100]", cast(const [..] u8) "0 0 100 100 re f")

    let resources = "/ExtGState << /GS0 5 0 R >> /XObject << /Fm0 7 0 R >>"
    let document  = transparencyDocument(resources, "/GS0 gs /Fm0 Do", objects.toSlice())
    let item      = onlyItem(document.pages[0], .Path)
    Swag.assert(item.hasMask)
    Swag.assert(item.maskImage.pixelColor(20, 180).a == 255)
    Swag.assert(item.maskImage.pixelColor(180, 20).a == 0)
}
