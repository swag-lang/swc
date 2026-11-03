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

    with let shape = testAddShape(f.capture, 1, 2, 10, 11, .Highlight)
    {
        .kind      = .RoundRectangle
        .roundSize = 18
    }

    with let line = testAddLine(f.capture, 3, 4, 20, 21, .PixSel)
    {
        .bezier      = true
        .xc          = 6
        .yc          = 7
        .paintShadow = false
    }

    let arrow = testAddArrow(f.capture, 5, 6, 30, 31)
    arrow.endSize = 9

    var points: Array'Math.Vector2
    points.add({7, 8})
    points.add({22, 8})
    points.add({18, 25})

    with let polygon = testAddPolygon(f.capture, points.toSlice(), .Highlight)
    {
        .bezier      = true
        .paintShadow = false
    }

    let draw = testAddDraw(f.capture, points.toSlice(), .PixSel)
    draw.paintShadow = false

    let text = testAddText(f.capture, 9, 10, 30, 12)
    text.text      = "roundtrip"
    text.fontSize  = 32
    text.alignHorz = .RightBottom
    text.alignVert = .LeftTop

    with let step = testAddStep(f.capture, 11, 12, 20, 20)
    {
        .index     = 5
        .kind      = .Rectangle
        .typeIndex = .LetterUp
    }

    let image = testAddImage(f.capture, 13, 14, 16, 17)
    image.kind    = .Image
    image.place   = .Free
    image.freePos = {2, 3, 8, 9}
    image.image   = Image.create(4, 3, .BGRA8)
    image.image.fill(ColorYellow)

    with let callout = testAddCallout(f.capture, 15, 16, 40, 24)
    {
        .text      = "hi there"
        .roundSize = 20
        .fontSize  = 36
        .boldSize  = 3
        .textColor = ColorGreen
        .tailX     = 8
        .tailY     = 70
        .fontStyle = .BoldItalic
        .alignHorz = .LeftTop
        .alignVert = .RightBottom
    }

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
    Swag.require(expect Scc.hasSignature(path))
    var container: Scc.Reader
    expect container.initialize(path)
    Swag.require(container.kind() == expect Guid128.parse("4a67acc2-5930-4e81-81dc-d12675bc6deb"))
    container.close()
    let loaded = expect Capture.load(path)
    defer Memory.delete(loaded)
    Swag.require(loaded.width == 64)
    Swag.require(loaded.height == 48)
    Swag.require(loaded.forms.count == 9)
    Swag.require(loaded.backImg.isValid())
    Swag.require(loaded.backImgOriginal.isValid())
    Swag.require(loaded.title == "My Capture Name")
    Swag.require(loaded.sourceKind == .Screen)
    Swag.require(loaded.capturedAt == f.capture.capturedAt)
    Swag.require(loaded.sourceApplication == "chrome")
    Swag.require(loaded.sourceExecutable == "C:\\Program Files\\Google\\Chrome\\chrome.exe")
    Swag.require(loaded.sourceWindowTitle == "Swag - Chromium")
    Swag.require(loaded.sourceWindowClass == "Chrome_WidgetWin_1")
    Swag.require(loaded.tags.count == 2)
    Swag.require(loaded.hasTag("BROWSER"))
    Swag.require(loaded.favorite)
    Swag.require(loaded.rating == 5)

    let lShape = assume cast(*FormShape, loaded.forms[0])
    Swag.require(lShape.capture == loaded)
    Swag.require(lShape.subKind == .Highlight)
    Swag.require(lShape.kind == .RoundRectangle)
    Swag.require(lShape.roundSize == 18)

    let lLine = assume cast(*FormLine, loaded.forms[1])
    Swag.require(lLine.subKind == .PixSel)
    Swag.require(lLine.bezier)
    Swag.require(lLine.xc == 6)
    Swag.require(lLine.yc == 7)
    Swag.require(not lLine.paintShadow)

    let lArrow = assume cast(*FormArrow, loaded.forms[2])
    Swag.require(lArrow.endSize == 9)

    let lPolygon = assume cast(*FormPolygon, loaded.forms[3])
    Swag.require(lPolygon.subKind == .Highlight)
    Swag.require(lPolygon.bezier)
    Swag.require(not lPolygon.paintShadow)
    Swag.require(lPolygon.points.count == 3)

    let lDraw = assume cast(*FormDraw, loaded.forms[4])
    Swag.require(lDraw.subKind == .PixSel)
    Swag.require(not lDraw.paintShadow)
    Swag.require(lDraw.points.count == 3)

    let lText = assume cast(*FormText, loaded.forms[5])
    Swag.require(lText.text == "roundtrip")
    Swag.require(lText.fontSize == 32)
    Swag.require(lText.alignHorz == .RightBottom)
    Swag.require(lText.alignVert == .LeftTop)

    let lStep = assume cast(*FormStep, loaded.forms[6])
    Swag.require(lStep.index == 5)
    Swag.require(lStep.kind == .Rectangle)
    Swag.require(lStep.typeIndex == .LetterUp)

    let lImage = assume cast(*FormImage, loaded.forms[7])
    Swag.require(lImage.kind == .Image)
    Swag.require(lImage.place == .Free)
    Gui.Testing.assertRect(lImage.freePos, 2, 3, 8, 9)
    Swag.require(lImage.image.isValid())
    Swag.require(lImage.image.width == 4)
    Swag.require(lImage.image.height == 3)

    let lCallout = assume cast(*FormCallout, loaded.forms[8])
    Swag.require(lCallout.capture == loaded)
    Swag.require(lCallout.text == "hi there")
    Swag.require(lCallout.roundSize == 20)
    Swag.require(lCallout.fontSize == 36)
    Swag.require(lCallout.boldSize == 3)
    Swag.require(lCallout.textColor == ColorGreen)
    Swag.require(lCallout.tailX == 8)
    Swag.require(lCallout.tailY == 70)
    Swag.require(lCallout.fontStyle == .BoldItalic)
    Swag.require(lCallout.alignHorz == .LeftTop)
    Swag.require(lCallout.alignVert == .RightBottom)
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
    let loaded = expect Capture.load(path, preview: true)
    defer Memory.delete(loaded)
    Swag.require(loaded.forms.count == 0)
    Swag.require(not loaded.backImg.isValid())
    Swag.require(loaded.preview.isValid())
    Swag.require(loaded.preview.width == 8)
    Swag.require(loaded.preview.height == 6)
    Swag.require(loaded.title == "Preview Title")

    let deferred = expect Capture.load(path, preview: true, deferPreviewDecode: true)
    defer Memory.delete(deferred)
    Swag.require(not deferred.preview.isValid())
    Swag.require(not deferred.previewBytes.isEmpty())
    expect deferred.materializePreview()
    Swag.require(deferred.preview.isValid())
    Swag.require(deferred.preview.width == 8)
    Swag.require(deferred.preview.height == 6)

    var libraryView: LibraryView
    var libraryItem: LibraryItem
    libraryItem.kind        = .Capture
    libraryItem.fi.fullName = path
    libraryView.loadOne(&libraryItem)
    Swag.require(libraryItem.loaded)
    Swag.require(libraryItem.capture != null)
    Swag.require(not libraryItem.capture.preview.isValid())
    Swag.require(not libraryItem.capture.previewBytes.isEmpty())
    Swag.require(libraryItem.haar.size != 0)
}

