#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Capture save/load round-trips every concrete form type and its regression-sensitive fields.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    f.capture.width     = 64
    f.capture.height    = 48
    f.capture.widthOrg  = 64
    f.capture.heightOrg = 48
    f.capture.backImg   = Image.create(64, 48, .BGRA8)
    f.capture.backImg.fill(ColorBlue)
    f.capture.backImgOriginal = Image.create(64, 48, .BGRA8)
    f.capture.backImgOriginal.fill(ColorGreen)

    let shape = testAddShape(f.capture, 1, 2, 10, 11, .Highlight)
    shape.kind      = .RoundRectangle
    shape.roundSize = 18

    let line = testAddLine(f.capture, 3, 4, 20, 21, .PixSel)
    line.bezier      = true
    line.xc          = 6
    line.yc          = 7
    line.paintShadow = false

    let arrow = testAddArrow(f.capture, 5, 6, 30, 31)
    arrow.endSize = 9

    var points: Array'Math.Vector2
    points.add({7, 8})
    points.add({22, 8})
    points.add({18, 25})

    let polygon = testAddPolygon(f.capture, points.toSlice(), .Highlight)
    polygon.bezier      = true
    polygon.paintShadow = false

    let draw = testAddDraw(f.capture, points.toSlice(), .PixSel)
    draw.paintShadow = false

    let text = testAddText(f.capture, 9, 10, 30, 12)
    text.text      = "roundtrip"
    text.fontSize  = 32
    text.alignHorz = .RightBottom
    text.alignVert = .LeftTop

    let step = testAddStep(f.capture, 11, 12, 20, 20)
    step.index     = 5
    step.kind      = .Rectangle
    step.typeIndex = .LetterUp

    let image = testAddImage(f.capture, 13, 14, 16, 17)
    image.kind    = .Image
    image.place   = .Free
    image.freePos = {2, 3, 8, 9}
    image.image   = Image.create(4, 3, .BGRA8)
    image.image.fill(ColorYellow)

    let callout = testAddCallout(f.capture, 15, 16, 40, 24)
    callout.text      = "hi there"
    callout.roundSize = 20
    callout.fontSize  = 36
    callout.boldSize  = 3
    callout.textColor = ColorGreen
    callout.tailX     = 8
    callout.tailY     = 70
    callout.fontStyle = .BoldItalic
    callout.alignHorz = .LeftTop
    callout.alignVert = .RightBottom

    f.capture.title             = "My Capture Name"
    f.capture.sourceKind        = .Screen
    f.capture.capturedAt        = {year: 2026, month: 8, day: 8, hour: 14, minute: 30}
    f.capture.sourceApplication = "chrome"
    f.capture.sourceExecutable  = "C:\\Program Files\\Google\\Chrome\\chrome.exe"
    f.capture.sourceWindowTitle = "Swag - Chromium"
    f.capture.sourceWindowClass = "Chrome_WidgetWin_1"
    f.capture.tags.add("documentation")
    f.capture.tags.add("browser")
    f.capture.favorite = true
    f.capture.rating   = 5

    let path = testTempCapturePath()
    defer discard catch File.delete(path)
    f.capture.file    = path
    f.capture.changed = true

    expect f.capture.save()
    Swag.assert(expect Scc.hasSignature(path))
    var container: Scc.Reader
    expect container.initialize(path)
    Swag.assert(container.kind() == expect Guid128.parse("7355af24-cf65-447b-918c-18ac74e6dc66"))
    container.close()
    let loaded = expect Capture.load(path)!
    defer Memory.delete(loaded)
    Swag.assert(loaded.width == 64)
    Swag.assert(loaded.height == 48)
    Swag.assert(loaded.forms.count == 9)
    Swag.assert(loaded.backImg.isValid())
    Swag.assert(loaded.backImgOriginal.isValid())
    Swag.assert(loaded.title == "My Capture Name")
    Swag.assert(loaded.sourceKind == .Screen)
    Swag.assert(loaded.capturedAt == f.capture.capturedAt)
    Swag.assert(loaded.sourceApplication == "chrome")
    Swag.assert(loaded.sourceExecutable == "C:\\Program Files\\Google\\Chrome\\chrome.exe")
    Swag.assert(loaded.sourceWindowTitle == "Swag - Chromium")
    Swag.assert(loaded.sourceWindowClass == "Chrome_WidgetWin_1")
    Swag.assert(loaded.tags.count == 2)
    Swag.assert(loaded.hasTag("BROWSER"))
    Swag.assert(loaded.favorite)
    Swag.assert(loaded.rating == 5)

    let lShape = cast(*FormShape) loaded.forms[0].buffer
    Swag.assert(lShape.capture == loaded)
    Swag.assert(lShape.subKind == .Highlight)
    Swag.assert(lShape.kind == .RoundRectangle)
    Swag.assert(lShape.roundSize == 18)

    let lLine = cast(*FormLine) loaded.forms[1].buffer
    Swag.assert(lLine.subKind == .PixSel)
    Swag.assert(lLine.bezier)
    Swag.assert(lLine.xc == 6)
    Swag.assert(lLine.yc == 7)
    Swag.assert(!lLine.paintShadow)

    let lArrow = cast(*FormArrow) loaded.forms[2].buffer
    Swag.assert(lArrow.endSize == 9)

    let lPolygon = cast(*FormPolygon) loaded.forms[3].buffer
    Swag.assert(lPolygon.subKind == .Highlight)
    Swag.assert(lPolygon.bezier)
    Swag.assert(!lPolygon.paintShadow)
    Swag.assert(lPolygon.points.count == 3)

    let lDraw = cast(*FormDraw) loaded.forms[4].buffer
    Swag.assert(lDraw.subKind == .PixSel)
    Swag.assert(!lDraw.paintShadow)
    Swag.assert(lDraw.points.count == 3)

    let lText = cast(*FormText) loaded.forms[5].buffer
    Swag.assert(lText.text == "roundtrip")
    Swag.assert(lText.fontSize == 32)
    Swag.assert(lText.alignHorz == .RightBottom)
    Swag.assert(lText.alignVert == .LeftTop)

    let lStep = cast(*FormStep) loaded.forms[6].buffer
    Swag.assert(lStep.index == 5)
    Swag.assert(lStep.kind == .Rectangle)
    Swag.assert(lStep.typeIndex == .LetterUp)

    let lImage = cast(*FormImage) loaded.forms[7].buffer
    Swag.assert(lImage.kind == .Image)
    Swag.assert(lImage.place == .Free)
    Gui.Testing.assertRect(lImage.freePos, 2, 3, 8, 9)
    Swag.assert(lImage.image.isValid())
    Swag.assert(lImage.image.width == 4)
    Swag.assert(lImage.image.height == 3)

    let lCallout = cast(*FormCallout) loaded.forms[8].buffer
    Swag.assert(lCallout.capture == loaded)
    Swag.assert(lCallout.text == "hi there")
    Swag.assert(lCallout.roundSize == 20)
    Swag.assert(lCallout.fontSize == 36)
    Swag.assert(lCallout.boldSize == 3)
    Swag.assert(lCallout.textColor == ColorGreen)
    Swag.assert(lCallout.tailX == 8)
    Swag.assert(lCallout.tailY == 70)
    Swag.assert(lCallout.fontStyle == .BoldItalic)
    Swag.assert(lCallout.alignHorz == .LeftTop)
    Swag.assert(lCallout.alignVert == .RightBottom)
}

