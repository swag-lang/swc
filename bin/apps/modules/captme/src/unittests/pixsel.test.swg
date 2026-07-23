#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Pixel selection fill and clear mutate only through undoable image replacement.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)

    f.capture.width = 30
    f.capture.height = 30
    f.capture.backImg = Image.create(30, 30, .BGRA8)
    f.capture.backImg.fill(Argb.Zero)

    let pixSel = testAddShape(f.capture, 5, 5, 10, 10, .PixSel)
    pixSel.kind = .Rectangle
    f.capture.selection.add(0)

    f.main.pixSelFillCol = ColorRed
    f.main.sendCommandEvent(ActionPixSel.Fill)
    let filledBytes = Testing.countNonZeroBytes(f.capture.backImg)
    @assert(filledBytes > 0)
    @assert(f.capture.canUndo())

    f.capture.undo()
    @assert(Testing.countNonZeroBytes(f.capture.backImg) == 0)

    f.capture.redo()
    @assert(Testing.countNonZeroBytes(f.capture.backImg) == filledBytes)

    f.main.sendCommandEvent(ActionPixSel.Clear)
    @assert(Testing.countNonZeroBytes(f.capture.backImg) == 0)

    f.capture.undo()
    @assert(Testing.countNonZeroBytes(f.capture.backImg) == filledBytes)

    f.shutdown()
}

// Smart fill uses surrounding pixels to replace a pixel-selection area and remains undoable.
#test
{
    var f: HeadlessFixture
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
    let pixSel = testAddShape(f.capture, 6, 6, 12, 12, .PixSel)
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
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)

    f.capture.width = 24
    f.capture.height = 24
    f.capture.backImg = Testing.indexedImage(24, 24)

    let before = f.capture.backImg.getPixelColor(12, 12)
    let pixSel = testAddShape(f.capture, 6, 6, 12, 12, .PixSel)
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
    var f: HeadlessFixture
    f.setup()

    let pixSel = testAddShape(f.capture, 4, 4, 10, 10, .PixSel)
    pixSel.kind = .Rectangle
    discard testAddText(f.capture, 20, 4, 10, 10)
    f.capture.selection.add(0)
    f.capture.selection.add(1)

    let pixSels = f.main.getPixSels()
    @assert(pixSels.count == 1)
    @assert(@dataof(pixSels[0]) == pixSel)

    f.shutdown()
}
