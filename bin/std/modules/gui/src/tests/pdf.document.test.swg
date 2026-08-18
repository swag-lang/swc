#global if #command == Swag.CompilerCommand.Test

using Core, Pixel, Pdf

private func pdfFixturePath(name: string)->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, Format.toString("datas/%", name).toString())
}

private func loadPdfFixture(name: string, pageCount: u64)->Document
{
    let result = expect Document.load(pdfFixturePath(name))
    @assert(result.pages.count == pageCount)
    for page in result.pages do
        @assert(page.width > 0 and page.height > 0 and Math.isFinite(page.width) and Math.isFinite(page.height))
    return result
}

private func sampleDocument()->Document
{
    var document = Document.create()
    document.metadata.title    = "PDF round trip"
    document.metadata.author   = "Swag tests"
    document.metadata.producer = "Pdf module"

    var page = Page.create(240, 160)
    page.addText("Hello PDF", 24, 20, 18, Color.fromRgb(20, 30, 40))

    var triangle: LinePathList
    let path = triangle.newPath()
    path.start(24, 64)
    path.lineTo(104, 64)
    path.lineTo(64, 128)
    path.close()
    page.addPath(triangle, fillColor: Color.fromRgb(247, 249, 0), stroke: true, strokeColor: Color.fromRgb(11, 11, 13), strokeWidth: 2)

    let pixels: [12] u8 = [255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 255]
    let image           = Image.create(2, 2, .RGB8, pixels)
    page.addImage(image, 144, 40, 64, 64)
    document.addPage(#move page)
    return document
}

// Real files from an independent PDF implementation cover classic and compressed object
// representations, page inheritance, raster images, and nested vector forms.
#test
{
    // A classic file laid out with `Tm` and simple fonts, and a compressed one whose text is
    // addressed by a composite font through a `/ToUnicode` CMap.
    let classic = loadPdfFixture("pdfbox-classic-flate.pdf", 1)
    @assert(pageText(classic.pages[0]).contains("Cell with colspan 3"))
    @assert(pageText(classic.pages[0]).contains("Cell with rowspan 2"))

    // Its eleven two-byte codes map to nine characters, the other two being unmapped glyphs.
    let compressed = loadPdfFixture("pdfbox-object-stream.pdf", 1)
    @assert(Utf8.countRunes(pageText(compressed.pages[0]).toString()) == 9)

    let jpeg = loadPdfFixture("pdfbox-jpeg-rgb.pdf", 1)
    var hasImage: bool
    for item in jpeg.pages[0].items where item.kind == .Image do
        hasImage = true
    @assert(hasImage)

    let rotation = loadPdfFixture("pdfbox-rotation.pdf", 2)
    @assert(rotation.pages[0].width == rotation.pages[1].height)
    @assert(rotation.pages[0].height == rotation.pages[1].width)

    let form = loadPdfFixture("pdfbox-form-xobject.pdf", 1)
    var pathCount: u64
    for item in form.pages[0].items where item.kind == .Path do
        pathCount += 1
    @assert(pathCount > 100)
}

// Covers the complete in-memory chain: edit, encode, decode, inspect, and render.
#test
{
    let source = sampleDocument()
    let bytes  = expect source.encode()
    @assert(bytes.count > 400)
    @assert(cast(string) bytes.toSlice()[0 to 7] == "%PDF-1.7")

    var decoded = expect Document.decode(bytes.toSlice())
    @assert(decoded.pages.count == 1)
    @assert(decoded.metadata.title == "PDF round trip")
    @assert(decoded.metadata.author == "Swag tests")
    @assert(decoded.pages[0].width == 240 and decoded.pages[0].height == 160)
    @assert(decoded.pages[0].items.count == 3)
    @assert(decoded.pages[0].items[0].kind == .Text)
    @assert(decoded.pages[0].items[0].textValue() == "Hello PDF")
    @assert(decoded.pages[0].items[1].kind == .Path)
    @assert(decoded.pages[0].items[2].kind == .Image)
    let imageTransform = decoded.pages[0].items[2].itemTransform()
    @assert(imageTransform.m11 == 64 and imageTransform.m12 == 0)
    @assert(imageTransform.m21 == 0 and imageTransform.m22 == 64)
    @assert(imageTransform.tx == 144 and imageTransform.ty == 40)

    let rendered = expect decoded.editPage(0).render({scale: 2, maxDimension: 1024})
    @assert(rendered.width == 480 and rendered.height == 320)
    @assert(rendered.isValid())

    // Render-target image rows are stored bottom-up.
    let imageBottomLeft = rendered.pixelColor(304, rendered.height - 193)
    @assert(imageBottomLeft.b > imageBottomLeft.r and imageBottomLeft.b > imageBottomLeft.g)

    let editablePage = decoded.editPage(0)
    editablePage.setText(0, "Edited PDF")
    editablePage.setTextSize(0, 20)
    editablePage.setItemTransform(0, Math.Transform2{1, 0.2, 0.1, 1, 30, 24})
    editablePage.setPathStrokeColor(1, Color.fromRgb(50, 60, 70))
    editablePage.setPathStrokeWidth(1, 3)
    editablePage.setItemTransform(1, Math.Transform2.createTranslation(5, 7))
    editablePage.setItemTransform(2, Math.Transform2{32, 4, 6, 48, 152, 56})

    let editedBytes = expect decoded.encode()
    let edited      = expect Document.decode(editedBytes.toSlice())
    @assert(edited.pages[0].items[0].textValue() == "Edited PDF")
    @assert(edited.pages[0].items[0].textSize() == 20)
    let editedTextTransform = edited.pages[0].items[0].itemTransform()
    @assert(Math.isEqualEpsilon(editedTextTransform.m12, 0.2, 0.001))
    @assert(Math.isEqualEpsilon(editedTextTransform.m21, 0.1, 0.001))
    @assert(editedTextTransform.tx == 30 and editedTextTransform.ty == 24)
    @assert(edited.pages[0].items[1].pathStrokeWidth() == 3)
    let editedStroke = edited.pages[0].items[1].itemStrokeColor()
    @assert(editedStroke.r == 50 and editedStroke.g == 60 and editedStroke.b == 70)
    let editedPath = edited.pages[0].items[1].pathValue()!
    @assert(editedPath.toSlice()[0].startPoint == Math.Vector2{29, 71})
    let editedImageTransform = edited.pages[0].items[2].itemTransform()
    @assert(editedImageTransform.m11 == 32 and editedImageTransform.m12 == 4)
    @assert(editedImageTransform.m21 == 6 and editedImageTransform.m22 == 48)
    @assert(editedImageTransform.tx == 152 and editedImageTransform.ty == 56)
}

// The file entry points use a mapped input and produce the same editable model.
#test
{
    let fileName = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("pdf-module-%{X016}.pdf", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    let source = sampleDocument()
    expect source.save(fileName)
    let loaded = expect Document.load(fileName)
    @assert(loaded.pages.count == 1)
    @assert(loaded.pages[0].items.count == 3)
}

// The streaming reader indexes every page but does not decode a later page's stream until that
// page is requested.
#test
{
    let fileName = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("pdf-streaming-%{X016}.pdf", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var bytes: Array'u8
    bytes.add(cast(const [..] u8) "%PDF-1.7\n")
    addObject(&bytes, 1, "<< /Type /Catalog /Pages 2 0 R >>")
    addObject(&bytes, 2, "<< /Type /Pages /Count 2 /Kids [3 0 R 4 0 R] >>")
    addObject(&bytes, 3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 40 30] /Resources << >> /Contents 5 0 R >>")
    addObject(&bytes, 4, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 40 30] /Resources << >> /Contents 6 0 R >>")
    addStreamObject(&bytes, 5, "", cast(const [..] u8) "2 2 20 12 re f")
    addStreamObject(&bytes, 6, "/Filter /UnsupportedForStreamingTest", cast(const [..] u8) "deferred")
    bytes.add(cast(const [..] u8) "trailer\n<< /Root 1 0 R >>\n%%EOF\n")
    expect File.writeAllBytes(fileName, bytes.toSlice())

    var reader = expect Reader.open(fileName)
    @assert(reader.pageCount() == 2)
    var first = expect reader.loadPage(0)
    @assert(first.width == 40 and first.height == 30 and first.items.count == 1)
    let image = expect first.render({scale: 1})
    @assert(image.isValid())
    @assert(image.pixelColor(0, 0).a == 255)

    let transparent = expect first.render({scale: 1, background: Color.fromArgb(Argb.Zero)})
    @assert(transparent.pixelColor(0, 0).a == 0)

    discard catch reader.loadPage(1) as deferredError
    @assert(deferredError != null)
    discard catch reader.loadPage(2) as rangeError
    @assert(rangeError != null)

    discard catch Document.load(fileName) as eagerError
    @assert(eagerError != null)
}

#test
{
    discard catch Document.decode("not a PDF") as error
    @assert(error != null)

    var empty = Document.create()
    discard catch empty.encode() as emptyError
    @assert(emptyError != null)
}

#test
{
    let ascii85 = expect decodeAscii85("z!!~>")
    @assert(ascii85.count == 5)
    for value in ascii85 do
        @assert(value == 0)

    let encoded: [7] u8 = [2, 'A', 'B', 'C', 254, 'Z', 128]
    let runLength       = expect decodeRunLength(encoded)
    @assert(runLength.count == 6)
    @assert(cast(string) runLength.toSlice() == "ABCZZZ")
}

// A forward indirect length must win over delimiter scanning. This stream's final Adler-32 byte
// is itself LF (0x0A), so trimming line endings before resolving object 5 corrupts valid Flate.
#test
{
    const compressed: [9] u8 = [0x78, 0x9C, 0xE3, 0x04, 0x00, 0x00, 0x0A, 0x00, 0x0A]
    var bytes: Array'u8
    bytes.add(cast(const [..] u8) "%PDF-1.7\n")
    addObject(&bytes, 1, "<< /Type /Catalog /Pages 2 0 R >>")
    addObject(&bytes, 2, "<< /Type /Pages /Count 1 /Kids [3 0 R] >>")
    addObject(&bytes, 3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 40 30] /Resources << >> /Contents 4 0 R >>")
    bytes.add(cast(const [..] u8) "4 0 obj\n<< /Length 5 0 R /Filter /FlateDecode >>\nstream\n")
    bytes.add(compressed)
    bytes.add(cast(const [..] u8) "endstream\nendobj\n")
    addObject(&bytes, 5, "9")
    bytes.add(cast(const [..] u8) "trailer\n<< /Root 1 0 R >>\n%%EOF\n")

    let document = expect Document.decode(bytes.toSlice())
    @assert(document.pages.count == 1)
    @assert(document.pages[0].items.count == 0)
}

// A CropBox trims the page to the region a reader displays: the page takes the crop's
// dimensions, and content is placed relative to the crop origin.
#test
{
    var bytes: Array'u8
    bytes.add(cast(const [..] u8) "%PDF-1.7\n")
    addObject(&bytes, 1, "<< /Type /Catalog /Pages 2 0 R >>")
    addObject(&bytes, 2, "<< /Type /Pages /Count 1 /Kids [3 0 R] >>")
    addObject(&bytes, 3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /CropBox [10 20 110 70] /Resources << >> /Contents 4 0 R >>")
    addStreamObject(&bytes, 4, "", cast(const [..] u8) "10 20 5 5 re f")
    bytes.add(cast(const [..] u8) "trailer\n<< /Root 1 0 R >>\n%%EOF\n")

    let document = expect Document.decode(bytes.toSlice())
    let page     = document.pages[0]
    @assert(page.width == 100 and page.height == 50)

    // The rectangle sits at the crop origin, so it lands at the page's bottom-left corner.
    let item   = onlyItem(page, .Path)
    let bounds = item.pathValue()!.controlBounds()
    @assert(Math.isEqualEpsilon(bounds.x, 0, 0.01) and Math.isEqualEpsilon(bounds.bottom(), 50, 0.01))
}

// A CropBox reaching outside the MediaBox is bounded by it, and a malformed one is ignored.
#test
{
    var bytes: Array'u8
    bytes.add(cast(const [..] u8) "%PDF-1.7\n")
    addObject(&bytes, 1, "<< /Type /Catalog /Pages 2 0 R >>")
    addObject(&bytes, 2, "<< /Type /Pages /Count 2 /Kids [3 0 R 5 0 R] >>")
    addObject(&bytes, 3, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /CropBox [-50 -50 100 200] /Resources << >> /Contents 4 0 R >>")
    addStreamObject(&bytes, 4, "", cast(const [..] u8) "")
    addObject(&bytes, 5, "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 100] /CropBox [300 300 400 400] /Resources << >> /Contents 6 0 R >>")
    addStreamObject(&bytes, 6, "", cast(const [..] u8) "")
    bytes.add(cast(const [..] u8) "trailer\n<< /Root 1 0 R >>\n%%EOF\n")

    let document = expect Document.decode(bytes.toSlice())
    @assert(document.pages[0].width == 100 and document.pages[0].height == 100)
    @assert(document.pages[1].width == 200 and document.pages[1].height == 100)
}

// A preamble before the header does not cost the document: every reader accepts a file whose
// `%PDF-` marker sits within the first bytes rather than at byte zero.
#test
{
    var bytes: Array'u8
    bytes.add(cast(const [..] u8) "Content-Type: application/pdf; some mail preamble\n\n")
    bytes.add(singlePagePdf("", cast(const [..] u8) "0 0 5 5 re f", "").toSlice())
    let document = expect Document.decode(bytes.toSlice())
    @assert(document.pages.count == 1)
    discard onlyItem(document.pages[0], .Path)
}

// A render restricted to a source region rasterizes that region alone: the output image is the
// region's size, and a mark outside it contributes nothing.
#test
{
    var page = Page.create(200, 100)
    var left: LinePathList
    with let leftPath = left.newPath()
    {
        .start(0, 0)
        .lineTo(100, 0)
        .lineTo(100, 100)
        .lineTo(0, 100)
        .close()
    }

    page.addPath(left, fillColor: Color.fromRgb(255, 0, 0))
    var right: LinePathList
    with let rightPath = right.newPath()
    {
        .start(100, 0)
        .lineTo(200, 0)
        .lineTo(200, 100)
        .lineTo(100, 100)
        .close()
    }

    page.addPath(right, fillColor: Color.fromRgb(0, 255, 0))

    let whole = expect page.render({scale: 1})
    @assert(whole.width == 200 and whole.height == 100)

    let region = expect page.render({scale: 1, sourceRect: {100, 0, 100, 100}})
    @assert(region.width == 100 and region.height == 100)
    @assert(region.pixelColor(50, 50).g == 255 and region.pixelColor(50, 50).r == 0)

    // The same region at twice the scale is the zoomed view: same content, more pixels.
    let zoomed = expect page.render({scale: 2, sourceRect: {100, 0, 100, 100}})
    @assert(zoomed.width == 200 and zoomed.height == 200)
    @assert(zoomed.pixelColor(100, 100).g == 255)
}