// Preview loading reads only the SCC profile header and preview chunk.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    f.capture.width   = 32
    f.capture.height  = 32
    f.capture.backImg = Image.create(32, 32, .BGRA8)
    f.capture.backImg.fill(ColorRed)
    f.capture.preview = Image.create(8, 6, .BGRA8)
    f.capture.preview.fill(ColorBlue)
    f.capture.title = "Preview Title"
    discard testAddShape(f.capture, 2, 3, 4, 5)

    let path = testTempCapturePath()
    defer discard catch File.delete(path)
    f.capture.file    = path
    f.capture.changed = true

    expect f.capture.save()
    let loaded = expect Capture.load(path, preview: true)!
    defer Memory.delete(loaded)
    Swag.assert(loaded.forms.count == 0)
    Swag.assert(!loaded.backImg.isValid())
    Swag.assert(loaded.preview.isValid())
    Swag.assert(loaded.preview.width == 8)
    Swag.assert(loaded.preview.height == 6)
    Swag.assert(loaded.title == "Preview Title")

    let deferred = expect Capture.load(path, preview: true, deferPreviewDecode: true)!
    defer Memory.delete(deferred)
    Swag.assert(!deferred.preview.isValid())
    Swag.assert(!deferred.previewBytes.isEmpty())
    expect deferred.materializePreview()
    Swag.assert(deferred.preview.isValid())
    Swag.assert(deferred.preview.width == 8)
    Swag.assert(deferred.preview.height == 6)

    var libraryView: LibraryView
    var libraryItem: LibraryItem
    libraryItem.kind        = .Capture
    libraryItem.fi.fullname = path
    libraryView.loadOne(&libraryItem)
    Swag.assert(libraryItem.loaded)
    Swag.assert(libraryItem.capture != null)
    Swag.assert(!libraryItem.capture!.preview.isValid())
    Swag.assert(!libraryItem.capture!.previewBytes.isEmpty())
    Swag.assert(libraryItem.haar.size != 0)
}
