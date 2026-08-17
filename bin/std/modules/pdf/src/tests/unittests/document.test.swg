using Core, Pixel

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

    let rendered = expect decoded.pages[0].render({scale: 2, maxDimension: 1024})
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
