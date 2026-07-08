#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Pixel selection fill and clear mutate only through undoable image replacement.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)

    f.capture.width = 30
    f.capture.height = 30
    f.capture.backImg = Image.create(30, 30, .BGRA8)
    f.capture.backImg.fill(Argb.Zero)

    let pixSel = captmeTestAddShape(f.capture, 5, 5, 10, 10, .PixSel)
    pixSel.kind = .Rectangle
    f.capture.selection.add(0)

    f.main.pixSelFillCol = ColorRed
    f.main.sendCommandEvent(ActionPixSel.Fill)
    let filledBytes = captmeTestCountNonZeroBytes(f.capture.backImg)
    @assert(filledBytes > 0)
    @assert(f.capture.canUndo())

    f.capture.undo()
    @assert(captmeTestCountNonZeroBytes(f.capture.backImg) == 0)

    f.capture.redo()
    @assert(captmeTestCountNonZeroBytes(f.capture.backImg) == filledBytes)

    f.main.sendCommandEvent(ActionPixSel.Clear)
    @assert(captmeTestCountNonZeroBytes(f.capture.backImg) == 0)

    f.capture.undo()
    @assert(captmeTestCountNonZeroBytes(f.capture.backImg) == filledBytes)

    f.shutdown()
}

// Smart fill uses surrounding pixels to replace a pixel-selection area and remains undoable.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)

    f.capture.width = 24
    f.capture.height = 24
    f.capture.backImg = Image.create(24, 24, .BGRA8)
    f.capture.backImg.visitPixels()
    {
        let r = cast(u8) ((x * 17 + y * 3) % 255)
        let g = cast(u8) ((x * 5 + y * 19) % 255)
        let b = cast(u8) ((x * 29 + y * 7) % 255)
        dref cast(*u32) pix = Color.fromArgb(255'u8, r, g, b).argb
    }

    let before = f.capture.backImg.getPixelColor(12, 12)
    let pixSel = captmeTestAddShape(f.capture, 6, 6, 12, 12, .PixSel)
    pixSel.kind = .Rectangle
    f.capture.selection.add(0)

    f.main.sendCommandEvent(ActionPixSel.SmartFill)
    let after = f.capture.backImg.getPixelColor(12, 12)
    @assert(after.argb != before.argb)

    f.capture.undo()
    @assert(f.capture.backImg.getPixelColor(12, 12).argb == before.argb)

    f.capture.redo()
    @assert(f.capture.backImg.getPixelColor(12, 12).argb == after.argb)

    f.shutdown()
}

// Smart move captures a pixel selection into a movable image form, then deletes the
// original selection as one undoable operation. This exercises renderer-backed
// texture creation in the GUI headless host.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)

    f.capture.width = 24
    f.capture.height = 24
    f.capture.backImg = captmeTestIndexedImage(24, 24)

    let before = f.capture.backImg.getPixelColor(12, 12)
    let pixSel = captmeTestAddShape(f.capture, 6, 6, 12, 12, .PixSel)
    pixSel.kind = .Rectangle
    f.capture.selection.add(0)

    f.main.sendCommandEvent(ActionPixSel.SmartMove)

    @assert(f.capture.forms.count == 1)
    @assert(f.capture.selection.count == 1)
    @assert(f.capture.selection[0] == 0)
    @assert(@kindof(f.capture.forms[0]) == FormImage)

    let imgForm = cast(*FormImage) @dataof(f.capture.forms[0])
    @assert(imgForm.kind == .Capture)
    @assert(imgForm.image.isValid())
    @assert(imgForm.image.width == 12)
    @assert(imgForm.image.height == 12)
    @assert(imgForm.texture.isValid())
    @assert(f.capture.backImg.getPixelColor(12, 12).argb != before.argb)

    f.capture.undo()
    @assert(f.capture.forms.count == 1)
    @assert(@kindof(f.capture.forms[0]) == FormShape)
    @assert(f.capture.backImg.getPixelColor(12, 12).argb == before.argb)

    f.capture.redo()
    @assert(f.capture.forms.count == 1)
    @assert(@kindof(f.capture.forms[0]) == FormImage)

    f.shutdown()
}