// Preview metadata came from several legacy migrations. Invalid text or paths are
// indexing damage, not document damage: loading the Library drops those optional values
// while leaving the capture available to open through its full model.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    f.capture.width, f.capture.widthOrg   = 8
    f.capture.height, f.capture.heightOrg = 6
    f.capture.backImg                     = Image.create(8, 6, .BGRA8)
    f.capture.sourceApplication           = "bad\napplication"
    f.capture.sourceExecutable            = "bad|application.exe"
    f.capture.sourceWindowTitle           = "bad\nwindow"
    f.capture.sourceWindowClass           = "bad\nclass"
    f.capture.linkedImage                 = "bad|linked.png"
    f.capture.linkedUpToDate              = false

    let path = testTempCapturePath()
    defer discard catch File.delete(path)
    f.capture.file    = path
    f.capture.changed = true

    expect f.capture.save()
    let preview = expect Capture.load(path, preview: true)
    defer Memory.delete(preview)
    Swag.require(preview.sourceApplication.isEmpty())
    Swag.require(preview.sourceExecutable.isEmpty())
    Swag.require(preview.sourceWindowTitle.isEmpty())
    Swag.require(preview.sourceWindowClass.isEmpty())
    Swag.require(preview.linkedImage.isEmpty())
    Swag.require(preview.linkedUpToDate)
}
