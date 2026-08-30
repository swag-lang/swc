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
    @assert(expect Scc.hasSignature(path))
    var container: Scc.Reader
    expect container.initialize(path)
    @assert(container.kind() == expect Guid128.parse("4a67acc2-5930-4e81-81dc-d12675bc6deb"))
    container.close()
    let loaded = expect Capture.load(path)!
    defer Memory.delete(loaded)
    @assert(loaded.width == 64)
    @assert(loaded.height == 48)
    @assert(loaded.forms.count == 9)
    @assert(loaded.backImg.isValid())
    @assert(loaded.backImgOriginal.isValid())
    @assert(loaded.title == "My Capture Name")
    @assert(loaded.sourceKind == .Screen)
    @assert(loaded.capturedAt == f.capture.capturedAt)
    @assert(loaded.sourceApplication == "chrome")
    @assert(loaded.sourceExecutable == "C:\\Program Files\\Google\\Chrome\\chrome.exe")
    @assert(loaded.sourceWindowTitle == "Swag - Chromium")
    @assert(loaded.sourceWindowClass == "Chrome_WidgetWin_1")
    @assert(loaded.tags.count == 2)
    @assert(loaded.hasTag("BROWSER"))
    @assert(loaded.favorite)
    @assert(loaded.rating == 5)

    let lShape = cast(*FormShape) @dataof(loaded.forms[0])
    @assert(lShape.capture == loaded)
    @assert(lShape.subKind == .Highlight)
    @assert(lShape.kind == .RoundRectangle)
    @assert(lShape.roundSize == 18)

    let lLine = cast(*FormLine) @dataof(loaded.forms[1])
    @assert(lLine.subKind == .PixSel)
    @assert(lLine.bezier)
    @assert(lLine.xc == 6)
    @assert(lLine.yc == 7)
    @assert(!lLine.paintShadow)

    let lArrow = cast(*FormArrow) @dataof(loaded.forms[2])
    @assert(lArrow.endSize == 9)

    let lPolygon = cast(*FormPolygon) @dataof(loaded.forms[3])
    @assert(lPolygon.subKind == .Highlight)
    @assert(lPolygon.bezier)
    @assert(!lPolygon.paintShadow)
    @assert(lPolygon.points.count == 3)

    let lDraw = cast(*FormDraw) @dataof(loaded.forms[4])
    @assert(lDraw.subKind == .PixSel)
    @assert(!lDraw.paintShadow)
    @assert(lDraw.points.count == 3)

    let lText = cast(*FormText) @dataof(loaded.forms[5])
    @assert(lText.text == "roundtrip")
    @assert(lText.fontSize == 32)
    @assert(lText.alignHorz == .RightBottom)
    @assert(lText.alignVert == .LeftTop)

    let lStep = cast(*FormStep) @dataof(loaded.forms[6])
    @assert(lStep.index == 5)
    @assert(lStep.kind == .Rectangle)
    @assert(lStep.typeIndex == .LetterUp)

    let lImage = cast(*FormImage) @dataof(loaded.forms[7])
    @assert(lImage.kind == .Image)
    @assert(lImage.place == .Free)
    Gui.Testing.assertRect(lImage.freePos, 2, 3, 8, 9)
    @assert(lImage.image.isValid())
    @assert(lImage.image.width == 4)
    @assert(lImage.image.height == 3)

    let lCallout = cast(*FormCallout) @dataof(loaded.forms[8])
    @assert(lCallout.capture == loaded)
    @assert(lCallout.text == "hi there")
    @assert(lCallout.roundSize == 20)
    @assert(lCallout.fontSize == 36)
    @assert(lCallout.boldSize == 3)
    @assert(lCallout.textColor == ColorGreen)
    @assert(lCallout.tailX == 8)
    @assert(lCallout.tailY == 70)
    @assert(lCallout.fontStyle == .BoldItalic)
    @assert(lCallout.alignHorz == .LeftTop)
    @assert(lCallout.alignVert == .RightBottom)
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
    @assert(loaded.forms.count == 0)
    @assert(!loaded.backImg.isValid())
    @assert(loaded.preview.isValid())
    @assert(loaded.preview.width == 8)
    @assert(loaded.preview.height == 6)
    @assert(loaded.title == "Preview Title")

    let deferred = expect Capture.load(path, preview: true, deferPreviewDecode: true)!
    defer Memory.delete(deferred)
    @assert(!deferred.preview.isValid())
    @assert(!deferred.previewBytes.isEmpty())
    expect deferred.materializePreview()
    @assert(deferred.preview.isValid())
    @assert(deferred.preview.width == 8)
    @assert(deferred.preview.height == 6)

    var libraryView: LibraryView
    var libraryItem: LibraryItem
    libraryItem.kind        = .Capture
    libraryItem.fi.fullname = path
    libraryView.loadOne(&libraryItem)
    @assert(libraryItem.loaded)
    @assert(libraryItem.capture != null)
    @assert(!libraryItem.capture!.preview.isValid())
    @assert(!libraryItem.capture!.previewBytes.isEmpty())
    @assert(libraryItem.haar.size != 0)
}