// Pixel-selection extraction filters the current selection without rendering.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let pixSel = captmeTestAddShape(f.capture, 4, 4, 10, 10, .PixSel)
    pixSel.kind = .Rectangle
    discard captmeTestAddText(f.capture, 20, 4, 10, 10)
    f.capture.selection.add(0)
    f.capture.selection.add(1)

    let pixSels = f.main.getPixSels()
    @assert(pixSels.count == 1)
    @assert(@dataof(pixSels[0]) == pixSel)

    f.shutdown()
}

// Capture save/load round-trips every concrete form type and its regression-sensitive fields.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    f.capture.width = 64
    f.capture.height = 48
    f.capture.widthOrg = 64
    f.capture.heightOrg = 48
    f.capture.backImg = Image.create(64, 48, .BGRA8)
    f.capture.backImg.fill(ColorBlue)

    let shape = captmeTestAddShape(f.capture, 1, 2, 10, 11, .Highlight)
    shape.kind = .RoundRectangle
    shape.roundSize = 18

    let line = captmeTestAddLine(f.capture, 3, 4, 20, 21, .PixSel)
    line.bezier = true
    line.xc = 6
    line.yc = 7
    line.paintShadow = false

    let arrow = captmeTestAddArrow(f.capture, 5, 6, 30, 31)
    arrow.endSize = 9

    var points: Array'Math.Vector2
    points.add({7, 8})
    points.add({22, 8})
    points.add({18, 25})

    let polygon = captmeTestAddPolygon(f.capture, points.toSlice(), .Highlight)
    polygon.bezier = true
    polygon.paintShadow = false

    let draw = captmeTestAddDraw(f.capture, points.toSlice(), .PixSel)
    draw.paintShadow = false

    let text = captmeTestAddText(f.capture, 9, 10, 30, 12)
    text.text = "roundtrip"
    text.fontSize = 32
    text.alignHorz = .RightBottom
    text.alignVert = .LeftTop

    let step = captmeTestAddStep(f.capture, 11, 12, 20, 20)
    step.index = 5
    step.kind = .Rectangle
    step.typeIndex = .LetterUp

    let image = captmeTestAddImage(f.capture, 13, 14, 16, 17)
    image.kind = .Image
    image.place = .Free
    image.freePos = {2, 3, 8, 9}
    image.image = Image.create(4, 3, .BGRA8)
    image.image.fill(ColorYellow)

    let path = captmeTestTempCapturePath()
    defer { discard catch File.delete(path) }
    f.capture.file = path
    f.capture.changed = true

    catch f.capture.save()
    @assert(@err == null)

    let loaded = catch Capture.load(path)
    @assert(@err == null)
    @assert(loaded != null)
    defer { Memory.delete(loaded) }

    @assert(loaded.width == 64)
    @assert(loaded.height == 48)
    @assert(loaded.forms.count == 8)
    @assert(loaded.backImg.isValid())

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
    captmeTestAssertRect(lImage.freePos, 2, 3, 8, 9)
    @assert(lImage.image.isValid())
    @assert(lImage.image.width == 4)
    @assert(lImage.image.height == 3)

    f.shutdown()
}

// Preview loading ignores heavy images while preserving form metadata.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    f.capture.width = 32
    f.capture.height = 32
    f.capture.backImg = Image.create(32, 32, .BGRA8)
    f.capture.backImg.fill(ColorRed)
    discard captmeTestAddShape(f.capture, 2, 3, 4, 5)

    let path = captmeTestTempCapturePath()
    defer { discard catch File.delete(path) }
    f.capture.file = path
    f.capture.changed = true

    catch f.capture.save()
    @assert(@err == null)

    let loaded = catch Capture.load(path, preview: true)
    @assert(@err == null)
    @assert(loaded != null)
    defer { Memory.delete(loaded) }

    @assert(loaded.forms.count == 1)
    @assert(!loaded.backImg.isValid())
    @assert((cast(*BaseForm) @dataof(loaded.forms[0])).capture == loaded)

    f.shutdown()
}
